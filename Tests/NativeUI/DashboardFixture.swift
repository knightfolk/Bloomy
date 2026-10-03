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
    case frozenSettings = "Frozen settings"
    case fanConfirmation = "Fan confirmation"
    case noLANAddresses = "No LAN addresses"
    case multipleStartup = "Multiple startup models", missingStartupModel = "Missing startup download"
    case ambiguousStartup = "Ambiguous startup alias", startupLoadingOff = "Startup loading off"
    case emptyCatalog = "Empty model catalog", unavailableCatalog = "Unavailable model catalog"
    var id: String { rawValue }
    var hasCurrentRuntime: Bool { self != .stale && self != .offline && self != .unavailableRuntime }
    var hasStaleCatalog: Bool { self == .stale || self == .staleCatalog }
    func availability<T: Equatable & Sendable>(_ value: T, at date: Date) -> SourceAvailability<T> {
        switch self {
        case .stale: .stale(value: value, capturedAt: date, reason: "Synthetic source stopped refreshing")
        case .offline, .unavailableRuntime: .unavailable(reason: "Synthetic source unavailable")
        default: .available(value: value, capturedAt: date)
        }
    }
}

private enum FixtureLogTimeZone: String, CaseIterable, Identifiable {
    case system = "Mac local", utc = "UTC", kathmandu = "Kathmandu"
    var id: Self { self }
    var value: TimeZone {
        switch self {
        case .system: .autoupdatingCurrent
        case .utc: TimeZone(secondsFromGMT: 0)!
        case .kathmandu: TimeZone(identifier: "Asia/Kathmandu")!
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
    static func logEvents(_ scenario: FixtureScenario, now: Date) -> [LogEvent] {
        let date = scenario == .stale ? now.addingTimeInterval(-900) : now
        return (0..<48).map { index in
            let eventDate = date.addingTimeInterval(Double(-index * 60))
            let severity: LogSeverity = index % 9 == 0 ? .warning : .info
            let source: LogSource = index % 2 == 0 ? .legacy : .unified
            let message = index % 9 == 0 ? "Synthetic delayed refresh; retained evidence" : "Synthetic job completed"
            return LogEvent(timestamp: eventDate, severity: severity, category: "Synthetic review",
                message: message, source: source, processID: 4242, processImage: "Fixture")
        }
    }
    static func snapshot(_ scenario: FixtureScenario, now: Date, events: [LogEvent]? = nil) -> TelemetrySnapshot {
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
        // Offline has matching current synthetic daemon and official CLI
        // stopped-status evidence; unrelated sources remain unavailable.
        let stateAvailability: SourceAvailability<DaemonState> = scenario == .offline
            ? .available(value: state, capturedAt: date) : scenario.availability(state, at: date)
        return TelemetrySnapshot(state: stateAvailability,
            loadedModels: scenario.availability(LoadedModelsState(schema: 1,
                models: Array(modelIDs.prefix(2)), updatedAt: date.timeIntervalSince1970), at: date),
            status: scenario == .offline
                ? .available(value: status, capturedAt: date) : scenario.availability(status, at: date),
            eventFeed: scenario.availability(EventFeed(events: events ?? logEvents(scenario, now: now), legacyReadAt: date, unifiedActivityAt: date), at: date),
            tokenRate: scenario.hasCurrentRuntime ? .available(tokensPerSecond: 52.7, label: "Synthetic observed rate") : .unavailable(reason: "Synthetic inactive source"),
            diagnostics: scenario.hasCurrentRuntime ? [] : [AcquisitionDiagnostic(id: "fixture", source: "Synthetic review", message: "Synthetic source \(scenario.rawValue.lowercased())", occurredAt: now)],
            capturedAt: now, menuStatus: scenario.hasCurrentRuntime ? .online : scenario == .stale ? .stale : .offline)
    }
}

/// Event payloads are seeded once for one prepared session. Source capture
/// dates can advance without rewriting the immutable keys used by Logs.
private actor FixtureLogFeed {
    private var retained: [LogEvent]
    private var arrivals = 0
    init(events: [LogEvent]) { retained = Array(events.prefix(100)) }
    func events(limit: Int = 100) -> [LogEvent] { Array(retained.prefix(max(0, min(limit, 100)))) }
    func prepend(at date: Date, count: Int = 1) {
        for _ in 0..<min(100, max(0, count)) {
            arrivals += 1
            retained.insert(LogEvent(timestamp: date, severity: .notice, category: "Synthetic arrival",
                message: "Synthetic log arrival \(arrivals) · \(UUID().uuidString)", source: .unified,
                processID: 4242, processImage: "Fixture"), at: 0)
        }
        if retained.count > 100 { retained.removeLast(retained.count - 100) }
    }
}

private struct FixtureTelemetrySource: TelemetrySource {
    let scenario: FixtureScenario
    let logFeed: FixtureLogFeed
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
        guard scenario != .offline, scenario != .unavailableRuntime else { return [] }
        return await logFeed.events(limit: limit)
    }
}
private enum FixtureError: Error { case offline }

private enum FixtureActivityRead: String, CaseIterable, Identifiable, Sendable {
    case normal = "Normal Earnings"
    case empty = "Empty Earnings"
    case knownZero = "Recorded zero with unknown gaps"
    case tiny = "Overlapping micro-dollar earnings"
    var id: String { rawValue }
}

private enum FixtureEarningsReadMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal, hold, fail, empty
    var id: Self { self }
}

/// Counts the first-query gate, not completion of the entire production report.
private struct FixtureEarningsReadSnapshot: Codable, Sendable {
    var revision: UInt64 = 0
    var nextMode = FixtureEarningsReadMode.normal
    var started: UInt64 = 0
    var completed: UInt64 = 0
    var failed: UInt64 = 0
    var cancelled: UInt64 = 0
    var empty: UInt64 = 0
    var heldReadID: UInt64?
}

