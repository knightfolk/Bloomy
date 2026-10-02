// Opt-in local native review. Every provider, account, chat, and token dependency
// below is synthetic. Never call MonitorStore.start() from this host.
import AppKit
import SwiftUI
@testable import DarkbloomTelemetry

enum FixtureScenario: String, CaseIterable, Identifiable, Sendable {
    case fresh = "Fresh", stale = "Stale", staleCatalog = "Stale catalog", offline = "Offline"
    case expiredSettings = "Expired settings", expiredHelper = "Expired helper", unavailableSettings = "Unavailable settings"
    case partialCooling = "Partial cooling", disabledHelper = "Disabled helper", unavailableRuntime = "Unavailable runtime"
    case aliasStartup = "Aliased startup", liveHosting = "Reported local endpoint"
    var id: String { rawValue }
    var hasCurrentRuntime: Bool { self != .stale && self != .offline && self != .unavailableRuntime }
    var hasStaleCatalog: Bool { self == .stale || self == .staleCatalog }
    func availability<T: Equatable & Sendable>(_ value: T, at date: Date) -> SourceAvailability<T> {
        switch self {
        case .fresh, .staleCatalog, .expiredSettings, .expiredHelper, .unavailableSettings, .partialCooling, .disabledHelper, .aliasStartup, .liveHosting:
            .available(value: value, capturedAt: date)
        case .stale: .stale(value: value, capturedAt: date, reason: "Synthetic source stopped refreshing")
        case .offline, .unavailableRuntime: .unavailable(reason: "Synthetic source unavailable")
        }
    }
}

private enum FixtureData {
    static let modelIDs = ["qwen3.8-27b", "gemma-4-26b-qat-4bit", "gpt-oss-20b", "ternary-bonsai-2-27b"]
    static let catalog = [
        CatalogModel(id: modelIDs[0], displayName: "Qwen 3.8 27B", family: "qwen", modelType: "text", capabilities: ["chat", "tools"], sizeGB: 16.3, minimumRAMGB: 36, active: true),
        CatalogModel(id: modelIDs[1], displayName: "Gemma 4 26B", family: "gemma", modelType: "text", capabilities: ["chat"], sizeGB: 15.6, minimumRAMGB: 32, active: true),
        CatalogModel(id: modelIDs[2], displayName: "GPT-OSS 20B", family: "gpt", modelType: "text", capabilities: ["chat"], sizeGB: 12.1, minimumRAMGB: 24, active: true),
        CatalogModel(id: modelIDs[3], displayName: "PrismML Bonsai 2 27B", family: "bonsai", modelType: "text", capabilities: ["chat"], sizeGB: 8.6, minimumRAMGB: 16, active: true),
        CatalogModel(id: "qwen3-8b", displayName: "Qwen 3 8B", family: "qwen", modelType: "text", capabilities: ["chat", "tools"], sizeGB: 5.2, minimumRAMGB: 12, active: true)
    ]
    static func snapshot(_ scenario: FixtureScenario, now: Date) -> TelemetrySnapshot {
        let date = scenario == .stale ? now.addingTimeInterval(-900) : now
        let state = DaemonState(schema: 1, version: "0.9.17", currentModel: scenario == .offline ? "" : modelIDs[0],
            warmModels: scenario == .offline ? [] : Array(modelIDs.prefix(2)),
            stats: ProviderStats(tokensGenerated: 126_400, requestsServed: 236, usageGaps: 0),
            trust: TrustState(level: "verified", status: scenario == .offline ? "offline" : "online",
                reason: "Synthetic review", receivedAt: date.timeIntervalSince1970),
            capacity: scenario == .offline ? nil : MemoryCapacity(totalMemoryGB: 64, gpuMemoryActiveGB: 32, gpuMemoryCacheGB: 6),
            slots: scenario == .offline ? [] : [ModelSlot(model: modelIDs[0], mtpEnabled: true, mtpActive: true,
                mtpReason: nil, kvBackend: "paged", requestedKVBackend: "paged")],
            inferenceActive: scenario.hasCurrentRuntime,
            startedAt: now.addingTimeInterval(-10_800).timeIntervalSince1970,
            writtenAt: date.timeIntervalSince1970, pid: 4242,
            processIdentity: ProcessIdentity(pid: 4242, startTimeMicros: 1_800_000_000),
            advertisedModels: scenario == .offline ? [] : Array(modelIDs.prefix(3)),
            lifecycle: ProviderLifecycleState(outcome: scenario == .offline ? .stopped : .serving,
                remainingRequests: scenario.hasCurrentRuntime ? 2 : 0, coordinatorAcknowledged: true),
            startupPreloadPendingModels: [], autopilotPhase: scenario == .offline ? nil : "shadow")
        var status = StatusSnapshot()
        status.version = "0.9.17"; status.providerName = "Synthetic review provider"
        status.hardware = "Synthetic 64 GB Mac"; status.daemon = scenario == .offline ? "Stopped" : "Running"
        status.configuredModel = modelIDs[0]; status.localModelCount = catalog.count
        status.requestCount = 236; status.tokenCount = 126_400
        let events: [LogEvent] = (0..<48).map { index in
            let eventDate = date.addingTimeInterval(Double(-index * 60))
            let severity: LogSeverity = index % 9 == 0 ? .warning : .info
            let source: LogSource = index % 2 == 0 ? .legacy : .unified
            let message = index % 9 == 0 ? "Synthetic delayed refresh; retained evidence" : "Synthetic job completed"
            return LogEvent(timestamp: eventDate, severity: severity, category: "Synthetic review",
                message: message, source: source, processID: 4242, processImage: "Fixture")
        }
        // Offline has matching current synthetic daemon and official CLI
        // stopped-status evidence; unrelated sources remain unavailable.
        let stateAvailability: SourceAvailability<DaemonState> = scenario == .offline
            ? .available(value: state, capturedAt: date) : scenario.availability(state, at: date)
        return TelemetrySnapshot(state: stateAvailability,
            loadedModels: scenario.availability(LoadedModelsState(schema: 1,
                models: Array(modelIDs.prefix(2)), updatedAt: date.timeIntervalSince1970), at: date),
            status: scenario == .offline
                ? .available(value: status, capturedAt: date) : scenario.availability(status, at: date),
            eventFeed: scenario.availability(EventFeed(events: events, legacyReadAt: date, unifiedActivityAt: date), at: date),
            tokenRate: scenario.hasCurrentRuntime ? .available(tokensPerSecond: 52.7, label: "Synthetic observed rate") : .unavailable(reason: "Synthetic inactive source"),
            diagnostics: scenario.hasCurrentRuntime ? [] : [AcquisitionDiagnostic(id: "fixture", source: "Synthetic review", message: "Synthetic source \(scenario.rawValue.lowercased())", occurredAt: now)],
            capturedAt: now, menuStatus: scenario.hasCurrentRuntime ? .online : scenario == .stale ? .stale : .offline)
    }
}

private struct FixtureTelemetrySource: TelemetrySource {
    let scenario: FixtureScenario
    func readDaemonState() async throws -> DaemonState {
        guard let value = FixtureData.snapshot(scenario, now: Date()).state.value else { throw FixtureError.offline }
        return value
    }
    func readLoadedModels() async throws -> LoadedModelsState {
        guard let value = FixtureData.snapshot(scenario, now: Date()).loadedModels.value else { throw FixtureError.offline }; return value
    }
    func readStatus() async throws -> StatusSnapshot {
        guard let value = FixtureData.snapshot(scenario, now: Date()).status.value else { throw FixtureError.offline }; return value
    }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] {
        Array((FixtureData.snapshot(scenario, now: Date()).eventFeed.value?.events ?? []).prefix(limit))
    }
}
private enum FixtureError: Error { case offline }

