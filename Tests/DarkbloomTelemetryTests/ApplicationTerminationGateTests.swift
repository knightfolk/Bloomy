import AppKit
import Testing
@testable import DarkbloomMonitor

@Suite("Application termination gate", .timeLimit(.minutes(1)))
@MainActor
struct ApplicationTerminationGateTests {
    @Test("the production delegate gates termination before AppKit exits")
    func productionDelegateGatesTermination() {
        let delegate = DarkbloomMonitorAppDelegate()

        #expect(delegate.responds(to: NSSelectorFromString("applicationShouldTerminate:")))
    }

    @Test("blocked cleanup prevents termination approval and retry")
    func blockedCleanupPreventsApproval() async {
        let gate = ApplicationTerminationGate()
        let started = TerminationSignal()
        let finish = TerminationSignal()
        let retried = TerminationSignal()
        var retries = 0
        let cleanup: @MainActor () async -> Void = {
            started.signal()
            await finish.wait()
        }
        let retry: @MainActor () -> Void = {
            retries += 1
            retried.signal()
        }

        #expect(gate.requestTermination(cleanup: cleanup, retryTermination: retry) == .terminateCancel)
        await started.wait()
        #expect(retries == 0)
        #expect(gate.requestTermination(cleanup: cleanup, retryTermination: retry) == .terminateCancel)
        #expect(retries == 0)

        finish.signal()
        await retried.wait()
    }

    @Test("repeated Quit requests share one cleanup and one retry")
    func repeatedQuitCoalescesCleanup() async {
        let gate = ApplicationTerminationGate()
        let started = TerminationSignal()
        let finish = TerminationSignal()
        let retried = TerminationSignal()
        var cleanups = 0
        var retries = 0
        let cleanup: @MainActor () async -> Void = {
            cleanups += 1
            started.signal()
            await finish.wait()
        }
        let retry: @MainActor () -> Void = {
            retries += 1
            retried.signal()
        }

        #expect(gate.requestTermination(cleanup: cleanup, retryTermination: retry) == .terminateCancel)
        // Requests arriving before the cleanup task starts must also coalesce.
        #expect(gate.requestTermination(cleanup: cleanup, retryTermination: retry) == .terminateCancel)
        await started.wait()
        #expect(gate.requestTermination(cleanup: cleanup, retryTermination: retry) == .terminateCancel)
        #expect(cleanups == 1)
        #expect(retries == 0)

        finish.signal()
        await retried.wait()
        #expect(cleanups == 1)
        #expect(retries == 1)
        #expect(gate.requestTermination(cleanup: cleanup, retryTermination: retry) == .terminateNow)
        #expect(cleanups == 1)
        #expect(retries == 1)
    }

    @Test("the completion retry is approved after async cleanup finishes")
    func completionRetryApprovesTermination() async {
        let gate = ApplicationTerminationGate()
        let started = TerminationSignal()
        let finish = TerminationSignal()
        let retried = TerminationSignal()
        var cleanupFinished = false
        var retryReply: NSApplication.TerminateReply?

        let initialReply = gate.requestTermination(
            cleanup: {
                started.signal()
                await finish.wait()
                cleanupFinished = true
            },
            retryTermination: {
                #expect(cleanupFinished)
                retryReply = gate.requestTermination(
                    cleanup: { Issue.record("Approved termination must not start cleanup again") },
                    retryTermination: { Issue.record("Approved termination must not retry again") }
                )
                retried.signal()
            }
        )
        #expect(initialReply == .terminateCancel)
        await started.wait()
        #expect(!cleanupFinished)
        #expect(retryReply == nil)

        finish.signal()
        await retried.wait()
        #expect(cleanupFinished)
        #expect(retryReply == .terminateNow)
    }
}

/// Deterministic suspension avoids timing assumptions or live app termination.
@MainActor
private final class TerminationSignal {
    private var signalled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !signalled else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func signal() {
        signalled = true
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}
