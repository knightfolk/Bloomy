import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Visible model demand history read loop", .serialized)
@MainActor
struct ModelDemandHistoryReadLoopTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("the rolling range advances without writes and performs one read per five-minute sleep")
    func rollingReadRange() async {
        let clock = DemandLoopClock(instant)
        let rows = [observation(at: instant.addingTimeInterval(-86_250), active: 10),
            observation(at: instant.addingTimeInterval(-60), active: 1)]
        let reader = DemandLoopReader(observations: rows)
        let sleeper = DemandLoopSleeper()
        let published = DemandLoopPublications()
        let loop = run(clock: clock, reader: reader, sleeper: sleeper, published: published)
        defer { loop.cancel() }
        await sleeper.waitForEntries(1)
        #expect(await reader.ranges == [DateInterval(start: instant.addingTimeInterval(-86_400), end: instant)])
        #expect(published.successes.count == 1)
        #expect(published.completed?.history(for: "model").validCount == 2)
        #expect(published.completed?.upperBound == 10)
        #expect(await sleeper.requested == [300])

        clock.advance(300)
        for _ in 0..<10 { await Task.yield() }
        #expect(await reader.ranges.count == 1)
        #expect(published.successes.count == 1)
        await sleeper.wake()
        await sleeper.waitForEntries(2)
        #expect(await reader.ranges == [
            DateInterval(start: instant.addingTimeInterval(-86_400), end: instant),
            DateInterval(start: instant.addingTimeInterval(-86_100), end: instant.addingTimeInterval(300))])
        #expect(await sleeper.requested == [300, 300])
        #expect(published.successes.count == 2)
        #expect(published.completed?.history(for: "model").validCount == 1)
        #expect(published.completed?.history(for: "model").points.first?.capturedAt == rows[1].capturedAt)
        #expect(published.completed?.range?.end == instant.addingTimeInterval(300))
        #expect(published.completed?.upperBound == 1)
        loop.cancel()
        await loop.value
        #expect(await sleeper.pendingCount == 0)
    }

    @Test("a read cancelled before entry skips its dependencies")
    func cancellationBeforeRead() async {
        let reader = DemandLoopReader(observations: [])
        let sleeper = DemandLoopSleeper()
        let published = DemandLoopPublications()
        let loop = run(clock: DemandLoopClock(instant), reader: reader, sleeper: sleeper, published: published)
        loop.cancel()
        await loop.value
        #expect(await reader.ranges.isEmpty)
        #expect(await sleeper.requested.isEmpty)
        #expect(published.results.isEmpty)
    }

    @Test("a cancelled held read cannot publish late success or an ordinary error", arguments: [false, true])
    func cancelledLateRead(failing: Bool) async {
        let reader = DemandLoopReader(observations: [observation(at: instant, active: 2)],
            heldCalls: [1], failingCalls: failing ? [1] : [])
        let sleeper = DemandLoopSleeper()
        let published = DemandLoopPublications()
        let loop = run(clock: DemandLoopClock(instant), reader: reader, sleeper: sleeper, published: published)
        defer { loop.cancel() }
        await reader.waitForEntries(1)
        loop.cancel()
        await reader.release()
        await loop.value
        #expect(await reader.completedCount == 1)
        #expect(published.results.isEmpty)
        #expect(await sleeper.requested.isEmpty)
    }

    @Test("cancellation during a held sleep releases it and joins the finite loop task")
    func cancelledSleep() async {
        let reader = DemandLoopReader(observations: [])
        let sleeper = DemandLoopSleeper()
        let published = DemandLoopPublications()
        let loop = run(clock: DemandLoopClock(instant), reader: reader, sleeper: sleeper, published: published)
        await sleeper.waitForEntries(1)
        #expect(await sleeper.pendingCount == 1)
        loop.cancel()
        await loop.value
        #expect(await sleeper.pendingCount == 0)
        #expect(await sleeper.cancellations == 1)
        #expect(await reader.ranges.count == 1)
        #expect(published.results.count == 1)
        #expect(published.failures == 0)
    }

    @Test("an initial read failure retains the previous report token until successful recovery")
    func failureRetainsOriginalScopeUntilRecovery() async throws {
        let originalRange = DateInterval(start: instant.addingTimeInterval(-90_000), end: instant.addingTimeInterval(-3_600))
        let original = try ModelDemandHistoryPresentation(report: .init(range: originalRange,
            readAt: instant.addingTimeInterval(-3_600),
            observations: [observation(at: originalRange.end.addingTimeInterval(-30), active: 10)]))
        let clock = DemandLoopClock(instant)
        let reader = DemandLoopReader(observations: [observation(at: instant, active: 2)], failingCalls: [1])
        let sleeper = DemandLoopSleeper()
        let published = DemandLoopPublications(completed: original)
        let loop = run(clock: clock, reader: reader, sleeper: sleeper, published: published)
        defer { loop.cancel() }
        await sleeper.waitForEntries(1)
        #expect(published.failures == 1)
        #expect(published.successes.isEmpty)
        #expect(published.completed?.state == .retained)
        #expect(published.completed?.range == original.range)
        #expect(published.completed?.readAt == original.readAt)
        #expect(published.completed?.upperBound == original.upperBound)
        #expect(published.completed?.history(for: "model").points == original.history(for: "model").points)

        clock.advance(300)
        await sleeper.wake()
        await sleeper.waitForEntries(2)
        #expect(published.results.count == 2)
        #expect(published.failures == 1)
        #expect(published.successes.count == 1)
        #expect(published.completed?.state == .available)
        #expect(published.completed?.range?.end == instant.addingTimeInterval(300))
        #expect(published.completed?.readAt == instant.addingTimeInterval(300))
        #expect(published.completed?.upperBound == 2)
        #expect(published.completed?.history(for: "model").points.first?.capturedAt == instant)
        loop.cancel()
        await loop.value
    }

    @Test("a report for a different range publishes failure and preserves the previous scope")
    func rejectsMismatchedReportRange() async throws {
        let requested = DateInterval(start: instant.addingTimeInterval(-86_400), end: instant)
        let mismatched = DateInterval(start: requested.start.addingTimeInterval(1), end: requested.end)
        let original = try ModelDemandHistoryPresentation(report: .init(range: requested,
            readAt: instant.addingTimeInterval(-30),
            observations: [observation(at: instant.addingTimeInterval(-60), active: 1)]))
        let reader = DemandLoopReader(observations: [observation(at: instant, active: 10)], reportRange: mismatched)
        let sleeper = DemandLoopSleeper()
        let published = DemandLoopPublications(completed: original)
        let loop = run(clock: DemandLoopClock(instant), reader: reader, sleeper: sleeper, published: published)
        defer { loop.cancel() }
        await sleeper.waitForEntries(1)
        #expect(await reader.ranges == [requested])
        #expect(published.results.count == 1)
        #expect(published.successes.isEmpty)
        #expect(published.failures == 1)
        if case .failure(let error)? = published.results.first {
            #expect(error as? NetworkDemandHistoryDatabaseError == .invalidInterval)
        } else {
            Issue.record("A mismatched report scope must produce a read failure")
        }
        #expect(published.completed?.state == .retained)
        #expect(published.completed?.range == original.range)
        #expect(published.completed?.readAt == original.readAt)
        #expect(published.completed?.upperBound == original.upperBound)
        #expect(published.completed?.history(for: "model").points == original.history(for: "model").points)
        #expect(await sleeper.requested == [300])
        loop.cancel()
        await loop.value
    }

    @Test("pre-cancelled preparation throws before indexing even an empty report", arguments: [false, true])
    func preparationChecksCancellation(hasRows: Bool) async {
        let gate = DemandPreparationGate()
        let report = NetworkDemandHistoryReport(range: DateInterval(start: instant.addingTimeInterval(-86_400), end: instant),
            readAt: instant, observations: hasRows ? [observation(at: instant, active: 2)] : [])
        let preparation = Task.detached {
            // This gate intentionally resumes a cancelled task normally. The
            // initializer itself must reject its already-cancelled caller.
            await gate.wait()
            return try ModelDemandHistoryPresentation(report: report)
        }
        await gate.waitForEntry()
        preparation.cancel()
        await gate.release()
        do {
            _ = try await preparation.value
            Issue.record("Cancelled history preparation returned a presentation")
        } catch is CancellationError {} catch {
            Issue.record("Cancelled preparation must throw CancellationError")
        }
    }

    private func observation(at date: Date, active: Int) -> NetworkDemandHistoryObservation {
        .init(capturedAt: date, models: [.init(modelID: "model", activeRequests: active,
            queuedRequests: 0, loadedProviders: 1)])
    }

    private func run(clock: DemandLoopClock, reader: DemandLoopReader,
        sleeper: DemandLoopSleeper, published: DemandLoopPublications) -> Task<Void, Never> {
        Task {
            await ModelDemandHistoryReadLoop.run(now: { clock.now() },
                sleep: { try await sleeper.sleep($0) },
                read: { try await reader.read(in: $0) },
                publish: { published.receive($0) })
        }
    }
}

