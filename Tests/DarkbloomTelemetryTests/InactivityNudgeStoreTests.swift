import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Automatic inactivity nudge")
@MainActor
struct InactivityNudgeStoreTests {
    private let epoch = 2_000_000.0

    @Test("fresh installation stays off and does not request earnings")
    func optIn() async {
        let defaults = makeDefaults()
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = NudgeTestSpy()
        let store = await makeStore(defaults: defaults, clock: clock, key: key, spy: spy)
        #expect(!store.enabled)
        #expect(store.inactivityMinutes == 15)
        #expect(store.keyPresent)
        driveIdle(store, clock: clock)
        await Task.yield()
        #expect(spy.earningsChecks == 0)
        #expect(spy.sends == 0)
        await store.stop()
    }

    @Test("continuous idle and base rewards dispatch one bounded attempt")
    func rewardOnlyDispatch() async {
        let defaults = makeDefaults()
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = NudgeTestSpy()
        let store = await makeStore(defaults: defaults, clock: clock, key: key, spy: spy)
        store.setEnabled(true)
        driveIdle(store, clock: clock, minutes: 15)
        #expect(await eventually { spy.preflightAllowed })
        #expect(spy.earningsChecks == 1)
        #expect(spy.lastSince == Date(timeIntervalSince1970: epoch))
        #expect(store.lastAttempt == Date(timeIntervalSince1970: epoch + 900))
        #expect(spy.lastModel == "model-a")
        #expect(spy.preflightAllowed)
        store.observe(state(at: epoch + 900))
        await Task.yield()
        #expect(spy.sends == 1)
        await store.stop()
    }

    @Test("completed CLI switch remains eligible for automatic reward-only nudge")
    func completedSwitchDispatch() async {
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = NudgeTestSpy()
        let store = await makeStore(defaults: makeDefaults(), clock: clock, key: key, spy: spy)
        store.setEnabled(true)
        driveIdle(store, clock: clock, minutes: 15,
                  modelSwitch: .init(outcome: .switched, models: ["model-a"], remainingRequests: 0))
        #expect(await eventually { spy.preflightAllowed })
        #expect(spy.sends == 1)
        #expect(store.lastAttempt == Date(timeIntervalSince1970: epoch + 900))
        await store.stop()
    }

    @Test("invalid switch evidence reports paused instead of watching")
    func invalidSwitchReportsPaused() async {
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = NudgeTestSpy()
        let store = await makeStore(defaults: makeDefaults(), clock: clock, key: key, spy: spy)
        store.setEnabled(true)
        for outcome in [ProviderModelSwitchOutcome.switching, .failed, .timedOut] {
            store.observe(state(at: epoch,
                modelSwitch: .init(outcome: outcome, models: ["model-a"], remainingRequests: 0)))
            #expect(store.status.hasPrefix("Paused:"))
        }
        store.observe(state(at: epoch,
            modelSwitch: .init(outcome: .switched, models: ["model-a"], remainingRequests: 1)))
        #expect(store.status.hasPrefix("Paused:"))
        #expect(spy.earningsChecks == 0)
        #expect(spy.sends == 0)
        await store.stop()
    }

    @Test("unavailable, incomplete, or recorded work evidence does not send")
    func incompleteEarningsCannotDispatch() async {
        for evidence in [NudgeEarningsEvidence.unavailable, .insufficientHistory, .workRecorded] {
            let clock = NudgeTestClock(epoch)
            let key = FakeConsumerKeyStore()
            key.inject("watcher-test-key")
            let spy = NudgeTestSpy(evidence: evidence)
            let store = await makeStore(defaults: makeDefaults(), clock: clock, key: key, spy: spy)
            store.setEnabled(true)
            driveIdle(store, clock: clock)
            #expect(await eventually { spy.earningsChecks == 1 })
            #expect(spy.sends == 0)
            #expect(store.lastAttempt == nil)
            await store.stop()
        }
    }

