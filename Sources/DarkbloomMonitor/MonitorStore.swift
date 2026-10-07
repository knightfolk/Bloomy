import AppKit
import DarkbloomTelemetry
import SwiftUI

@MainActor
final class MonitorStore: ObservableObject {
    var actionHistory: ActionHistoryStore?
    var performanceHistory: PerformanceHistoryStore?
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

    @Published private(set) var snapshot: TelemetrySnapshot
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
    private var earningsRefreshTask: Task<AccountRefreshState, Never>?
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
        menuAttentionPreferences: UserDefaults = .standard
    ) {
        self.service = service
        self.providerExtras = providerExtras
        self.gpuUsage = gpuUsage ?? SystemGPUUsageStore()
        self.energyPreferences = energyPreferences
        self.menuAttentionPreferences = menuAttentionPreferences
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
    }

    func attachRecommendationInventory(_ snapshot: @escaping @MainActor () -> ProviderControlSnapshot?) {
        recommendationControlSnapshot = snapshot
    }

    func refreshRecommendation() async {
        let input = RecommendationEvidenceAssembler.make(
            at: now(), network: networkCapacity, telemetry: snapshot,
            control: recommendationControlSnapshot?(), observedWork: modelWorkEarnings
        )
        guard let recommendationJournal else {
            recommendationDecision = RecommendationEvaluator.evaluate(input)
            recommendationHistory = []
            recommendationHistoryAvailable = false
            return
        }
        do {
            let decision = try await recommendationJournal.record(input)
            let history = try await recommendationJournal.recent(limit: 12).map(\.storedDecision)
            recommendationDecision = decision
            recommendationHistory = history
            recommendationHistoryAvailable = true
        } catch {
            recommendationDecision = RecommendationEvaluator.evaluate(input)
            recommendationHistory = []
            recommendationHistoryAvailable = false
        }
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
        let state = await earningsClient.financialSessionState()
        guard expectedContext == nil || expectedContext == state.context else { throw AccountEarningsClientError.sessionChanged }
        guard let context = state.context, state.ledgerReady else { return nil }
        do {
            let report = try await earningsClient.financialReport(context: context, providerID: nil, model: model,
                in: range, unit: unit, calendar: calendar)
            try await earningsClient.validateFinancialContext(context)
            guard report == nil || report?.accountScope == context.accountScope else { throw AccountEarningsClientError.sessionChanged }
            return report
        } catch {
            try await earningsClient.validateFinancialContext(context)
            throw error
        }
    }

    func refreshModelServingProfitability() async {
        guard energyPreferences.bool(forKey: "electricity.enabled"),
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
        let range = DateInterval(start: start, end: end)
        guard let activity = try? await earningsClient.activityByModel(
            in: range,
            unit: .hour,
            calendar: .current
        ) else {
            modelServingProfitAverages = []
            modelServingProfitCapturedAt = nil
            observeProfitSwitch()
            return
        }
        modelServingProfitAverages = ModelProfitability.servingAverages(
            activity: activity,
            energy: energy?.intervals ?? []
        )
        modelServingProfitCapturedAt = accountEarningsCapturedAt
        observeProfitSwitch()
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
        if let earningsRefreshTask {
            let refresh = await earningsRefreshTask.value
            accountEarningsCapturedAt = refresh.accountCapturedAt
            earnings = refresh.earnings
            todayEarningsReading = refresh.todayEarnings
            weekEarningsReading = refresh.weekEarnings
            modelEarnings = refresh.modelEarnings
            modelWorkEarnings = refresh.modelWorkEarnings
            earningsPerHourUSD = refresh.freshlyReadToday.flatMap {
                EarningsHourlyRate.derive(
                    microUSD: $0.microUSD,
                    observedSeconds: $0.observedSeconds
                )
            }
            jobSummary = refresh.jobSummary
            await refreshModelServingProfitability()
            return
        }

        let client = earningsClient
        let previousEarnings = earnings
        let previousJobSummary = jobSummary
        let previousModelEarnings = modelEarnings
        let previousToday = todayEarningsReading
        let previousWeek = weekEarningsReading
        let refreshedAt = now()
        let calendar = Calendar.current
        let task = Task<AccountRefreshState, Never> {
            let refreshedEarnings: EarningsPresentationValue
            do {
                let value = try await client.fetch(now: refreshedAt)
                switch value {
                case .available, .observed, .day:
                    refreshedEarnings = value
                case .stale(let microUSD, let reason):
                    refreshedEarnings = .stale(microUSD: microUSD, reason: reason)
                case .unavailable(let reason):
                    refreshedEarnings = Self.staleOrUnavailable(
                        previous: previousEarnings,
                        reason: reason
                    )
                }
            } catch {
                refreshedEarnings = Self.staleOrUnavailable(
                    previous: previousEarnings,
                    reason: error.localizedDescription
                )
            }

            let refreshedJobSummary: SourceAvailability<JobCompletionSummary>
            do {
                if let summary = try await client.jobCompletionSummary(
                    now: refreshedAt,
                    calendar: calendar
                ) {
                    refreshedJobSummary = .available(value: summary, capturedAt: refreshedAt)
                } else {
                    refreshedJobSummary = Self.staleOrUnavailable(
                        previous: previousJobSummary,
                        reason: "Local completed-job history is unavailable"
                    )
                }
            } catch {
                refreshedJobSummary = Self.staleOrUnavailable(
                    previous: previousJobSummary,
                    reason: error.localizedDescription
                )
            }
            let refreshedTodayEarnings: SourceAvailability<ObservedEarningsWindow>
            let refreshedWeekEarnings: SourceAvailability<CalendarWeekEarningsSummary>
            let refreshedModelEarnings = (try? await client.modelEarnings(
                since: refreshedAt.addingTimeInterval(-7 * 86_400)
            )) ?? previousModelEarnings
            var refreshedModelWork: [ModelWorkEarnings] = []
            switch refreshedEarnings {
            case .available, .observed, .day:
                refreshedModelWork = (try? await client.modelWorkEarnings(
                    in: DateInterval(start: calendar.startOfDay(for: refreshedAt), end: refreshedAt),
                    calendar: calendar)) ?? []
                do {
                    if let value = try await client.todayEarningsSummary(now: refreshedAt, calendar: calendar) {
                        refreshedTodayEarnings = .available(value: value, capturedAt: refreshedAt)
                    } else {
                        refreshedTodayEarnings = .unavailable(reason: "Today's observed earnings are unavailable")
                    }
                } catch {
                    refreshedTodayEarnings = Self.staleOrUnavailable(previous: previousToday,
                        reason: "Today's earnings refresh failed")
                }
                do {
                    if let value = try await client.weekEarningsSummary(now: refreshedAt, calendar: calendar) {
                        refreshedWeekEarnings = .available(value: value, capturedAt: refreshedAt)
                    } else {
                        refreshedWeekEarnings = .unavailable(reason: "This week's observed earnings are unavailable")
                    }
                } catch {
                    refreshedWeekEarnings = Self.staleOrUnavailable(previous: previousWeek,
                        reason: "This week's earnings refresh failed")
                }
            case .stale, .unavailable:
                refreshedTodayEarnings = Self.staleOrUnavailable(previous: previousToday,
                    reason: "Account earnings could not be refreshed")
                refreshedWeekEarnings = Self.staleOrUnavailable(previous: previousWeek,
                    reason: "Account earnings could not be refreshed")
            }
            let accountCapturedAt: Date?
            switch refreshedEarnings {
            case .available, .observed, .day: accountCapturedAt = refreshedAt
            case .stale, .unavailable: accountCapturedAt = nil
            }
            return AccountRefreshState(
                accountCapturedAt: accountCapturedAt,
                earnings: refreshedEarnings,
                jobSummary: refreshedJobSummary,
                todayEarnings: refreshedTodayEarnings,
                weekEarnings: refreshedWeekEarnings,
                modelEarnings: refreshedModelEarnings,
                modelWorkEarnings: refreshedModelWork
            )
        }
        earningsRefreshTask = task
        let refresh = await task.value
        accountEarningsCapturedAt = refresh.accountCapturedAt
        earnings = refresh.earnings
        todayEarningsReading = refresh.todayEarnings
        weekEarningsReading = refresh.weekEarnings
        modelEarnings = refresh.modelEarnings
        modelWorkEarnings = refresh.modelWorkEarnings
        earningsPerHourUSD = refresh.freshlyReadToday.flatMap {
            EarningsHourlyRate.derive(
                microUSD: $0.microUSD,
                observedSeconds: $0.observedSeconds
            )
        }
        jobSummary = refresh.jobSummary
        earningsRefreshTask = nil
        await refreshModelServingProfitability()
        // Invalidate local history queries even if the displayed account total
        // is unchanged: ingestion may have filled older buckets or rewards.
        activityRevision &+= 1
    }

    func setDashboardVisible(_ visible: Bool) {
        guard dashboardVisible != visible else { return }
        dashboardVisible = visible
        let previousSeries = networkSeriesPollingTask
        previousSeries?.cancel()
        if visible, hasStarted, shutdownTask == nil {
            startNetworkSeriesPolling(after: previousSeries)
        }
        // Wake a stale source on open, but never bypass failure backoff by
        // repeatedly opening the dashboard. Keep a single owned polling task.
        if visible, hasStarted, shutdownTask == nil, networkPollingPolicy.failures == 0,
           networkCapacity.value?.isFresh(at: now()) != true {
            let previous = networkCapacityPollingTask
            previous?.cancel()
            startNetworkCapacityPolling(after: previous)
        }
    }

    private func startNetworkCapacityPolling(after previous: Task<Void, Never>? = nil) {
        guard networkCapacityClient != nil else { return }
        networkCapacityPollingTask = Task { [weak self] in
            await previous?.value
            while !Task.isCancelled {
                await self?.refreshNetworkCapacity()
                guard let delay = self?.networkPollingPolicy.delay(
                    dashboardVisible: self?.dashboardVisible == true || self?.profitSwitch?.enabled == true,
                    jitter: self?.publicPollingJitter() ?? 0
                ) else { return }
                guard let sleep = self?.publicPollingSleep else { return }
                do { try await sleep(delay) }
                catch { return }
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
        guard let networkCapacityClient else { return }
        networkCapacityRefreshGeneration &+= 1
        let refreshGeneration = networkCapacityRefreshGeneration
        let capturedAt = now()
        do {
            let value = try await networkCapacityClient.fetch(at: capturedAt)
            guard !Task.isCancelled,
                  shutdownTask == nil,
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
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, shutdownTask == nil else { return }
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
        let calendar = Calendar.current
        guard enabled, result.issue == nil, !result.intervals.isEmpty,
              let day = calendar.dateInterval(of: .day, for: date) else {
            if energyEarnings != nil { energyEarnings = nil }
            return
        }
        let key = EnergyActivityKey(day: day, accountCapturedAt: accountEarningsCapturedAt,
                                    activityRevision: activityRevision)
        do {
            let buckets: [ActivityBucket]
            if energyActivityKey == key, let cached = energyActivityBuckets {
                buckets = cached
            } else {
                guard let fetched = try await earningsClient.activity(in: day, unit: .hour, calendar: calendar) else {
                    if energyEarnings != nil { energyEarnings = nil }
                    return
                }
                guard !Task.isCancelled else { return }
                energyActivityKey = key
                energyActivityBuckets = fetched
                buckets = fetched
            }
            let value = EnergyEarnings.matching(buckets: buckets,
                energy: EnergyHistory.overlapping(result.intervals, with: day), day: day, now: date)
            if energyEarnings != value { energyEarnings = value }
            energyEarningsDay = day.start
        } catch {
            // Failed activity reads do not become cache hits; retry with the
            // next fresh energy reading instead of displaying stale profit.
            if energyEarnings != nil { energyEarnings = nil }
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
