import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Controlled performance history reads", .serialized)
@MainActor
struct PerformanceHistoryReadInjectionTests {
    @Test("an injected initial read can remain held and finish empty without opening the journal")
    func heldInitialRead() async throws {
        let reader = ControlledPerformanceReader()
        await reader.prepare(held: true)
        let store = makeStore(reader)
        let task = Task { try await store.samples(in: range) }
        defer { task.cancel() }
        try await waitForEntry(reader)
        #expect(await reader.completed == 0)
        #expect(store.storageError == nil)
        #expect(store.recordingStartedAt == nil)
        await reader.release()
        #expect(try await task.value.isEmpty)
        #expect(await reader.completed == 1)
        #expect(store.revision == 0)
        #expect(store.storageError == nil)
    }

    @Test("cancellation before a read does not call its injected dependency")
    func cancelledBeforeRead() async throws {
        let reader = ControlledPerformanceReader()
        let store = makeStore(reader)
        let task = Task { try await store.samples(in: range) }
        task.cancel()
        await expectCancellation(task)
        #expect(await reader.entered == 0)
        #expect(store.storageError == nil)
    }

    @Test("a cancelled injected read cannot publish rows or a late ordinary error", arguments: [false, true])
    func cancelledAfterRead(fails: Bool) async throws {
        let reader = ControlledPerformanceReader()
        await reader.prepare(held: true, fails: fails, rows: [sample])
        let store = makeStore(reader)
        let task = Task { try await store.samples(in: range) }
        defer { task.cancel() }
        try await waitForEntry(reader)
        task.cancel()
        // This dependency deliberately ignores cancellation. The store owns
        // the final rejection of its late success or non-cancellation failure.
        await reader.release()
        await expectCancellation(task)
        #expect(await reader.completed == 1)
        #expect(store.storageError == nil)
    }

    @Test("injected failures publish safe history errors and successful recovery clears them")
    func failureAndRecovery() async throws {
        let reader = ControlledPerformanceReader()
        await reader.prepare(fails: true)
        let store = makeStore(reader)
        do {
            _ = try await store.samples(in: range)
            Issue.record("A failed dependency must not return a history result")
        } catch is ControlledPerformanceReadFailure {} catch {
            Issue.record("Unexpected injected failure: \(type(of: error))")
        }
        #expect(store.storageError == "Performance history could not be read. Refresh to retry.")
        #expect(store.storageError?.contains("private synthetic detail") == false)
        await reader.prepare(rows: [sample])
        #expect(try await store.samples(in: range) == [sample])
        #expect(store.storageError == nil)
        #expect(store.revision == 0)
    }

    @Test("cancellation retains an earlier read fault until a successful recovery")
    func cancellationRetainsReadFault() async throws {
        let reader = ControlledPerformanceReader()
        await reader.prepare(fails: true)
        let store = makeStore(reader)
        _ = try? await store.samples(in: range)
        let previousError = store.storageError
        #expect(previousError != nil)
        await reader.prepare(held: true, rows: [sample])
        let task = Task { try await store.samples(in: range) }
        defer { task.cancel() }
        try await waitForEntry(reader, count: 2)
        task.cancel()
        await reader.release()
        await expectCancellation(task)
        #expect(store.storageError == previousError)
        await reader.prepare(rows: [sample])
        #expect(try await store.samples(in: range) == [sample])
        #expect(store.storageError == nil)
    }

    private var range: DateInterval {
        let now = sample.observedAt
        return .init(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
    }
    private var sample: PerformanceSample {
        .init(id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
              observedAt: Date(timeIntervalSince1970: 1_800_000_000), quality: .current)
    }
    private func makeStore(_ reader: ControlledPerformanceReader) -> PerformanceHistoryStore {
        // An invalid journal path proves the injected read owns the operation;
        // this suite neither creates nor changes a database or other files.
        PerformanceHistoryStore(url: URL(fileURLWithPath: "/dev/null/metrics.sqlite3"),
            readSamples: { interval in try await reader.read(interval) })
    }
    private func waitForEntry(_ reader: ControlledPerformanceReader, count: Int = 1) async throws {
        for _ in 0..<100 {
            if await reader.entered >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Controlled history read did not start within its bounded wait")
        throw CancellationError()
    }
    private func expectCancellation(_ task: Task<[PerformanceSample], Error>) async {
        do {
            _ = try await task.value
            Issue.record("Cancelled history must not publish a result")
        } catch is CancellationError {} catch {
            Issue.record("Obsolete history failure must be cancellation, got \(type(of: error))")
        }
    }
}

private struct ControlledPerformanceReadFailure: Error, LocalizedError {
    var errorDescription: String? { "private synthetic detail" }
}

private actor ControlledPerformanceReader {
    private var held = false
    private var fails = false
    private var rows: [PerformanceSample] = []
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = 0
    private(set) var completed = 0

    func prepare(held: Bool = false, fails: Bool = false, rows: [PerformanceSample] = []) {
        self.held = held
        self.fails = fails
        self.rows = rows
    }
    func read(_ interval: DateInterval) async throws -> [PerformanceSample] {
        entered += 1
        if held {
            await withCheckedContinuation { continuation = $0 }
        }
        completed += 1
        if fails { throw ControlledPerformanceReadFailure() }
        return rows.filter { interval.contains($0.observedAt) }
    }
    func release() {
        held = false
        let pending = continuation
        continuation = nil
        pending?.resume()
    }
}
