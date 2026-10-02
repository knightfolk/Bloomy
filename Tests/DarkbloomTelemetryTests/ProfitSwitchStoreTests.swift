import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Automatic profit switching")
@MainActor
struct ProfitSwitchStoreTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("a malformed reported phase cannot become legacy permission to swap")
    func malformedReportedPhase() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        let json: [String: Any] = ["schema": 1, "version": "fixture", "pid": 42,
            "current_model": "current", "warm_models": ["current"], "advertised_models": ["current"],
            "stats": ["tokens_generated": 1, "requests_served": 1, "usage_gaps": 0],
            "inference_active": false, "started_at": start.timeIntervalSince1970 - 7_200,
            "written_at": start.timeIntervalSince1970,
            "process_identity": ["pid": 42, "start_time_micros": 1234], "autopilot_phase": 42]
        let state = try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: json))
        #expect(state.autopilotPhase == nil)
        #expect(state.autopilotPhaseIsUnrecognized)
        fixture.store.observe(telemetry: TelemetrySnapshot(
            state: .available(value: state, capturedAt: start), loadedModels: .unavailable(reason: "unused"),
            status: .unavailable(reason: "unused"), eventFeed: .unavailable(reason: "unused"),
            tokenRate: .unavailable(reason: "unused"), diagnostics: [], capturedAt: start, menuStatus: .online),
            network: .unavailable(reason: "unused"), profits: [], profitsCapturedAt: nil)
        #expect(fixture.store.status == "Paused while Autopilot owns model selection.")
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
    }

    @Test("native Autopilot ownership prevents competing Bloomy swaps",
          arguments: ["active", "paused", "waiting", "waiting_inventory", "transitioning", "recovering", "future-phase"])
    func autopilotOwnsSelection(phase: String) async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_700, autopilotPhase: phase)
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
        #expect(fixture.store.enabled)
        #expect(fixture.store.status == "Paused while Autopilot owns model selection.")
    }

    @Test("off and shadow modes preserve optional Bloomy profit switching", arguments: ["off", "shadow"])
    func observationDoesNotOwnSelection(phase: String) async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_600, autopilotPhase: phase)
        await waitForSwitch(fixture.controller)
        #expect(await fixture.controller.switches == ["candidate"])
        await fixture.store.stop()
    }

    @Test("fresh Autopilot ownership discovered after refresh prevents dispatch", arguments: ["active", "future-phase"])
    func lateOwnership(phase: String) async throws {
        let fixture = try makeFixture(controllerAutopilotPhase: phase)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_600, autopilotPhase: "shadow")
        // Let the queued refresh/dispatch path run. Cancelling immediately
        // would make this pass even if the post-refresh ownership guard broke.
        await waitForSwitch(fixture.controller)
        await fixture.store.stop()
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
    }

    @Test("switching is off by default")
    func defaultOff() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        #expect(!fixture.store.enabled)
        await drive(fixture, through: 3_700)
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
    }

    @Test("active serving work prevents a switch even after dwell and confirmation")
    func activeWorkStaysOnCurrentModel() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_700, active: true)
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
    }

    @Test("sustained measured profit triggers one native switch after one hour idle")
    func profitableIdleSwitchesOnceWithoutWarmup() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_590)
        #expect(await fixture.controller.switches.isEmpty)

        await observe(fixture, offset: 3_600)
        await waitForSwitch(fixture.controller)
        #expect(await fixture.controller.switches == ["candidate"])
        #expect(fixture.store.lastAttempt == start.addingTimeInterval(3_600))
        #expect(fixture.control.switchWarmupStatus == nil)
        #expect(await fixture.warmup.calls.isEmpty)
        await fixture.store.stop()
    }

    @Test("a failed native attempt consumes the saved daily budget across store recreation")
    func failedAttemptPersistsBudget() async throws {
        let suite = "ProfitSwitch-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set([
            start.addingTimeInterval(-36_000).timeIntervalSince1970,
            start.addingTimeInterval(-18_000).timeIntervalSince1970,
        ], forKey: "profitSwitch.attempts")
        let fixture = try makeFixture(suite: suite, defaults: defaults, switchFails: true)
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_600)
        await waitForSwitch(fixture.controller)
        #expect(await fixture.controller.switches == ["candidate"])
        #expect(fixture.store.lastAttempt == start.addingTimeInterval(3_600))
        #expect((defaults.array(forKey: "profitSwitch.attempts") as? [Double])?.count == 3)
        await fixture.store.stop()

        let recreated = try makeFixture(suite: suite, defaults: defaults, clock: fixture.clock)
        #expect(recreated.store.enabled)
        #expect(recreated.store.lastAttempt == start.addingTimeInterval(3_600))
        await drive(recreated, from: 3_610, through: 7_300)
        #expect(await recreated.controller.switches.isEmpty)
        #expect(recreated.store.status.contains("Daily limit"))
        await recreated.store.stop()
    }

    @Test("unknown candidate net profit cannot authorize a switch")
    func unknownProfitPreventsSwitch() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_700, knownCandidateProfit: false)
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
    }

    @Test("insufficient available memory keeps a profitable cold candidate ineligible")
    func lowAvailableMemoryPreventsSwitch() async throws {
        let fixture = try makeFixture(availableMemoryGB: 0)
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 3_700)
        #expect(await fixture.controller.switches.isEmpty)
        #expect(fixture.store.lastAttempt == nil)
    }

    @Test("updated timing persists and starts a new confirmation window")
    func timingUpdateResetsConfirmation() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        fixture.store.setEnabled(true)
        await drive(fixture, through: 1_500)
        fixture.store.updateTiming(ProfitSwitchTiming(
            confirmationMinutes: 20, minimumHoldMinutes: 30,
            returnCooldownMinutes: 120, loadAllowanceMinutes: 3
        ))
        await drive(fixture, from: 1_510, through: 2_690)
        #expect(await fixture.controller.switches.isEmpty)

        let recreated = try makeFixture(suite: fixture.suite, defaults: fixture.defaults, clock: fixture.clock)
        #expect(recreated.store.timing == fixture.store.timing)
        #expect(recreated.store.enabled)

        await observe(fixture, offset: 2_700)
        await waitForSwitch(fixture.controller)
        #expect(await fixture.controller.switches == ["candidate"])
        await fixture.store.stop()
    }

    @Test("profit switch settings render in a grouped Form")
    func settingsRender() async throws {
        let fixture = try makeFixture()
        defer { fixture.defaults.removePersistentDomain(forName: fixture.suite) }
        let host = NSHostingController(rootView: Form {
            ProfitSwitchSettingsView(store: fixture.store)
        }.formStyle(.grouped))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        let size = NSSize(width: 700, height: 700)
        window.setContentSize(size)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.frame = NSRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.bounds.width == 700)
        #expect(!fixture.store.enabled)
        if ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" {
            let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/bloomy-profit-switch-settings.png"))
        }
    }

    private func makeFixture(
        suite: String = "ProfitSwitch-\(UUID().uuidString)",
        defaults providedDefaults: UserDefaults? = nil,
        clock providedClock: ProfitTestClock? = nil,
        switchFails: Bool = false,
        availableMemoryGB: Double? = 128,
        controllerAutopilotPhase: String? = nil
    ) throws -> ProfitFixture {
        let defaults = try #require(providedDefaults ?? UserDefaults(suiteName: suite))
        let clock = providedClock ?? ProfitTestClock(start)
        let controller = ProfitTestController(clock: clock, switchFails: switchFails,
            autopilotPhase: controllerAutopilotPhase)
        let warmup = ProfitTestWarmup()
        let control = ProviderControlStore(controller: controller, warmupProbe: warmup, now: { clock.now() })
        let store = ProfitSwitchStore(control: control, defaults: defaults,
                                      now: { clock.now() }, installedMemoryGB: 64,
                                      availableMemoryGB: { availableMemoryGB })
        return ProfitFixture(suite: suite, defaults: defaults, clock: clock, controller: controller,
                             warmup: warmup, control: control, store: store)
    }

    private func drive(
        _ fixture: ProfitFixture,
        from first: Int = 0,
        through last: Int,
        active: Bool = false,
        knownCandidateProfit: Bool = true,
        autopilotPhase: String? = nil
    ) async {
        for second in stride(from: first, through: last, by: 10) {
            await observe(fixture, offset: second, active: active,
                          knownCandidateProfit: knownCandidateProfit, autopilotPhase: autopilotPhase)
        }
    }

    private func observe(
        _ fixture: ProfitFixture,
        offset: Int,
        active: Bool = false,
        knownCandidateProfit: Bool = true,
        autopilotPhase: String? = nil
    ) async {
        let instant = start.addingTimeInterval(Double(offset))
        fixture.clock.set(instant)
        if fixture.control.snapshot == nil { await fixture.control.refresh() }
        let state = profitDaemon(at: instant, active: active, autopilotPhase: autopilotPhase)
        let telemetry = TelemetrySnapshot(
            state: .available(value: state, capturedAt: instant),
            loadedModels: .unavailable(reason: "unused"),
            status: .unavailable(reason: "unused"),
            eventFeed: .unavailable(reason: "unused"),
            tokenRate: .unavailable(reason: "unused"),
            diagnostics: [], capturedAt: instant, menuStatus: .online
        )
        let capture = start.addingTimeInterval(Double((offset / 60) * 60))
        let network = NetworkCapacitySnapshot(models: [
            profitCapacity("current", active: 1, warm: 5),
            profitCapacity("candidate", active: 10, warm: 20),
        ], capturedAt: capture)
        let profits = [
            profitAverage("current", gross: 1.5, net: 1),
            profitAverage("candidate", gross: 3, net: knownCandidateProfit ? 2 : nil),
        ]
        fixture.store.observe(telemetry: telemetry,
                              network: .available(value: network, capturedAt: instant),
                              profits: profits, profitsCapturedAt: instant)
    }

    private func waitForSwitch(_ controller: ProfitTestController) async {
        for _ in 0..<100 {
            if await !controller.switches.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}

private struct ProfitFixture {
    let suite: String
    let defaults: UserDefaults
    let clock: ProfitTestClock
    let controller: ProfitTestController
    let warmup: ProfitTestWarmup
    let control: ProviderControlStore
    let store: ProfitSwitchStore
}

private final class ProfitTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: Date

    init(_ instant: Date) { self.instant = instant }
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return instant }
    func set(_ value: Date) { lock.lock(); defer { lock.unlock() }; instant = value }
}