private struct FixtureEarnings: AccountEarningsFetching {
    let scenario: FixtureScenario
    func fetch(now: Date) async throws -> EarningsPresentationValue {
        switch scenario {
        case .fresh, .staleCatalog, .expiredSettings, .expiredHelper, .unavailableSettings, .partialCooling, .disabledHelper, .aliasStartup, .liveHosting:
            .observed(microUSD: 6_420_000, observedSeconds: 10_800)
        case .stale: .stale(microUSD: 6_420_000, reason: "Synthetic account source stale")
        case .offline, .unavailableRuntime: .unavailable(reason: "Synthetic account source unavailable")
        }
    }
    func jobCompletionSummary(now: Date, calendar: Calendar) async throws -> JobCompletionSummary? {
        guard scenario.hasCurrentRuntime else { return nil }
        return JobCompletionSummary(completedToday: 236, averagePerDay: 188, averagingDays: 7,
            dayStart: calendar.startOfDay(for: now), capturedAt: now)
    }
    func todayEarningsSummary(now: Date, calendar: Calendar) async throws -> ObservedEarningsWindow? {
        guard scenario.hasCurrentRuntime else { return nil }
        return ObservedEarningsWindow(microUSD: 6_420_000, observedSeconds: 10_800,
            calendarDayStart: calendar.startOfDay(for: now), capturedAt: now, coversDayToDate: false)
    }
    func weekEarningsSummary(now: Date, calendar: Calendar) async throws -> CalendarWeekEarningsSummary? {
        guard scenario.hasCurrentRuntime else { return nil }
        return CalendarWeekEarningsSummary(microUSD: 42_400_000, isComplete: false,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: now)?.start, capturedAt: now)
    }
    func modelEarnings(since: Date) async throws -> [ModelEarnings] {
        guard scenario.hasCurrentRuntime else { return [] }
        return FixtureData.modelIDs.prefix(3).enumerated().map { ModelEarnings(model: $0.element,
            microUSD: Int64(3_000_000 / ($0.offset + 1)), jobs: Int64(100 / ($0.offset + 1))) }
    }
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        guard scenario.hasCurrentRuntime else { return nil }
        return try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar).enumerated().map { index, interval in
            ActivityBucket(interval: interval, totals: ActivityTotals(workMicroUSD: Int64(150_000 + index % 7 * 30_000),
                rewardMicroUSD: 20_000, jobs: Int64(5 + index % 5), promptTokens: 2_000, completionTokens: 5_000), coverage: .recorded)
        }
    }
    func activityModels(in range: DateInterval) async throws -> [String] { scenario.hasCurrentRuntime ? Array(FixtureData.modelIDs.prefix(3)) : [] }
    func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]? {
        try await activity(in: range, unit: unit, calendar: calendar)
    }
}
private actor FixtureCapacity: NetworkCapacityFetching {
    let scenario: FixtureScenario
    var attempts = 0
    init(scenario: FixtureScenario) { self.scenario = scenario }
    func fetch(at capturedAt: Date) async throws -> NetworkCapacitySnapshot {
        attempts += 1
        if scenario == .offline || (scenario == .stale && attempts > 1) { throw FixtureError.offline }
        let models = FixtureData.modelIDs.enumerated().map { index, id in
            ["id": id, "ready": true, "can_accept": true, "routable_providers": 8 + index,
             "warm_providers": 4 + index, "running_providers": 9, "cold_providers": 2,
             "active_requests": 14 - index * 3, "queued_requests": index, "queue_limit": 16,
             "aggregate_tps": 420, "estimated_ttft_ms": 180, "token_budget_remaining": 8_000,
             "token_budget_total": 16_000] as [String: Any]
        }
        return try NetworkCapacityParser.parse(JSONSerialization.data(withJSONObject: ["models": models]), capturedAt: capturedAt)
    }
}
private actor FixtureCatalog: PublicCatalogFetching {
    let scenario: FixtureScenario
    private var attempts = 0
    init(scenario: FixtureScenario) { self.scenario = scenario }
    func fetch(at capturedAt: Date) async throws -> PublicCatalogSnapshot {
        attempts += 1
        if scenario == .offline || (scenario.hasStaleCatalog && attempts > 1) { throw FixtureError.offline }
        return PublicCatalogSnapshot(models: FixtureData.catalog, capturedAt: capturedAt)
    }
}
private actor FixturePricing: PublicPricingFetching {
    let scenario: FixtureScenario
    private var attempts = 0
    init(scenario: FixtureScenario) { self.scenario = scenario }
    func fetch(at capturedAt: Date) async throws -> PublicPricingSnapshot {
        attempts += 1
        if scenario == .offline || (scenario == .stale && attempts > 1) { throw FixtureError.offline }
        let prices = FixtureData.modelIDs.map { ["model": $0, "input_price": 18_000, "output_price": 90_000] as [String: Any] }
        return try PublicPricingSnapshot.parse(JSONSerialization.data(withJSONObject: ["prices": prices]), capturedAt: capturedAt)
    }
}
private actor FixtureSeries: NetworkSeriesFetching {
    let scenario: FixtureScenario
    private var attempts = 0
    init(scenario: FixtureScenario) { self.scenario = scenario }
    func fetch(at date: Date) async throws -> NetworkSeriesSnapshot {
        attempts += 1
        if scenario == .offline || (scenario == .stale && attempts > 1) { throw FixtureError.offline }
        let end = Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / 3_600) * 3_600)
        let start = end.addingTimeInterval(-86_400)
        let buckets: [NetworkSeriesBucket] = (0..<24).map { index in
            let timestamp = start.addingTimeInterval(Double(index * 3_600))
            let requests = Int64(500 + index * 12)
            let promptTokens = Int64(25_000 + index * 300)
            let completionTokens = Int64(40_000 + index * 900)
            return NetworkSeriesBucket(timestamp: timestamp, requests: requests,
                promptTokens: promptTokens, completionTokens: completionTokens)
        }
        return NetworkSeriesSnapshot(buckets: buckets, bucketSeconds: 3_600, startAt: start, endAt: end, updatedAt: date, capturedAt: date)
    }
}
private actor FixtureController: ProviderControlling {
    let scenario: FixtureScenario
    var selection = ProviderModelSelection(enabled: Array(FixtureData.modelIDs.prefix(3)), preloaded: Array(FixtureData.modelIDs.prefix(2)))
    var slots = 3
    var startupPreload: Bool? = true
    var concurrent = 4
    init(scenario: FixtureScenario) {
        self.scenario = scenario
        if scenario == .aliasStartup {
            // Use the catalog's actual unique family alias independently of
            // the exact preload selector.
            selection = ProviderModelSelection(enabled: [FixtureData.modelIDs[0], FixtureData.modelIDs[1], "gpt"],
                preloaded: ["gpt-oss-20b"])
            slots = 1
        }
    }
    func refresh() async throws -> ProviderControlSnapshot {
        let now = Date()
        // Match ProviderControlService: expired runtime evidence is omitted
        // before building inventory, never retained as current residency.
        let daemon = scenario.hasCurrentRuntime ? FixtureData.snapshot(scenario, now: now).state.value : nil
        let loadedModelIDs = scenario.hasCurrentRuntime ? Array(FixtureData.modelIDs.prefix(2)) : []
        // Bonsai and Qwen 3 8B are downloaded but neither selected nor resident.
        // Keep the three advertised models and two saved preload models intact.
        let local = FixtureData.catalog.map { LocalModel(id: $0.id, modelType: "text", sizeBytes: Int64($0.sizeGB * 1e9), estimatedMemoryGB: nil) }
        let runtimeSource: ProviderControlSourceState = scenario.hasCurrentRuntime
            ? .fresh(evidenceAt: now) : scenario == .stale
            ? .stale("Synthetic runtime source stale") : .unavailable("Synthetic source offline")
        let catalogSource: ProviderControlSourceState = scenario.hasStaleCatalog
            ? .stale("Synthetic catalog/local inventory retained") : runtimeSource
        return ProviderControlSnapshot(inventory: ModelInventoryBuilder.build(catalog: FixtureData.catalog,
            local: local, selection: selection, daemon: daemon, loadedModels: loadedModelIDs),
            draft: ProviderConfigDraft(sourceRevision: "synthetic", original: selection, selection: selection,
                originalMaxModelSlots: slots, maxModelSlots: slots,
                originalStartupPreload: startupPreload, startupPreload: startupPreload,
                originalEngineV2MaxConcurrent: concurrent, engineV2MaxConcurrent: concurrent),
            daemonState: daemon, capturedAt: now,
            sources: ProviderControlSourceStates(catalog: catalogSource, localModels: catalogSource, daemon: runtimeSource, loadedModels: runtimeSource))
    }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        selection = draft.selection; slots = draft.maxModelSlots ?? 3; concurrent = draft.engineV2MaxConcurrent ?? 4
        startupPreload = draft.startupPreload
        return ProviderConfigSaveResult(draft: try await refresh().draft, restartRequired: true)
    }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {}
    func delete(_ localModelID: String) async throws {}
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {}
}
private actor FixtureExtras: ProviderExtrasProviding {
    let scenario: FixtureScenario
    var minutes = 30
    var mtp = false
    var autoUpdate = true
    init(scenario: FixtureScenario) { self.scenario = scenario }
    func refresh() async -> ProviderExtrasSnapshot {
        let now = Date()
        let date = scenario == .stale ? now.addingTimeInterval(-900)
            : scenario == .expiredSettings ? now.addingTimeInterval(-90) : now
        if scenario == .unavailableSettings {
            return ProviderExtrasSnapshot(capturedAt: now,
                idlePolicy: .unavailable(reason: "Synthetic first read failed"),
                betaFeatures: .unavailable(reason: "Synthetic first read failed"),
                fanStatus: .unavailable(reason: "Synthetic first read failed"),
                autoUpdateStatus: .unavailable(reason: "Synthetic first read failed"))
        }
        let helperExpired = scenario == .expiredHelper || scenario == .partialCooling
        let helperDate = helperExpired ? now.addingTimeInterval(-90) : date
        let fans = (0..<(scenario == .partialCooling ? 2 : 1)).map {
            ProviderFanReading(index: $0, actualRPM: 2_200, targetRPM: 2_200, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic")
        }
        let fan = ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
            helper: ProviderFanHelperStatus(enabled: scenario != .disabledHelper, providerActive: true, mode: "automatic", chip: "Synthetic",
                gpuTemperatureCelsius: 54, triggerTemperatureCelsius: 65, releaseTemperatureCelsius: 55,
                speedPercent: 80, fans: fans, updatedAt: helperDate),
            diagnostic: ProviderFanDiagnostic(chip: "Synthetic", supported: true,
                gpuTemperatures: scenario == .expiredHelper ? [] : [ProviderFanTemperature(key: "Synthetic GPU", celsius: scenario == .partialCooling ? 42 : 54)],
                fans: scenario == .partialCooling
                    ? [ProviderFanReading(index: 0, actualRPM: nil, targetRPM: nil, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic"),
                       ProviderFanReading(index: 1, actualRPM: 1_200, targetRPM: nil, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic")]
                    : helperExpired ? [] : fans),
            helperErrorPresent: false, diagnosticErrorPresent: false)
        return ProviderExtrasSnapshot(capturedAt: date,
            idlePolicy: scenario.availability(ProviderIdlePolicy(idleTimeoutMinutes: minutes, policy: "idle_timeout", summary: "Free after \(minutes) minutes idle", pinned: false), at: date),
            betaFeatures: scenario.availability([ProviderBetaFeature(id: "mtp", title: "Multi-token prediction", state: mtp ? .on : .auto,
                enabled: mtp ? true : nil, requiresRestart: true, summary: "Synthetic setting for eligible models.")], at: date),
            fanStatus: scenario.availability(fan, at: date),
            autoUpdateStatus: scenario.availability(ProviderAutoUpdateStatus(enabled: autoUpdate), at: date))
    }
    func saveIdle(minutes: Int) async throws { self.minutes = minutes }
    func setBeta(id: String, enabled: Bool) async throws { mtp = enabled }
    func setAutoUpdate(enabled: Bool) async throws { autoUpdate = enabled }
}

// The builder injects this client into CLIUpdateStatusStore.shared in a staged
// source copy: the production update view remains unchanged.
struct FixtureCLIUpdates: CLIUpdateProviding {
    func checkForUpdate() async -> SourceAvailability<CLIUpdateStatus> {
        .available(value: .upToDate(version: "0.9.17"), capturedAt: Date())
    }
}
// The production Infrastructure disclosure starts NetworkCacheStore polling.
// Its staged default client must also be inert before any fixture launch.
struct FixtureNetworkCache: NetworkCacheFetching {
    func fetch(at capturedAt: Date) async throws -> NetworkCacheSnapshot {
        NetworkCacheSnapshot(routingMode: .shadow, plannerEnabled: true,
            plannerRunning: true, plannerReady: true, capturedAt: capturedAt)
    }
}
private struct FixtureEndpoint: LocalEndpointFetching {
    var reportsEndpoint = false
    func fetch() async -> LocalEndpointAvailability {
        if reportsEndpoint {
            return .live(LocalEndpointRecord(baseURL: "http://127.0.0.1:8123/v1", apiKey: "",
                host: "127.0.0.1", port: 8123, processID: 4242, version: "Synthetic fixture", updatedAt: Date()))
        }
        return .none("Synthetic endpoint; no real server")
    }
}
private final class FixtureTokens: ConsumerKeyManaging, LocalEndpointTokenManaging, @unchecked Sendable {
    private let lock = NSLock()
    private var consumer: String?
    private var bearer: String?
    var hasKey: Bool { lock.withLock { consumer != nil } }
    func store(_ key: String) throws { lock.withLock { consumer = key } }
    func remove() { lock.withLock { consumer = nil } }
    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? {
        guard let value = lock.withLock({ consumer }) else { return nil }; return try body(value)
    }
    func saveBearerToken(_ token: String) throws { lock.withLock { bearer = token } }
    func withBearerToken(_ action: (String) -> Void) -> Bool {
        guard let value = lock.withLock({ bearer }) else { return false }; action(value); return true
    }
}
private struct FixtureChat: LocalChatRouteClient, NetworkChatRouteClient {
    let scenario: FixtureScenario
    func models(now: Date) async throws -> ChatModelListSnapshot {
        if !scenario.hasCurrentRuntime { throw FixtureError.offline }
        return ChatModelListSnapshot(modelIDs: FixtureData.modelIDs, capturedAt: now)
    }
    func complete(model: String, messages: [ChatMessagePayload]) async throws -> ChatCompletionOutcome {
        if !scenario.hasCurrentRuntime { throw FixtureError.offline }
        return ChatCompletionOutcome(content: "Synthetic reply — no model was called. This review conversation lives only in fixture memory.", model: model,
            finishReason: "stop", promptTokens: 12, completionTokens: 22)
    }
}

private enum FixturePopupHeightBudget: String, CaseIterable, Identifiable {
    case screen = "Screen"
    case compact = "360 pt"
    case short = "240 pt"
    case tiny = "80 pt"
    var id: String { rawValue }
    var maximumHeight: CGFloat? {
        switch self {
        case .screen: nil
        case .compact: 360
        case .short: 240
        case .tiny: 80
        }
    }
}

private enum FixtureChatVerification: String, CaseIterable, Identifiable, Sendable {
    case fresh = "Fresh verification"
    case expiring = "Verification expires in 10 s"
    case expired = "Verification already expired"
    case failed = "Verification fails"
    case empty = "Empty model list"
    var id: String { rawValue }
}

// A new test chat gets a new client/snapshot. Backdating an existing store's
// read would correctly lose to its newer accepted sample. Only the first read
// aged read is controlled: the production Refresh button recovers with a current
// list. Failure/empty modes remain explicit until Next verification read changes
// them, so a repeated failure cannot look like a successful refresh.
// There is no fixture expiry timer or repeated chat-state publication.
private actor FixtureChatVerificationClient: LocalChatRouteClient {
    private var verification: FixtureChatVerification
    private var reads = 0
    init(_ verification: FixtureChatVerification) { self.verification = verification }
    func setVerification(_ value: FixtureChatVerification) {
        verification = value
        reads = 0
    }
    func models(now: Date) async throws -> ChatModelListSnapshot {
        reads += 1
        if verification == .failed { throw FixtureError.offline }
        if verification == .empty { return ChatModelListSnapshot(modelIDs: [], capturedAt: now) }
        if reads == 1 {
            switch verification {
            case .fresh: break
            case .expiring:
                return ChatModelListSnapshot(modelIDs: FixtureData.modelIDs,
                    capturedAt: now.addingTimeInterval(-110))
            case .expired:
                return ChatModelListSnapshot(modelIDs: FixtureData.modelIDs,
                    capturedAt: now.addingTimeInterval(-121))
            case .failed, .empty: break
            }
        }
        return ChatModelListSnapshot(modelIDs: FixtureData.modelIDs, capturedAt: now)
    }
    func complete(model: String, messages: [ChatMessagePayload]) async throws -> ChatCompletionOutcome {
        ChatCompletionOutcome(content: "Synthetic reply — no model was called. This review conversation lives only in fixture memory.",
            model: model, finishReason: "stop", promptTokens: 12, completionTokens: 22)
    }
}
private struct FixtureBalance: ConsumerBalanceFetching {
    func fetch(now: Date) async throws -> ConsumerBalanceSnapshot { ConsumerBalanceSnapshot(balanceMicroUSD: 2_400_000, capturedAt: now) }
}

@MainActor
private final class FixtureModel: ObservableObject {
    let defaults: UserDefaults
    let directory: URL
    let focusDiagnostics: FixtureFocusDiagnostics
    let navigation: DashboardNavigation
    let settingsDraft = ProviderSettingsDraftState()
    let chatDraft = ChatDraftState()
    let popupSettingsDraft = ProviderSettingsDraftState()
    let updateProtection = AppUpdateEditorProtection()
    let hostingDraft: HostingSettingsDraftState
    var presentDashboard: ((DashboardDestination?, SettingsPage?) -> Void)?
    var presentMenuBarPopup: (() -> Void)?
    lazy var popup = FixturePopoverController(model: self)
    @Published var monitor: MonitorStore
    @Published var control: ProviderControlStore
    @Published var hosting: HostingSettingsStore
    @Published var chat: ChatStore
    @Published var ready = false
    @Published var issue: String?
    @Published var scenario: FixtureScenario = .fresh
    @Published var focusTracing: Bool
    @Published var staticActivity = false
    @Published var grayscale = false
    @Published var popupHeightBudget: FixturePopupHeightBudget = .screen
    @Published private(set) var nativeProofStatus = "Native proof"
    private var nativeProofTask: Task<Void, Never>?
    @Published private(set) var chatVerificationTest: FixtureChatVerification?
    private var chatVerificationClient: FixtureChatVerificationClient?
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0
    private var isTerminating = false
    private var dashboardVisible = true

    init() {
        let suite = "dev.darkbloom.dashboard-fixture.session.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.set("light", forKey: ApplicationAppearance.defaultsKey)
        // Deliberately unsupported review-only value: the picker must display
        // the policy's effective five-minute fallback until an explicit choice.
        defaults.set(99, forKey: MenuBarAttentionPolicy.defaultsKey)
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyDashboardFixture-\(UUID().uuidString)", isDirectory: true)
        focusDiagnostics = FixtureFocusDiagnostics(directory: directory)
        focusTracing = focusDiagnostics.isEnabled
        navigation = DashboardNavigation(defaults: defaults)
        let stores = Self.makeStores(.fresh, defaults: defaults, directory: directory)
        monitor = stores.0; control = stores.1; hosting = stores.2; chat = stores.3
        hostingDraft = HostingSettingsDraftState(options: stores.2.options)
    }
    private static func makeStores(_ scenario: FixtureScenario, defaults: UserDefaults, directory: URL) -> (MonitorStore, ProviderControlStore, HostingSettingsStore, ChatStore) {
        let tokens = FixtureTokens()
        let controller = FixtureController(scenario: scenario)
        let control = ProviderControlStore(controller: controller, homeDirectory: directory, hostingOptions: { .default })
        let extras = ProviderExtrasStore(client: FixtureExtras(scenario: scenario))
        let monitor = MonitorStore(service: TelemetryService(source: FixtureTelemetrySource(scenario: scenario)),
            initial: FixtureData.snapshot(scenario, now: Date()), providerExtras: extras,
            earningsClient: FixtureEarnings(scenario: scenario),
            networkCapacityClient: FixtureCapacity(scenario: scenario), publicCatalogClient: FixtureCatalog(scenario: scenario),
            publicPricingClient: FixturePricing(scenario: scenario), networkSeriesClient: FixtureSeries(scenario: scenario),
            energyPreferences: defaults, energyRecorder: EnergyRecorder(file: directory.appendingPathComponent("energy.json"), readPower: { _ in nil }),
            gpuUsage: SystemGPUUsageStore(read: { nil }), menuAttentionPreferences: defaults)
        monitor.inactivityNudge = InactivityNudgeStore(keyStore: tokens, defaults: defaults,
            evidence: { _ in .unavailable }, canAct: { false }, send: { _, _ in nil })
        monitor.profitSwitch = ProfitSwitchStore(control: control, defaults: defaults, installedMemoryGB: 64, availableMemoryGB: { 24 })
        if scenario == .liveHosting {
            defaults.set(HostingEndpointMode.standalone.rawValue, forKey: HostingSettingsStore.modeKey)
        }
        let hosting = HostingSettingsStore(controlStore: control, endpointClient: FixtureEndpoint(reportsEndpoint: scenario == .liveHosting), tokenFile: tokens,
            cliVersionProvider: { scenario == .offline ? nil : "0.9.17" }, defaults: defaults,
            lanScanner: { ["192.168.50.20"] }, copyToken: { _ in true }, copyCommand: { _ in true })
        let chat = ChatStore(localClient: FixtureChat(scenario: scenario), networkClient: FixtureChat(scenario: scenario),
            balanceClient: FixtureBalance(), pricingClient: FixturePricing(scenario: scenario), keyStore: tokens)
        monitor.attachRecommendationInventory { control.snapshot }
        monitor.setDashboardVisible(true)
        hosting.refreshEnvironment()
        return (monitor, control, hosting, chat)
    }
    func tick() async {
        guard ready, !isTerminating, scenario.hasCurrentRuntime || scenario == .offline else { return }
        let currentScenario = scenario
        let currentMonitor = monitor
        let currentControl = control
        await currentMonitor.accept(FixtureData.snapshot(currentScenario, now: Date()))
        await currentControl.refreshPreservingDraft()
    }
    func setDashboardVisible(_ visible: Bool) {
        dashboardVisible = visible
        monitor.setDashboardVisible(visible)
    }
    func startVerificationChat(_ verification: FixtureChatVerification) {
        guard ready, !isTerminating, scenario.hasCurrentRuntime, !chat.isSending else { return }
        let client = FixtureChatVerificationClient(verification)
        let replacement = ChatStore(localClient: client,
            networkClient: FixtureChat(scenario: scenario), balanceClient: FixtureBalance(),
            pricingClient: FixturePricing(scenario: scenario), keyStore: FixtureTokens())
        // Explicit menu action starts a genuinely new, empty local chat.
        // Nothing migrates from the previous conversation or credential store.
        replacement.startConversation(route: .local)
        chat = replacement
        chatVerificationClient = client
        chatVerificationTest = verification
        navigation.selected = .chat
        navigation.revealSelectedSection()
    }
    func setNextVerificationRead(_ verification: FixtureChatVerification) async {
        guard ready, !isTerminating, let client = chatVerificationClient, !chat.isSending else { return }
        let generation = loadGeneration
        await client.setVerification(verification)
        guard generation == loadGeneration, !isTerminating else { return }
        chatVerificationTest = verification
    }
    func load() async {
        guard !isTerminating else { return }
        let requestedScenario = scenario
        loadGeneration += 1
        let generation = loadGeneration
        ready = false; issue = nil
        let previous = loadTask
        previous?.cancel()
        // Join previous preparation before another task can seed the same
        // history. Only the current request may publish prepared stores.
        let task = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, !Task.isCancelled, generation == self.loadGeneration else { return }
            await self.prepare(requestedScenario, generation: generation)
        }
        loadTask = task
        await task.value
        if generation == loadGeneration { loadTask = nil }
    }
    private func prepare(_ requestedScenario: FixtureScenario, generation: Int) async {
        await popup.closeAndWait(resetContent: true)
        guard !Task.isCancelled, generation == loadGeneration else { return }
        let stores = Self.makeStores(requestedScenario, defaults: defaults, directory: directory)
        let preparedMonitor = stores.0
        let preparedControl = stores.1
        var preparationIssue: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let performanceURL = directory.appendingPathComponent("performance-\(requestedScenario.id).sqlite")
            let seedPerformance = !FileManager.default.fileExists(atPath: performanceURL.path)
            let database = try PerformanceHistoryDatabase(url: performanceURL)
            let now = Date()
            for index in 0..<(seedPerformance ? 360 : 0) {
                let date = now.addingTimeInterval(Double(index - 359) * 30)
                // A bounded 90-second Bonsai visit: switch in at sample 356,
                // remain singly resident/idle with flat counters through 358,
                // switch back to Gemma at 359 without a counter increment.
                // Other single-model visits contain active work and stale gaps.
                let idleVisit = (356..<359).contains(index)
                let idleBoundary = index == 359
                let modelIndex = idleVisit ? 3 : index < 180 ? 0 : 1
                let modelID = FixtureData.modelIDs[modelIndex]
                let active = !idleVisit && !idleBoundary && index % 12 != 0
                let counterIndex = min(index, 355)
                try database.record(PerformanceSample(observedAt: date, sourceCapturedAt: date,
                    quality: index % 80 == 0 ? .stale : .current, providerSession: "4242:1800",
                    model: modelID, residentModels: [modelID],
                    advertisedModels: Array(FixtureData.modelIDs.prefix(3)), inferenceActive: active,
                    activeRequests: active ? 2 : 0, tokensPerSecond: active ? 40 + Double(index % 20) : 0,
                    tokensGenerated: Int64(counterIndex * 300), requestsServed: Int64(counterIndex / 3),
                    gpuUtilizationPercent: Double(35 + index % 45), gpuMemoryGB: 32, powerWatts: 75 + Double(index % 20), autopilotPhase: index % 90 < 8 ? "waiting_inventory" : "shadow"))
            }
            preparedMonitor.performanceHistory = PerformanceHistoryStore(url: performanceURL)
            let history = ActionHistoryStore(url: directory.appendingPathComponent("actions-\(requestedScenario.id).sqlite"))
            if history.events.isEmpty {
                for index in 0..<48 {
                    history.record(action: index % 3 == 0 ? .swap : .saveSettings, trigger: .manual,
                        outcome: index % 9 == 0 ? .failed : .succeeded, model: FixtureData.modelIDs[index % 3],
                        reason: index % 9 == 0 ? .notConfirmed : .completed)
                }
            }
            preparedMonitor.actionHistory = history; preparedControl.actionHistory = history
            await preparedControl.refresh(); await preparedMonitor.providerExtras?.refresh()
            await preparedMonitor.refreshEarnings(); await preparedMonitor.refreshPublicCatalog(); await preparedMonitor.refreshPublicPricing()
            if requestedScenario != .offline { await preparedMonitor.refreshNetworkCapacity(); await preparedMonitor.refreshNetworkSeries() }
            if requestedScenario == .stale {
                await preparedMonitor.refreshNetworkCapacity(); await preparedMonitor.refreshNetworkSeries()
                await preparedMonitor.refreshPublicPricing()
            }
            if requestedScenario.hasStaleCatalog { await preparedMonitor.refreshPublicCatalog() }
            await preparedMonitor.refreshRecommendation()
        } catch { preparationIssue = "Synthetic history preparation failed: \(error.localizedDescription)" }
        guard !Task.isCancelled, generation == loadGeneration, !isTerminating else {
            await preparedMonitor.stop()
            return
        }
        // Window events can arrive while synthetic sources are preparing.
        // Publish the replacement with the latest native visibility state.
        preparedMonitor.setDashboardVisible(dashboardVisible)
        monitor = preparedMonitor; control = preparedControl; hosting = stores.2; chat = stores.3
        chatVerificationTest = nil
        chatVerificationClient = nil
        issue = preparationIssue
        ready = true
    }
    func runNativeProof() {
        guard nativeProofTask == nil, ready, !isTerminating else { return }
        nativeProofStatus = "Proof running…"
        nativeProofTask = Task { @MainActor in
            let motion = await MenuBarMotionProof.run(outputDirectory: self.directory)
            let models = await ModelManagerAccessibilityProof.run(outputDirectory: self.directory)
            let charts = await ChartAccessibilityProof.run(outputDirectory: self.directory)
            let passed = motion && models["success"] as? Bool == true && charts
            let result: [String: Any] = ["synthetic": true, "terminal": "completed", "passed": passed,
                "motion": motion, "models": models["success"] as? Bool == true, "charts": charts]
            do {
                let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: self.directory.appendingPathComponent("native-proof-result.json"), options: .atomic)
                self.nativeProofStatus = passed ? "Proof passed" : "Proof failed"
            } catch {
                self.nativeProofStatus = "Proof write failed"
                FileHandle.standardError.write(Data("Fixture native proof result write failed.\n".utf8))
            }
            self.nativeProofTask = nil
        }
    }

    func stopForTermination() async {
        isTerminating = true
        setDashboardVisible(false)
        ready = false
        loadGeneration += 1
        let loading = loadTask
        loading?.cancel()
        await loading?.value
        loadTask = nil
        let proof = nativeProofTask
        proof?.cancel()
        await proof?.value
        nativeProofTask = nil
        await popup.closeAndWait(resetContent: true)
        await monitor.stop()
    }
}

