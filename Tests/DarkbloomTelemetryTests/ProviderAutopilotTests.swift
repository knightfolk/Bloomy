import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Native Autopilot integration")
struct ProviderAutopilotTests {
    @Test("consent and shadow evidence never imply active control; unknown protocol refuses")
    func boundedStatus() throws {
        let status = try ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: true, live: true))
        #expect(status.isEnrolled)
        #expect(status.isLiveConfirmed)
        #expect(!status.isActivelyManaging)
        #expect(status.phase == .shadow)
        #expect(status.selectedModels == ["EigenLabs/Qwen3.8-27B-4bit-mtp"])
        #expect(!status.allows(.resume))
        #expect(throws: ProviderExtrasParseError.unsupportedValue) {
            try ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: true, live: true, protocolVersion: 4))
        }
        #expect(try ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: false)).live == nil)
    }

    @Test("malformed consent and unbounded model payloads cannot enable controls")
    func malformedStatus() {
        #expect(throws: ProviderExtrasParseError.invalidPayload) {
            try ProviderExtrasParser.parseAutopilot(Data(#"{"live":{}}"#.utf8))
        }
        #expect(throws: ProviderExtrasParseError.invalidValue) {
            try ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: true, models: []))
        }
        #expect(throws: ProviderExtrasParseError.invalidValue) {
            try ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: true, models: [String(repeating: "x", count: 257)]))
        }
        #expect(throws: ProviderExtrasParseError.invalidPayload) {
            try ProviderExtrasParser.parseAutopilot(Data(repeating: 32, count: 256 * 1_024 + 1))
        }
    }

    @Test("start enrolls internally with saved models and existing hosting flags")
    func commandPreservesFlags() {
        let command = DarkbloomCommand.start(executable: URL(fileURLWithPath: "/fixture/darkbloom"),
            config: URL(fileURLWithPath: "/fixture/provider.toml"), models: ["first", "second"],
            hosting: HostingOptions(mode: .unified, port: 8123), autopilot: true)
        #expect(command.arguments == ["start", "--config", "/fixture/provider.toml", "--timeout", "600",
            "--autopilot", "--model", "first", "--model", "second", "--local-endpoint", "--port", "8123", "--bind", "127.0.0.1"])
        #expect(!command.arguments.contains("--all"))
        #expect(!command.arguments.contains("--schedule"))
        #expect(!command.arguments.contains("--idle-timeout"))
    }

    @Test("ordinary offline models pass; embedded and catalog gates need runtime evidence")
    func eligibility() {
        #expect(ProviderAutopilotModelPreflight.isEligible(testModel("ordinary"), runtimeCapabilities: nil))
        let gated = testModel("EigenLabs/Qwen3.8-27B-4bit-mtp")
        #expect(!ProviderAutopilotModelPreflight.isEligible(gated, runtimeCapabilities: nil))
        #expect(!ProviderAutopilotModelPreflight.isEligible(gated, runtimeCapabilities: ["apple_m5"]))
        #expect(ProviderAutopilotModelPreflight.isEligible(gated, runtimeCapabilities: ["apple_m5", "mlx_nax"]))
        #expect(!ProviderAutopilotModelPreflight.isEligible(testModel("other", requirements: ["future_feature"]), runtimeCapabilities: []))
    }

    @Test("policy baseline preserves defaults and detects schedule, idle and reserve changes")
    func preservation() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("provider.toml")
        try Data("[backend]\n[provider]\n".utf8).write(to: path)
        let absent = try ProviderAutopilotPreservationBaseline.read(path)
        try Data("[backend]\nidle_timeout_mins = 60\n[provider]\nmemory_reserve_gb = 4\n[coordinator]\nprivate_only = false\n[schedule]\nenabled = false\n".utf8).write(to: path)
        #expect(try ProviderAutopilotPreservationBaseline.read(path) == absent)
        try Data("[backend]\nidle_timeout_mins=0\n[provider]\nmemory_reserve_gb=8\n[schedule]\nenabled=true\n[[schedule.windows]]\ndays=[\"mon\"]\nstart=\"09:00\"\nend=\"17:00\"\n".utf8).write(to: path)
        #expect(try ProviderAutopilotPreservationBaseline.read(path) != absent)
    }

    @Test("policy comparison normalizes equivalent numeric, quote and weekday forms")
    func semanticNormalization() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("provider.toml")
        try Data("[provider]\nmemory_reserve_gb=4\n[schedule]\nenabled=true\n[[schedule.windows]]\ndays=['mon','tue']\nstart='09:00'\nend='17:00'\n".utf8).write(to: path)
        let original = try ProviderAutopilotPreservationBaseline.read(path)
        try Data("[provider]\nmemory_reserve_gb=4.0\n[schedule]\nenabled=true\n[[schedule.windows]]\ndays=[\"Tuesday\",\"Monday\"]\nstart=\"09:00\"\nend=\"17:00\"\n".utf8).write(to: path)
        #expect(try ProviderAutopilotPreservationBaseline.read(path) == original)
    }

    @Test("every missing saved selector blocks dispatch, without keeping the valid subset")
    func allSelectorsRequired() async throws {
        let harness = try AutopilotHarness(models: ["ordinary", "missing"])
        defer { harness.cleanup() }
        await #expect(throws: ProviderControlError.self) {
            _ = try await harness.service.performAutopilotEnrollment(hosting: .default, onPhase: nil)
        }
        #expect(await harness.runner.startCount == 0)
    }

    @Test("alias preload mismatch is refused before exact-model startup rewrites config")
    func aliasPreloadGuard() async throws {
        let harness = try AutopilotHarness(models: ["family-alias"], preloaded: ["family-alias"], catalogFamily: "family-alias")
        defer { harness.cleanup() }
        await #expect(throws: ProviderControlError.self) {
            _ = try await harness.service.performAutopilotEnrollment(hosting: .default, onPhase: nil)
        }
        #expect(await harness.runner.startCount == 0)
    }

    @Test("enrollment failure preserves actionable Models repair guidance in the store")
    @MainActor
    func aliasPreloadStoreGuidance() async throws {
        let harness = try AutopilotHarness(models: ["family-alias"], preloaded: ["family-alias"], catalogFamily: "family-alias")
        defer { harness.cleanup() }
        let store = ProviderControlStore(controller: harness.service, hostingOptions: { .default })
        #expect(await store.enrollAutopilot() == false)
        #expect(store.errorMessage == "Saved preload aliases would lose their enabled match during enrollment. In Models, clear those preloads or reselect the exact downloaded model IDs, save, then retry.")
        #expect(await harness.runner.startCount == 0)
    }

    @Test("enrollment guidance accepts only fixed diagnostics", arguments: [
        "Autopilot enrollment is unavailable in this build",
        "Autopilot requires network provider serving",
        "Refresh Autopilot status before enrolling",
        "Autopilot is already enrolled. Refresh its current settings instead of restarting.",
        "Autopilot requires a saved network model selection"
    ])
    @MainActor
    func fixedEnrollmentGuidance(reason: String) async {
        let controller = RefusedAutopilotController(error: .liveSwitchUnavailable(reason))
        let store = ProviderControlStore(controller: controller, hostingOptions: { .default })
        #expect(await store.enrollAutopilot() == false)
        #expect(store.errorMessage == reason)
    }

    @Test("untrusted enrollment diagnostics remain hidden")
    @MainActor
    func unsafeEnrollmentGuidance() async {
        let controller = RefusedAutopilotController(error: .liveSwitchUnavailable("private path /Users/private/secret"))
        let store = ProviderControlStore(controller: controller, hostingOptions: { .default })
        #expect(await store.enrollAutopilot() == false)
        #expect(store.errorMessage == "Autopilot enrollment is unavailable. Refresh before trying again.")
    }

    @Test("nonzero enrollment reconciles saved consent and policies but does not claim live")
    func nonzeroReconciliation() async throws {
        let harness = try AutopilotHarness(models: ["ordinary"], startExit: 1)
        defer { harness.cleanup() }
        let result = try await harness.service.performAutopilotEnrollment(hosting: .default, onPhase: nil)
        #expect(!result.commandSucceeded)
        #expect(result.savedPolicyPreserved)
        #expect(result.savedEnrollmentConfirmed)
        #expect(!result.liveEnrollmentConfirmed)
        #expect(result.controls.snapshot != nil)
        #expect(await harness.runner.statusReads == 2)
        #expect(await harness.runner.startCount == 1)
    }

    @Test("launched cancellation and drain timeout still reconcile saved enrollment")
    func ambiguousEnrollmentReconciliation() async throws {
        for failure in [AutopilotStartFailure.cancelled, .timedOut] {
            let harness = try AutopilotHarness(models: ["ordinary"], startFailure: failure)
            defer { harness.cleanup() }
            let result = try await harness.service.performAutopilotEnrollment(hosting: .default, onPhase: nil)
            #expect(!result.commandSucceeded)
            #expect(result.savedEnrollmentConfirmed)
            #expect(!result.liveEnrollmentConfirmed)
            #expect(result.controls.snapshot != nil)
            #expect(await harness.runner.statusReads == 2)
            #expect(await harness.runner.startCount == 1)
        }
    }

    @Test("already enrolled and private-only configurations never restart")
    func noRedundantStart() async throws {
        let existing = try AutopilotHarness(models: ["ordinary"], enrolled: true)
        defer { existing.cleanup() }
        await #expect(throws: ProviderControlError.self) {
            _ = try await existing.service.performAutopilotEnrollment(hosting: .default, onPhase: nil)
        }
        #expect(await existing.runner.startCount == 0)
        let privateHarness = try AutopilotHarness(models: ["ordinary"], privateOnly: true)
        defer { privateHarness.cleanup() }
        await #expect(throws: ProviderControlError.self) {
            _ = try await privateHarness.service.performAutopilotEnrollment(hosting: .default, onPhase: nil)
        }
        #expect(await privateHarness.runner.startCount == 0)
    }

    @Test("cancelled policy writes still merge authoritative saved pause into the store")
    @MainActor
    func cancelledPolicyStoreReconciliation() async throws {
        let client = CancelledAutopilotPolicyClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        #expect(store.snapshot?.autopilotStatus?.value?.configuredPaused == false)
        let mutation = Task { @MainActor in
            do { try await store.setAutopilotPolicy(.pause); return false }
            catch { return true }
        }
        await client.waitUntilMutationStarted()
        mutation.cancel()
        #expect(await mutation.value)
        #expect(store.autopilotEvidenceIsFresh)
        #expect(store.snapshot?.autopilotStatus?.value?.configuredPaused == true)
        #expect(store.snapshot?.autopilotStatus?.value?.allows(.resume) == true)
    }

    @Test("confirmed enrollment history reflects observed success after caller cancellation")
    @MainActor
    func cancelledConfirmedEnrollmentHistory() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let controller = CancelledConfirmedAutopilotController()
        let store = ProviderControlStore(controller: controller, hostingOptions: { .default })
        let history = ActionHistoryStore(url: directory.appendingPathComponent("history.sqlite"))
        store.actionHistory = history
        let enrollment = Task { @MainActor in await store.enrollAutopilot() }
        await controller.waitUntilStarted()
        store.cancelCurrentOperation()
        await controller.release()
        #expect(await enrollment.value)
        #expect(history.events.first?.action == .autopilotEnrollment)
        #expect(history.events.first?.outcome == .succeeded)
        #expect(history.events.first?.reason == nil)
    }

    @Test("enrollment cancellation fixture retains release before waiter registration")
    func enrollmentFixtureReleaseLatch() async throws {
        let controller = CancelledConfirmedAutopilotController()
        await controller.release()
        let result = try await controller.performAutopilotEnrollment(hosting: .default, onPhase: nil)
        #expect(result.liveEnrollmentConfirmed)
    }

    @Test("shared background cadence skips held visible fan reads and only renews Autopilot evidence")
    @MainActor
    func sharedAutopilotPolling() async throws {
        let clock = AutopilotPollingClock()
        let client = AutopilotPollingClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refreshBackground()
        let initial = store.snapshot
        let token = store.beginVisibleFanObservation()
        await client.waitUntilFanBlocked()
        let safetyRelease = Task {
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await client.releaseFan()
        }
        defer { safetyRelease.cancel() }
        await store.refreshBackground()
        #expect(await client.statusReads == 0)
        #expect(await client.fullReads == 1)
        #expect(await client.released == false)
        #expect(store.snapshot?.autopilotStatus == initial?.autopilotStatus)
        await client.releaseFan()
        let stopped = store.endVisibleFanObservation(token)
        await stopped?.value
        clock.advance()
        await store.refreshBackground()
        #expect(await client.fullReads == 1)
        #expect(await client.statusReads == 1)
        #expect(store.snapshot?.capturedAt == initial?.capturedAt)
        #expect(store.snapshot?.idlePolicy == initial?.idlePolicy)
        guard case .available(_, let capturedAt) = store.snapshot?.autopilotStatus else {
            Issue.record("Expected fresh Autopilot evidence"); return
        }
        #expect(capturedAt == clock.now())
        await store.stop()
    }

    @Test("legacy extras clients do not trigger a full read for unsupported Autopilot polling")
    func legacyPollingDefault() async {
        let client = LegacyAutopilotPollingClient()
        let status = await client.refreshAutopilot()
        #expect(await client.fullReads == 0)
        guard case .unavailable = status else { Issue.record("Expected unsupported status"); return }
    }

    @Test("failed refresh retains explicitly stale evidence and refuses policy writes")
    @MainActor
    func staleStore() async throws {
        let client = AutopilotStoreClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        #expect(store.autopilotEvidenceIsFresh)
        await client.fail()
        await store.refreshAutopilot()
        guard case .stale = store.snapshot?.autopilotStatus else { Issue.record("Expected retained stale status"); return }
        #expect(!store.autopilotEvidenceIsFresh)
        await #expect(throws: ProviderSettingsEvidenceError.self) { try await store.setAutopilotPolicy(.pause) }
        #expect(await client.mutations == 0)
    }
}