private actor FixtureEarnings: AccountEarningsFetching {
    let scenario: FixtureScenario
    private var limitedModels = false
    private var activityRead = FixtureActivityRead.normal
    private var queryActivityRead = FixtureActivityRead.normal
    private var readState = FixtureEarningsReadSnapshot()
    private var pending: (id: UInt64, continuation: CheckedContinuation<FixtureEarningsReadMode, Error>)?
    private var activeGateID: UInt64?
    private var gateWaiters: [CheckedContinuation<Void, Never>] = []
    private var stateChanged: (@Sendable (FixtureEarningsReadSnapshot) -> Void)?
    init(scenario: FixtureScenario) { self.scenario = scenario }
    func setLimitedModels(_ value: Bool) -> Bool {
        guard activeGateID == nil else { return false }
        limitedModels = value
        return true
    }
    func setActivityRead(_ value: FixtureActivityRead) -> Bool {
        guard activeGateID == nil else { return false }
        activityRead = value
        queryActivityRead = value
        return true
    }
    func observeReads(_ observer: @escaping @Sendable (FixtureEarningsReadSnapshot) -> Void) {
        stateChanged = observer
        publishReadState()
    }
    func setNextRead(_ mode: FixtureEarningsReadMode) {
        guard activeGateID == nil else { return }
        readState.nextMode = mode
        publishReadState()
    }
    func releaseHeld(as mode: FixtureEarningsReadMode) {
        guard let held = pending else { return }
        pending = nil
        held.continuation.resume(returning: mode == .hold ? .normal : mode)
    }
    /// Cancellation resolves and joins the one owned gate before teardown returns.
    func cancelHeldAndWait() async {
        guard activeGateID != nil else { return }
        cancelHeld()
        await withCheckedContinuation { gateWaiters.append($0) }
    }
    func readSnapshot() -> FixtureEarningsReadSnapshot { readState }
    private func publishReadState() {
        readState.revision &+= 1
        readState.heldReadID = activeGateID
        stateChanged?(readState)
    }
    private func cancelHeld(_ id: UInt64? = nil) {
        guard let held = pending, id == nil || held.id == id else { return }
        pending = nil
        held.continuation.resume(throwing: CancellationError())
    }
    private func holdRead(_ id: UInt64) async throws -> FixtureEarningsReadMode {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending = (id, continuation)
                    publishReadState()
                }
            }
        } onCancel: {
            Task { await self.cancelHeld(id) }
        }
    }
    private func beginActivityQuery() async throws {
        try Task.checkCancellation()
        // A new scope cancels and joins a previous held gate; never accumulate holds.
        await cancelHeldAndWait()
        try Task.checkCancellation()
        readState.started &+= 1
        let id = readState.started
        var mode = readState.nextMode
        readState.nextMode = .normal
        activeGateID = id
        let persistentRead = activityRead
        defer {
            activeGateID = nil
            publishReadState()
            let waiters = gateWaiters
            gateWaiters.removeAll()
            for waiter in waiters { waiter.resume() }
        }
        do {
            if mode == .hold { mode = try await holdRead(id) }
            try Task.checkCancellation()
            if mode == .fail { throw FixtureError.offline }
            queryActivityRead = mode == .empty ? .empty : persistentRead
            readState.completed &+= 1
            if queryActivityRead == .empty { readState.empty &+= 1 }
        } catch {
            if error is CancellationError || Task.isCancelled {
                readState.cancelled &+= 1
                throw CancellationError()
            }
            readState.failed &+= 1
            throw error
        }
    }
    func fetch(now: Date) async throws -> EarningsPresentationValue {
        switch scenario {
        case .fresh, .staleCatalog, .expiredSettings, .expiredHelper, .unavailableSettings, .partialCooling, .disabledHelper, .aliasStartup, .liveHosting, .frozenSettings, .fanConfirmation, .noLANAddresses, .multipleStartup, .missingStartupModel, .ambiguousStartup, .startupLoadingOff, .emptyCatalog, .unavailableCatalog:
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
        if queryActivityRead == .empty { return [] }
        return try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar).enumerated().map { index, interval in
            if queryActivityRead == .knownZero {
                return ActivityBucket(interval: interval,
                    totals: index % 3 == 0 ? ActivityTotals(workMicroUSD: 0, rewardMicroUSD: 0, jobs: 0, promptTokens: 0, completionTokens: 0) : nil,
                    coverage: index % 3 == 0 ? .recorded : .unavailable)
            }
            if queryActivityRead == .tiny {
                return ActivityBucket(interval: interval,
                    totals: index % 3 == 0 ? ActivityTotals(workMicroUSD: 3, rewardMicroUSD: 1, jobs: 3, promptTokens: 12, completionTokens: 30) : nil,
                    coverage: index % 3 == 0 ? .recorded : .unavailable)
            }
            return ActivityBucket(interval: interval, totals: ActivityTotals(workMicroUSD: Int64(150_000 + index % 7 * 30_000),
                rewardMicroUSD: 20_000, jobs: Int64(5 + index % 5), promptTokens: 2_000, completionTokens: 5_000), coverage: .recorded)
        }
    }
    func activityModels(in range: DateInterval) async throws -> [String] {
        try await beginActivityQuery()
        return scenario.hasCurrentRuntime && queryActivityRead != .empty ? Array(FixtureData.modelIDs.prefix(limitedModels ? 1 : 3)) : []
    }
    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        guard scenario.hasCurrentRuntime, queryActivityRead != .normal else { return nil }
        guard queryActivityRead != .empty else { return [] }
        return try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar).enumerated().flatMap { index, interval in
            guard index % 3 == 0 else { return [ModelActivityBucket]() }
            return FixtureData.modelIDs.prefix(limitedModels ? 1 : 3).map { model in
                ModelActivityBucket(interval: interval, model: model, workMicroUSD: queryActivityRead == .tiny ? 1 : 0)
            }
        }
    }
    func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]? {
        if limitedModels, let model, model != FixtureData.modelIDs.first { return [] }
        if queryActivityRead != .normal, let model {
            guard FixtureData.modelIDs.prefix(3).contains(model) else { return [] }
            return try await activity(in: range, unit: unit, calendar: calendar)?.map { bucket in
                ActivityBucket(interval: bucket.interval,
                    totals: bucket.totals.map { _ in
                        ActivityTotals(workMicroUSD: queryActivityRead == .tiny ? 1 : 0,
                            rewardMicroUSD: 0, jobs: queryActivityRead == .tiny ? 1 : 0,
                            promptTokens: queryActivityRead == .tiny ? 4 : 0, completionTokens: queryActivityRead == .tiny ? 10 : 0)
                    }, coverage: bucket.coverage)
            }
        }
        return try await activity(in: range, unit: unit, calendar: calendar)
    }
}
private actor FixtureCapacity: NetworkCapacityFetching {
    let scenario: FixtureScenario
    let fixedCapture: Date?
    var attempts = 0
    init(scenario: FixtureScenario, fixedCapture: Date? = nil) {
        self.scenario = scenario; self.fixedCapture = fixedCapture
    }
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
        return try NetworkCapacityParser.parse(JSONSerialization.data(withJSONObject: ["models": models]), capturedAt: fixedCapture ?? capturedAt)
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
private enum FixtureAutopilotMode: String, CaseIterable, Sendable {
    case off = "Off", shadow = "Observing", active = "Active", paused = "Paused"
    case waiting = "Waiting", mismatch = "Unconfirmed", unavailable = "Unavailable"
    case blockedPreload = "Preload needs repair"
}

private actor FixtureAutopilot {
    private var mode: FixtureAutopilotMode = .off
    private var enrollmentCount = 0
    private var policyCount = 0
    func setMode(_ value: FixtureAutopilotMode) { mode = value }
    func read() -> SourceAvailability<ProviderAutopilotStatus> {
        guard mode != .unavailable else { return .unavailable(reason: "Synthetic Autopilot read failed") }
        let enabled = mode != .off && mode != .blockedPreload
        return .available(value: .init(configuredEnabled: enabled, consentRecorded: enabled,
            configuredPaused: mode == .paused, selectedModels: enabled ? FixtureData.modelIDs : [],
            pinnedModels: [], configuredRevision: "fixture",
            live: enabled ? .init(protocolVersion: 3, enabled: true, active: mode == .active,
                observeOnly: mode == .shadow, paused: mode == .paused, cachedOnly: true,
                revision: mode == .mismatch ? "old" : "fixture") : nil,
            phase: mode == .active ? .active : mode == .paused ? .paused : mode == .waiting ? .waiting : .shadow),
            capturedAt: Date())
    }
    func enroll() { enrollmentCount += 1; mode = .shadow }
    func setupIsBlocked() -> Bool { mode == .blockedPreload }
    func apply(_ action: ProviderAutopilotPolicyAction) {
        policyCount += 1
        mode = action == .disable ? .off : action == .pause ? .paused : .shadow
    }
    func proof() -> [String: Int] { ["synthetic": 1, "enrollmentCount": enrollmentCount, "policyCount": policyCount] }
}

private struct FixtureModelControlProof: Codable, Sendable {
    let enabled: [String]
    let preloaded: [String]
    let startupPreload: Bool?
    let maxModelSlots: Int
    let saveCount: Int
    let lifecycleCount: Int
}

/// Public draft fields only. This fixture constructs drafts without a source
/// file state, and never reads a provider configuration or credential file.
private struct FixtureModelDraftProof: Codable, Sendable {
    let sourceRevision: String
    let originalEnabled: [String]
    let originalPreloaded: [String]
    let enabled: [String]
    let preloaded: [String]
    let originalMaxModelSlots: Int?
    let maxModelSlots: Int?
    let originalStartupPreload: Bool?
    let startupPreload: Bool?
    let originalEngineV2MaxConcurrent: Int?
    let engineV2MaxConcurrent: Int?
    let hasChanges: Bool

    init(_ draft: ProviderConfigDraft) {
        sourceRevision = draft.sourceRevision
        originalEnabled = draft.original.enabled; originalPreloaded = draft.original.preloaded
        enabled = draft.selection.enabled; preloaded = draft.selection.preloaded
        originalMaxModelSlots = draft.originalMaxModelSlots; maxModelSlots = draft.maxModelSlots
        originalStartupPreload = draft.originalStartupPreload; startupPreload = draft.startupPreload
        originalEngineV2MaxConcurrent = draft.originalEngineV2MaxConcurrent
        engineV2MaxConcurrent = draft.engineV2MaxConcurrent
        hasChanges = draft.hasChanges
    }
}

private struct FixtureModelStateProof: Codable, Sendable {
    let synthetic: Bool
    let controlIdentity: String
    let draft: FixtureModelDraftProof?
    let saved: FixtureModelControlProof
    let error: String?
    let modelSheetWindowNumbers: [Int]
}

private actor FixtureController: ProviderControlling {
    let scenario: FixtureScenario
    let autopilot: FixtureAutopilot
    private var removedModels = Set<String>()
    private var delayNextRead = false
    private var transientGemmaHidden = false
    private var failNextRead = false
    func delayNextControlRead() { delayNextRead = true }
    func hideGemmaTemporarily(_ hidden: Bool) { transientGemmaHidden = hidden }
    func failNextControlRead() { failNextRead = true }
    var selection = ProviderModelSelection(enabled: Array(FixtureData.modelIDs.prefix(3)), preloaded: Array(FixtureData.modelIDs.prefix(2)))
    var slots = 3
    var startupPreload: Bool? = true
    var concurrent = 4
    private var saveCount = 0
    private var lifecycleCount = 0
    func modelControlProof() -> FixtureModelControlProof {
        .init(enabled: selection.enabled, preloaded: selection.preloaded, startupPreload: startupPreload,
            maxModelSlots: slots, saveCount: saveCount, lifecycleCount: lifecycleCount)
    }
    init(scenario: FixtureScenario, autopilot: FixtureAutopilot) {
        self.scenario = scenario
        self.autopilot = autopilot
        if scenario == .aliasStartup {
            // Use the catalog's actual unique family alias independently of
            // the exact preload selector.
            selection = ProviderModelSelection(enabled: [FixtureData.modelIDs[0], FixtureData.modelIDs[1], "gpt"],
                preloaded: ["gpt-oss-20b"])
            slots = 1
        }
        if [.multipleStartup, .missingStartupModel, .ambiguousStartup, .startupLoadingOff].contains(scenario) {
            slots = 1
        }
        if scenario == .missingStartupModel { selection.preloaded = [FixtureData.modelIDs[0]] }
        if scenario == .ambiguousStartup { selection.preloaded = ["qwen"] }
        if scenario == .startupLoadingOff {
            selection.preloaded = [FixtureData.modelIDs[2]]
            startupPreload = false
        }
    }
    func removeGemmaFromInventory() {
        let removed = FixtureData.modelIDs[1]
        removedModels.insert(removed)
        selection.enabled.removeAll { $0 == removed }
        selection.preloaded.removeAll { $0 == removed }
    }
    func refresh() async throws -> ProviderControlSnapshot {
        if failNextRead { failNextRead = false; throw FixtureError.offline }
        if scenario == .unavailableCatalog { throw FixtureError.offline }
        if delayNextRead {
            delayNextRead = false
            // A finite, cancellable inert read makes the production editor's
            // busy state observable without touching the real provider.
            try await Task.sleep(for: .seconds(20))
        }
        let now = Date()
        // Match ProviderControlService: expired runtime evidence is omitted
        // before building inventory, never retained as current residency.
        let daemon = scenario.hasCurrentRuntime ? FixtureData.snapshot(scenario, now: now).state.value : nil
        let loadedModelIDs = scenario.hasCurrentRuntime ? Array(FixtureData.modelIDs.prefix(2)).filter { !removedModels.contains($0) } : []
        // Bonsai and Qwen 3 8B are downloaded but neither selected nor resident.
        // Keep the three advertised models and two saved preload models intact.
        let catalog = scenario == .emptyCatalog ? [] : FixtureData.catalog.filter {
            !removedModels.contains($0.id) && !(transientGemmaHidden && $0.id == FixtureData.modelIDs[1])
        }
        let local = catalog.filter { scenario != .missingStartupModel || $0.id != FixtureData.modelIDs[0] }
            .map { LocalModel(id: $0.id, modelType: "text", sizeBytes: Int64($0.sizeGB * 1e9), estimatedMemoryGB: nil) }
        let runtimeSource: ProviderControlSourceState = scenario.hasCurrentRuntime
            ? .fresh(evidenceAt: now) : scenario == .stale
            ? .stale("Synthetic runtime source stale") : .unavailable("Synthetic source offline")
        let catalogSource: ProviderControlSourceState = scenario.hasStaleCatalog
            ? .stale("Synthetic catalog/local inventory retained") : runtimeSource
        return ProviderControlSnapshot(inventory: ModelInventoryBuilder.build(catalog: catalog,
            local: local, selection: selection, daemon: daemon, loadedModels: loadedModelIDs),
            draft: ProviderConfigDraft(sourceRevision: "synthetic", original: selection, selection: selection,
                originalMaxModelSlots: slots, maxModelSlots: slots,
                originalStartupPreload: startupPreload, startupPreload: startupPreload,
                originalEngineV2MaxConcurrent: concurrent, engineV2MaxConcurrent: concurrent),
            daemonState: daemon, capturedAt: now,
            sources: ProviderControlSourceStates(catalog: catalogSource, localModels: catalogSource, daemon: runtimeSource, loadedModels: runtimeSource))
    }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        saveCount += 1
        selection = draft.selection; slots = draft.maxModelSlots ?? 3; concurrent = draft.engineV2MaxConcurrent ?? 4
        startupPreload = draft.startupPreload
        return ProviderConfigSaveResult(draft: try await refresh().draft, restartRequired: true)
    }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {}
    func delete(_ localModelID: String) async throws {}
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { lifecycleCount += 1 }
    func performAutopilotEnrollment(hosting: HostingOptions,
        onPhase: ProviderMutationPhaseObserver?) async throws -> ProviderAutopilotEnrollmentCompletion {
        if await autopilot.setupIsBlocked() {
            throw ProviderControlError.inventoryUnavailable(
                "Saved preload aliases would lose their enabled match during enrollment. In Models, clear those preloads or reselect the exact downloaded model IDs, save, then retry."
            )
        }
        await autopilot.enroll()
        await onPhase?(.reconciling)
        return .init(controls: .refreshed(try await refresh()), status: await autopilot.read(),
            commandSucceeded: true, savedPolicyPreserved: true)
    }
}
private enum FixtureFanReadback: String, CaseIterable, Identifiable, Sendable {
    case held = "Original policy", missing = "Failed readback", matching = "Confirm submission"
    var id: String { rawValue }
}