@MainActor
private final class FixturePopoverController: NSObject, NSPopoverDelegate {
    private weak var model: FixtureModel?
    private let popover = NSPopover()
    private let visibility = PopoverVisibility()
    private var hostedMonitor: MonitorStore?
    private var fanExtras: ProviderExtrasStore?
    private var fanToken: UUID?
    private var fanCancellations: [UUID: Task<Void, Never>] = [:]
    private var isClosing = false
    private var closeWaiters: [CheckedContinuation<Void, Never>] = []
    private var geometryRecords = 0

    init(model: FixtureModel) {
        self.model = model
        super.init()
        popover.behavior = .transient
        popover.delegate = self
    }

    func show(from button: NSView) {
        guard let model, model.ready, !isClosing else { return }
        if popover.isShown {
            isClosing = true
            popover.performClose(button)
            return
        }
        if popover.contentViewController == nil {
            hostedMonitor = model.monitor
            let content = FixturePopoverContent(model: model, store: model.monitor, control: model.control,
                visibility: visibility, defaults: model.defaults,
                openSettings: { [weak self] page in self?.navigate(.settings, settingsPage: page) },
                openDashboard: { [weak self] in self?.navigate() },
                openModels: { [weak self] in self?.navigate(.models) },
                openHosting: { [weak self] in self?.navigate(.hosting) },
                updateProtection: model.updateProtection, popupSettingsDraft: model.popupSettingsDraft)
            let contentController = FittingPopoverHostingController(rootView: content, popover: popover)
            popover.contentViewController = contentController
            contentController.view.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(contentFrameChanged),
                name: NSView.frameDidChangeNotification, object: contentController.view)
            contentController.prepareForPresentation()
        }
        let control = model.control
        Task { @MainActor [weak control] in await control?.refreshPreservingDraft() }
        (popover.contentViewController as? FittingPopoverHostingController<FixturePopoverContent>)?
            .prepareForPresentation(anchorView: button, maximumContentHeight: model.popupHeightBudget.maximumHeight)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverWillShow(_ notification: Notification) {
        if fanToken == nil {
            fanExtras = hostedMonitor?.providerExtras
            fanToken = fanExtras?.beginVisibleFanObservation()
        }
        visibility.setVisible(true)
    }