private final class DemandLoopClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

@MainActor
private final class DemandLoopPublications {
    private(set) var results: [Result<ModelDemandHistoryPresentation, Error>] = []
    private(set) var successes: [ModelDemandHistoryPresentation] = []
    private(set) var failures = 0
    private(set) var completed: ModelDemandHistoryPresentation?
    init(completed: ModelDemandHistoryPresentation? = nil) { self.completed = completed }
    func receive(_ result: Result<ModelDemandHistoryPresentation, Error>) {
        results.append(result)
        switch result {
        case .success(let value): completed = value; successes.append(value)
        case .failure: failures += 1; completed?.state = .retained
        }
    }
}

private enum DemandLoopReadFailure: Error { case unavailable }

private actor DemandLoopReader {
    private let observations: [NetworkDemandHistoryObservation]
    private let heldCalls: Set<Int>
    private let failingCalls: Set<Int>
    private let reportRange: DateInterval?
    private var held: CheckedContinuation<Void, Never>?
    private var entryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var ranges: [DateInterval] = []
    private(set) var completedCount = 0
    init(observations: [NetworkDemandHistoryObservation], heldCalls: Set<Int> = [], failingCalls: Set<Int> = [],
        reportRange: DateInterval? = nil) {
        self.observations = observations
        self.heldCalls = heldCalls
        self.failingCalls = failingCalls
        self.reportRange = reportRange
    }
    func read(in range: DateInterval) async throws -> NetworkDemandHistoryReport {
        ranges.append(range)
        let call = ranges.count
        let ready = entryWaiters.filter { $0.0 <= call }
        entryWaiters.removeAll { $0.0 <= call }
        ready.forEach { $0.1.resume() }
        // Deliberately ignore cancellation to exercise the loop's late-result guard.
        if heldCalls.contains(call) { await withCheckedContinuation { held = $0 } }
        completedCount += 1
        if failingCalls.contains(call) { throw DemandLoopReadFailure.unavailable }
        return .init(range: reportRange ?? range, readAt: range.end,
            observations: observations.filter { range.contains($0.capturedAt) })
    }
    func waitForEntries(_ count: Int) async {
        if ranges.count >= count { return }
        await withCheckedContinuation { entryWaiters.append((count, $0)) }
    }
    func release() { held?.resume(); held = nil }
}

