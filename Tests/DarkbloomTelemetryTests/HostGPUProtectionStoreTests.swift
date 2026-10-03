import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Host GPU protection store")
@MainActor
struct HostGPUProtectionStoreTests {
    @MainActor
    private final class Fixture {
        let suite = "HostGPUProtectionTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        var date = Date(timeIntervalSince1970: 2_000_000_000)
        var pauses = 0
        var resumes = 0
        var pauseSucceeds = true
        var resumeSucceeds = true
        var canAct = true
        var retain = true
        var deferred = false
        var events: [HostGPUProtectionStore.Event] = []
        lazy var store = HostGPUProtectionStore(defaults: defaults, now: { self.date }, pause: {
            self.pauses += 1
            return self.pauseSucceeds
        }, resume: {
            self.resumes += 1
            return self.resumeSucceeds
        }, canAct: { self.canAct }, shouldRetainPause: { self.retain },
            actionWasDeferred: { self.deferred }, onEvent: { self.events.append($0) })
        init() { defaults = UserDefaults(suiteName: suite)! }
        func clean() { defaults.removePersistentDomain(forName: suite) }
        func observe(percent: Double = 90, idle: Bool = true, running: Bool = true, increment: Double = 3) {
            let context = HostGPUProtectionProviderContext(running: running, idle: idle, capturedAt: date, identity: "fixture")
            store.observe(sample: .init(percent: percent, capturedAt: date), provider: context)
            date = date.addingTimeInterval(increment)
        }
        func settle() async { for _ in 0..<20 { await Task.yield() } }
        func breach() async {
            for _ in 0..<6 { observe() }
            await settle()
        }
        func recover() async {
            for _ in 0..<42 { observe(percent: 50, idle: false, running: false); await settle() }
        }
    }