    func popoverDidShow(_ notification: Notification) {
        captureGeometry(phase: "popover.didShow")
    }

    @objc private func contentFrameChanged(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.popover.isShown else { return }
            self.captureGeometry(phase: "popover.contentFrameChanged")
        }
    }

    private func captureGeometry(phase: String) {
        guard let model, model.focusTracing, model.ready, geometryRecords < 6,
              let view = popover.contentViewController?.view, let window = view.window else { return }
        view.layoutSubtreeIfNeeded()
        let contentScreenRect = window.convertToScreen(view.convert(view.bounds, to: nil))
        let values: [String: Any] = [
            "schema": 1, "phase": phase,
            "reviewHeightBudget": model.popupHeightBudget.rawValue,
            "popoverContentSize": NSStringFromSize(popover.contentSize),
            "hostingFrame": NSStringFromRect(view.frame),
            "hostingBounds": NSStringFromRect(view.bounds),
            "hostingFittingSize": NSStringFromSize(view.fittingSize),
            "windowFrame": NSStringFromRect(window.frame),
            "contentScreenRect": NSStringFromRect(contentScreenRect),
            "screenVisibleFrame": window.screen.map { NSStringFromRect($0.visibleFrame) } ?? "nil",
            "contentFitsScreen": window.screen?.visibleFrame.contains(contentScreenRect) ?? false
        ]
        guard var data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]) else { return }
        geometryRecords += 1
        data.append(0x0A)
        let output = model.directory.appendingPathComponent("popup-geometry.jsonl")
        do {
            if !FileManager.default.fileExists(atPath: output.path) {
                try data.write(to: output, options: .atomic)
            } else {
                let file = try FileHandle(forWritingTo: output)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: data)
            }
        } catch {
            FileHandle.standardError.write(Data("Fixture popup geometry diagnostic write failed.\n".utf8))
        }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func popoverWillClose(_ notification: Notification) {
        isClosing = true
        endObservation()
    }

    func popoverDidClose(_ notification: Notification) {
        endObservation()
        isClosing = false
        let waiters = closeWaiters
        closeWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func closeNativePopover() async {
        guard popover.isShown || isClosing else { return }
        await withCheckedContinuation { continuation in
            // Register before requesting closure: AppKit may notify synchronously.
            closeWaiters.append(continuation)
            if !isClosing {
                isClosing = true
                popover.performClose(nil)
            }
        }
    }

    private func endObservation() {
        visibility.setVisible(false)
        guard let token = fanToken else { return }
        fanToken = nil
        if let cancelled = fanExtras?.endVisibleFanObservation(token) {
            let id = UUID()
            fanCancellations[id] = cancelled
            // Retain every reader until its join finishes, then release it.
            Task { @MainActor [weak self] in
                await cancelled.value
                self?.fanCancellations.removeValue(forKey: id)
            }
        }
        fanExtras = nil
    }

    func closeAndWait(resetContent: Bool = false) async {
        repeat {
            await closeNativePopover()
            endObservation()
            let pending = fanCancellations
            for (id, cancellation) in pending {
                await cancellation.value
                fanCancellations.removeValue(forKey: id)
            }
            // Reopening while readers are joined requires another native close.
            // Each close awaits its delegate event, leaving AppKit free to finish.
        } while popover.isShown || isClosing || !fanCancellations.isEmpty
        if resetContent {
            if let view = popover.contentViewController?.view {
                NotificationCenter.default.removeObserver(self, name: NSView.frameDidChangeNotification, object: view)
            }
            popover.contentViewController = nil
            hostedMonitor = nil
        }
    }

    private func navigate(_ destination: DashboardDestination? = nil, settingsPage: SettingsPage? = nil) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            await closeAndWait()
            guard let model else { return }
            model.presentDashboard?(destination, settingsPage)
        }
    }
}

