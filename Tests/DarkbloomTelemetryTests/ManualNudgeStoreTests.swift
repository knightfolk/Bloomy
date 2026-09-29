import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Manual self-route nudge")
@MainActor
struct ManualNudgeStoreTests {
    private let instant = 2_000_000.0

    @Test("setup saves a key without sending or enabling automation, and removal restores setup")
    func setupIsExplicit() async {
        let clock = ManualNudgeClock(instant)
        let key = FakeConsumerKeyStore()
        let spy = ManualNudgeSpy()
        let store = makeStore(clock: clock, key: key) { _, _ in
            spy.sends += 1
            return .sent
        }
        #expect(!store.keyPresent)
        #expect(store.saveKey("nudge-setup-test-key") == nil)
        #expect(store.keyPresent)
        #expect(!store.enabled)
        #expect(spy.sends == 0)
        #expect(store.lastAttempt == nil)
        store.removeKey()
        #expect(!store.keyPresent)
        #expect(spy.sends == 0)
        await store.stop()
    }

    @Test("multiple advertised models require an exact self-route model ID")
    func exactRouteForMultipleAdvertised() {
        #expect(NudgeSelfRouteModel.familyFallback(
            for: state(advertised: ["model-a", "model-b"]), catalogFamily: "model-family"
        ) == "")
        #expect(NudgeSelfRouteModel.familyFallback(
            for: state(advertised: ["model-a"]), catalogFamily: "model-family"
        ) == "model-family")
        #expect(NudgeSelfRouteModel.familyFallback(
            for: state(advertised: nil), catalogFamily: "model-family"
        ) == "")
    }

    @Test("explicit nudge works with automation off and multiple advertised but one warm model")
    func manualWithOneWarmModel() async {
        let clock = ManualNudgeClock(instant)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = ManualNudgeSpy()
        let store = makeStore(clock: clock, key: key) { state, canSend in
            spy.models.append(state.currentModel)
            spy.preflights.append(await canSend())
            return .sent
        }
        store.observe(state(advertised: ["model-a", "model-b"]))

        #expect(store.enabled == false)
        #expect(store.manualUnavailableReason == nil)
        #expect(await store.nudgeNow())
        #expect(spy.models == ["model-a"])
        #expect(spy.preflights == [true])
        #expect(store.manualStatus?.contains("Self-test responded") == true)
        #expect(store.lastAttempt == nil)
        await store.stop()
    }

    @Test("manual nudge works after a completed CLI model switch")
    func manualAfterCompletedSwitch() async {
        let clock = ManualNudgeClock(instant)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = ManualNudgeSpy()
        let store = makeStore(clock: clock, key: key) { _, canSend in
            spy.preflights.append(await canSend())
            spy.sends += 1
            return .sent
        }
        store.observe(state(modelSwitch: .init(
            outcome: .switched, models: ["model-a"], remainingRequests: 0
        )))
        #expect(store.manualUnavailableReason == nil)
        #expect(await store.nudgeNow())
        #expect(spy.preflights == [true])
        #expect(spy.sends == 1)
        await store.stop()
    }

    @Test("missing dedicated nudge key prevents any send")
    func missingKey() async {
        let clock = ManualNudgeClock(instant)
        let key = FakeConsumerKeyStore()
        let spy = ManualNudgeSpy()
        let store = makeStore(clock: clock, key: key) { _, _ in
            spy.sends += 1
            return .sent
        }
        store.observe(state())

        #expect(store.manualUnavailableReason?.contains("nudge key") == true)
        #expect(await store.nudgeNow() == false)
        #expect(spy.sends == 0)
        #expect(store.manualStatus?.contains("Add a nudge key") == true)
        await store.stop()
    }

    @Test("stale, busy, or more than one warm model cannot start a manual request")
    func requiresFreshIdleSingleWarm() async {
        let clock = ManualNudgeClock(instant)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = ManualNudgeSpy()
        let store = makeStore(clock: clock, key: key) { _, _ in
            spy.sends += 1
            return .sent
        }
        let ineligible = [
            state(at: instant - 11),
            state(inferenceActive: true),
            state(warm: ["model-a", "model-b"]),
            state(advertised: ["model-b"]),
            state(lifecycle: .init(outcome: .serving, remainingRequests: 1)),
            state(pending: ["model-b"]),
            state(modelSwitch: .init(outcome: .switching, models: ["model-a"], remainingRequests: 0)),
            state(modelSwitch: .init(outcome: .failed, models: ["model-a"], remainingRequests: 0)),
            state(modelSwitch: .init(outcome: .switched, models: ["model-a"], remainingRequests: 1)),
        ]
        for candidate in ineligible {
            store.observe(candidate)
            #expect(store.manualUnavailableReason != nil)
            #expect(await store.nudgeNow() == false)
        }
        #expect(spy.sends == 0)
        await store.stop()

        let blocked = makeStore(clock: clock, key: key, canAct: { false }) { _, _ in
            spy.sends += 1
            return .sent
        }
        blocked.observe(state())
        #expect(blocked.manualUnavailableReason?.contains("provider action") == true)
        #expect(await blocked.nudgeNow() == false)
        #expect(spy.sends == 0)
        await blocked.stop()
    }

    @Test("work or model changes before POST invalidate the original candidate")
    func rechecksCandidateBeforePost() async {
        for changed in [
            state(requests: 1),
            state(model: "model-b", advertised: ["model-b", "model-a"], warm: ["model-b"]),
            state(inferenceActive: true),
        ] {
            let clock = ManualNudgeClock(instant)
            let key = FakeConsumerKeyStore()
            key.inject("watcher-test-key")
            let box = ManualNudgeStoreBox()
            let spy = ManualNudgeSpy()
            let store = makeStore(clock: clock, key: key) { _, canSend in
                box.store?.observe(changed)
                spy.preflights.append(await canSend())
                return .failed
            }
            box.store = store
            store.observe(state())
            #expect(await store.nudgeNow() == false)
            #expect(spy.preflights == [false])
            await store.stop()
        }
    }

    @Test("in-flight manual request blocks duplicates and key removal invalidates POST")
    func duplicateAndRemovedKey() async {
        let clock = ManualNudgeClock(instant)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let gate = ManualNudgeGate()
        let spy = ManualNudgeSpy()
        let store = makeStore(clock: clock, key: key) { _, canSend in
            spy.sends += 1
            await gate.wait()
            spy.preflights.append(await canSend())
            return .failed
        }
        store.observe(state())
        let first = Task { await store.nudgeNow() }
        #expect(await eventually { await gate.isWaiting })
        #expect(store.isManuallyNudging)
        #expect(await store.nudgeNow() == false)
        #expect(spy.sends == 1)

        store.removeKey()
        await gate.release()
        #expect(await first.value == false)
        #expect(spy.preflights == [false])
        #expect(!store.isManuallyNudging)
        #expect(store.manualStatus?.contains("nudge key") == true)
        await store.stop()
    }

    private func makeStore(
        clock: ManualNudgeClock,
        key: FakeConsumerKeyStore,
        canAct: @escaping @MainActor () -> Bool = { true },
        send: @escaping @MainActor (DaemonState, @escaping @Sendable () async -> Bool) async -> SelfRouteWarmupResult?
    ) -> InactivityNudgeStore {
        let suite = "ManualNudgeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return InactivityNudgeStore(
            keyStore: key, defaults: defaults, now: { clock.now },
            evidence: { _ in .unavailable }, canAct: canAct, send: send
        )
    }

    private func state(
        at writtenAt: TimeInterval? = nil,
        model: String = "model-a",
        advertised: [String]? = ["model-a"],
        warm: [String] = ["model-a"],
        requests: Int64 = 0,
        inferenceActive: Bool = false,
        lifecycle: ProviderLifecycleState = .init(outcome: .serving, remainingRequests: 0),
        pending: [String] = [],
        modelSwitch: ProviderModelSwitchState? = nil
    ) -> DaemonState {
        let writtenAt = writtenAt ?? instant
        return DaemonState(
            schema: 1, version: "test", currentModel: model, warmModels: warm,
            stats: .init(tokensGenerated: requests, requestsServed: requests, usageGaps: 0),
            trust: .init(level: "hardware", status: "online", reason: "test", receivedAt: writtenAt),
            capacity: nil, slots: [], inferenceActive: inferenceActive,
            startedAt: instant - 1_000, writtenAt: writtenAt, pid: 1,
            processIdentity: .init(pid: 1, startTimeMicros: 1),
            advertisedModels: advertised,
            lifecycle: lifecycle, startupPreloadPendingModels: pending,
            modelSwitch: modelSwitch
        )
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private struct ManualNudgeClock: Sendable {
    let seconds: TimeInterval
    init(_ seconds: TimeInterval) { self.seconds = seconds }
    var now: Date { Date(timeIntervalSince1970: seconds) }
}

@MainActor
private final class ManualNudgeSpy {
    var sends = 0
    var models: [String] = []
    var preflights: [Bool] = []
}

@MainActor
private final class ManualNudgeStoreBox {
    var store: InactivityNudgeStore?
}

private actor ManualNudgeGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var isWaiting = false

    func wait() async {
        isWaiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}