    @Test("new inference while account lookup is suspended cancels the candidate")
    func trafficDuringEarningsLookup() async {
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let gate = NudgeEvidenceGate()
        let spy = NudgeTestSpy()
        let store = InactivityNudgeStore(
            keyStore: key, defaults: makeDefaults(), now: { clock.now },
            evidence: { since in
                await gate.check(since: since)
            },
            canAct: { true },
            send: { state, preflight in
                spy.sends += 1
                spy.lastModel = state.currentModel
                spy.preflightAllowed = await preflight()
                return spy.outcome
            }
        )
        await store.refreshKeyStatus()
        store.setEnabled(true)
        driveIdle(store, clock: clock)
        #expect(await eventually { await gate.hasRequest })
        clock.set(epoch + 1_810)
        store.observe(state(at: epoch + 1_810, requests: 1))
        await gate.resolve(.baseRewardsOnly)
        await Task.yield()
        #expect(spy.sends == 0)
        #expect(store.lastAttempt == nil)
        await store.stop()
    }

    @Test("turning the watcher off during lookup prevents dispatch")
    func disableDuringEarningsLookup() async {
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let gate = NudgeEvidenceGate()
        let spy = NudgeTestSpy()
        let store = InactivityNudgeStore(
            keyStore: key, defaults: makeDefaults(), now: { clock.now },
            evidence: { since in await gate.check(since: since) },
            canAct: { true },
            send: { _, _ in spy.sends += 1; return .sent }
        )
        await store.refreshKeyStatus()
        store.setEnabled(true)
        driveIdle(store, clock: clock)
        #expect(await eventually { await gate.hasRequest })
        store.setEnabled(false)
        await gate.resolve(.baseRewardsOnly)
        await Task.yield()
        #expect(spy.sends == 0)
        #expect(store.lastAttempt == nil)
        await store.stop()
    }

    @Test("cooldown survives recreation and three attempts in a day exhaust the limit")
    func persistedBudget() async {
        let defaults = makeDefaults()
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let clock = NudgeTestClock(epoch)
        let firstSpy = NudgeTestSpy()
        let first = await makeStore(defaults: defaults, clock: clock, key: key, spy: firstSpy)
        first.setEnabled(true)
        driveIdle(first, clock: clock)
        #expect(await eventually { firstSpy.preflightAllowed })
        await first.stop()

        // A new store gets a fresh idle window but must honor the prior attempt.
        let secondSpy = NudgeTestSpy()
        let second = await makeStore(defaults: defaults, clock: clock, key: key, spy: secondSpy)
        driveIdle(second, clock: clock, from: epoch + 1_810)
        await Task.yield()
        #expect(secondSpy.sends == 0)
        #expect(secondSpy.earningsChecks == 0)
        #expect(second.status.contains("Cooldown"))
        await second.stop()

        // A valid persisted ledger with three prior attempts must fail closed.
        defaults.set([epoch + 1_800, epoch + 5_400, epoch + 9_000],
                     forKey: "inactivityNudge.attempts")
        let thirdSpy = NudgeTestSpy()
        let third = await makeStore(defaults: defaults, clock: clock, key: key, spy: thirdSpy)
        driveIdle(third, clock: clock, from: epoch + 12_000)
        await Task.yield()
        #expect(thirdSpy.sends == 0)
        #expect(thirdSpy.earningsChecks == 0)
        #expect(third.status.contains("Daily limit"))
        await third.stop()
    }

    @Test("disabled polling does not flood history and rejected sends are not duplicate skips")
    func historyTransitions() async throws {
        let clock = NudgeTestClock(epoch)
        let key = FakeConsumerKeyStore()
        key.inject("watcher-test-key")
        let spy = NudgeTestSpy()
        spy.outcome = .keyRejected
        let store = await makeStore(defaults: makeDefaults(), clock: clock, key: key, spy: spy)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watcher-history-\(UUID())/actions.sqlite3")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let history = ActionHistoryStore(url: url)
        store.actionHistory = history
        for offset in stride(from: 0, through: 3600, by: 10) {
            clock.set(epoch + Double(offset))
            store.observe(state(at: epoch + Double(offset)))
        }
        #expect(history.events.filter { $0.action == .watcher && $0.reason == .disabled }.count == 1)
        clock.set(epoch)
        store.setEnabled(true)
        driveIdle(store, clock: clock, minutes: 15)
        #expect(await eventually { history.events.contains { $0.action == .nudge && $0.outcome == .failed } })
        #expect(history.events.filter { $0.action == .nudge && $0.reason == .keyRejected }.count == 1)
        #expect(!history.events.contains { $0.action == .watcher && $0.reason == .keyRejected })
        await store.stop()
    }