private struct FixturePopoverContent: View {
    @ObservedObject var model: FixtureModel
    @ObservedObject var store: MonitorStore
    let control: ProviderControlStore
    @ObservedObject var visibility: PopoverVisibility
    let defaults: UserDefaults
    @AppStorage private var appearance: String
    let openSettings: (SettingsPage?) -> Void
    let openDashboard: () -> Void
    let openModels: () -> Void
    let openHosting: () -> Void
    let updateProtection: AppUpdateEditorProtection
    let popupSettingsDraft: ProviderSettingsDraftState

    init(model: FixtureModel, store: MonitorStore, control: ProviderControlStore, visibility: PopoverVisibility,
         defaults: UserDefaults, openSettings: @escaping (SettingsPage?) -> Void,
         openDashboard: @escaping () -> Void, openModels: @escaping () -> Void,
         openHosting: @escaping () -> Void, updateProtection: AppUpdateEditorProtection,
         popupSettingsDraft: ProviderSettingsDraftState) {
        self.model = model; self.store = store; self.control = control; self.visibility = visibility
        self.defaults = defaults
        _appearance = AppStorage(wrappedValue: "light", ApplicationAppearance.defaultsKey, store: defaults)
        self.openSettings = openSettings; self.openDashboard = openDashboard
        self.openModels = openModels; self.openHosting = openHosting
        self.updateProtection = updateProtection; self.popupSettingsDraft = popupSettingsDraft
    }

