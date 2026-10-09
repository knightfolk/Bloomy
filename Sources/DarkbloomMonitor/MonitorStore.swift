import AppKit
import DarkbloomTelemetry
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {
    var actionHistory: ActionHistoryStore?
    var performanceHistory: PerformanceHistoryStore?
    let networkDemandHistory: NetworkDemandHistoryStore?
    private var networkDemandRecordingTasks: [UUID: Task<Void, Never>] = [:]
    private var networkDemandRecordingStopping = false
    private var performanceSamplingTask: Task<Void, Never>?
    let providerExtras: ProviderExtrasStore?
    /// Whole-Mac GPU utilization sampler owned by the app lifecycle so the
    /// menu-bar ring keeps working with no dashboard open. Views observe it;
    /// only `start()`/`stop()` drive it.
    let gpuUsage: SystemGPUUsageStore
    private var providerExtrasTask: Task<Void, Never>?
    @Published private(set) var energy: EnergyRecordingSnapshot?
    @Published private(set) var energyEarnings: EnergyEarnings?
    private var energyEarningsDay: Date?
    private struct EnergyActivityKey: Equatable {
        let day: DateInterval
        let context: AccountEarningsContext
        let accountCapturedAt: Date?
        let activityRevision: UInt64
    }
    private var energyActivityKey: EnergyActivityKey?
    private var energyActivityBuckets: [ActivityBucket]?

    var electricityEstimatesEnabled: Bool { energyPreferences.bool(forKey: "electricity.enabled") }

    var currentEnergyReading: EnergyReading? {
        guard energyPreferences.bool(forKey: "electricity.enabled"),
              ElectricityCost.rate(energyPreferences.string(forKey: "electricity.usdPerKWh") ?? "") != nil,
              let reading = energy?.reading,
              (0...30).contains(Date().timeIntervalSince(reading.date)) else { return nil }
        return reading
    }

    var currentEnergyEarnings: EnergyEarnings? {
        guard energyPreferences.bool(forKey: "electricity.enabled"),
              ElectricityCost.rate(energyPreferences.string(forKey: "electricity.usdPerKWh") ?? "") != nil,
              energyEarningsDay == Calendar.current.startOfDay(for: Date()) else { return nil }
        return energyEarnings
    }
    private var energyTask: Task<Void, Never>?
    private let energyRecorder: EnergyRecorder
    /// Narrowly scoped preferences dependency for the electricity settings,
    /// so tests can inject an isolated suite instead of mutating `.standard`.
    private let energyPreferences: UserDefaults
    private let menuAttentionPreferences: UserDefaults
    private var menuAttentionPolicy = MenuBarAttentionPolicy()
    private var observedMenuAttentionThreshold: TimeInterval?
    static let earningsPollingInterval: Duration = .seconds(600)
    @Published private(set) var dashboardVisible = false
    private var networkPollingPolicy = NetworkPollingPolicy()
    private var modelControlsVisibilityOwners: Set<UUID> = []
    private var nextNetworkCapacityAttempt = Date.distantPast
    private var networkCapacityPollingSleeping = false

    @Published private(set) var snapshot: TelemetrySnapshot
    @Published private(set) var providerThroughputPeak = ProviderThroughputPeak()
    private let readinessProcessIdentityReader: @Sendable (Int32) -> ProcessIdentity?
    private var readinessIdentitySource: SourceAvailability<DaemonState>?
    private var readinessProcessIdentity: ProcessIdentity?

    /// One kernel identity lookup per changed daemon observation, shared by the
    /// visible summaries. Clock ticks and financial publications don't reread it.
    func providerReadiness(at date: Date) -> ProviderReadinessPresentation {
        if readinessIdentitySource != snapshot.state {
            readinessIdentitySource = snapshot.state
            if case .available(let state, _) = snapshot.state {
                readinessProcessIdentity = readinessProcessIdentityReader(state.pid)
            } else {
                readinessProcessIdentity = nil
            }
        }
        return .make(snapshot: snapshot, now: date, liveProcessIdentity: readinessProcessIdentity)
    }
    /// App-owned watcher; telemetry observations drive its idle window.
    var inactivityNudge: InactivityNudgeStore?
    /// App-owned opt-in watcher. It receives only accepted telemetry and
    /// current source availability, so failed refreshes cannot look live.
    var profitSwitch: ProfitSwitchStore?
    var hostGPUProtection: HostGPUProtectionStore?
    @Published private(set) var servingSlowdownWarning: String?
    private var slowdownPolicy = ServingSlowdownPolicy()
    private var slowdownSettings: HostGPUProtectionSettings?
    private var slowdownWasWarned = false
    @Published private(set) var alertHistory: [AlertRecord] = []
    @Published private(set) var alertHistoryAvailable = false
    @Published private(set) var thermalState: SystemThermalState
    @Published private(set) var earnings: EarningsPresentationValue
    @Published private(set) var todayEarningsReading: SourceAvailability<ObservedEarningsWindow>
    var todayEarnings: ObservedEarningsWindow? { todayEarningsReading.value }
    @Published private(set) var earningsPerHourUSD: Double?
    @Published private(set) var weekEarningsReading: SourceAvailability<CalendarWeekEarningsSummary>
    var weekEarnings: CalendarWeekEarningsSummary? { weekEarningsReading.value }
    @Published private(set) var observedUptime: ObservedUptimeValue
    @Published private(set) var jobSummary: SourceAvailability<JobCompletionSummary>
    @Published private(set) var averageTokenRate: TokenRate
    @Published private(set) var modelTokenRateAverages: [ModelTokenRateAverage]
    @Published private(set) var modelEarnings: [ModelEarnings]
    @Published private(set) var modelWorkEarnings: [ModelWorkEarnings] = []
    @Published private(set) var modelServingProfitAverages: [ModelServingProfitAverage] = []
    @Published private(set) var modelServingProfitCapturedAt: Date?
    @Published private(set) var networkCapacity: SourceAvailability<NetworkCapacitySnapshot>
    @Published private(set) var recommendationDecision: RecommendationDecision?
    @Published private(set) var recommendationHistory: [RecommendationDecision] = []
    @Published private(set) var recommendationHistoryAvailable = false
    @Published private(set) var publicCatalog: SourceAvailability<PublicCatalogSnapshot> = .unavailable(reason: "Waiting for public catalog")
    @Published private(set) var publicPricing: SourceAvailability<PublicPricingSnapshot> = .unavailable(reason: "Waiting for customer pricing")
    @Published private(set) var networkSeries: SourceAvailability<NetworkSeriesSnapshot> = .unavailable(reason: "Open the dashboard to load network history")
    @Published private(set) var networkSeriesRefreshing = false
    @Published private(set) var activityRevision: UInt64 = 0
    @Published private(set) var financialContext: AccountEarningsContext?
    @Published private(set) var financialLedgerReady = false
    private var financialSessionTask: Task<Void, Never>?
    private var financialSessionObservationID: UUID?
    private var earningsRefreshID: UUID?
    private var latestFinancialRefreshID: UUID?
    private var publishedFinancialRefreshID: UUID?
    private var financialStopping = false
    private var financialSessionReadID: UInt64 = 0
    private var latestFinancialSessionRead: Task<AccountEarningsSessionState, Never>?
    @Published private(set) var financialSessionEpoch: UInt64 = 0
    private var earningsRefreshContext: AccountEarningsContext?
    /// Non-published acquisition diagnostic; observing it adds no UI updates.
    private(set) var earningsRefreshWaiterCount = 0
    private var latestFinancialSessionState: AccountEarningsSessionState = .unavailable

    private let service: TelemetryService
    private let earningsClient: any AccountEarningsFetching
    private let uptimeRecorder: (any ObservedUptimeRecording)?
    private let alertHistoryRecorder: (any AlertHistoryRecording)?
    private let alertNotifier: (any OperationalAlertNotifying)?
    private var alertEngine: OperationalAlertEngine
    private var alertStateRestored = false
    private var alertStateRestorationTask: Task<(Set<OperationalAlertCode>, [AlertRecord])?, Never>?
    private var pendingAlertTransitions: [AlertTransition] = []
    private var alertPersistenceInFlight = false
    private let tokenRateRecorder: (any ModelTokenRateRecording)?
    private struct RecordedTokenRate: Equatable {
        let processIdentity: ProcessIdentity
        let writtenAt: TimeInterval
        let model: String
        let tokensPerSecond: Double
    }
    private var lastRecordedTokenRate: RecordedTokenRate?
    private var tokenRateAveragesDay: Date?
    private var tokenRateAveragesNeedRefresh = true
    private let networkCapacityClient: (any NetworkCapacityFetching)?
    private let recommendationJournal: RecommendationJournal?
    private var recommendationControlSnapshot: (@MainActor () -> ProviderControlSnapshot?)?
    private let publicCatalogClient: (any PublicCatalogFetching)?
    private var publicCatalogPollingTask: Task<Void, Never>?
    private var publicCatalogRefreshing = false
    private var publicCatalogFailures = 0
    private let publicPricingClient: (any PublicPricingFetching)?
    private var publicPricingPollingTask: Task<Void, Never>?
    private var publicPricingRefreshing = false
    private var publicPricingFailures = 0
    private let networkSeriesClient: (any NetworkSeriesFetching)?
    private var networkSeriesPollingTask: Task<Void, Never>?
    private var networkSeriesFailures = 0
    private var nextNetworkSeriesAttempt = Date.distantPast
    private let now: @Sendable () -> Date
    private let publicPollingSleep: @Sendable (TimeInterval) async throws -> Void
    private let publicPollingJitter: @Sendable () -> Double
    private var tokenRateAccumulator = ActiveTokenRateAccumulator()
    private var observationTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var earningsPollingTask: Task<Void, Never>?
    private var networkCapacityPollingTask: Task<Void, Never>?
    private var accountEarningsCapturedAt: Date?
    private var earningsRefreshTask: Task<AccountRefreshState?, Never>?
    private var shutdownTask: Task<Void, Never>?
    private var thermalObserver: NSObjectProtocol?
    private var networkCapacityRefreshGeneration = 0
    private var latestNetworkCapacityCapturedAt: Date?
    private var hasStarted = false

    init(
        service: TelemetryService,
        initial: TelemetrySnapshot,
        providerExtras: ProviderExtrasStore? = nil,
        initialEnergy: EnergyRecordingSnapshot? = nil,
        earningsClient: any AccountEarningsFetching = AuthenticatedEarningsClient(
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        ),
        uptimeRecorder: (any ObservedUptimeRecording)? = nil,
        alertHistory: (any AlertHistoryRecording)? = nil,
        alertNotifier: (any OperationalAlertNotifying)? = nil,
        alertPolicy: OperationalAlertPolicy = .init(),
        tokenRateRecorder: (any ModelTokenRateRecording)? = nil,
        networkCapacityClient: (any NetworkCapacityFetching)? = nil,
        networkDemandHistory: NetworkDemandHistoryStore? = nil,
        recommendationJournal: RecommendationJournal? = nil,
        publicCatalogClient: (any PublicCatalogFetching)? = nil,
        publicPricingClient: (any PublicPricingFetching)? = nil,
        networkSeriesClient: (any NetworkSeriesFetching)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        publicPollingSleep: @escaping @Sendable (TimeInterval) async throws -> Void = {
            try await Task.sleep(for: .seconds($0))
        },
        publicPollingJitter: @escaping @Sendable () -> Double = { Double.random(in: 0...0.2) },
        energyPreferences: UserDefaults = .standard,
        energyRecorder: EnergyRecorder? = nil,
        gpuUsage: SystemGPUUsageStore? = nil,
        menuAttentionPreferences: UserDefaults = .standard,
        readinessProcessIdentityReader: @escaping @Sendable (Int32) -> ProcessIdentity? = { ProcessIdentity.read(pid: $0) }
    ) {
        self.service = service
        self.providerExtras = providerExtras
        self.gpuUsage = gpuUsage ?? SystemGPUUsageStore()
        self.energyPreferences = energyPreferences
        self.menuAttentionPreferences = menuAttentionPreferences
        self.readinessProcessIdentityReader = readinessProcessIdentityReader
        self.energyRecorder = energyRecorder ?? EnergyRecorder(
            file: MonitorApplicationIdentity
                .applicationSupportDirectory()
                .appendingPathComponent("energy-history.json")
        )
        energy = initialEnergy
        self.earningsClient = earningsClient
        self.uptimeRecorder = uptimeRecorder
        alertHistoryRecorder = alertHistory
        self.alertNotifier = alertNotifier
        alertEngine = OperationalAlertEngine(policy: alertPolicy)
        self.tokenRateRecorder = tokenRateRecorder
        self.networkCapacityClient = networkCapacityClient
        self.networkDemandHistory = networkDemandHistory
        self.recommendationJournal = recommendationJournal
        self.publicCatalogClient = publicCatalogClient
        self.publicPricingClient = publicPricingClient
        self.networkSeriesClient = networkSeriesClient
        self.now = now
        self.publicPollingSleep = publicPollingSleep
        self.publicPollingJitter = publicPollingJitter
        snapshot = initial
        thermalState = SystemThermalState(ProcessInfo.processInfo.thermalState)
        earnings = .unavailable(reason: "Waiting for authenticated account earnings")
        todayEarningsReading = .unavailable(reason: "Waiting for today's observed earnings")
        earningsPerHourUSD = nil
        weekEarningsReading = .unavailable(reason: "Waiting for this week's observed earnings")
        observedUptime = uptimeRecorder == nil
            ? .unavailable(reason: "Local observed-uptime storage unavailable")
            : .warming(observedSeconds: 0)
        jobSummary = .unavailable(reason: "Waiting for completed-job history")
        averageTokenRate = .unavailable(reason: "Waiting for active inference samples")
        modelTokenRateAverages = []
        modelEarnings = []
        networkCapacity = .unavailable(reason: "Waiting for network model demand")
        observeFinancialSession()
    }

    deinit {
        financialSessionTask?.cancel()
        latestFinancialSessionRead?.cancel()
    }

    private func observeFinancialSession() {
        guard financialSessionTask == nil, shutdownTask == nil, !financialStopping else { return }
        let client = earningsClient
        let observationID = UUID()
        financialSessionObservationID = observationID
        financialSessionTask = Task { [weak self] in
            let changes = await client.financialSessionChanges()
            for await _ in changes {
                guard !Task.isCancelled else { return }
                // An older buffered event must not undo a newer API-boundary
                // snapshot. Resolve current state before the actor publication.
                guard let request = self?.beginFinancialSessionRead() else { return }
                let state = await request.task.value
                guard !Task.isCancelled, let self,
                      self.financialSessionObservationID == observationID,
                      self.shutdownTask == nil, !self.financialStopping else { return }
                _ = await self.resolveFinancialSessionRead(id: request.id, state: state)
            }
        }
    }

    @discardableResult
    func synchronizeFinancialSession() async -> AccountEarningsSessionState {
        observeFinancialSession()
        let request = beginFinancialSessionRead()
        let state = await request.task.value
        return await resolveFinancialSessionRead(id: request.id, state: state)
    }

    private func beginFinancialSessionRead() -> (id: UInt64, task: Task<AccountEarningsSessionState, Never>) {
        financialSessionReadID &+= 1
        let client = earningsClient
        let task = Task { await client.financialSessionState() }
        latestFinancialSessionRead = task
        return (financialSessionReadID, task)
    }

    private func resolveFinancialSessionRead(id: UInt64, state: AccountEarningsSessionState) async -> AccountEarningsSessionState {
        var resolvedID = id
        var resolved = state
        // Superseded callers must await the newer snapshot, not return the
        // previous cached account while its authoritative read is still pending.
        while resolvedID != financialSessionReadID {
            guard !Task.isCancelled, !financialStopping, let latestFinancialSessionRead else { return .unavailable }
            resolvedID = financialSessionReadID
            resolved = await latestFinancialSessionRead.value
        }
        guard !Task.isCancelled, shutdownTask == nil, !financialStopping else { return .unavailable }
        applyFinancialSession(resolved)
        return latestFinancialSessionState
    }

    func validateFinancialContext(_ context: AccountEarningsContext) async throws {
        do {
            try await earningsClient.validateFinancialContext(context)
            let state = await synchronizeFinancialSession()
            guard state.context == context, state.ledgerReady else { throw AccountEarningsClientError.sessionChanged }
        } catch {
            _ = await synchronizeFinancialSession()
            throw error
        }
    }

    private func applyFinancialSession(_ state: AccountEarningsSessionState) {
        let revisionChanged = latestFinancialSessionState.revision != state.revision
        latestFinancialSessionState = state
        guard financialContext != state.context || financialLedgerReady != state.ledgerReady || revisionChanged else { return }
        // Session revisions change at identity/readiness boundaries, not on
        // ordinary ingestion. A buffered loss/restoration must also invalidate.
        if financialContext != state.context || (financialLedgerReady && (!state.ledgerReady || revisionChanged)) {
            clearFinancialPresentation()
        }
        financialContext = state.context
        financialLedgerReady = state.ledgerReady
        financialSessionEpoch &+= 1
        activityRevision &+= 1
    }

    private func clearFinancialPresentation() {
        let reason = "Waiting for this account's earnings"
        earnings = .unavailable(reason: reason)
        todayEarningsReading = .unavailable(reason: reason)
        weekEarningsReading = .unavailable(reason: reason)
        jobSummary = .unavailable(reason: "Work credit history is unavailable")
        accountEarningsCapturedAt = nil
        earningsPerHourUSD = nil
        publishedFinancialRefreshID = nil
        modelEarnings = []
        modelWorkEarnings = []
        modelServingProfitAverages = []
        modelServingProfitCapturedAt = nil
        energyActivityKey = nil
        energyActivityBuckets = nil
        energyEarnings = nil
        energyEarningsDay = nil
        recommendationDecision = nil
        recommendationHistory = []
        recommendationHistoryAvailable = false
        profitSwitch?.invalidateFinancialEvidence()
    }

    func attachRecommendationInventory(_ snapshot: @escaping @MainActor () -> ProviderControlSnapshot?) {
        recommendationControlSnapshot = snapshot
    }

    func refreshRecommendation() async {
        let state = await synchronizeFinancialSession()
        guard !Task.isCancelled, !financialStopping else { return }
        let context = state.context
        let epoch = financialSessionEpoch
        let revision = activityRevision
        let input = RecommendationEvidenceAssembler.make(
            at: now(), network: networkCapacity, telemetry: snapshot,
            control: recommendationControlSnapshot?(), observedWork: modelWorkEarnings)
        guard let recommendationJournal else {
            recommendationDecision = RecommendationEvaluator.evaluate(input)
            recommendationHistory = []
            recommendationHistoryAvailable = false
            return
        }
        do {
            let decision = try await recommendationJournal.record(input)
            guard await recommendationPublicationValid(context: context, epoch: epoch, revision: revision) else { return }
            recommendationDecision = decision
            // Existing journal rows have no account/session attribution. Keep
            // them for replay, but show only decisions accepted in this session.
            var history = recommendationHistory.filter { $0.id != decision.id }
            history.append(decision)
            recommendationHistory = Array(history.suffix(12))
            recommendationHistoryAvailable = true
        } catch {
            guard await recommendationPublicationValid(context: context, epoch: epoch, revision: revision) else { return }
            recommendationDecision = RecommendationEvaluator.evaluate(input)
            recommendationHistory = []
            recommendationHistoryAvailable = false
        }
    }

    private func recommendationPublicationValid(context: AccountEarningsContext?, epoch: UInt64,
                                               revision: UInt64) async -> Bool {
        if let context, (try? await earningsClient.validateFinancialContext(context)) == nil {
            _ = await synchronizeFinancialSession()
            return false
        }
        let state = await synchronizeFinancialSession()
        return !Task.isCancelled && !financialStopping && state.context == context
            && financialContext == context && financialSessionEpoch == epoch && activityRevision == revision
    }

    func start() {
        guard !hasStarted, shutdownTask == nil else { return }
        hasStarted = true
        observeThermalState()
        gpuUsage.start()
        performanceSamplingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.recordPerformanceSample()
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
            }
        }
        if providerExtras != nil {
            providerExtrasTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.providerExtras?.refreshBackground()
                    do { try await Task.sleep(for: .seconds(30)) }
                    catch { return }
                }
            }
        }
        energyTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let enabled = energyPreferences.bool(forKey: "electricity.enabled")
                let rate = ElectricityCost.rate(energyPreferences.string(forKey: "electricity.usdPerKWh") ?? "")
                let sampleTime = Date()
                let activity = self.modelPowerActivity(at: sampleTime)
                let result = await self.energyRecorder.sample(
                    enabled: enabled,
                    rate: rate,
                    now: sampleTime,
                    modelActivity: activity
                )
                guard !Task.isCancelled else { return }
                self.energy = enabled ? result : nil
                await self.updateEnergyEarnings(using: result, enabled: enabled, at: Date())
                do { try await Task.sleep(for: .seconds(10)) }
                catch { return }
            }
        }

        earningsPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshEarnings()
                do {
                    try await Task.sleep(for: Self.earningsPollingInterval)
                } catch {
                    return
                }
            }
        }

        startNetworkCapacityPolling()
        if dashboardVisible { startNetworkSeriesPolling() }
        if publicPricingClient != nil {
            publicPricingPollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshPublicPricing()
                    guard let self else { return }
                    let delay = PublicPollingBackoff.delay(base: 900, cap: 21_600, failures: self.publicPricingFailures, jitter: self.publicPollingJitter())
                    do { try await self.publicPollingSleep(delay) }
                    catch { return }
                }
            }
        }
        if publicCatalogClient != nil {
            publicCatalogPollingTask = Task { [weak self] in
                while !Task.isCancelled {
                    await self?.refreshPublicCatalog()
                    guard let self else { return }
                    let delay = PublicPollingBackoff.delay(base: 1_800, cap: 21_600, failures: self.publicCatalogFailures, jitter: self.publicPollingJitter())
                    do { try await self.publicPollingSleep(delay) }
                    catch { return }
                }
            }
        }

        observationTask = Task { [weak self] in
            guard let self else { return }
            let snapshots = await service.snapshots()
            await service.start()

            for await snapshot in snapshots {
                guard !Task.isCancelled else { return }
                await self.accept(snapshot)
                await self.recordObservedUptime(from: snapshot)
            }
        }
    }

    func refresh() {
        guard shutdownTask == nil, refreshTask == nil else { return }

        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { refreshTask = nil }
            async let refreshed = service.refreshNow()
            async let earningsRefresh: Void = refreshEarnings()
            async let networkRefresh: Void = refreshNetworkCapacity()
            let snapshot = await refreshed
            await earningsRefresh
            await networkRefresh
            guard !Task.isCancelled, shutdownTask == nil else { return }
            await self.accept(snapshot)
        }
    }

    func makeSupportPacketPreview() async throws -> SupportPacketSnapshot {
        var recentAlerts: [AlertRecord] = []
        let reportAlertHistoryAvailable: Bool
        if let alertHistoryRecorder, await restoreAlertStateIfNeeded() {
            recentAlerts = try await alertHistoryRecorder.recentHistory(limit: 500)
            reportAlertHistoryAvailable = true
            alertHistory = recentAlerts
            alertHistoryAvailable = true
        } else {
            reportAlertHistoryAvailable = false
            alertHistoryAvailable = false
        }

        let modelAllowlist: Set<String>
        if case .available(let catalog, _) = publicCatalog {
            modelAllowlist = Set(catalog.models.prefix(512).map(\.id))
        } else {
            modelAllowlist = []
        }
        return try SupportPacketSnapshot.make(
            snapshot: snapshot,
            alerts: recentAlerts,
            allowlistedModelIDs: modelAllowlist,
            recommendation: recommendationDecision,
            recommendationHistory: recommendationHistory,
            createdAt: now(),
            alertHistoryAvailable: reportAlertHistoryAvailable
        )
    }

    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String? = nil) async throws -> [ActivityBucket]? {
        try await financialReport(in: range, unit: unit, calendar: calendar, model: model)?.activityBuckets(model: model)
    }

    func activityModels(in range: DateInterval) async throws -> [String] {
        try await financialReport(in: range, unit: .day, calendar: .current)?.models ?? []
    }

    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        try await financialReport(in: range, unit: unit, calendar: calendar)?.modelActivity
    }

    /// One context-bound report. A complete view will capture and pass its
    /// context explicitly; compatibility callers still resolve before reading.
    func financialReport(context expectedContext: AccountEarningsContext? = nil,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar,
        model: String? = nil) async throws -> AccountCreditReport? {
        try await readFinancialReport(context: expectedContext, in: range, unit: unit,
            calendar: calendar, model: model, localProvider: false)
    }

    /// Account money cannot calibrate this Mac's power or serving economics.
    /// The client must supply a separately verified local-provider report.
    func localProviderFinancialReport(context expectedContext: AccountEarningsContext? = nil,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        try await readFinancialReport(context: expectedContext, in: range, unit: unit,
            calendar: calendar, model: nil, localProvider: true)
    }

    private func readFinancialReport(context expectedContext: AccountEarningsContext?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar,
        model: String?, localProvider: Bool) async throws -> AccountCreditReport? {
        let state = await synchronizeFinancialSession()
        guard expectedContext == nil || expectedContext == state.context else { throw AccountEarningsClientError.sessionChanged }
        guard let context = state.context, state.ledgerReady else { return nil }
        let epoch = financialSessionEpoch
        do {
            let report: AccountCreditReport?
            if localProvider {
                report = try await earningsClient.localProviderFinancialReport(context: context,
                    in: range, unit: unit, calendar: calendar)?.report
            } else {
                report = try await earningsClient.financialReport(context: context, providerID: nil, model: model,
                    in: range, unit: unit, calendar: calendar)
            }
            try await validateFinancialContext(context)
            guard epoch == financialSessionEpoch else { throw AccountEarningsClientError.sessionChanged }
            guard report == nil || report?.accountScope == context.accountScope else { throw AccountEarningsClientError.sessionChanged }
            return report
        } catch {
            try await validateFinancialContext(context)
            guard epoch == financialSessionEpoch else { throw AccountEarningsClientError.sessionChanged }
            throw error
        }
    }

    func refreshModelServingProfitability() async {
        let state = await synchronizeFinancialSession()
        guard let context = state.context, state.ledgerReady,
              energyPreferences.bool(forKey: "electricity.enabled"),
              ElectricityCost.rate(energyPreferences.string(forKey: "electricity.usdPerKWh") ?? "") != nil,
              let first = energy?.intervals.first?.start,
              let last = energy?.intervals.last?.end,
              last > first else {
            modelServingProfitAverages = []
            modelServingProfitCapturedAt = nil
            observeProfitSwitch()
            return
        }
        let end = min(last, now())
        let start = max(first, end.addingTimeInterval(-7 * 86_400))
        guard end > start else { return }
        let range = DateInterval(start: start, end: end)
        let revision = activityRevision
        let capturedAt = accountEarningsCapturedAt
        let intervals = energy?.intervals ?? []
        do {
            guard let report = try await localProviderFinancialReport(context: context, in: range, unit: .hour, calendar: .current) else {
                if financialContext == context, activityRevision == revision,
                   accountEarningsCapturedAt == capturedAt {
                    modelServingProfitAverages = []
                    modelServingProfitCapturedAt = nil
                    observeProfitSwitch()
                }
                return
            }
            try await validateFinancialContext(context)
            guard activityRevision == revision, accountEarningsCapturedAt == capturedAt,
                  energy?.intervals == intervals else { return }
            modelServingProfitAverages = ModelProfitability.servingAverages(
                activity: report.modelActivity, energy: intervals)
            modelServingProfitCapturedAt = capturedAt
            observeProfitSwitch()
        } catch {
            if financialContext == context, activityRevision == revision,
               accountEarningsCapturedAt == capturedAt, energy?.intervals == intervals {
                modelServingProfitAverages = []
                modelServingProfitCapturedAt = nil
                observeProfitSwitch()
            }
        }
    }

    func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]? {
        try await financialReport(in: range, unit: .day, calendar: .current)?.hourlyEarningsAverages
    }

    func activityTokenRates(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String) async throws -> [ModelRateBucket]? {
        try await tokenRateRecorder?.history(in: range, unit: unit, calendar: calendar, model: model)
    }

    func refreshTelemetryImmediately() async {
        guard shutdownTask == nil else { return }

        // The first read drains any refresh that began before a provider command.
        // The second read is therefore guaranteed to begin after that command.
        _ = await service.refreshNow()
        guard !Task.isCancelled, shutdownTask == nil else { return }
        let refreshed = await service.refreshNow()
        guard !Task.isCancelled, shutdownTask == nil else { return }
        await accept(refreshed)
    }

    func refreshEarnings() async {
        guard !Task.isCancelled, shutdownTask == nil, !financialStopping else { return }
        var initial = await synchronizeFinancialSession()
        guard !Task.isCancelled, shutdownTask == nil else { return }
        while let task = earningsRefreshTask {
            let joinedID = earningsRefreshID
            let joinedContext = earningsRefreshContext
            earningsRefreshWaiterCount += 1
            let refresh = await task.value
            earningsRefreshWaiterCount -= 1
            if let refresh { await publishFinancialRefresh(refresh) }
            guard !Task.isCancelled, shutdownTask == nil, !financialStopping,
                  joinedContext != initial.context else { return }
            // Drain an obsolete acquisition before starting the explicitly
            // requested current account; preserve same-session coalescing.
            if earningsRefreshID == joinedID {
                earningsRefreshTask = nil
                earningsRefreshID = nil
                earningsRefreshContext = nil
            }
            let latest = await synchronizeFinancialSession()
            guard latest.context == initial.context else { return }
            initial = latest
        }

        let client = earningsClient
        let previousContext = initial.context
        let previousSessionEpoch = financialSessionEpoch
        let previousLedgerReady = initial.ledgerReady
        let previousEarnings = earnings
        let previousJobSummary = jobSummary
        let previousModelEarnings = modelEarnings
        let previousToday = todayEarningsReading
        let previousWeek = weekEarningsReading
        let refreshedAt = now()
        let calendar = Calendar.current
        let refreshID = UUID()
        let task = Task<AccountRefreshState?, Never> {
            var context = previousContext
            let refreshedEarnings: EarningsPresentationValue
            do {
                let result = try await client.fetchWithContext(now: refreshedAt)
                context = result.context
                try await client.validateFinancialContext(result.context)
                switch result.value {
                case .available, .observed, .day, .stale:
                    refreshedEarnings = result.value
                case .unavailable(let reason):
                    refreshedEarnings = Self.staleOrUnavailable(
                        previous: result.context == previousContext ? previousEarnings : .unavailable(reason: reason),
                        reason: reason)
                }
            } catch {
                guard let previousContext,
                      (try? await client.validateFinancialContext(previousContext)) != nil else { return nil }
                // A failed first acquisition must not manufacture a partially
                // refreshed dashboard from later independent getters. Retention
                // requires an already accepted snapshot from this same session.
                if case .unavailable = previousEarnings { return nil }
                refreshedEarnings = Self.staleOrUnavailable(previous: previousEarnings, reason: error.localizedDescription)
            }
            guard let context else { return nil }
            // Every later getter must still belong to the fetch's context,
            // including failures. Only same-context previous values may remain.
            let sameContext = context == previousContext
            let refreshedJobSummary: SourceAvailability<JobCompletionSummary>
            do {
                if let value = try await Self.readFinancial(context, client: client, read: {
                    try await client.jobCompletionSummary(now: refreshedAt, calendar: calendar)
                }) {
                    refreshedJobSummary = .available(value: value, capturedAt: refreshedAt)
                } else {
                    refreshedJobSummary = .unavailable(reason: "Work credit history is unavailable")
                }
            } catch {
                guard (try? await client.validateFinancialContext(context)) != nil else { return nil }
                refreshedJobSummary = Self.staleOrUnavailable(
                    previous: sameContext ? previousJobSummary : .unavailable(reason: "Work credit history is unavailable"),
                    reason: error.localizedDescription)
            }
            let refreshedModelEarnings: [ModelEarnings]
            do {
                refreshedModelEarnings = try await Self.readFinancial(context, client: client, read: {
                    try await client.modelEarnings(since: refreshedAt.addingTimeInterval(-7 * 86_400))
                })
            } catch {
                guard (try? await client.validateFinancialContext(context)) != nil else { return nil }
                refreshedModelEarnings = sameContext ? previousModelEarnings : []
            }
            let refreshedTodayEarnings: SourceAvailability<ObservedEarningsWindow>
            let refreshedWeekEarnings: SourceAvailability<CalendarWeekEarningsSummary>
            var refreshedModelWork: [ModelWorkEarnings] = []
            switch refreshedEarnings {
            case .available, .observed, .day:
                do {
                    refreshedModelWork = try await Self.readFinancial(context, client: client, read: {
                        try await client.modelWorkEarnings(
                            in: DateInterval(start: calendar.startOfDay(for: refreshedAt), end: refreshedAt), calendar: calendar)
                    })
                } catch {
                    guard (try? await client.validateFinancialContext(context)) != nil else { return nil }
                }
                do {
                    if let value = try await Self.readFinancial(context, client: client, read: {
                        try await client.todayEarningsSummary(now: refreshedAt, calendar: calendar)
                    }) {
                        refreshedTodayEarnings = .available(value: value, capturedAt: refreshedAt)
                    } else {
                        refreshedTodayEarnings = .unavailable(reason: "Today's observed earnings are unavailable")
                    }
                } catch {
                    guard (try? await client.validateFinancialContext(context)) != nil else { return nil }
                    refreshedTodayEarnings = Self.staleOrUnavailable(
                        previous: sameContext ? previousToday : .unavailable(reason: "Today's observed earnings are unavailable"),
                        reason: "Today's earnings refresh failed")
                }
                do {
                    if let value = try await Self.readFinancial(context, client: client, read: {
                        try await client.weekEarningsSummary(now: refreshedAt, calendar: calendar)
                    }) {
                        refreshedWeekEarnings = .available(value: value, capturedAt: refreshedAt)
                    } else {
                        refreshedWeekEarnings = .unavailable(reason: "This week's observed earnings are unavailable")
                    }
                } catch {
                    guard (try? await client.validateFinancialContext(context)) != nil else { return nil }
                    refreshedWeekEarnings = Self.staleOrUnavailable(
                        previous: sameContext ? previousWeek : .unavailable(reason: "This week's observed earnings are unavailable"),
                        reason: "This week's earnings refresh failed")
                }
            case .stale, .unavailable:
                refreshedTodayEarnings = Self.staleOrUnavailable(
                    previous: sameContext ? previousToday : .unavailable(reason: "Today's observed earnings are unavailable"),
                    reason: "Account earnings could not be refreshed")
                refreshedWeekEarnings = Self.staleOrUnavailable(
                    previous: sameContext ? previousWeek : .unavailable(reason: "This week's observed earnings are unavailable"),
                    reason: "Account earnings could not be refreshed")
            }
            guard (try? await client.validateFinancialContext(context)) != nil else { return nil }
            let accountCapturedAt: Date?
            switch refreshedEarnings {
            case .available, .observed, .day: accountCapturedAt = refreshedAt
            case .stale, .unavailable: accountCapturedAt = nil
            }
            return AccountRefreshState(context: context, requestID: refreshID,
                initialSessionEpoch: previousSessionEpoch, initialLedgerReady: previousLedgerReady, accountCapturedAt: accountCapturedAt,
                earnings: refreshedEarnings, jobSummary: refreshedJobSummary,
                todayEarnings: refreshedTodayEarnings, weekEarnings: refreshedWeekEarnings,
                modelEarnings: refreshedModelEarnings, modelWorkEarnings: refreshedModelWork)
        }
        earningsRefreshID = refreshID
        earningsRefreshContext = previousContext
        latestFinancialRefreshID = refreshID
        earningsRefreshTask = task
        let refresh = await task.value
        if earningsRefreshID == refreshID {
            earningsRefreshTask = nil
            earningsRefreshID = nil
            earningsRefreshContext = nil
        }
        if let refresh { await publishFinancialRefresh(refresh) }
        else { _ = await synchronizeFinancialSession() }
    }

    private static func readFinancial<T: Sendable>(_ context: AccountEarningsContext,
        client: any AccountEarningsFetching, read: () async throws -> T) async throws -> T {
        try await client.validateFinancialContext(context)
        do {
            let value = try await read()
            try await client.validateFinancialContext(context)
            return value
        } catch {
            try await client.validateFinancialContext(context)
            throw error
        }
    }

    private func publishFinancialRefresh(_ refresh: AccountRefreshState) async {
        guard !Task.isCancelled, shutdownTask == nil else { return }
        do { try await earningsClient.validateFinancialContext(refresh.context) }
        catch { _ = await synchronizeFinancialSession(); return }
        let state = await synchronizeFinancialSession()
        guard !Task.isCancelled, shutdownTask == nil, !financialStopping,
              state.context == refresh.context, state.ledgerReady, financialContext == refresh.context,
              (!refresh.initialLedgerReady || refresh.initialSessionEpoch == financialSessionEpoch),
              latestFinancialRefreshID == refresh.requestID,
              publishedFinancialRefreshID != refresh.requestID else { return }
        publishedFinancialRefreshID = refresh.requestID
        accountEarningsCapturedAt = refresh.accountCapturedAt
        earnings = refresh.earnings
        todayEarningsReading = refresh.todayEarnings
        weekEarningsReading = refresh.weekEarnings
        modelEarnings = refresh.modelEarnings
        modelWorkEarnings = refresh.modelWorkEarnings
        earningsPerHourUSD = refresh.freshlyReadToday.flatMap {
            $0.coversDayToDate ? EarningsHourlyRate.derive(microUSD: $0.microUSD, observedSeconds: $0.observedSeconds) : nil
        }
        jobSummary = refresh.jobSummary
        activityRevision &+= 1
        await refreshModelServingProfitability()
    }

    func setDashboardVisible(_ visible: Bool) {
        guard dashboardVisible != visible else { return }
        let demandWasVisible = networkCapacityPollingVisible
        dashboardVisible = visible
        let previousSeries = networkSeriesPollingTask
        previousSeries?.cancel()
        if visible, hasStarted, shutdownTask == nil {
            startNetworkSeriesPolling(after: previousSeries)
        }
        updateNetworkCapacityPollingVisibility(previouslyVisible: demandWasVisible)
    }

    /// A popup model panel participates in the existing demand loop without
    /// making the dashboard or its unrelated history polling visible.
    func setModelControlsVisible(_ visible: Bool, owner: UUID) {
        let demandWasVisible = networkCapacityPollingVisible
        if visible { modelControlsVisibilityOwners.insert(owner) }
        else { modelControlsVisibilityOwners.remove(owner) }
        updateNetworkCapacityPollingVisibility(previouslyVisible: demandWasVisible)
    }

    private var networkCapacityPollingVisible: Bool {
        dashboardVisible || !modelControlsVisibilityOwners.isEmpty || profitSwitch?.enabled == true
    }

    private func updateNetworkCapacityPollingVisibility(previouslyVisible: Bool) {
        let visible = networkCapacityPollingVisible
        guard visible != previouslyVisible, hasStarted, shutdownTask == nil,
              networkPollingPolicy.failures == 0, networkCapacityPollingSleeping else { return }
        // Fresh opens replace a hidden five-minute wait with a one-minute
        // wait. Stale opens wake immediately. Existing retry deadlines survive
        // repeated closes/opens, and an active read is never cancelled here.
        nextNetworkCapacityAttempt = now().addingTimeInterval(
            visible && networkCapacity.value?.isFresh(at: now()) != true ? 0
                : networkPollingPolicy.delay(dashboardVisible: visible, jitter: publicPollingJitter())
        )
        let previous = networkCapacityPollingTask
        previous?.cancel()
        startNetworkCapacityPolling(after: previous)
    }

    private func startNetworkCapacityPolling(after previous: Task<Void, Never>? = nil) {
        guard networkCapacityClient != nil else { return }
        networkCapacityPollingTask = Task { [weak self] in
            await previous?.value
            while !Task.isCancelled {
                guard let delay = self.map({ max(0, $0.nextNetworkCapacityAttempt.timeIntervalSince($0.now())) }),
                      let sleep = self?.publicPollingSleep else { return }
                if delay > 0 {
                    self?.networkCapacityPollingSleeping = true
                    do { try await sleep(delay) }
                    catch {
                        self?.networkCapacityPollingSleeping = false
                        return
                    }
                    self?.networkCapacityPollingSleeping = false
                }
                guard !Task.isCancelled else { return }
                await self?.refreshNetworkCapacity()
                guard !Task.isCancelled, let self else { return }
                self.nextNetworkCapacityAttempt = self.now().addingTimeInterval(self.networkPollingPolicy.delay(
                    dashboardVisible: self.networkCapacityPollingVisible,
                    jitter: self.publicPollingJitter()
                ))
            }
        }
    }

    private func startNetworkSeriesPolling(after previous: Task<Void, Never>? = nil) {
        guard networkSeriesClient != nil else { return }
        networkSeriesPollingTask = Task { [weak self] in
            await previous?.value
            while !Task.isCancelled {
                guard let delay = self.map({ max(0, $0.nextNetworkSeriesAttempt.timeIntervalSince($0.now())) }) else { return }
                if delay > 0 {
                    guard let sleep = self?.publicPollingSleep else { return }
                    do { try await sleep(delay) }
                    catch { return }
                }
                guard !Task.isCancelled, self?.dashboardVisible == true else { return }
                await self?.refreshNetworkSeries()
            }
        }
    }

    var canRefreshNetworkSeries: Bool {
        networkSeriesClient != nil && dashboardVisible && !networkSeriesRefreshing && shutdownTask == nil
    }

    func manuallyRefreshNetworkSeries() async {
        guard canRefreshNetworkSeries, !Task.isCancelled else { return }
        await refreshNetworkSeries()
        guard hasStarted, dashboardVisible, shutdownTask == nil, !Task.isCancelled else { return }
        // A manual success shortens an old failure delay; another failure can
        // lengthen it. Replace the owned sleep so both honor the new deadline.
        let previous = networkSeriesPollingTask
        previous?.cancel()
        startNetworkSeriesPolling(after: previous)
    }

    func refreshNetworkSeries() async {
        guard let networkSeriesClient, dashboardVisible, !networkSeriesRefreshing, shutdownTask == nil, !Task.isCancelled else { return }
        networkSeriesRefreshing = true
        nextNetworkSeriesAttempt = now().addingTimeInterval(300)
        defer { networkSeriesRefreshing = false }
        do {
            let value = try await networkSeriesClient.fetch(at: now())
            guard !Task.isCancelled, shutdownTask == nil, dashboardVisible else { return }
            let age = now().timeIntervalSince(value.updatedAt)
            guard age.isFinite, age >= -60, age <= 900 else { throw NetworkSeriesError.invalidSeries }
            networkSeries = .available(value: value, capturedAt: value.capturedAt)
            networkSeriesFailures = 0
            nextNetworkSeriesAttempt = now().addingTimeInterval(300)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, shutdownTask == nil, dashboardVisible else { return }
            networkSeriesFailures = min(4, networkSeriesFailures + 1)
            nextNetworkSeriesAttempt = now().addingTimeInterval(PublicPollingBackoff.delay(base: 300, cap: 3_600, failures: networkSeriesFailures, jitter: publicPollingJitter()))
            if let value = networkSeries.value {
                networkSeries = .stale(value: value, capturedAt: value.capturedAt, reason: "Network history refresh failed")
            } else {
                networkSeries = .unavailable(reason: "Network history is unavailable")
            }
        }
    }

    func refreshNetworkCapacity() async {
        guard !Task.isCancelled, shutdownTask == nil, !networkDemandRecordingStopping,
              let networkCapacityClient else { return }
        networkCapacityRefreshGeneration &+= 1
        let refreshGeneration = networkCapacityRefreshGeneration
        let capturedAt = now()
        do {
            let value = try await networkCapacityClient.fetch(at: capturedAt)
            guard !Task.isCancelled,
                  shutdownTask == nil, !networkDemandRecordingStopping,
                  refreshGeneration == networkCapacityRefreshGeneration
            else { return }
            guard value.isFresh(at: now()) else {
                markNetworkCapacityRefreshFailed()
                observeProfitSwitch()
                await refreshRecommendation()
                return
            }
            guard latestNetworkCapacityCapturedAt.map({ value.capturedAt >= $0 }) ?? true else {
                return
            }
            networkCapacity = .available(value: value, capturedAt: value.capturedAt)
            latestNetworkCapacityCapturedAt = value.capturedAt
            networkPollingPolicy.succeeded()
            observeProfitSwitch()
            await refreshRecommendation()
            // Publication and decision work precede disk suspension. Keep the
            // accepted value even if another refresh starts during that await.
            guard !Task.isCancelled, shutdownTask == nil, !networkDemandRecordingStopping,
                  let networkDemandHistory else { return }
            let recordingID = UUID()
            let recording = Task { await networkDemandHistory.observe(value) }
            networkDemandRecordingTasks[recordingID] = recording
            await withTaskCancellationHandler {
                await recording.value
            } onCancel: {
                recording.cancel()
            }
            networkDemandRecordingTasks[recordingID] = nil
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, shutdownTask == nil, !networkDemandRecordingStopping else { return }
            guard refreshGeneration == networkCapacityRefreshGeneration else { return }
            markNetworkCapacityRefreshFailed()
            observeProfitSwitch()
            await refreshRecommendation()
        }
    }

    func refreshPublicCatalog() async {
        guard let publicCatalogClient, !publicCatalogRefreshing, shutdownTask == nil, !Task.isCancelled else { return }
        publicCatalogRefreshing = true
        defer { publicCatalogRefreshing = false }
        do {
            let value = try await publicCatalogClient.fetch(at: now())
            guard !Task.isCancelled, shutdownTask == nil else { return }
            let age = now().timeIntervalSince(value.capturedAt)
            guard age.isFinite, age >= 0, age <= 1_800 else { throw PublicCatalogError.invalidCatalog }
            publicCatalog = .available(value: value, capturedAt: value.capturedAt)
            publicCatalogFailures = 0
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, shutdownTask == nil else { return }
            publicCatalogFailures = min(4, publicCatalogFailures + 1)
            if let value = publicCatalog.value {
                publicCatalog = .stale(value: value, capturedAt: value.capturedAt, reason: "Public catalog refresh failed")
            } else {
                publicCatalog = .unavailable(reason: "Public catalog is unavailable")
            }
        }
    }

    func refreshPublicPricing() async {
        guard let publicPricingClient, !publicPricingRefreshing, shutdownTask == nil, !Task.isCancelled else { return }
        publicPricingRefreshing = true
        defer { publicPricingRefreshing = false }
        do {
            let value = try await publicPricingClient.fetch(at: now())
            guard !Task.isCancelled, shutdownTask == nil else { return }
            let age = now().timeIntervalSince(value.capturedAt)
            guard age.isFinite, age >= 0, age <= 900 else { throw PublicPricingError.invalidPricing }
            publicPricing = .available(value: value, capturedAt: value.capturedAt)
            publicPricingFailures = 0
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, shutdownTask == nil else { return }
            publicPricingFailures = min(5, publicPricingFailures + 1)
            if let value = publicPricing.value {
                publicPricing = .stale(value: value, capturedAt: value.capturedAt, reason: "Customer pricing refresh failed")
            } else {
                publicPricing = .unavailable(reason: "Customer pricing is unavailable")
            }
        }
    }

    var currentTodayEarnings: ObservedEarningsWindow? {
        guard case .available = todayEarningsReading,
              case .day = EarningsPresentationValue.calendarDay(todayEarnings, now: now(), calendar: .current) else { return nil }
        return todayEarnings
    }

    var currentWeekEarnings: CalendarWeekEarningsSummary? {
        guard case .available = weekEarningsReading,
              weekEarnings?.isCurrent(at: now(), calendar: .current) == true else { return nil }
        return weekEarnings
    }

    var displayedTodayEarnings: CalendarEarningsReading<ObservedEarningsWindow>? {
        CalendarEarningsPresentation.day(todayEarningsReading, now: now(), calendar: .current)
    }

    var displayedWeekEarnings: CalendarEarningsReading<CalendarWeekEarningsSummary>? {
        CalendarEarningsPresentation.week(weekEarningsReading, now: now(), calendar: .current)
    }

    var currentJobSummary: JobCompletionSummary? {
        guard case .available(let value, _) = jobSummary,
              value.isCurrent(at: now(), calendar: .current) else { return nil }
        return value
    }

    var currentModelTokenRateAverages: [ModelTokenRateAverage] {
        CalendarTokenRates.current(modelTokenRateAverages, at: now(), calendar: .current)
    }

    var currentDayAverageTokenRate: Double? {
        CalendarTokenRates.weightedAverage(currentModelTokenRateAverages)
    }

    func menuPresentation(mode: MenuBarDisplayMode) -> MenuBarPresentation {
        MenuBarPresentation.make(
            snapshot: snapshot,
            thermal: thermalState,
            earnings: .calendarDay(currentTodayEarnings, now: now(), calendar: .current),
            mode: mode,
            activeModelAverage: currentModelTokenRateAverages.first {
                $0.model == snapshot.state.value?.currentModel
            }?.tokensPerSecond
        )
    }

    /// Shares the same verified idle prompt with the status item and popup.
    /// The policy's timer is independent of the opt-in automatic nudge.
    var menuAttention: MenuBarAttention? {
        guard let threshold = menuAttentionThreshold,
              threshold == observedMenuAttentionThreshold else { return nil }
        return menuAttentionPolicy.attention(for: snapshot, at: now(), idleThreshold: threshold)
    }

    private var menuAttentionThreshold: TimeInterval? {
        let minutes = menuAttentionPreferences.object(forKey: MenuBarAttentionPolicy.defaultsKey) as? Int
            ?? MenuBarAttentionPolicy.defaultIdleMinutes
        return MenuBarAttentionPolicy.threshold(for: minutes)
    }

    /// The menu-bar GPU ring, composed from the shared utilization sampler
    /// and the lifecycle-owned fan status polling. Nil means "render no ring".
    func menuGPURing(
        now: Date = Date(),
        thresholds: MenuBarGPURing.Thresholds = .standard
    ) -> MenuBarGPURing? {
        switch gpuUsage.reading(at: now) {
        case .current(let percentage, let sampledAt):
            return MenuBarGPURing.make(
                utilization: percentage,
                sampledAt: sampledAt,
                fanStatus: providerExtras?.snapshot?.fanStatus,
                now: now,
                thresholds: thresholds
            )
        case .stale(let percentage, let sampledAt):
            return MenuBarGPURing.lastSample(utilization: percentage, sampledAt: sampledAt)
        case .unavailable:
            return nil
        }
    }

    func stop() async {
        financialStopping = true
        // Close the manual-refresh recording boundary before the first await.
        networkDemandRecordingStopping = true
        let networkDemandRecordingTasks = Array(networkDemandRecordingTasks.values)
        networkDemandRecordingTasks.forEach { $0.cancel() }
        for recording in networkDemandRecordingTasks { await recording.value }
        financialSessionObservationID = nil
        financialSessionTask?.cancel()
        await financialSessionTask?.value
        financialSessionTask = nil
        latestFinancialSessionRead?.cancel()
        _ = await latestFinancialSessionRead?.value
        latestFinancialSessionRead = nil
        slowdownPolicy.reset()
        servingSlowdownWarning = nil
        await hostGPUProtection?.stop()
        performanceSamplingTask?.cancel()
        await performanceSamplingTask?.value
        performanceSamplingTask = nil
        await profitSwitch?.stop()
        await inactivityNudge?.stop()
        menuAttentionPolicy.reset()
        gpuUsage.stop()
        providerExtrasTask?.cancel()
        await providerExtrasTask?.value
        providerExtrasTask = nil
        await providerExtras?.stop()
        energyTask?.cancel()
        await energyTask?.value
        energyTask = nil
        if let shutdownTask {
            await shutdownTask.value
            return
        }

        let observationTask = observationTask
        let refreshTask = refreshTask
        observationTask?.cancel()
        refreshTask?.cancel()
        earningsPollingTask?.cancel()
        networkCapacityPollingTask?.cancel()
        publicCatalogPollingTask?.cancel()
        publicPricingPollingTask?.cancel()
        networkSeriesPollingTask?.cancel()
        earningsRefreshTask?.cancel()
        if let thermalObserver {
            NotificationCenter.default.removeObserver(thermalObserver)
            self.thermalObserver = nil
        }

        let service = service
        let earningsPollingTask = earningsPollingTask
        let earningsRefreshTask = earningsRefreshTask
        let networkCapacityPollingTask = networkCapacityPollingTask
        let publicCatalogPollingTask = publicCatalogPollingTask
        let publicPricingPollingTask = publicPricingPollingTask
        let networkSeriesPollingTask = networkSeriesPollingTask
        let shutdownTask = Task {
            await service.stop()
            await observationTask?.value
            await refreshTask?.value
            await earningsPollingTask?.value
            await networkCapacityPollingTask?.value
            await publicCatalogPollingTask?.value
            await publicPricingPollingTask?.value
            await networkSeriesPollingTask?.value
            _ = await earningsRefreshTask?.value
        }
        self.shutdownTask = shutdownTask
        await shutdownTask.value
        self.observationTask = nil
        self.refreshTask = nil
        self.earningsPollingTask = nil
        self.earningsRefreshTask = nil
        self.networkCapacityPollingTask = nil
        self.publicCatalogPollingTask = nil
        self.publicPricingPollingTask = nil
        self.networkSeriesPollingTask = nil
    }

    func quit() async {
        await stop()
        NSApplication.shared.terminate(nil)
    }

    private func observeThermalState() {
        thermalState = SystemThermalState(ProcessInfo.processInfo.thermalState)
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.thermalState = SystemThermalState(ProcessInfo.processInfo.thermalState)
            }
        }
    }

    private func modelPowerActivity(at date: Date) -> ModelPowerActivity? {
        guard case .available(let state, _) = snapshot.state else { return nil }
        let age = date.timeIntervalSince(Date(timeIntervalSince1970: state.writtenAt))
        guard age.isFinite, (0...15).contains(age) else { return nil }
        if state.inferenceActive {
            guard !state.currentModel.isEmpty else { return nil }
            return ModelPowerActivity(modelID: state.currentModel, inferenceActive: true)
        }
        return ModelPowerActivity(
            modelID: nil,
            inferenceActive: false
        )
    }

    func accept(_ snapshot: TelemetrySnapshot) async {
        var peak = providerThroughputPeak
        peak.observe(snapshot, now: now())
        if peak != providerThroughputPeak { providerThroughputPeak = peak }
        // Compare with the recorded baseline before adding this observation.
        observeServingSlowdown(snapshot)
        if let state = snapshot.state.value {
            tokenRateAccumulator.record(
                snapshot.tokenRate,
                processIdentity: state.processIdentity,
                writtenAt: state.writtenAt
            )
            if tokenRateRecorder == nil {
                averageTokenRate = tokenRateAccumulator.value
            }
        }
        await refreshTokenRateAveragesIfNeeded(from: snapshot)
        let previousCurrentModel = self.snapshot.state.value?.currentModel
        let attentionThreshold = menuAttentionThreshold
        if attentionThreshold != observedMenuAttentionThreshold {
            menuAttentionPolicy.reset()
            observedMenuAttentionThreshold = attentionThreshold
        }
        if let attentionThreshold {
            menuAttentionPolicy.observe(snapshot, at: now(), idleThreshold: attentionThreshold)
        } else {
            menuAttentionPolicy.reset()
        }
        self.snapshot = snapshot
        await recordPerformanceSample()
        if hostGPUProtection?.isHoldingProvider != true {
            inactivityNudge?.observe(snapshot)
            observeProfitSwitch()
        }
        await recordOperationalAlertTransitions(from: snapshot)
        if previousCurrentModel != snapshot.state.value?.currentModel {
            await refreshRecommendation()
        }
    }

    private func refreshTokenRateAveragesIfNeeded(from snapshot: TelemetrySnapshot) async {
        guard let tokenRateRecorder else { return }
        let day = Calendar.current.startOfDay(for: snapshot.capturedAt)
        if let state = snapshot.state.value,
           case .available(let tokensPerSecond, _) = snapshot.tokenRate {
            let sample = RecordedTokenRate(processIdentity: state.processIdentity,
                                           writtenAt: state.writtenAt, model: state.currentModel,
                                           tokensPerSecond: tokensPerSecond)
            if sample != lastRecordedTokenRate {
                do {
                    let inserted = try await tokenRateRecorder.recordIfNew(
                        model: sample.model, tokensPerSecond: sample.tokensPerSecond,
                        capturedAt: snapshot.capturedAt, processIdentity: sample.processIdentity,
                        writtenAt: sample.writtenAt
                    )
                    lastRecordedTokenRate = sample
                    if inserted { tokenRateAveragesNeedRefresh = true }
                } catch {
                    // Do not remember failed writes: the same observation must
                    // be retried even when the next tick has unchanged telemetry.
                    tokenRateAveragesNeedRefresh = true
                }
            }
        }

        if tokenRateAveragesNeedRefresh || tokenRateAveragesDay != day {
            do {
                let averages = try await tokenRateRecorder.averages(from: day, through: snapshot.capturedAt)
                if modelTokenRateAverages != averages { modelTokenRateAverages = averages }
                tokenRateAveragesDay = day
                tokenRateAveragesNeedRefresh = false
            } catch {
                // Preserve the last successful read and retry on the next tick.
                tokenRateAveragesNeedRefresh = true
            }
        }

        // With no pending insertion or failed read, the cached values cover
        // this accepted snapshot too. Advance only the range metadata, never
        // sample counts or measured rates, so current-day displays stay valid.
        if !tokenRateAveragesNeedRefresh, tokenRateAveragesDay == day {
            let period = DateInterval(start: day, end: snapshot.capturedAt)
            let current = modelTokenRateAverages.map { value in
                // A recorder without a qualified period remains unqualified.
                guard value.queryPeriod?.start == day else { return value }
                return ModelTokenRateAverage(model: value.model, tokensPerSecond: value.tokensPerSecond,
                                             sampleCount: value.sampleCount, queryPeriod: period)
            }
            if modelTokenRateAverages != current { modelTokenRateAverages = current }
        }

        let rate: TokenRate
        if tokenRateAveragesDay == day {
            if let value = CalendarTokenRates.weightedAverage(modelTokenRateAverages) {
                rate = .available(tokensPerSecond: value, label: "today's average")
            } else {
                rate = .unavailable(reason: "No measured token rates today")
            }
        } else {
            rate = .unavailable(reason: "Today's measured token rates are unavailable")
        }
        if averageTokenRate != rate { averageTokenRate = rate }
    }

    func updateEnergyEarnings(using result: EnergyRecordingSnapshot, enabled: Bool, at date: Date) async {
        let state = await synchronizeFinancialSession()
        let calendar = Calendar.current
        guard let context = state.context, state.ledgerReady, enabled,
              result.issue == nil, !result.intervals.isEmpty,
              let day = calendar.dateInterval(of: .day, for: date) else {
            energyEarnings = nil
            energyEarningsDay = nil
            return
        }
        let key = EnergyActivityKey(day: day, context: context, accountCapturedAt: accountEarningsCapturedAt,
                                    activityRevision: activityRevision)
        do {
            let buckets: [ActivityBucket]
            if energyActivityKey == key, let cached = energyActivityBuckets {
                buckets = cached
            } else {
                guard let report = try await localProviderFinancialReport(context: context, in: day, unit: .hour, calendar: calendar) else {
                    if financialContext == context, key.activityRevision == activityRevision,
                       key.accountCapturedAt == accountEarningsCapturedAt { energyEarnings = nil }
                    return
                }
                buckets = report.activityBuckets()
            }
            try await validateFinancialContext(context)
            // A refresh during the suspended read invalidates this cache entry,
            // even when the account has not changed. Retry on the next sample.
            guard key.accountCapturedAt == accountEarningsCapturedAt,
                  key.activityRevision == activityRevision else { return }
            energyActivityKey = key
            energyActivityBuckets = buckets
            let value = EnergyEarnings.matching(buckets: buckets,
                energy: EnergyHistory.overlapping(result.intervals, with: day), day: day, now: date)
            if energyEarnings != value { energyEarnings = value }
            energyEarningsDay = day.start
        } catch {
            // An obsolete failure cannot clear a newer account's result.
            if financialContext == context, key.activityRevision == activityRevision,
               key.accountCapturedAt == accountEarningsCapturedAt { energyEarnings = nil }
        }
    }

    private func recordPerformanceSample() async {
        guard let performanceHistory else { return }
        let date = now()
        let gpu: Double?
        if case .current(let value, _) = gpuUsage.reading(at: date) { gpu = value }
        else { gpu = nil }
        let power = currentEnergyReading.flatMap { $0.estimated ? nil : $0.watts }
        await performanceHistory.observe(.capture(snapshot, at: date, gpuPercentage: gpu, powerWatts: power))
    }

    private func recordOperationalAlertTransitions(from snapshot: TelemetrySnapshot) async {
        guard alertHistoryRecorder != nil,
              await restoreAlertStateIfNeeded() else { return }
        pendingAlertTransitions.append(contentsOf: alertEngine.transitions(for: snapshot))
        await flushOperationalAlertTransitions()
    }

    private func restoreAlertStateIfNeeded() async -> Bool {
        guard let alertHistoryRecorder else { return false }
        if alertStateRestored { return true }
        if alertStateRestorationTask == nil {
            alertStateRestorationTask = Task {
                do {
                    async let active = alertHistoryRecorder.activeAlertCodes()
                    async let recent = alertHistoryRecorder.recentHistory(limit: 100)
                    return try await (active, recent)
                } catch {
                    return nil
                }
            }
        }
        let restorationTask = alertStateRestorationTask
        guard let restored = await restorationTask?.value else {
            alertStateRestorationTask = nil
            alertHistoryAvailable = false
            return false
        }
        alertEngine.restoreActiveAlerts(restored.0)
        alertHistory = restored.1
        alertHistoryAvailable = true
        alertStateRestored = true
        alertStateRestorationTask = nil
        return true
    }

    private func flushOperationalAlertTransitions() async {
        guard !alertPersistenceInFlight,
              let alertHistoryRecorder,
              !pendingAlertTransitions.isEmpty else { return }
        alertPersistenceInFlight = true
        defer { alertPersistenceInFlight = false }

        while !pendingAlertTransitions.isEmpty {
            let batch = pendingAlertTransitions
            do {
                try await alertHistoryRecorder.record(batch)
                pendingAlertTransitions.removeFirst(batch.count)
                if let history = try? await alertHistoryRecorder.recentHistory(limit: 100) {
                    alertHistory = history
                    alertHistoryAvailable = true
                } else {
                    alertHistoryAvailable = false
                }
                await alertNotifier?.deliver(batch)
            } catch {
                alertHistoryAvailable = false
                return
            }
        }
    }

    private func recordObservedUptime(from snapshot: TelemetrySnapshot) async {
        guard let uptimeRecorder else { return }
        do {
            observedUptime = try await uptimeRecorder.record(
                status: snapshot.menuStatus,
                at: snapshot.capturedAt
            )
        } catch {
            observedUptime = .unavailable(reason: error.localizedDescription)
        }
    }

    private func markNetworkCapacityRefreshFailed() {
        networkPollingPolicy.failed()
        switch networkCapacity {
        case .available(let value, let previousAt),
             .stale(let value, let previousAt, _):
            networkCapacity = .stale(
                value: value,
                capturedAt: previousAt,
                reason: "Network demand refresh failed"
            )
        case .unavailable:
            networkCapacity = .unavailable(reason: "Network demand is unavailable")
        }
    }

    var profitSwitchEvidenceCapturedAt: Date? {
        guard energyPreferences.bool(forKey: "electricity.enabled"),
              ElectricityCost.rate(energyPreferences.string(forKey: "electricity.usdPerKWh") ?? "") != nil,
              let sourceDate = accountEarningsCapturedAt,
              (0...900).contains(now().timeIntervalSince(sourceDate)),
              let reading = energy?.reading, energy?.issue == nil,
              (0...30).contains(now().timeIntervalSince(reading.date)),
              let calibratedAt = modelServingProfitCapturedAt else { return nil }
        return min(sourceDate, calibratedAt)
    }

    private func observeProfitSwitch() {
        guard hostGPUProtection?.isHoldingProvider != true else { return }
        profitSwitch?.observe(
            telemetry: snapshot,
            network: networkCapacity,
            profits: modelServingProfitAverages,
            profitsCapturedAt: profitSwitchEvidenceCapturedAt
        )
    }

    private func observeServingSlowdown(_ telemetry: TelemetrySnapshot) {
        let instant = now()
        let settings = hostGPUProtection?.settings ?? .init()
        if slowdownSettings != settings {
            slowdownPolicy = ServingSlowdownPolicy(thresholdRatio: settings.throughputFloorPercent / 100,
                sustainedSeconds: settings.slowdownSeconds)
            slowdownSettings = settings
        }
        let input: ServingSlowdownInput?
        if settings.mode != .off, case .available(let state, let capturedAt) = telemetry.state,
           (0...10).contains(instant.timeIntervalSince(capturedAt)),
           state.startupPreloadPendingModels?.isEmpty == true,
           state.lifecycle?.outcome == .serving, state.availability == nil,
           state.modelSwitch.map({ ![.serving, .switched].contains($0.outcome) }) != true {
            let speed: Double?
            if case .available(let value, _) = telemetry.tokenRate { speed = value }
            else { speed = nil }
            let highGPU: Bool
            if case .current(let gpu, _) = gpuUsage.reading(at: instant) {
                highGPU = gpu >= settings.ceilingPercent
            } else { highGPU = false }
            let baseline = currentModelTokenRateAverages.first { $0.model == state.currentModel }
            input = .init(modelID: state.currentModel,
                providerIdentity: "\(state.processIdentity.pid):\(state.processIdentity.startTimeMicros)",
                currentTokensPerSecond: speed, baselineTokensPerSecond: baseline?.tokensPerSecond,
                baselineSampleCount: baseline?.sampleCount ?? 0,
                capturedAt: Date(timeIntervalSince1970: state.writtenAt),
                isActiveInference: state.inferenceActive, highHostGPU: highGPU)
        } else { input = nil }
        if let report = slowdownPolicy.observe(input, at: instant) {
            servingSlowdownWarning = "Possible GPU contention · \(report.currentTokensPerSecond.formatted(.number.precision(.fractionLength(1)))) tok/s vs \(report.baselineTokensPerSecond.formatted(.number.precision(.fractionLength(1)))) recorded for this model."
            if !slowdownWasWarned {
                actionHistory?.record(action: .servingSlowdown, trigger: .automatic, outcome: .succeeded,
                    model: telemetry.state.value?.currentModel)
            }
            slowdownWasWarned = true
        } else {
            servingSlowdownWarning = nil
            slowdownWasWarned = false
        }
    }

    private static func staleOrUnavailable(
        previous: EarningsPresentationValue,
        reason: String
    ) -> EarningsPresentationValue {
        switch previous {
        case .available(let microUSD), .stale(let microUSD, _):
            .stale(microUSD: microUSD, reason: reason)
        case .observed, .day:
            .unavailable(reason: reason)
        case .unavailable:
            .unavailable(reason: reason)
        }
    }

    private static func staleOrUnavailable<Value: Equatable & Sendable>(
        previous: SourceAvailability<Value>,
        reason: String
    ) -> SourceAvailability<Value> {
        switch previous {
        case .available(let value, let capturedAt), .stale(let value, let capturedAt, _):
            .stale(value: value, capturedAt: capturedAt, reason: reason)
        case .unavailable:
            .unavailable(reason: reason)
        }
    }
}

private struct AccountRefreshState: Sendable {
    let context: AccountEarningsContext
    let requestID: UUID
    let initialSessionEpoch: UInt64
    let initialLedgerReady: Bool
    let accountCapturedAt: Date?
    let earnings: EarningsPresentationValue
    let jobSummary: SourceAvailability<JobCompletionSummary>
    let todayEarnings: SourceAvailability<ObservedEarningsWindow>
    let weekEarnings: SourceAvailability<CalendarWeekEarningsSummary>
    var freshlyReadToday: ObservedEarningsWindow? {
        if case .available(let value, _) = todayEarnings { value } else { nil }
    }
    let modelEarnings: [ModelEarnings]
    let modelWorkEarnings: [ModelWorkEarnings]
}