private actor ProfitTestController: ProviderControlling {
    private let clock: ProfitTestClock
    private let switchFails: Bool
    private let autopilotPhase: String?
    private var currentModel = "current"
    private(set) var switches: [String] = []

    init(clock: ProfitTestClock, switchFails: Bool, autopilotPhase: String? = nil) {
        self.clock = clock
        self.switchFails = switchFails
        self.autopilotPhase = autopilotPhase
    }

    func refresh() async throws -> ProviderControlSnapshot {
        profitControlSnapshot(at: clock.now(), model: currentModel, autopilotPhase: autopilotPhase)
    }

    func performSingleModelSwitch(
        modelID: String,
        onPhase: ProviderMutationPhaseObserver?
    ) async throws -> ProviderMutationCompletion {
        switches.append(modelID)
        if switchFails { throw ProfitTestFailure.switchFailed }
        currentModel = modelID
        await onPhase?(.reconciling)
        return .refreshed(profitControlSnapshot(at: clock.now(), model: currentModel))
    }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        throw ProfitTestFailure.unexpectedOperation
    }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {
        throw ProfitTestFailure.unexpectedOperation
    }
    func delete(_ localModelID: String) async throws { throw ProfitTestFailure.unexpectedOperation }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        throw ProfitTestFailure.unexpectedOperation
    }
}