    var body: some View {
        MonitorPopover(store: store, isVisible: visibility.isVisible,
            ownsVisibleFanPolling: false, openSettings: openSettings,
            openDashboard: openDashboard, openModels: openModels, openHosting: openHosting,
            updateProtection: updateProtection, popupSettingsDraft: popupSettingsDraft)
            .environmentObject(control)
            .defaultAppStorage(defaults)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .saturation(model.grayscale ? 0 : 1)
    }
}

private struct FixturePopupButton: NSViewRepresentable {
    let show: () -> Void
    let enabled: Bool
    func makeCoordinator() -> Coordinator { Coordinator(show: show) }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Popup", target: context.coordinator, action: #selector(Coordinator.show(_:)))
        button.bezelStyle = .rounded
        button.setAccessibilityLabel("Open synthetic native popup")
        button.setAccessibilityIdentifier("fixture.popup.open")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        button.isEnabled = enabled
        context.coordinator.showPopup = show
    }
    @MainActor
    final class Coordinator: NSObject {
        var showPopup: () -> Void
        init(show: @escaping () -> Void) { showPopup = show }
        @objc func show(_ sender: NSButton) { showPopup() }
    }
}

/// Only this inert review app owns the item. Its genuine menu-bar anchor avoids
/// measuring a popup clipped by an unrelated dashboard banner button.
@MainActor
private final class FixtureStatusItemController: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: StatusItemController.itemWidth)
    private weak var model: FixtureModel?

    init(model: FixtureModel) {
        self.model = model
        super.init()
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(showPopup)
        button.sendAction(on: [.leftMouseUp])
        button.setAccessibilityLabel("Bloomy synthetic menu-bar review")
        button.setAccessibilityIdentifier("fixture.menu-bar")
        let host = FixtureStatusHostingView(rootView: FixtureMenuBarRoot(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            host.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            host.topAnchor.constraint(equalTo: button.topAnchor),
            host.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
    }

    @objc func showPopup() {
        guard let model, let button = item.button else { return }
        model.popup.show(from: button)
    }

    func invalidate() {
        item.button?.subviews.forEach { $0.removeFromSuperview() }
        NSStatusBar.system.removeStatusItem(item)
    }
}

private final class FixtureStatusHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct FixtureMenuBarRoot: View {
    @ObservedObject var model: FixtureModel

    var body: some View {
        // Scenario changes replace the stores; bind to the current fake one.
        FixtureMenuBarContent(model: model, store: model.monitor)
    }
}

private struct FixtureMenuBarContent: View {
    @ObservedObject var model: FixtureModel
    @ObservedObject var store: MonitorStore

    var body: some View {
        if let extras = store.providerExtras {
            FixtureExtrasMenuBarContent(model: model, store: store, extras: extras)
        } else {
            FixtureMenuBarLabel(model: model, store: store, fanStatus: nil)
        }
    }
}

private struct FixtureExtrasMenuBarContent: View {
    let model: FixtureModel
    let store: MonitorStore
    @ObservedObject var extras: ProviderExtrasStore

    var body: some View {
        FixtureMenuBarLabel(model: model, store: store, fanStatus: extras.snapshot?.fanStatus)
    }
}

private struct FixtureMenuBarLabel: View {
    @ObservedObject var model: FixtureModel
    @ObservedObject var store: MonitorStore
    let fanStatus: SourceAvailability<ProviderFanStatus>?
    @State private var freshnessCheckedAt = Date()

    var body: some View {
        let now = max(Date(), freshnessCheckedAt)
        let values = MenuBarIndicators.make(snapshot: store.snapshot,
            utilization: nil, sampledAt: nil, fanStatus: fanStatus, now: now)
        MenuBarLabel(presentation: store.menuPresentation(mode: .statusOnly),
            uptime: store.observedUptime,
            family: MenuBarIndicators.modelFamily(snapshot: store.snapshot, now: now),
            indicators: values, forceStationaryActivity: model.staticActivity)
            .saturation(model.grayscale ? 0 : 1)
            .background(FixtureMenuBarMotionCapture(enabled: model.focusTracing && model.ready,
                stationary: model.staticActivity,
                outputURL: model.directory.appendingPathComponent("menu-bar-motion.jsonl")))
            .task(id: values.nextFreshnessChange) {
                guard let deadline = values.nextFreshnessChange else { return }
                do { try await Task.sleep(for: .seconds(max(0.01, deadline.timeIntervalSinceNow))) }
                catch { return }
                freshnessCheckedAt = Date()
            }
    }
}

/// Opt-in, bounded evidence from this fixture's own status item. It reads the
/// actual native layer after a render and does not add a sampling clock.
private struct FixtureMenuBarMotionCapture: NSViewRepresentable {
    let enabled: Bool
    let stationary: Bool
    let outputURL: URL

    func makeNSView(context: Context) -> NSView { NSView() }
    func makeCoordinator() -> Coordinator { Coordinator() }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.revision += 1
        let revision = coordinator.revision
        guard enabled else { return }
        DispatchQueue.main.async {
            guard coordinator.revision == revision else { return }
            guard let window = view.window else { return }
            var ancestor: NSView? = view
            while let current = ancestor, !(current is NSStatusBarButton) { ancestor = current.superview }
            guard let button = ancestor as? NSStatusBarButton else { return }
            @MainActor func findArc(_ root: NSView) -> MenuBarActivityArc.ActivityArcView? {
                if let arc = root as? MenuBarActivityArc.ActivityArcView { return arc }
                for child in root.subviews {
                    if let arc = findArc(child) { return arc }
                }
                return nil
            }
            guard let arc = findArc(button), let layer = arc.layer?.sublayers?.first else { return }
            coordinator.record([
                "schema": 1,
                "stationaryRequested": stationary,
                "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                "windowVisible": window.isVisible,
                "windowOccluded": !window.occlusionState.contains(.visible),
                "viewHidden": arc.isHiddenOrHasHiddenAncestor,
                "activeArcVisible": !layer.isHidden,
                "rotationInstalled": layer.animation(forKey: "inferenceRotation") != nil
            ], to: outputURL)
        }
    }

    @MainActor
    final class Coordinator {
        var revision = 0
        private var lastRecord: Data?
        private var recordCount = 0

        func record(_ values: [String: Any], to url: URL) {
            guard recordCount < 48,
                  var data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
                  data != lastRecord else { return }
            let record = data
            data.append(0x0A)
            do {
                if !FileManager.default.fileExists(atPath: url.path) {
                    try data.write(to: url, options: .atomic)
                } else {
                    let file = try FileHandle(forWritingTo: url)
                    defer { try? file.close() }
                    try file.seekToEnd()
                    try file.write(contentsOf: data)
                }
                lastRecord = record
                recordCount += 1
            } catch {
                FileHandle.standardError.write(Data("Fixture motion diagnostic write failed.\n".utf8))
            }
        }
    }
}