private actor DemandLoopSleeper {
    private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var entryWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private(set) var requested: [TimeInterval] = []
    private(set) var cancellations = 0
    var pendingCount: Int { pending.count }
    func sleep(_ seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending[id] = continuation
                requested.append(seconds)
                let ready = entryWaiters.filter { $0.0 <= requested.count }
                entryWaiters.removeAll { $0.0 <= requested.count }
                ready.forEach { $0.1.resume() }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    func waitForEntries(_ count: Int) async {
        if requested.count >= count { return }
        await withCheckedContinuation { entryWaiters.append((count, $0)) }
    }
    func wake() {
        let waiters = Array(pending.values)
        pending.removeAll()
        waiters.forEach { $0.resume() }
    }
    private func cancel(_ id: UUID) {
        guard let continuation = pending.removeValue(forKey: id) else { return }
        cancellations += 1
        continuation.resume(throwing: CancellationError())
    }
}

private actor DemandPreparationGate {
    private var entered = false
    private var held: CheckedContinuation<Void, Never>?
    private var entryWaiter: CheckedContinuation<Void, Never>?
    func wait() async {
        entered = true
        entryWaiter?.resume()
        entryWaiter = nil
        await withCheckedContinuation { held = $0 }
    }
    func waitForEntry() async {
        if entered { return }
        await withCheckedContinuation { entryWaiter = $0 }
    }
    func release() {
        held?.resume()
        held = nil
    }
}