    private func makeStore(
        defaults: UserDefaults,
        clock: NudgeTestClock,
        key: FakeConsumerKeyStore,
        spy: NudgeTestSpy
    ) async -> InactivityNudgeStore {
        let store = InactivityNudgeStore(
            keyStore: key, defaults: defaults, now: { clock.now },
            evidence: { since in
                await MainActor.run {
                    spy.earningsChecks += 1
                    spy.lastSince = since
                    return spy.evidence
                }
            },
            canAct: { true },
            send: { state, preflight in
                spy.sends += 1
                spy.lastModel = state.currentModel
                spy.preflightAllowed = await preflight()
                return spy.outcome
            }
        )
        await store.refreshKeyStatus()
        return store
    }

    private func driveIdle(_ store: InactivityNudgeStore, clock: NudgeTestClock,
                           from start: TimeInterval? = nil, minutes: Int = 30,
                           modelSwitch: ProviderModelSwitchState? = nil) {
        store.setInactivityMinutes(minutes)
        let start = start ?? epoch
        for offset in stride(from: 0, through: minutes * 60, by: 10) {
            let tick = start + Double(offset)
            clock.set(tick)
            store.observe(state(at: tick, modelSwitch: modelSwitch))
        }
    }

    private func state(
        at writtenAt: TimeInterval,
        requests: Int64 = 0,
        modelSwitch: ProviderModelSwitchState? = nil
    ) -> DaemonState {
        DaemonState(
            schema: 1, version: "test", currentModel: "model-a", warmModels: ["model-a"],
            stats: .init(tokensGenerated: requests, requestsServed: requests, usageGaps: 0),
            trust: .init(level: "hardware", status: "online", reason: "test", receivedAt: writtenAt),
            capacity: nil, slots: [], inferenceActive: false,
            startedAt: epoch - 1_000, writtenAt: writtenAt, pid: 1,
            processIdentity: .init(pid: 1, startTimeMicros: 1), advertisedModels: ["model-a"],
            modelLoadFailures: [], lifecycle: .init(outcome: .serving, remainingRequests: 0),
            startupPreloadPendingModels: [], modelSwitch: modelSwitch
        )
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "InactivityNudgeStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0..<2_000 {
            if await condition() { return true }
            await Task.yield()
        }
        return false
    }
}

private final class NudgeTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant: TimeInterval
    init(_ instant: TimeInterval) { self.instant = instant }
    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return Date(timeIntervalSince1970: instant)
    }
    func set(_ instant: TimeInterval) {
        lock.lock(); self.instant = instant; lock.unlock()
    }
}

@MainActor
private final class NudgeTestSpy {
    var evidence: NudgeEarningsEvidence
    var outcome: SelfRouteWarmupResult = .sent
    var earningsChecks = 0
    var sends = 0
    var lastSince: Date?
    var lastModel: String?
    var preflightAllowed = false
    init(evidence: NudgeEarningsEvidence = .baseRewardsOnly) { self.evidence = evidence }
}

private actor NudgeEvidenceGate {
    private var continuation: CheckedContinuation<NudgeEarningsEvidence, Never>?
    private(set) var hasRequest = false

    func check(since: Date) async -> NudgeEarningsEvidence {
        hasRequest = true
        return await withCheckedContinuation { continuation = $0 }
    }

    func resolve(_ result: NudgeEarningsEvidence) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