// Read-only, opt-in AppKit evidence. No key events are consumed or synthesized,
// no focus/key-view policy is changed, and no control text/value is recorded.
@MainActor
private final class FixtureFocusDiagnostics {
    var isEnabled = CommandLine.arguments.contains("--focus-diagnostics")
    let outputURL: URL
    private var capturedReady = false
    private var navigationKeys = 0
    private var capturedRecords = 0
    private let maximumRecords = 49
    private let maximumNavigationKeys = 24
    private let maximumViews = 384
    private let maximumLoopLength = 64

    init(directory: URL) {
        outputURL = directory.appendingPathComponent("focus-diagnostics.jsonl")
    }

    func captureReady(_ window: NSWindow) {
        guard isEnabled, !capturedReady else { return }
        capturedReady = true
        capture(window, phase: "ready")
    }

    func begin(_ event: NSEvent, window: NSWindow) -> Int? {
        guard isEnabled, capturedReady, event.type == .keyDown,
              [48, 49, 123, 124, 125, 126].contains(Int(event.keyCode)),
              navigationKeys < maximumNavigationKeys,
              capturedRecords < maximumRecords else { return nil }
        navigationKeys += 1
        capture(window, phase: "before", eventNumber: navigationKeys)
        return navigationKeys
    }

    func end(window: NSWindow, eventNumber: Int) {
        capture(window, phase: "after", eventNumber: eventNumber)
    }

    func captureWindowState(_ window: NSWindow, phase: String) {
        // Preparation creates the isolated output directory before ready.
        guard capturedReady else { return }
        capture(window, phase: phase)
    }

    private func capture(_ window: NSWindow, phase: String, eventNumber: Int? = nil) {
        // Lifecycle and key-event evidence share the original overall limit.
        guard isEnabled, capturedRecords < maximumRecords else { return }
        capturedRecords += 1
        var views: [NSView] = []
        var treeTruncated = false
        func visit(_ view: NSView, depth: Int) {
            guard views.count < maximumViews, depth < 32 else { treeTruncated = true; return }
            views.append(view)
            for child in view.subviews { visit(child, depth: depth + 1) }
        }
        if let content = window.contentView { visit(content, depth: 0) }
        let ids = Dictionary(uniqueKeysWithValues: views.enumerated().map { (ObjectIdentifier($0.element), $0.offset) })
        func reference(_ responder: NSResponder?) -> [String: Any] {
            guard let responder else { return ["kind": "nil"] }
            var result: [String: Any] = ["class": String(String(describing: type(of: responder)).prefix(160))]
            if let id = ids[ObjectIdentifier(responder)] { result["id"] = id }
            return result
        }
        func loop(_ start: NSView?, validOnly: Bool) -> [String: Any] {
            var visited = Set<ObjectIdentifier>()
            var sequence: [[String: Any]] = []
            var current = start
            while let view = current, sequence.count < maximumLoopLength {
                guard visited.insert(ObjectIdentifier(view)).inserted else {
                    return ["views": sequence, "end": "cycle", "returnsTo": reference(view)]
                }
                sequence.append(reference(view))
                current = validOnly ? view.nextValidKeyView : view.nextKeyView
            }
            return ["views": sequence, "end": current == nil ? "nil" : "limit"]
        }
        let nodes: [[String: Any]] = views.enumerated().map { id, view in
            let rect = view.convert(view.bounds, to: nil)
            var node: [String: Any] = [
                "id": id, "class": String(String(describing: type(of: view)).prefix(160)),
                "parent": reference(view.superview),
                "windowRect": [rect.origin.x, rect.origin.y, rect.size.width, rect.size.height],
                "acceptsFirstResponder": view.acceptsFirstResponder,
                "canBecomeKeyView": view.canBecomeKeyView,
                "hidden": view.isHiddenOrHasHiddenAncestor,
                "nextKeyView": reference(view.nextKeyView),
                "nextValidKeyView": reference(view.nextValidKeyView)
            ]
            if let control = view as? NSControl { node["enabled"] = control.isEnabled }
            if let table = view as? NSTableView {
                node["tableRows"] = table.numberOfRows
                node["selectedRows"] = Array(table.selectedRowIndexes)
            }
            return node
        }
        let start = (window.firstResponder as? NSView) ?? window.initialFirstResponder ?? window.contentView
        var record: [String: Any] = [
            "schema": 1, "phase": phase,
            "fullKeyboardAccess": NSApplication.shared.isFullKeyboardAccessEnabled,
            "autorecalculatesKeyViewLoop": window.autorecalculatesKeyViewLoop,
            "isKeyWindow": window.isKeyWindow,
            "isMiniaturized": window.isMiniaturized,
            "isVisible": window.isVisible,
            "windowNumber": window.windowNumber,
            "windowFrame": [window.frame.origin.x, window.frame.origin.y, window.frame.width, window.frame.height],
            "firstResponder": reference(window.firstResponder),
            "initialFirstResponder": reference(window.initialFirstResponder),
            "treeTruncated": treeTruncated, "nodes": nodes,
            "nextKeyLoop": loop(start, validOnly: false),
            "nextValidKeyLoop": loop(start, validOnly: true)
        ]
        if let eventNumber { record["eventNumber"] = eventNumber }
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0A)
        do {
            if !FileManager.default.fileExists(atPath: outputURL.path) {
                try data.write(to: outputURL, options: .atomic)
            } else {
                let file = try FileHandle(forWritingTo: outputURL)
                defer { try? file.close() }
                try file.seekToEnd()
                try file.write(contentsOf: data)
            }
        } catch {
            FileHandle.standardError.write(Data("Fixture focus diagnostic write failed.\n".utf8))
        }
    }
}

@MainActor
private final class FixtureWindow: NSWindow {
    var focusDiagnostics: FixtureFocusDiagnostics?
    override func sendEvent(_ event: NSEvent) {
        let eventNumber = focusDiagnostics?.begin(event, window: self)
        super.sendEvent(event)
        if let eventNumber { focusDiagnostics?.end(window: self, eventNumber: eventNumber) }
    }
}

private struct FixtureWindowCapture: NSViewRepresentable {
    let size: CGSize
    let ready: Bool
    let traceEnabled: Bool
    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.setContentSize(size)
            window.title = "Bloomy Dashboard — Synthetic Review"
            if let diagnostics = (window as? FixtureWindow)?.focusDiagnostics {
                diagnostics.isEnabled = traceEnabled
                if ready { diagnostics.captureReady(window) }
            }
        }
    }
}

private struct FixtureChatVerificationControls: View {
    @ObservedObject var model: FixtureModel
    @ObservedObject var chat: ChatStore