private enum ProfitTestFailure: Error { case switchFailed, unexpectedOperation }

private actor ProfitTestWarmup: SelfRouteWarmupProbing {
    private(set) var calls: [String] = []
    func warm(modelID: String, family: String) async -> SelfRouteWarmupResult {
        calls.append(modelID)
        return .sent
    }
}

private func profitDaemon(at date: Date, model: String = "current", active: Bool = false,
    autopilotPhase: String? = nil) -> DaemonState {
    DaemonState(
        schema: 1, version: "fixture", currentModel: model, warmModels: [model],
        stats: ProviderStats(tokensGenerated: 1, requestsServed: 1, usageGaps: 0),
        trust: TrustState(level: "hardware", status: "online", reason: "same_binary",
                          receivedAt: date.timeIntervalSince1970),
        capacity: MemoryCapacity(totalMemoryGB: 64, gpuMemoryActiveGB: 4, gpuMemoryCacheGB: 0),
        slots: [], inferenceActive: active,
        startedAt: date.timeIntervalSince1970 - 7_200,
        writtenAt: date.timeIntervalSince1970,
        pid: 42, processIdentity: ProcessIdentity(pid: 42, startTimeMicros: 1234),
        advertisedModels: [model],
        lifecycle: ProviderLifecycleState(outcome: .serving, remainingRequests: active ? 1 : 0),
        startupPreloadPendingModels: [],
        modelSwitch: ProviderModelSwitchState(outcome: .serving, models: [model],
                                              remainingRequests: active ? 1 : 0),
        runtimeCapabilities: [], autopilotPhase: autopilotPhase
    )
}