private struct FixtureFanProof: Codable, Sendable {
    let synthetic: Bool
    let commandCount: Int
    let readback: String
    let submittedSpeedPercent: Double?
    let submittedTemperatureCelsius: Double?
}

private actor FixtureExtras: ProviderExtrasProviding {
    let scenario: FixtureScenario
    let autopilot: FixtureAutopilot
    private let frozenAt = Date()
    var minutes = 30
    var mtp = false
    var autoUpdate = true
    private var submittedFanPolicy: ProviderFanPolicy?
    private var fanCommandCount = 0
    private var fanReadback: FixtureFanReadback = .held
    func setFanReadback(_ value: FixtureFanReadback) { fanReadback = value }
    func fanProof() -> FixtureFanProof {
        FixtureFanProof(synthetic: true, commandCount: fanCommandCount, readback: fanReadback.rawValue,
            submittedSpeedPercent: submittedFanPolicy?.speedPercent,
            submittedTemperatureCelsius: submittedFanPolicy?.triggerTemperatureCelsius)
    }
    init(scenario: FixtureScenario, autopilot: FixtureAutopilot) { self.scenario = scenario; self.autopilot = autopilot }
    func refreshAutopilot() async -> SourceAvailability<ProviderAutopilotStatus> { await autopilot.read() }
    func setAutopilotPolicy(_ action: ProviderAutopilotPolicyAction) async throws { await autopilot.apply(action) }
    func setAutopilotMode(_ value: FixtureAutopilotMode) async { await autopilot.setMode(value) }
    func autopilotProof() async -> [String: Int] { await autopilot.proof() }
    func refresh() async -> ProviderExtrasSnapshot {
        let now = Date()
        let date = scenario == .frozenSettings ? frozenAt : scenario == .stale ? now.addingTimeInterval(-900)
            : scenario == .expiredSettings ? now.addingTimeInterval(-90) : now
        if scenario == .unavailableSettings {
            return ProviderExtrasSnapshot(capturedAt: now,
                idlePolicy: .unavailable(reason: "Synthetic first read failed"),
                betaFeatures: .unavailable(reason: "Synthetic first read failed"),
                fanStatus: .unavailable(reason: "Synthetic first read failed"),
                autoUpdateStatus: .unavailable(reason: "Synthetic first read failed"),
                autopilotStatus: .unavailable(reason: "Synthetic first read failed"))
        }
        let helperExpired = scenario == .expiredHelper || scenario == .partialCooling
        let helperDate = helperExpired ? now.addingTimeInterval(-90) : date
        let fans = (0..<(scenario == .partialCooling ? 2 : 1)).map {
            ProviderFanReading(index: $0, actualRPM: 2_200, targetRPM: 2_200, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic")
        }
        let observedPolicy = fanReadback == .matching ? submittedFanPolicy : nil
        let fan = ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
            helper: ProviderFanHelperStatus(enabled: scenario != .disabledHelper, providerActive: true, mode: "automatic", chip: "Synthetic",
                gpuTemperatureCelsius: 54, triggerTemperatureCelsius: observedPolicy?.triggerTemperatureCelsius ?? 65, releaseTemperatureCelsius: 55,
                speedPercent: observedPolicy?.speedPercent ?? 80, fans: fans, updatedAt: helperDate),
            diagnostic: ProviderFanDiagnostic(chip: "Synthetic", supported: true,
                gpuTemperatures: scenario == .expiredHelper ? [] : [ProviderFanTemperature(key: "Synthetic GPU", celsius: scenario == .partialCooling ? 42 : 54)],
                fans: scenario == .partialCooling
                    ? [ProviderFanReading(index: 0, actualRPM: nil, targetRPM: nil, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic"),
                       ProviderFanReading(index: 1, actualRPM: 1_200, targetRPM: nil, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic")]
                    : helperExpired ? [] : fans),
            helperErrorPresent: false, diagnosticErrorPresent: false)
        let autopilotSource = await autopilot.read()
        let observedAutopilot = autopilotSource.value.map { scenario.availability($0, at: date) } ?? autopilotSource
        return ProviderExtrasSnapshot(capturedAt: date,
            idlePolicy: scenario.availability(ProviderIdlePolicy(idleTimeoutMinutes: minutes, policy: "idle_timeout", summary: "Free after \(minutes) minutes idle", pinned: false), at: date),
            betaFeatures: scenario.availability([ProviderBetaFeature(id: "mtp", title: "Multi-token prediction", state: mtp ? .on : .auto,
                enabled: mtp ? true : nil, requiresRestart: true, summary: "Synthetic setting for eligible models.")], at: date),
            fanStatus: scenario == .fanConfirmation && fanReadback == .missing && submittedFanPolicy != nil
                ? .unavailable(reason: "Synthetic fan readback failed") : scenario.availability(fan, at: date),
            autoUpdateStatus: scenario.availability(ProviderAutoUpdateStatus(enabled: autoUpdate), at: date),
            autopilotStatus: observedAutopilot)
    }
    func saveIdle(minutes: Int) async throws { self.minutes = minutes }
    func setBeta(id: String, enabled: Bool) async throws { mtp = enabled }
    func setAutoUpdate(enabled: Bool) async throws { autoUpdate = enabled }
    func configureFan(policy: ProviderFanPolicy) async throws {
        guard scenario == .fanConfirmation else { throw ProviderExtrasMutationError.unsupportedFanControl }
        submittedFanPolicy = policy
        fanCommandCount += 1
    }
}

// The builder injects this client into CLIUpdateStatusStore.shared in a staged
// source copy: the production update view remains unchanged.
enum FixtureCLIUpdateRead: String, CaseIterable, Identifiable, Sendable {
    case current = "Current", staleCurrent = "Last-known current"
    case staleUpdate = "Last-known update", staleRestart = "Last-known restart"
    case staleQuarantine = "Last-known quarantine", failed = "Failed check"
    var id: String { rawValue }
}

actor FixtureCLIUpdates: CLIUpdateProviding {
    static let shared = FixtureCLIUpdates()
    private var read: FixtureCLIUpdateRead = .current
    private let retainedAt = Date().addingTimeInterval(-172_800)
    func setRead(_ read: FixtureCLIUpdateRead) { self.read = read }
    func checkForUpdate() async -> SourceAvailability<CLIUpdateStatus> {
        let status: CLIUpdateStatus
        switch read {
        case .current: return .available(value: .upToDate(version: "0.9.17"), capturedAt: Date())
        case .failed: return .unavailable(reason: "Synthetic update check failed")
        case .staleCurrent: status = .upToDate(version: "0.9.17")
        case .staleUpdate: status = .updateAvailable(current: "0.9.16", latest: "0.9.17")
        case .staleRestart: status = .restartRequired(current: "0.9.16", installed: "0.9.17")
        case .staleQuarantine: status = .quarantined(version: "0.9.17")
        }
        return .stale(value: status, capturedAt: retainedAt, reason: "Synthetic update check failed")
    }
}
// The production Infrastructure disclosure starts NetworkCacheStore polling.
// Its staged default client must also be inert before any fixture launch.
struct FixtureNetworkCache: NetworkCacheFetching {
    func fetch(at capturedAt: Date) async throws -> NetworkCacheSnapshot {
        try await FixtureNetworkCacheProbe.shared.recordFetch(at: capturedAt)
        return NetworkCacheSnapshot(routingMode: .shadow, plannerEnabled: true,
            plannerRunning: true, plannerReady: true, capturedAt: capturedAt)
    }
}

/// Count only inert cache reads so native disclosure/visibility review does
/// not infer task suspension from appearance alone. No new polling clock.
actor FixtureNetworkCacheProbe {
    static let shared = FixtureNetworkCacheProbe()
    private var outputURL: URL?
    private var reads = 0
    private var lastReadAt: Date?

    func readCount() -> Int { reads }

    func configure(directory: URL) throws {
        let url = directory.appendingPathComponent("network-cache-read-proof.json")
        guard outputURL != url else { return }
        outputURL = url
        reads = 0
        lastReadAt = nil
        try write()
    }

    func recordFetch(at date: Date) throws {
        reads += 1
        lastReadAt = date
        try write()
    }

    private func write() throws {
        guard let outputURL else { return }
        var value: [String: Any] = ["synthetic": true, "reads": reads]
        if let lastReadAt { value["lastReadAt"] = lastReadAt.timeIntervalSince1970 }
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            .write(to: outputURL, options: .atomic)
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
    case matchingText = "Same text from both speakers"
    case heldReply = "Held reply for 30 seconds"
    case collidingModels = "Two models with the same short name"
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
        let modelIDs = verification == .collidingModels
            ? ["vendor-one/qwen3.8-27b", "vendor-two/qwen3.8-27b"] : FixtureData.modelIDs
        if verification == .failed { throw FixtureError.offline }
        if verification == .empty { return ChatModelListSnapshot(modelIDs: [], capturedAt: now) }
        if reads == 1 {
            switch verification {
            case .fresh, .matchingText, .heldReply, .collidingModels: break
            case .expiring:
                return ChatModelListSnapshot(modelIDs: FixtureData.modelIDs,
                    capturedAt: now.addingTimeInterval(-110))
            case .expired:
                return ChatModelListSnapshot(modelIDs: FixtureData.modelIDs,
                    capturedAt: now.addingTimeInterval(-121))
            case .failed, .empty: break
            }
        }
        return ChatModelListSnapshot(modelIDs: modelIDs, capturedAt: now)
    }
    func complete(model: String, messages: [ChatMessagePayload]) async throws -> ChatCompletionOutcome {
        let mode = verification
        if mode == .heldReply { try await Task.sleep(for: .seconds(30)) }
        let reply = mode == .matchingText ? messages.last?.content ?? "Same synthetic text"
            : "Synthetic reply — no model was called. This review conversation lives only in fixture memory."
        return ChatCompletionOutcome(content: reply,
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
    @Published var cliUpdateRead: FixtureCLIUpdateRead = .current
    @Published var fanReadback: FixtureFanReadback = .held
    private var extrasClient: FixtureExtras
    private var controllerClient: FixtureController
    private var earningsClient: FixtureEarnings
    private var logFeed: FixtureLogFeed
    @Published var limitedActivityModels = false
    @Published var activityRead = FixtureActivityRead.normal
    @Published private(set) var earningsReadState = FixtureEarningsReadSnapshot()
    private var earningsReadSession = UUID()
    @Published var modelSheetHeightLimit: CGFloat?
    @Published var networkExpiryReview = false
    private var chatWindow: ChatWindowController?
    private weak var chatWindowStore: ChatStore?
    @Published var focusTracing: Bool
    @Published var staticActivity = false
    @Published var grayscale = false
    @Published var logTimeZone: FixtureLogTimeZone = .system
    @Published var popupHeightBudget: FixturePopupHeightBudget = .screen
    @Published private(set) var nativeProofStatus = "Native proof"
    private var nativeProofTask: Task<Void, Never>?
    @Published private(set) var cacheProofStatus = "Cache visibility proof"
    private var cacheProofTask: Task<Void, Never>?
    @Published private(set) var chatFocusProofStatus = "Chat Cancel focus proof"
    private var chatFocusProofTask: Task<Void, Never>?
    @Published private(set) var modelKeyboardProofStatus = "Model keyboard proof"
    private var modelKeyboardProofTask: Task<Void, Never>?
    @Published private(set) var metricsReview = false
    private var metricsReads: FixtureMetricsReads?
    private var gpuProtectionProof: FixtureGPUProtectionProof?
    var proofRunning: Bool { nativeProofTask != nil || cacheProofTask != nil || chatFocusProofTask != nil || modelKeyboardProofTask != nil }
    @Published private(set) var chatVerificationTest: FixtureChatVerification?
    private var chatVerificationClient: FixtureChatVerificationClient?
    private var loadTask: Task<Void, Never>?
    private var telemetryPublicationTask: Task<Void, Never>?
    private var telemetryPublicationID = UUID()
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
        monitor = stores.0; control = stores.1; hosting = stores.2; chat = stores.3; extrasClient = stores.4
        controllerClient = stores.5; earningsClient = stores.6
        logFeed = stores.7
        hostingDraft = HostingSettingsDraftState(options: stores.2.options)
    }
    private static func makeStores(_ scenario: FixtureScenario, defaults: UserDefaults, directory: URL,
        capacityCapturedAt: Date? = nil) -> (MonitorStore, ProviderControlStore, HostingSettingsStore, ChatStore, FixtureExtras, FixtureController, FixtureEarnings, FixtureLogFeed) {
        let tokens = FixtureTokens()
        let autopilot = FixtureAutopilot()
        let controller = FixtureController(scenario: scenario, autopilot: autopilot)
        let control = ProviderControlStore(controller: controller, homeDirectory: directory, hostingOptions: { .default })
        let extrasClient = FixtureExtras(scenario: scenario, autopilot: autopilot)
        let extras = ProviderExtrasStore(client: extrasClient)
        let earningsClient = FixtureEarnings(scenario: scenario)
        let seededAt = Date()
        let events = FixtureData.logEvents(scenario, now: seededAt)
        let logFeed = FixtureLogFeed(events: events)
        let monitor = MonitorStore(service: TelemetryService(source: FixtureTelemetrySource(scenario: scenario, logFeed: logFeed)),
            initial: FixtureData.snapshot(scenario, now: seededAt, events: events), providerExtras: extras,
            earningsClient: earningsClient,
            networkCapacityClient: FixtureCapacity(scenario: scenario, fixedCapture: capacityCapturedAt), publicCatalogClient: FixtureCatalog(scenario: scenario),
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
            lanScanner: { scenario == .noLANAddresses ? [] : ["192.168.50.20"] }, copyToken: { _ in true }, copyCommand: { _ in true })
        let chat = ChatStore(localClient: FixtureChat(scenario: scenario), networkClient: FixtureChat(scenario: scenario),
            balanceClient: FixtureBalance(), pricingClient: FixturePricing(scenario: scenario), keyStore: tokens)
        monitor.attachRecommendationInventory { control.snapshot }
        monitor.setDashboardVisible(true)
        hosting.refreshEnvironment()
        return (monitor, control, hosting, chat, extrasClient, controller, earningsClient, logFeed)
    }
    func limitActivityModels(_ value: Bool) async {
        guard ready, !isTerminating, await earningsClient.setLimitedModels(value) else { return }
        limitedActivityModels = value
    }
    func setActivityRead(_ value: FixtureActivityRead) async {
        guard ready, !isTerminating else { return }
        guard await earningsClient.setActivityRead(value) else { return }
        activityRead = value
    }
    func setNextEarningsRead(_ mode: FixtureEarningsReadMode) async {
        guard ready, !isTerminating, metricsReview else { return }
        await earningsClient.setNextRead(mode)
    }
    func releaseEarningsRead(_ mode: FixtureEarningsReadMode) async {
        guard ready, !isTerminating else { return }
        await earningsClient.releaseHeld(as: mode)
    }
    func saveEarningsReadProof() async {
        let snapshot = await earningsClient.readSnapshot()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(snapshot)
            try data.write(to: directory.appendingPathComponent("fixture-earnings-read-proof.json"), options: .atomic)
        } catch { issue = "Could not save synthetic Earnings read counts." }
    }
    private func observeEarningsReads() async {
        let session = UUID()
        earningsReadSession = session
        earningsReadState = FixtureEarningsReadSnapshot()
        await earningsClient.observeReads { [weak self] snapshot in
            Task { @MainActor [weak self] in
                guard let self, self.earningsReadSession == session,
                      snapshot.revision >= self.earningsReadState.revision else { return }
                self.earningsReadState = snapshot
            }
        }
    }
    func removeGemmaFromInventory() async {
        guard ready, !isTerminating else { return }
        await controllerClient.removeGemmaFromInventory()
        await control.refreshPreservingDraft()
    }
    func saveModelControlProof() async {
        guard ready, !isTerminating else { return }
        if let data = try? JSONEncoder().encode(await controllerClient.modelControlProof()) {
            try? data.write(to: directory.appendingPathComponent("fixture-model-control-proof.json"), options: .atomic)
        }
    }
    func setGemmaTemporarilyHidden(_ hidden: Bool) async {
        guard ready, !isTerminating else { return }
        await controllerClient.hideGemmaTemporarily(hidden)
        await control.refreshPreservingDraft()
    }
    func failNextModelControlRead() async {
        guard ready, !isTerminating else { return }
        await controllerClient.failNextControlRead()
    }
    func saveModelStateProof() async {
        guard ready, !isTerminating else { return }
        let proof = FixtureModelStateProof(synthetic: true,
            controlIdentity: String(describing: ObjectIdentifier(control)),
            draft: control.draft.map(FixtureModelDraftProof.init),
            saved: await controllerClient.modelControlProof(), error: control.errorMessage,
            modelSheetWindowNumbers: NSApplication.shared.windows.filter(\.isSheet).map(\.windowNumber).sorted())
        if let data = try? JSONEncoder().encode(proof) {
            try? data.write(to: directory.appendingPathComponent("fixture-model-state-proof.json"), options: .atomic)
        }
    }
    func setAutopilotMode(_ value: FixtureAutopilotMode) async {
        guard ready, !isTerminating else { return }
        await extrasClient.setAutopilotMode(value)
        await monitor.providerExtras?.refreshAutopilot()
    }
    func saveAutopilotProof() async {
        if let data = try? JSONEncoder().encode(await extrasClient.autopilotProof()) {
            try? data.write(to: directory.appendingPathComponent("fixture-autopilot-proof.json"), options: .atomic)
        }
    }
    func setNetworkExpiryReview(_ enabled: Bool) async {
        networkExpiryReview = enabled
        await load()
    }
    func openChatWindow() {
        guard ready, !isTerminating else { return }
        if chatWindowStore !== chat {
            chatWindow?.close()
            chatWindow = ChatWindowController(store: chat, frameAutosaveName: nil,
                defaults: defaults, updateProtection: updateProtection)
            chatWindowStore = chat
            chatWindow?.window?.title = "Bloomy Chat — Synthetic Review"
            chatWindow?.window?.setContentSize(NSSize(width: 460, height: 520))
        }
        chatWindow?.present()
    }
    private func retireChatWindow() {
        chatWindowStore?.cancelSend()
        chatWindow?.close()
        chatWindow = nil
        chatWindowStore = nil
    }
    func setFanReadback(_ value: FixtureFanReadback) async {
        guard ready, !isTerminating, scenario == .fanConfirmation else { return }
        fanReadback = value
        await extrasClient.setFanReadback(value)
        await monitor.providerExtras?.refreshFan()
        if let data = try? JSONEncoder().encode(await extrasClient.fanProof()) {
            try? data.write(to: directory.appendingPathComponent("fixture-fan-proof.json"), options: .atomic)
        }
    }
    func tick() async {
        guard ready, !isTerminating, !networkExpiryReview, !metricsReview, scenario != .frozenSettings,
              scenario.hasCurrentRuntime || scenario == .offline else { return }
        let currentScenario = scenario
        let currentMonitor = monitor
        let currentControl = control
        await publishTelemetry(scenario: currentScenario, monitor: currentMonitor, logFeed: logFeed)
        await currentControl.refreshPreservingDraft()
    }
    func delayNextControlRead() async {
        guard ready, !isTerminating else { return }
        await controllerClient.delayNextControlRead()
    }
    private func publishTelemetry(scenario: FixtureScenario, monitor: MonitorStore, logFeed: FixtureLogFeed) async {
        let generation = loadGeneration
        let previous = telemetryPublicationTask
        let publicationID = UUID()
        let task = Task { @MainActor [weak self] in
            // accept() can suspend. Read the latest retained feed only after
            // the previous publication finishes so arrivals cannot roll back.
            await previous?.value
            guard let self, !Task.isCancelled, self.ready, !self.isTerminating,
                  !self.metricsReview, generation == self.loadGeneration else { return }
            let events = await logFeed.events()
            guard !Task.isCancelled, self.ready, !self.isTerminating,
                  !self.metricsReview, generation == self.loadGeneration else { return }
            await monitor.accept(FixtureData.snapshot(scenario, now: Date(), events: events))
        }
        telemetryPublicationID = publicationID
        telemetryPublicationTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if telemetryPublicationID == publicationID { telemetryPublicationTask = nil }
    }
    var canPrependLogEvent: Bool {
        ready && !isTerminating && !proofRunning && scenario.hasCurrentRuntime
            && scenario != .frozenSettings && !networkExpiryReview && !metricsReview
    }
    func setMetricsReview(_ enabled: Bool) async {
        guard ready, !isTerminating, !proofRunning else { return }
        if !enabled, await earningsClient.readSnapshot().heldReadID != nil { return }
        metricsReview = enabled
        if enabled {
            let publication = telemetryPublicationTask
            publication?.cancel()
            await publication?.value
        } else {
            await metricsReads?.releaseHeld()
            await tick()
        }
    }
    func setNextMetricsRead(_ mode: FixtureMetricsReadMode) async {
        guard ready, !isTerminating, metricsReview else { return }
        await metricsReads?.setNext(mode)
    }
    func releaseMetricsRead(_ mode: FixtureMetricsReadMode) async {
        guard ready, !isTerminating, metricsReview else { return }
        await metricsReads?.releaseHeld(as: mode)
    }
    func appendMetricsObservation() async {
        guard ready, !isTerminating, metricsReview, let history = monitor.performanceHistory else { return }
        let date = Date()
        let model = FixtureData.modelIDs[0]
        await history.observe(PerformanceSample(observedAt: date, sourceCapturedAt: date,
            quality: .current, providerSession: "4242:1800", model: model,
            residentModels: [model], advertisedModels: [model], inferenceActive: true,
            activeRequests: 1, tokensPerSecond: 42, tokensGenerated: 1_000,
            requestsServed: 10, gpuUtilizationPercent: 35, gpuMemoryGB: 12,
            powerWatts: 70, autopilotPhase: "shadow"))
    }
    func saveMetricsReadProof() async {
        guard let metricsReads else { return }
        if let data = try? JSONEncoder().encode(await metricsReads.snapshot()) {
            try? data.write(to: directory.appendingPathComponent("fixture-metrics-read-proof.json"), options: .atomic)
        }
    }
    func showHighIdleGPU() async { await gpuProtectionProof?.highIdle() }
    func showRecoveredGPU() async { await gpuProtectionProof?.recover() }
    func saveGPUProtectionProof() { gpuProtectionProof?.save() }
    func prependLogEvent(count: Int = 1) async {
        guard canPrependLogEvent else { return }
        let generation = loadGeneration
        let currentScenario = scenario
        let currentMonitor = monitor
        let currentLogFeed = logFeed
        await currentLogFeed.prepend(at: Date(), count: count)
        guard !Task.isCancelled, canPrependLogEvent, generation == loadGeneration else { return }
        await publishTelemetry(scenario: currentScenario, monitor: currentMonitor, logFeed: currentLogFeed)
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
        retireChatWindow()
        chat.cancelSend()
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
        guard !isTerminating, cacheProofTask == nil, chatFocusProofTask == nil, modelKeyboardProofTask == nil else { return }
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
        await control.cancelCurrentOperationAndWait()
        await earningsClient.cancelHeldAndWait()
        guard !Task.isCancelled, generation == loadGeneration else { return }
        let stores = Self.makeStores(requestedScenario, defaults: defaults, directory: directory,
            capacityCapturedAt: networkExpiryReview ? Date().addingTimeInterval(-100) : nil)
        let preparedMonitor = stores.0
        let preparedControl = stores.1
        var preparationIssue: String?
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try await FixtureNetworkCacheProbe.shared.configure(directory: directory)
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
            let reads = try FixtureMetricsReads(url: performanceURL,
                proofURL: directory.appendingPathComponent("fixture-metrics-read-proof.json"))
            metricsReads = reads
            preparedMonitor.performanceHistory = PerformanceHistoryStore(url: performanceURL,
                readSamples: { interval in try await reads.samples(in: interval) },
                clearReadCache: { await reads.clearReadCache() })
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
        let gpuProof = FixtureGPUProtectionProof(defaults: defaults, directory: directory)
        preparedMonitor.attachHostGPUProtection(gpuProof.store)
        gpuProtectionProof = gpuProof
        retireChatWindow()
        chat.cancelSend()
        monitor = preparedMonitor; control = preparedControl; hosting = stores.2; chat = stores.3; extrasClient = stores.4
        controllerClient = stores.5; earningsClient = stores.6
        logFeed = stores.7
        limitedActivityModels = false
        activityRead = .normal
        await observeEarningsReads()
        fanReadback = .held
        chatVerificationTest = nil
        chatVerificationClient = nil
        issue = preparationIssue
        ready = true
    }
    func runNativeProof() {
        guard !proofRunning, ready, !isTerminating else { return }
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

    func runCacheVisibilityProof() {
        guard !proofRunning, loadTask == nil, ready, !isTerminating,
              navigation.selected == .overview else { return }
        cacheProofStatus = "Cache proof running…"
        cacheProofTask = Task { @MainActor in
            let passed = await NetworkCacheVisibilityProof.run(outputDirectory: self.directory)
            self.cacheProofStatus = passed ? "Cache proof passed" : "Cache proof failed"
            self.cacheProofTask = nil
        }
    }

    func stopForTermination() async {
        isTerminating = true
        setDashboardVisible(false)
        ready = false
        await control.cancelCurrentOperationAndWait()
        loadGeneration += 1
        let loading = loadTask
        loading?.cancel()
        await loading?.value
        loadTask = nil
        let publishing = telemetryPublicationTask
        publishing?.cancel()
        await publishing?.value
        telemetryPublicationTask = nil
        let proof = nativeProofTask
        proof?.cancel()
        await proof?.value
        nativeProofTask = nil
        let cacheProof = cacheProofTask
        cacheProof?.cancel()
        await cacheProof?.value
        cacheProofTask = nil
        let chatFocusProof = chatFocusProofTask
        chatFocusProof?.cancel()
        await chatFocusProof?.value
        chatFocusProofTask = nil
        let modelKeyboardProof = modelKeyboardProofTask
        modelKeyboardProof?.cancel()
        await modelKeyboardProof?.value
        modelKeyboardProofTask = nil
        await metricsReads?.cancelHeld()
        await earningsClient.cancelHeldAndWait()
        await popup.closeAndWait(resetContent: true)
        retireChatWindow()
        chat.cancelSend()
        await monitor.stop()
    }

    func runChatFocusProof() {
        guard !proofRunning, loadTask == nil, ready, !isTerminating,
              navigation.selected == .overview else { return }
        chatFocusProofStatus = "Chat focus proof running…"
        chatFocusProofTask = Task { @MainActor in
            let passed = await ChatComposerFocusProof.run(outputDirectory: self.directory)
            self.chatFocusProofStatus = passed ? "Chat focus proof passed" : "Chat focus proof failed"
            self.chatFocusProofTask = nil
        }
    }

    func runModelKeyboardProof() {
        guard !proofRunning, loadTask == nil, ready, !isTerminating,
              navigation.selected == .overview else { return }
        modelKeyboardProofStatus = "Model keyboard proof running…"
        modelKeyboardProofTask = Task { @MainActor in
            let passed = await ModelManageKeyboardProof.run(outputDirectory: self.directory)
            self.modelKeyboardProofStatus = passed ? "Model keyboard proof passed" : "Model keyboard proof failed"
            self.modelKeyboardProofTask = nil
        }
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
            hostingStore: model.hosting,
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
    struct NavigationEvent {
        let number: Int
        let keyCode: UInt16
        let modifiers: UInt
        let uptime: TimeInterval
    }
    private final class ResponderIdentity {
        weak var responder: NSResponder?
        let number: Int
        init(_ responder: NSResponder, number: Int) {
            self.responder = responder
            self.number = number
        }
    }
    var isEnabled = CommandLine.arguments.contains("--focus-diagnostics")
    let outputURL: URL
    private var capturedReady = false
    private var navigationKeys = 0
    private var capturedRecords = 0
    private let maximumRecords = 125
    private let maximumNavigationKeys = 24
    private let maximumViews = 384
    private let maximumLoopLength = 64
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private var responderIdentities: [ObjectIdentifier: ResponderIdentity] = [:]
    private var nextResponderIdentity = 0
    private var responderChanges = 0
    private var latestNavigation: NavigationEvent?

    init(directory: URL) {
        outputURL = directory.appendingPathComponent("focus-diagnostics.jsonl")
    }

    func captureReady(_ window: NSWindow) {
        guard isEnabled, !capturedReady else { return }
        capturedReady = true
        capture(window, phase: "ready")
    }

    func begin(_ event: NSEvent, window: NSWindow) -> NavigationEvent? {
        guard isEnabled, capturedReady, event.type == .keyDown,
              [48, 49, 123, 124, 125, 126].contains(Int(event.keyCode)),
              navigationKeys < maximumNavigationKeys,
              capturedRecords < maximumRecords else { return nil }
        navigationKeys += 1
        let navigation = NavigationEvent(number: navigationKeys, keyCode: event.keyCode,
                                         modifiers: event.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
                                         uptime: event.timestamp)
        latestNavigation = navigation
        capture(window, phase: "before", event: navigation)
        return navigation
    }

    func end(window: NSWindow, event: NavigationEvent) {
        capture(window, phase: "after", event: event)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let self, let window else { return }
            self.capture(window, phase: "next-turn", event: event)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(50)) { [weak self, weak window] in
            guard let self, let window else { return }
            self.capture(window, phase: "settled", event: event)
        }
    }

    func captureWindowState(_ window: NSWindow, phase: String) {
        // Preparation creates the isolated output directory before ready.
        guard capturedReady else { return }
        capture(window, phase: phase)
    }

    func captureResponderChange(_ window: NSWindow, requested: NSResponder?,
                                previous: NSResponder?, accepted: Bool) {
        guard isEnabled, capturedReady, responderChanges < 24,
              capturedRecords < maximumRecords else { return }
        responderChanges += 1
        capturedRecords += 1
        var record: [String: Any] = [
            "schema": 2, "phase": "responder-request",
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - startedAt,
            "previous": responderReference(previous),
            "requested": responderReference(requested),
            "firstResponder": responderReference(window.firstResponder),
            "accepted": accepted,
            "stack": Array(Thread.callStackSymbols.dropFirst(1).prefix(12)).map { String($0.prefix(240)) }
        ]
        if let latestNavigation { record["eventNumber"] = latestNavigation.number }
        write(record)
    }

    private func responderReference(_ responder: NSResponder?, ids: [ObjectIdentifier: Int] = [:]) -> [String: Any] {
        guard let responder else { return ["kind": "nil"] }
        let identity = ObjectIdentifier(responder)
        var result: [String: Any] = ["class": String(String(describing: type(of: responder)).prefix(160))]
        if let id = ids[identity] { result["id"] = id }
        if responderIdentities[identity]?.responder !== responder {
            nextResponderIdentity += 1
            responderIdentities[identity] = ResponderIdentity(responder, number: nextResponderIdentity)
        }
        result["stableID"] = responderIdentities[identity]?.number
        return result
    }

    private func capture(_ window: NSWindow, phase: String, event: NavigationEvent? = nil) {
        // Lifecycle and key-event evidence share the original overall limit.
        guard isEnabled, capturedRecords < maximumRecords else { return }
        capturedRecords += 1
        responderIdentities = responderIdentities.filter { $0.value.responder != nil }
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
            responderReference(responder, ids: ids)
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
            node["stableID"] = reference(view)["stableID"]
            if let control = view as? NSControl { node["enabled"] = control.isEnabled }
            if let table = view as? NSTableView {
                node["tableRows"] = table.numberOfRows
                node["selectedRows"] = Array(table.selectedRowIndexes)
            }
            return node
        }
        let start = (window.firstResponder as? NSView) ?? window.initialFirstResponder ?? window.contentView
        var record: [String: Any] = [
            "schema": 2, "phase": phase,
            "elapsedSeconds": ProcessInfo.processInfo.systemUptime - startedAt,
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
        if let event {
            record["eventNumber"] = event.number
            record["navigationKeyCode"] = event.keyCode
            record["navigationModifiers"] = event.modifiers
            record["navigationElapsedSeconds"] = event.uptime - startedAt
        }
        write(record)
    }

    private func write(_ record: [String: Any]) {
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
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        let previous = firstResponder
        let accepted = super.makeFirstResponder(responder)
        focusDiagnostics?.captureResponderChange(self, requested: responder,
                                                previous: previous, accepted: accepted)
        return accepted
    }
    override func sendEvent(_ event: NSEvent) {
        let eventNumber = focusDiagnostics?.begin(event, window: self)
        super.sendEvent(event)
        if let eventNumber { focusDiagnostics?.end(window: self, event: eventNumber) }
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
            if window.contentView?.frame.size != size {
                window.setContentSize(size)
            }
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
            Menu("CLI check") {
                ForEach(FixtureCLIUpdateRead.allCases) { read in
                    Button(read.rawValue) {
                        model.cliUpdateRead = read
                        Task {
                            await FixtureCLIUpdates.shared.setRead(read)
                            await CLIUpdateStatusStore.shared.refresh()
                        }
                    }
                }
            }
            .accessibilityLabel("Synthetic CLI update check: \(model.cliUpdateRead.rawValue)")
            .help("Changes only the fake update check; no network, installation or provider restart.")
            if model.scenario == .fanConfirmation {
                Menu("Fan readback") {
                    ForEach(FixtureFanReadback.allCases) { value in
                        Button(value.rawValue) { Task { await model.setFanReadback(value) } }
                    }
                }
                .accessibilityLabel("Synthetic fan readback: \(model.fanReadback.rawValue)")
                .help("Changes only fake readings for the same submitted policy. No helper or Mac fan is controlled.")
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.orange.opacity(0.08))
    }
}

private struct FixtureReviewView: View {
    @ObservedObject var model: FixtureModel
    @ObservedObject private var navigation: DashboardNavigation
    @AppStorage private var appearance: String
    @State private var compact: Bool
    private var showsReviewBanner: Bool {
        #if FIXTURE_HIDE_REVIEW_BANNER
        false
        #else
        true
        #endif
    }
    init(model: FixtureModel) {
        self.model = model
        self.navigation = model.navigation
        #if FIXTURE_COMPACT
        _compact = State(initialValue: true)
        #else
        _compact = State(initialValue: false)
        #endif
        _appearance = AppStorage(wrappedValue: "light", ApplicationAppearance.defaultsKey, store: model.defaults)
    }
    var body: some View {
            VStack(spacing: 0) {
                if showsReviewBanner {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("SYNTHETIC REVIEW · no live API calls").font(.headline)
                        Text("CPU/GPU off · Mac identity and thermal state actual; fan/°C samples synthetic")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Picker("Scenario", selection: $model.scenario) {
                        ForEach(FixtureScenario.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(width: 150).disabled(model.proofRunning)
                    Toggle("Dark", isOn: Binding(get: { appearance == "dark" }, set: { appearance = $0 ? "dark" : "light" })).toggleStyle(.checkbox)
                    Toggle("800 × 560", isOn: $compact).toggleStyle(.checkbox)
                    FixturePopupButton(show: { model.presentMenuBarPopup?() }, enabled: model.ready).frame(width: 64, height: 24)
                    Button("Reload") { Task { await model.load() } }.disabled(model.proofRunning)
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
                    Menu("Data checks") {
                        Button("Delay next control read for 20 seconds") {
                            Task { await model.delayNextControlRead() }
                        }
                        .disabled(!model.ready)
                        Menu("Synthetic Autopilot") {
                            ForEach(FixtureAutopilotMode.allCases, id: \.self) { mode in
                                Button(mode.rawValue) { Task { await model.setAutopilotMode(mode) } }
                            }
                            Divider()
                            Button("Save action counts") { Task { await model.saveAutopilotProof() } }
                        }
                        Menu("Synthetic host GPU protection") {
                            Button("High GPU while provider idle") { Task { await model.showHighIdleGPU() } }
                            Button("GPU recovered") { Task { await model.showRecoveredGPU() } }
                            Button("Save protection action counts") { model.saveGPUProtectionProof() }
                        }
                        Button(model.cacheProofStatus) { model.runCacheVisibilityProof() }
                            .disabled(model.proofRunning || !model.ready || navigation.selected != .overview)
                        Button(model.chatFocusProofStatus) { model.runChatFocusProof() }
                            .disabled(model.proofRunning || !model.ready || navigation.selected != .overview)
                        Button(model.modelKeyboardProofStatus) { model.runModelKeyboardProof() }
                            .disabled(model.proofRunning || !model.ready || navigation.selected != .overview)
                        Menu("Synthetic Metrics reads") {
                            Button(model.metricsReview ? "Resume synthetic observations" : "Pause synthetic observations") {
                                Task { await model.setMetricsReview(!model.metricsReview) }
                            }
                            .disabled(model.earningsReadState.heldReadID != nil)
                            ForEach([FixtureMetricsReadMode.normal, .hold, .fail, .empty], id: \.rawValue) { mode in
                                Button("Next read: \(mode.rawValue)") { Task { await model.setNextMetricsRead(mode) } }
                                    .disabled(!model.metricsReview)
                            }
                            Button("Release held read") { Task { await model.releaseMetricsRead(.normal) } }
                                .disabled(!model.metricsReview)
                            Button("Release held read as empty") { Task { await model.releaseMetricsRead(.empty) } }
                                .disabled(!model.metricsReview)
                            Button("Fail held read") { Task { await model.releaseMetricsRead(.fail) } }
                                .disabled(!model.metricsReview)
                            Button("Append current observation") { Task { await model.appendMetricsObservation() } }
                                .disabled(!model.metricsReview)
                            Button("Save read counts") { Task { await model.saveMetricsReadProof() } }
                        }
                        Divider()
                        Button("Prepend one synthetic log event") {
                            Task { await model.prependLogEvent() }
                        }
                        .disabled(!model.canPrependLogEvent)
                        .help("Adds one uniquely named event; older log payloads stay unchanged within the 100-event bound.")
                        Button("Fill synthetic log buffer (100 arrivals)") {
                            Task { await model.prependLogEvent(count: 100) }
                        }
                        .disabled(!model.canPrependLogEvent)
                        .help("One bounded synthetic publication replaces retained events; no real provider logs are touched.")
                        Menu("Display time zone: \(model.logTimeZone.rawValue)") {
                            ForEach(FixtureLogTimeZone.allCases) { zone in
                                Button(zone.rawValue) { model.logTimeZone = zone }
                            }
                        }
                        .help("Changes only this review dashboard's SwiftUI display environment; the Mac's preferences remain unchanged.")
                        Button(model.limitedActivityModels ? "Restore all Earnings models" : "Report only Qwen in Earnings") {
                            Task { await model.limitActivityModels(!model.limitedActivityModels) }
                        }
                        .disabled(model.earningsReadState.heldReadID != nil)
                        Menu("Synthetic Earnings reads") {
                            Button(model.metricsReview ? "Resume synthetic observations" : "Pause synthetic observations") {
                                Task { await model.setMetricsReview(!model.metricsReview) }
                            }
                            .disabled(model.earningsReadState.heldReadID != nil)
                            Text(model.earningsReadState.heldReadID.map { "Held read \($0)" }
                                ?? "Next read: \(model.earningsReadState.nextMode.rawValue)")
                            ForEach(FixtureEarningsReadMode.allCases) { mode in
                                Button("Next read: \(mode.rawValue)") { Task { await model.setNextEarningsRead(mode) } }
                                    .disabled(!model.metricsReview || model.earningsReadState.heldReadID != nil)
                            }
                            Divider()
                            Button("Release held read successfully") { Task { await model.releaseEarningsRead(.normal) } }
                                .disabled(model.earningsReadState.heldReadID == nil)
                            Button("Release held read as empty") { Task { await model.releaseEarningsRead(.empty) } }
                                .disabled(model.earningsReadState.heldReadID == nil)
                            Button("Fail held read") { Task { await model.releaseEarningsRead(.fail) } }
                                .disabled(model.earningsReadState.heldReadID == nil)
                            Divider()
                            Text("Gates: \(model.earningsReadState.started) started · \(model.earningsReadState.completed) completed")
                            Text("\(model.earningsReadState.failed) failed · \(model.earningsReadState.cancelled) cancelled · \(model.earningsReadState.empty) empty")
                            Button("Save Earnings read counts") { Task { await model.saveEarningsReadProof() } }
                        }
                        .help("Inert first-query gate. Choose a next read, then use Earnings Refresh or change scope.")
                        Menu("Earnings read: \(model.activityRead.rawValue)") {
                            ForEach(FixtureActivityRead.allCases) { read in
                                Button(read.rawValue) { Task { await model.setActivityRead(read) } }
                            }
                        }
                        .disabled(model.earningsReadState.heldReadID != nil)
                        Button("Remove Gemma from model inventory") {
                            Task { await model.removeGemmaFromInventory() }
                        }
                        Button("Save model control state") { Task { await model.saveModelControlProof() } }
                        Button("Limit model sheet to 360 pt") { model.modelSheetHeightLimit = 360 }
                        Button("Use screen height for model sheet") { model.modelSheetHeightLimit = nil }
                        Button(model.networkExpiryReview ? "End network expiry review" : "Network expiry in 20 seconds") {
                            Task { await model.setNetworkExpiryReview(!model.networkExpiryReview) }
                        }
                    }
                    .help("Changes only in-memory synthetic read results. Use Earnings Refresh after changing its model list.")
                    .disabled(!model.ready || model.proofRunning)
                    Spacer(minLength: 0)
                    Button(model.nativeProofStatus) { model.runNativeProof() }
                        .disabled(!model.ready || model.proofRunning)
                        .help("Run finite synthetic native checks; results: \(model.directory.path)")
                }
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Color.orange.opacity(0.08))
                if let issue = model.issue { Text(issue).foregroundStyle(.red).padding(6) }
                }
                DashboardRootView(store: model.monitor, controlStore: model.control, hostingStore: model.hosting,
                    chatStore: model.chat, openChatWindow: { model.openChatWindow() },
                    navigation: model.navigation, settingsDraft: model.settingsDraft,
                    chatDraft: model.chatDraft, hostingDraft: model.hostingDraft, updateProtection: model.updateProtection)
                    .environment(\.modelManagerSheetMaximumHeight, model.modelSheetHeightLimit)
                    .environment(\.timeZone, model.logTimeZone.value)
                    .disabled(model.proofRunning)
                    .saturation(model.grayscale ? 0 : 1)
                    .overlay { if !model.ready { ProgressView("Preparing synthetic sources…").padding().background(.regularMaterial) } }
            }
            .defaultAppStorage(model.defaults)
            .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
            .frame(minWidth: 800, minHeight: 560)
            .background(FixtureWindowCapture(size: compact ? CGSize(width: 800, height: 560) : CGSize(width: 1280, height: 900), ready: model.ready, traceEnabled: model.focusTracing))
            .task {
                ApplicationAppearance.applyStored(from: model.defaults)
                await model.load()
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(5)) } catch { return }
                    await model.tick()
                }
            }
            .onChange(of: model.scenario) { _, _ in Task { await model.load() } }
            .onChange(of: appearance) { _, value in ApplicationAppearance.apply(AppAppearanceMode(storedValue: value)) }
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
    private var visibilityRecords: [[String: Any]] = []
    private var visibilityObserver: DashboardVisibilityObserver?

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
        visibilityObserver = DashboardVisibilityObserver(window: window) { [weak self] visible in
            guard let self else { return }
            self.model.setDashboardVisible(visible)
            self.recordVisibility("observer.changed")
        }
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
        add("Hide Bloomy Dashboard Fixture", action: #selector(NSApplication.hide(_:)),
            key: "h", target: application, to: appMenu)
        appMenu.addItem(.separator())
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
        add("Toggle bounded focus diagnostics", action: #selector(toggleFocusDiagnostics),
            target: self, to: windowMenu)
        windowMenu.addItem(.separator())
        add("Show Dashboard", action: #selector(showDashboard), key: "d",
            modifiers: [.command, .shift], target: self, to: windowMenu)
        windowMenu.addItem(.separator())
        add("Remove Gemma from inventory (synthetic)", action: #selector(removeReviewGemma),
            key: "r", modifiers: [.command, .option, .control], target: self, to: windowMenu)
        add("Hide Gemma temporarily (synthetic)", action: #selector(hideReviewGemma), target: self, to: windowMenu)
        add("Restore Gemma (synthetic)", action: #selector(restoreReviewGemma), target: self, to: windowMenu)
        add("Fail next model controls read (synthetic)", action: #selector(failNextReviewModelRead), target: self, to: windowMenu)
        add("Save model draft state (synthetic)", action: #selector(saveReviewModelState), target: self, to: windowMenu)
        add("Check model feedback layout (synthetic)", action: #selector(checkReviewModelLayout), target: self, to: windowMenu)
        application.mainMenu = mainMenu
        application.windowsMenu = windowMenu
    }

    @objc private func showDashboard() {
        presentDashboard()
    }

    // Enable the same passive trace when the review banner is omitted. This
    // menu never changes the key-view loop or requests a first responder.
    @objc private func toggleFocusDiagnostics() { model.focusTracing.toggle() }

    @objc private func removeReviewGemma() {
        Task { await model.removeGemmaFromInventory() }
    }
    @objc private func hideReviewGemma() { Task { await model.setGemmaTemporarilyHidden(true) } }
    @objc private func restoreReviewGemma() { Task { await model.setGemmaTemporarilyHidden(false) } }
    @objc private func failNextReviewModelRead() { Task { await model.failNextModelControlRead() } }
    @objc private func saveReviewModelState() { Task { await model.saveModelStateProof() } }
    @objc private func checkReviewModelLayout() {
        guard let window, model.ready else { return }
        let result = ModelFeedbackLayoutProof.run(window: window)
        if let data = try? JSONEncoder().encode(result) {
            try? data.write(to: model.directory.appendingPathComponent("fixture-model-layout-proof.json"), options: .atomic)
        }
    }

    private func presentDashboard(section: DashboardDestination? = nil, settingsPage: SettingsPage? = nil) {
        guard !terminationRequested, let window else { return }
        if let settingsPage { model.navigation.settingsPage = settingsPage }
        if let section { model.navigation.selected = section }
        if section != nil || settingsPage != nil { model.navigation.revealSelectedSection() }
        visibilityObserver?.resetForPresentation()
        window.deminiaturize(nil)
        NSApplication.shared.activate()
        window.makeKeyAndOrderFront(nil)
        visibilityObserver?.refreshVisibility()
        model.focusDiagnostics.captureWindowState(window, phase: "window.presented")
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    // Share production visibility policy. Store.start() remains unused, so
    // native visibility changes cannot start autonomous collectors.
    private func recordVisibility(_ phase: String) {
        guard let window else { return }
        visibilityRecords.append([
            "phase": phase, "uptime": ProcessInfo.processInfo.systemUptime,
            "applicationHidden": NSApplication.shared.isHidden,
            "windowVisible": window.isVisible, "miniaturized": window.isMiniaturized,
            "compositorVisible": window.occlusionState.contains(.visible),
            "displayEnabled": model.monitor.dashboardVisible
        ])
        if visibilityRecords.count > 64 { visibilityRecords.removeFirst(visibilityRecords.count - 64) }
        guard let data = try? JSONSerialization.data(withJSONObject: visibilityRecords, options: [.sortedKeys]) else { return }
        try? data.write(to: model.directory.appendingPathComponent("dashboard-visibility-proof.json"), options: .atomic)
    }
    func applicationDidHide(_ notification: Notification) { recordVisibility("application.hidden") }
    func applicationDidUnhide(_ notification: Notification) { recordVisibility("application.unhidden") }

    func windowDidMiniaturize(_ notification: Notification) {
        recordVisibility("window.minimized")
        if let window { model.focusDiagnostics.captureWindowState(window, phase: "window.didMiniaturize") }
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        recordVisibility("window.restored")
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