    var body: some View {
        HStack(spacing: 10) {
            Menu("New synthetic local chat") {
                ForEach(FixtureChatVerification.allCases) { verification in
                    Button(verification.rawValue) { model.startVerificationChat(verification) }
                }
            }
            .disabled(!model.ready || !model.scenario.hasCurrentRuntime || chat.isSending)
            .help("Starts a new empty local chat with a controlled first model read; no real endpoint, key, or inference.")
            Menu("Next verification read") {
                ForEach(FixtureChatVerification.allCases) { verification in
                    Button(verification.rawValue) { Task { await model.setNextVerificationRead(verification) } }
                }
            }
            .disabled(model.chatVerificationTest == nil || chat.isSending || chat.isRefreshingModels)
            .help("Changes only the fake model-read response. Use Chat's production Refresh button to read it; the conversation and draft stay unchanged.")
            Text(model.chatVerificationTest?.rawValue ?? "Chat tests create a new empty conversation")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.orange.opacity(0.08))
    }
}

private struct FixtureReviewView: View {
    @ObservedObject var model: FixtureModel
    @AppStorage private var appearance: String
    @State private var compact = false
    init(model: FixtureModel) {
        self.model = model
        _appearance = AppStorage(wrappedValue: "light", ApplicationAppearance.defaultsKey, store: model.defaults)
    }
    var body: some View {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SYNTHETIC REVIEW · no live API calls").font(.headline)
                        Text("CPU/GPU off · Mac name and thermal are actual").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Picker("Scenario", selection: $model.scenario) {
                        ForEach(FixtureScenario.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 150)
                    Toggle("Dark", isOn: Binding(get: { appearance == "dark" }, set: { appearance = $0 ? "dark" : "light" })).toggleStyle(.checkbox)
                    Toggle("800 × 560", isOn: $compact).toggleStyle(.checkbox)
                    FixturePopupButton(show: { model.presentMenuBarPopup?() }, enabled: model.ready).frame(width: 64, height: 24)
                    Button("Reload") { Task { await model.load() } }
                    Toggle("Focus trace", isOn: $model.focusTracing).toggleStyle(.checkbox)
                        .help("Bounded native focus diagnostic: \(model.focusDiagnostics.outputURL.path)")
                }.padding(10).background(Color.orange.opacity(0.12))
                // Observe the child store directly so a completed model read
                // re-enables test controls without an unrelated fixture update.
                FixtureChatVerificationControls(model: model, chat: model.chat)
                HStack(spacing: 14) {
                    Toggle("Static menu-bar activity", isOn: $model.staticActivity).toggleStyle(.checkbox)
                    Toggle("Grayscale", isOn: $model.grayscale).toggleStyle(.checkbox)
                    Picker("Popup height", selection: $model.popupHeightBudget) {
                        ForEach(FixturePopupHeightBudget.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 210)
                    .help("Synthetic popup height budget only; the Mac's screen and preferences stay unchanged.")
                    Spacer(minLength: 0)
                    Button(model.nativeProofStatus) { model.runNativeProof() }
                        .disabled(!model.ready || model.nativeProofStatus == "Proof running…")
                        .help("Run finite synthetic native checks; results: \(model.directory.path)")
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
                if let issue = model.issue { Text(issue).foregroundStyle(.red).padding(6) }
                DashboardRootView(store: model.monitor, controlStore: model.control, hostingStore: model.hosting,
                    chatStore: model.chat, navigation: model.navigation, settingsDraft: model.settingsDraft,
                    chatDraft: model.chatDraft, hostingDraft: model.hostingDraft, updateProtection: model.updateProtection)
                    .saturation(model.grayscale ? 0 : 1)
                    .overlay { if !model.ready { ProgressView("Preparing synthetic sources…").padding().background(.regularMaterial) } }
            }
            .defaultAppStorage(model.defaults)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .frame(minWidth: 800, minHeight: 560)
            .background(FixtureWindowCapture(size: compact ? CGSize(width: 800, height: 560) : CGSize(width: 1280, height: 900), ready: model.ready, traceEnabled: model.focusTracing))
            .task {
                await model.load()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    await model.tick()
                }
            }
            .onChange(of: model.scenario) { _, _ in Task { await model.load() } }
    }
}

// Match the production DashboardWindowController host policy. A SwiftUI
// WindowGroup can add fullSizeContentView and make a different scroll-edge
// presentation; this fixture should compare the same native window policy.
@MainActor
private final class FixtureApplicationDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let model = FixtureModel()
    private var window: NSWindow?
    private var statusItem: FixtureStatusItemController?
    private let terminationGate = ApplicationTerminationGate()
    private var terminationRequested = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        installApplicationMenus()
        let content = NSHostingController(rootView: FixtureReviewView(model: model))
        let window = FixtureWindow(contentViewController: content)
        window.delegate = self
        window.focusDiagnostics = model.focusDiagnostics
        window.title = "Bloomy Dashboard — Synthetic Review"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1280, height: 900))
        window.contentMinSize = NSSize(width: 800, height: 560)
        window.center()
        self.window = window
        model.presentDashboard = { [weak self] section, settingsPage in
            self?.presentDashboard(section: section, settingsPage: settingsPage)
        }
        statusItem = FixtureStatusItemController(model: model)
        model.presentMenuBarPopup = { [weak self] in self?.statusItem?.showPopup() }
        presentDashboard()
    }

    private func installApplicationMenus(application: NSApplication = .shared) {
        let mainMenu = NSMenu()
        func submenu(_ title: String) -> NSMenu {
            let menu = NSMenu(title: title)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.submenu = menu
            mainMenu.addItem(item)
            return menu
        }
        func add(_ title: String, action: Selector, key: String = "",
                 modifiers: NSEvent.ModifierFlags = .command,
                 target: AnyObject? = nil, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }
        let appMenu = submenu("Bloomy Dashboard Fixture")
        add("Quit Bloomy Dashboard Fixture", action: #selector(NSApplication.terminate(_:)),
            key: "q", target: application, to: appMenu)

        // Same selectors and shortcuts as production; nil targets let the
        // native responder chain edit the focused synthetic text field.
        let editMenu = submenu("Edit")
        add("Undo", action: NSSelectorFromString("undo:"), key: "z", to: editMenu)
        add("Redo", action: NSSelectorFromString("redo:"), key: "z", modifiers: [.command, .shift], to: editMenu)
        editMenu.addItem(.separator())
        add("Cut", action: #selector(NSText.cut(_:)), key: "x", to: editMenu)
        add("Copy", action: #selector(NSText.copy(_:)), key: "c", to: editMenu)
        add("Paste", action: #selector(NSText.paste(_:)), key: "v", to: editMenu)
        add("Select All", action: #selector(NSText.selectAll(_:)), key: "a", to: editMenu)

        let windowMenu = submenu("Window")
        add("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", to: windowMenu)
        windowMenu.addItem(.separator())
        add("Show Dashboard", action: #selector(showDashboard), key: "d",
            modifiers: [.command, .shift], target: self, to: windowMenu)
        application.mainMenu = mainMenu
        application.windowsMenu = windowMenu
    }

    @objc private func showDashboard() {
        presentDashboard()
    }

    private func presentDashboard(section: DashboardDestination? = nil, settingsPage: SettingsPage? = nil) {
        guard !terminationRequested, let window else { return }
        if let settingsPage { model.navigation.settingsPage = settingsPage }
        if let section { model.navigation.selected = section }
        if section != nil || settingsPage != nil { model.navigation.revealSelectedSection() }
        window.deminiaturize(nil)
        model.setDashboardVisible(true)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        model.focusDiagnostics.captureWindowState(window, phase: "window.presented")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    // Mirror DashboardWindowController's visibility forwarding. Store.start()
    // remains unused, so these events cannot start its autonomous collectors.
    func windowWillClose(_ notification: Notification) { model.setDashboardVisible(false) }
    func windowDidMiniaturize(_ notification: Notification) {
        model.setDashboardVisible(false)
        if let window { model.focusDiagnostics.captureWindowState(window, phase: "window.didMiniaturize") }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        model.setDashboardVisible(true)
        if let window { model.focusDiagnostics.captureWindowState(window, phase: "window.didDeminiaturize") }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        terminationRequested = true
        model.ready = false
        return terminationGate.requestTermination(
            cleanup: {
                await self.model.stopForTermination()
                self.statusItem?.invalidate()
                self.statusItem = nil
            },
            retryTermination: { sender.terminate(nil) }
        )
    }
}

@main
struct DashboardFixture {
    @MainActor
    static func main() {
        if MotionCoverHost.runIfRequested(arguments: CommandLine.arguments) { return }
        let application = NSApplication.shared
        let delegate = FixtureApplicationDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        application.run()
        withExtendedLifetime(delegate) {}
    }
}