    @Test func deferredRecoveryWaitsForNewEvidenceWithoutRetryLatch() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause, recoverySeconds: 3, minimumPausedSeconds: 0))
        await f.breach()
        #expect(f.pauses == 1)
        f.deferred = true; f.resumeSucceeds = false
        f.observe(percent: 50, running: false); f.observe(percent: 50, running: false)
        await f.settle()
        #expect(f.resumes == 1)
        #expect(f.store.phase == .paused)
        #expect(f.store.isHoldingProvider)
        f.deferred = false; f.resumeSucceeds = true
        f.observe(percent: 50, running: false); f.observe(percent: 50, running: false)
        await f.settle()
        #expect(f.resumes == 2)
        #expect(!f.store.isHoldingProvider)
        await f.store.stop()
    }

    @Test func offByDefaultAndPersistence() async {
        let f = Fixture(); defer { f.clean() }
        await f.breach()
        #expect(f.store.settings.mode == .off)
        #expect(f.pauses == 0)
        f.store.updateSettings(.init(mode: .warn, ceilingPercent: 85))
        let restored = HostGPUProtectionStore(defaults: f.defaults, pause: { false }, resume: { false }, canAct: { true })
        #expect(restored.settings.mode == .warn)
        #expect(restored.settings.ceilingPercent == 85)
        #expect(!restored.isHoldingProvider)
        await f.store.stop()
    }

    @Test func warningAndActiveWorkDoNotMutateProvider() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .warn))
        await f.breach()
        #expect(f.store.phase == .warning)
        #expect(f.events.filter { $0 == .warning }.count == 1)
        f.observe(); await f.settle()
        #expect(f.events.filter { $0 == .warning }.count == 1)
        #expect(f.pauses == 0)
        f.store.updateSettings(.init(mode: .automaticPause))
        for _ in 0..<20 { f.observe(idle: false) }
        await f.settle()
        #expect(f.pauses == 0)
        #expect(f.resumes == 0)
        await f.store.stop()
    }

    @Test func oneConfirmedPauseAndOneRestartAfterRecovery() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause))
        await f.breach()
        #expect(f.pauses == 1)
        #expect(f.store.isHoldingProvider)
        for _ in 0..<10 { f.observe(); await f.settle() }
        #expect(f.pauses == 1)
        await f.recover()
        #expect(f.resumes == 1)
        #expect(!f.store.isHoldingProvider)
        #expect(f.events.filter { $0 == .pauseSucceeded }.count == 1)
        #expect(f.events.filter { $0 == .resumeSucceeded }.count == 1)
        await f.store.stop()
    }

    @Test func failedPauseNeverRestartsOrRetriesWithoutExplicitRetry() async {
        let f = Fixture(); defer { f.clean() }
        f.pauseSucceeds = false
        f.store.updateSettings(.init(mode: .automaticPause))
        await f.breach()
        #expect(f.store.phase == .error)
        #expect(!f.store.isHoldingProvider)
        await f.breach(); await f.recover()
        #expect(f.pauses == 1)
        #expect(f.resumes == 0)
        f.store.retry()
        await f.breach()
        #expect(f.pauses == 2)
        await f.store.stop()
    }

    @Test func manualMutationAndOffRevokeOwnershipWithoutRestart() async {
        for disable in [false, true] {
            let f = Fixture(); defer { f.clean() }
            f.store.updateSettings(.init(mode: .automaticPause))
            await f.breach()
            if disable { f.store.updateSettings(.init(mode: .off)) }
            else { f.store.invalidatePauseOwnership() }
            #expect(!f.store.isHoldingProvider)
            await f.recover()
            #expect(f.resumes == 0)
            #expect(f.store.status.contains("manual start"))
            await f.store.stop()
        }
    }

    @Test func settingsChangesRetainSuccessfulPauseButResetRecovery() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause))
        await f.breach()
        for _ in 0..<39 { f.observe(percent: 50, running: false); await f.settle() }
        #expect(f.resumes == 0)
        f.store.updateSettings(.init(mode: .automaticPause, resumePercent: 55))
        #expect(f.store.isHoldingProvider)
        for _ in 0..<10 { f.observe(percent: 50, running: false); await f.settle() }
        #expect(f.resumes == 0)
        for _ in 0..<12 { f.observe(percent: 50, running: false); await f.settle() }
        #expect(f.resumes == 1)
        await f.store.stop()
    }

    @Test func rootOwnershipLossAndFailedResumeSuppressRestartStorm() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause))
        await f.breach()
        f.resumeSucceeds = false
        await f.recover()
        #expect(f.resumes == 1)
        #expect(f.store.phase == .error)
        await f.recover()
        #expect(f.resumes == 1)
        f.retain = false
        f.observe(percent: 50, running: false)
        #expect(!f.store.isHoldingProvider)
        f.store.retry()
        await f.recover()
        #expect(f.resumes == 1)
        await f.store.stop()
    }

    @Test func settingChangeCancelsQueuedPauseAndRequiresNewDwell() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause))
        for _ in 0..<6 { f.observe() }
        f.store.updateSettings(.init(mode: .automaticPause, breachSeconds: 60))
        await f.settle()
        #expect(f.pauses == 0)
        await f.breach()
        #expect(f.pauses == 0)
        await f.store.stop()
    }

    @Test func lateActiveEvidencePreventsQueuedPause() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause))
        for _ in 0..<6 { f.observe() }
        f.observe(idle: false)
        await f.settle()
        #expect(f.pauses == 0)
        #expect(!f.store.isHoldingProvider)
        await f.store.stop()
    }

    @Test func settingsUpdateDuringResumeCannotRestartTwice() async {
        let f = Fixture(); defer { f.clean() }
        var continuation: CheckedContinuation<Bool, Never>?
        var restarts = 0
        let store = HostGPUProtectionStore(defaults: f.defaults, now: { f.date }, pause: { true }, resume: {
            restarts += 1
            return await withCheckedContinuation { continuation = $0 }
        }, canAct: { true })
        let settings = HostGPUProtectionSettings(mode: .automaticPause, breachSeconds: 3, recoverySeconds: 3, minimumPausedSeconds: 0)
        store.updateSettings(settings)
        func feed(_ percent: Double, running: Bool) {
            store.observe(sample: .init(percent: percent, capturedAt: f.date), provider: .init(running: running, idle: true, capturedAt: f.date, identity: "fixture"))
            f.date = f.date.addingTimeInterval(3)
        }
        feed(90, running: true); feed(90, running: true)
        await f.settle()
        #expect(store.isHoldingProvider)
        feed(50, running: false); feed(50, running: false)
        await f.settle()
        #expect(restarts == 1)
        #expect(store.phase == .resuming)
        store.updateSettings(.init(mode: .automaticPause, resumePercent: 55, breachSeconds: 3, recoverySeconds: 3, minimumPausedSeconds: 0))
        #expect(store.isHoldingProvider)
        continuation?.resume(returning: true)
        await f.settle()
        #expect(!store.isHoldingProvider)
        for _ in 0..<4 { feed(50, running: false); await f.settle() }
        #expect(restarts == 1)
        await store.stop()
    }

    @Test func shutdownCancelsUndispatchedActions() async {
        let f = Fixture(); defer { f.clean() }
        f.store.updateSettings(.init(mode: .automaticPause))
        for _ in 0..<6 { f.observe() }
        await f.store.stop()
        #expect(f.pauses == 0)
        #expect(f.resumes == 0)
        await f.breach()
        #expect(f.pauses == 0)
    }

    @Test func shutdownJoinsInFlightPauseWithoutRestart() async {
        let f = Fixture(); defer { f.clean() }
        var pauseStarted = false
        var pauseFinished = false
        var continuation: CheckedContinuation<Bool, Never>?
        let store = HostGPUProtectionStore(defaults: f.defaults, now: { f.date }, pause: {
            pauseStarted = true
            let result = await withCheckedContinuation { continuation = $0 }
            pauseFinished = true
            return result
        }, resume: { f.resumes += 1; return true }, canAct: { true })
        store.updateSettings(.init(mode: .automaticPause, breachSeconds: 3))
        for _ in 0..<2 {
            store.observe(sample: .init(percent: 90, capturedAt: f.date), provider: .init(running: true, idle: true, capturedAt: f.date, identity: "fixture"))
            f.date = f.date.addingTimeInterval(3)
        }
        await f.settle()
        #expect(pauseStarted)
        var joined = false
        let stopTask = Task { await store.stop(); joined = true }
        await f.settle()
        #expect(!joined)
        continuation?.resume(returning: true)
        await stopTask.value
        #expect(joined && pauseFinished)
        #expect(!store.isHoldingProvider)
        #expect(f.resumes == 0)
    }
}