private func testModel(_ id: String, requirements: [String]? = nil) -> CatalogModel {
    CatalogModel(id: id, displayName: id, family: id, modelType: "text", capabilities: ["text"],
                 sizeGB: 1, minimumRAMGB: 1, active: true, requiredProviderCapabilities: requirements)
}
private func autopilotJSON(enabled: Bool, live: Bool = false, protocolVersion: Int = 3,
                           models: [String] = ["EigenLabs/Qwen3.8-27B-4bit-mtp"], paused: Bool = false) -> Data {
    var payload: [String: Any] = ["configured": ["enabled": enabled, "consent_recorded": enabled,
        "paused": paused, "selected_models": models, "pinned_models": [], "revision": enabled ? "revision" : "",
        "min_idle_seconds": 120, "min_dwell_seconds": 180],
        "operation": ["reason": "/private/secret", "elapsedMs": 10], "phase": live ? "shadow" : "off"]
    if live { payload["live"] = ["protocol": protocolVersion, "enabled": true, "active": false,
        "observe_only": true, "paused": false, "cached_only": true, "revision": "revision",
        "session_id": "secret", "weight_hash": "secret"] }
    return try! JSONSerialization.data(withJSONObject: payload)
}
private actor AutopilotStoreClient: ProviderExtrasProviding {
    private var failing = false
    var mutations = 0
    func fail() { failing = true }
    func refreshAutopilot() async -> SourceAvailability<ProviderAutopilotStatus> {
        failing ? .unavailable(reason: "unavailable") : .available(
            value: try! ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: true)), capturedAt: Date())
    }
    func refresh() async -> ProviderExtrasSnapshot {
        ProviderExtrasSnapshot(capturedAt: Date(), idlePolicy: .unavailable(reason: "fixture"),
            betaFeatures: .unavailable(reason: "fixture"), fanStatus: .unavailable(reason: "fixture"),
            autopilotStatus: await refreshAutopilot())
    }
    func setAutopilotPolicy(_ action: ProviderAutopilotPolicyAction) async throws { mutations += 1 }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}