private func profitControlSnapshot(at date: Date, model: String, autopilotPhase: String? = nil) -> ProviderControlSnapshot {
    let catalog = ["current", "candidate"].map {
        CatalogModel(id: $0, displayName: $0, family: $0, modelType: "text",
                     capabilities: ["text"], sizeGB: 2, minimumRAMGB: 4,
                     active: true, requiredProviderCapabilities: [])
    }
    let local = ["current", "candidate"].map {
        LocalModel(id: $0, modelType: "text", sizeBytes: 1_000, estimatedMemoryGB: 4)
    }
    let selection = ProviderModelSelection(enabled: ["current", "candidate"], preloaded: [])
    let daemon = profitDaemon(at: date, model: model, autopilotPhase: autopilotPhase)
    let source: ProviderControlSourceState = .fresh(evidenceAt: date)
    return ProviderControlSnapshot(
        inventory: ModelInventoryBuilder.build(catalog: catalog, local: local,
                                                selection: selection, daemon: daemon, loadedModels: []),
        draft: ProviderConfigDraft(sourceRevision: "fixture", original: selection, selection: selection),
        daemonState: daemon, capturedAt: date,
        sources: ProviderControlSourceStates(catalog: source, localModels: source,
                                              daemon: source, loadedModels: source),
        liveSwitchAvailability: .available
    )
}

private func profitCapacity(_ id: String, active: Int, warm: Int) -> NetworkModelCapacity {
    NetworkModelCapacity(id: id, ready: true, canAccept: true, routableProviders: warm,
                         warmProviders: warm, runningProviders: 1, coldProviders: 0,
                         activeRequests: active, queuedRequests: 0, queueLimit: 50,
                         aggregateTokensPerSecond: 10, estimatedTimeToFirstTokenMS: 1,
                         tokenBudgetRemaining: 10, tokenBudgetTotal: 10)
}

private func profitAverage(_ id: String, gross: Double, net: Double?) -> ModelServingProfitAverage {
    ModelServingProfitAverage(model: id, grossUSDPerActiveHour: gross,
                              incrementalElectricityUSDPerActiveHour: net.map { gross - $0 },
                              profitUSDPerActiveHour: net, activeHours: 2,
                              coveredEarningHours: 2, activePowerSamples: 2, idlePowerSamples: 2)
}