private struct AutopilotHarness {
    let directory: URL
    let runner: AutopilotRunner
    let service: ProviderControlService
    init(models: [String], startExit: Int32 = 0, enrolled: Bool = false, privateOnly: Bool = false,
         startFailure: AutopilotStartFailure? = nil, preloaded: [String] = [],
         catalogFamily: String = "ordinary") throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let policy = DarkbloomSourcePolicy(homeDirectory: directory, environmentPath: "")
        try FileManager.default.createDirectory(at: policy.providerConfig.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: policy.cliCandidates[0].deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: policy.cliCandidates[0])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: policy.cliCandidates[0].path)
        let encodedModels = String(data: try JSONSerialization.data(withJSONObject: models), encoding: .utf8)!
        let encodedPreloads = String(data: try JSONSerialization.data(withJSONObject: preloaded), encoding: .utf8)!
        try Data("[backend]\nenabled_models=\(encodedModels)\npreload_models=\(encodedPreloads)\nidle_timeout_mins=60\n[coordinator]\nprivate_only=\(privateOnly)\n[provider]\nmemory_reserve_gb=4\n".utf8).write(to: policy.providerConfig)
        runner = AutopilotRunner(startExit: startExit, enrolled: enrolled, startFailure: startFailure, catalogFamily: catalogFamily)
        let config = LocalProviderConfigStore(configURL: policy.providerConfig, executable: policy.cliCandidates[0], runner: runner)
        service = ProviderControlService(policy: policy, telemetrySource: NoAutopilotDaemon(), configStore: config, runner: runner)
    }
    func cleanup() { try? FileManager.default.removeItem(at: directory) }
}
private enum AutopilotStartFailure: Equatable, Sendable { case cancelled, timedOut }
private actor AutopilotRunner: ProcessExecuting {
    let startExit: Int32
    let startFailure: AutopilotStartFailure?
    let catalogFamily: String
    var enrolled: Bool
    var startCount = 0
    var statusReads = 0
    init(startExit: Int32, enrolled: Bool, startFailure: AutopilotStartFailure?, catalogFamily: String) {
        self.startExit = startExit; self.enrolled = enrolled; self.startFailure = startFailure; self.catalogFamily = catalogFamily
    }
    func run(_ command: ProcessCommand, timeout: Duration, outputLimit: Int,
             onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws -> CommandResult {
        let args = command.arguments
        let data: Data
        var exit: Int32 = 0
        if args.first == "autopilot" {
            statusReads += 1; data = autopilotJSON(enabled: enrolled, models: ["ordinary"])
        } else if args.first == "start" {
            startCount += 1; enrolled = true
            if startFailure == .cancelled { throw CancellationError() }
            if startFailure == .timedOut { throw ProcessRunnerError.timedOut }
            data = Data(); exit = startExit
        } else if args.prefix(2) == ["models", "catalog"] {
            data = try JSONSerialization.data(withJSONObject: [["id": "ordinary", "display_name": "Ordinary", "family": catalogFamily,
                "model_type": "text", "capabilities": ["text"], "size_gb": 1, "min_ram_gb": 1, "active": true]])
        } else {
            data = Data(#"{"cacheDirectory":"/fixture/cache","filteredByConfig":false,"models":[{"id":"ordinary","model_type":"text","size_bytes":1}]}"#.utf8)
        }
        return CommandResult(exitCode: exit, standardOutput: data, standardError: Data())
    }
}
private struct NoAutopilotDaemon: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw ProviderExtrasParseError.invalidPayload }
    func readLoadedModels() async throws -> LoadedModelsState { throw ProviderExtrasParseError.invalidPayload }
    func readStatus() async throws -> StatusSnapshot { throw ProviderExtrasParseError.invalidPayload }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}

private actor CancelledAutopilotPolicyClient: ProviderExtrasProviding {
    private var paused = false
    private var started = false
    private var waiter: CheckedContinuation<Void, Never>?
    func waitUntilMutationStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            if started { continuation.resume() } else { waiter = continuation }
        }
    }
    func refresh() async -> ProviderExtrasSnapshot {
        ProviderExtrasSnapshot(capturedAt: Date(), idlePolicy: .unavailable(reason: "fixture"),
            betaFeatures: .unavailable(reason: "fixture"), fanStatus: .unavailable(reason: "fixture"),
            autopilotStatus: .available(value: try! ProviderExtrasParser.parseAutopilot(
                autopilotJSON(enabled: true, paused: paused)), capturedAt: Date()))
    }
    func setAutopilotPolicy(_ action: ProviderAutopilotPolicyAction) async throws {
        paused = true
        started = true
        waiter?.resume(); waiter = nil
        // Cancellation happens after policy persistence but before completion.
        try await Task.sleep(for: .seconds(60))
    }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}

private actor CancelledConfirmedAutopilotController: ProviderControlling {
    private var started = false
    private var released = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var completionWaiter: CheckedContinuation<Void, Never>?
    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            if started { continuation.resume() } else { startWaiter = continuation }
        }
    }
    func release() { released = true; completionWaiter?.resume(); completionWaiter = nil }
    func performAutopilotEnrollment(hosting: HostingOptions, onPhase: ProviderMutationPhaseObserver?) async throws -> ProviderAutopilotEnrollmentCompletion {
        started = true
        startWaiter?.resume(); startWaiter = nil
        await withCheckedContinuation { continuation in
            if released { continuation.resume() } else { completionWaiter = continuation }
        }
        await onPhase?(.reconciling)
        return ProviderAutopilotEnrollmentCompletion(controls: .refreshUncertain,
            status: .available(value: try! ProviderExtrasParser.parseAutopilot(
                autopilotJSON(enabled: true, live: true)), capturedAt: Date()),
            commandSucceeded: true, savedPolicyPreserved: true)
    }
    func refresh() async throws -> ProviderControlSnapshot { throw ProviderExtrasParseError.invalidPayload }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw ProviderExtrasParseError.invalidPayload }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {}
    func delete(_ localModelID: String) async throws {}
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {}
}

private final class AutopilotPollingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_788_282_000)
    func now() -> Date { lock.withLock { date } }
    func advance() { lock.withLock { date = date.addingTimeInterval(30) } }
}

private actor AutopilotPollingClient: ProviderExtrasProviding {
    let clock: AutopilotPollingClock
    var fullReads = 0
    var statusReads = 0
    var released = false
    private var blocked = false
    private var blockedWaiter: CheckedContinuation<Void, Never>?
    private var fanWaiter: CheckedContinuation<Void, Never>?
    init(clock: AutopilotPollingClock) { self.clock = clock }
    func waitUntilFanBlocked() async {
        await withCheckedContinuation { continuation in
            if blocked { continuation.resume() } else { blockedWaiter = continuation }
        }
    }
    func releaseFan() { released = true; fanWaiter?.resume(); fanWaiter = nil }
    func refreshFan() async -> SourceAvailability<ProviderFanStatus> {
        if !released {
            blocked = true; blockedWaiter?.resume(); blockedWaiter = nil
            await withCheckedContinuation { continuation in
                if released { continuation.resume() } else { fanWaiter = continuation }
            }
        }
        return .unavailable(reason: "fixture")
    }
    func refreshAutopilot() async -> SourceAvailability<ProviderAutopilotStatus> {
        statusReads += 1
        return status()
    }
    func refresh() async -> ProviderExtrasSnapshot {
        fullReads += 1
        return ProviderExtrasSnapshot(capturedAt: clock.now(),
            idlePolicy: .available(value: ProviderIdlePolicy(idleTimeoutMinutes: 60,
                policy: "free_when_idle", summary: "fixture", pinned: true), capturedAt: clock.now()),
            betaFeatures: .available(value: [], capturedAt: clock.now()), fanStatus: .unavailable(reason: "fixture"),
            autoUpdateStatus: .available(value: ProviderAutoUpdateStatus(enabled: false), capturedAt: clock.now()),
            autopilotStatus: status())
    }
    private func status() -> SourceAvailability<ProviderAutopilotStatus> {
        .available(value: try! ProviderExtrasParser.parseAutopilot(autopilotJSON(enabled: false)), capturedAt: clock.now())
    }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}

private actor LegacyAutopilotPollingClient: ProviderExtrasProviding {
    var fullReads = 0
    func refresh() async -> ProviderExtrasSnapshot {
        fullReads += 1
        return ProviderExtrasSnapshot(capturedAt: Date(), idlePolicy: .unavailable(reason: "fixture"),
            betaFeatures: .unavailable(reason: "fixture"), fanStatus: .unavailable(reason: "fixture"))
    }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}

private actor RefusedAutopilotController: ProviderControlling {
    let error: ProviderControlError
    init(error: ProviderControlError) { self.error = error }
    func performAutopilotEnrollment(hosting: HostingOptions, onPhase: ProviderMutationPhaseObserver?) async throws -> ProviderAutopilotEnrollmentCompletion { throw error }
    func refresh() async throws -> ProviderControlSnapshot { throw ProviderExtrasParseError.invalidPayload }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw ProviderExtrasParseError.invalidPayload }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {}
    func delete(_ localModelID: String) async throws {}
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {}
}
