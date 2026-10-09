import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Network demand history store", .serialized)
@MainActor
struct NetworkDemandHistoryStoreTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)
    private var range: DateInterval { .init(start: instant.addingTimeInterval(-600), end: instant.addingTimeInterval(600)) }

    @Test("construction is lazy, records reopen, and duplicate writes do not advance revision")
    func lazyPersistence() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("history.sqlite3")
        let clock = instant
        let store = NetworkDemandHistoryStore(url: url, now: { clock })
        #expect(!FileManager.default.fileExists(atPath: root.path))
        let snapshot = NetworkCapacitySnapshot(models: [], capturedAt: instant)
        await store.observe(snapshot)
        #expect(store.storageError == nil)
        #expect(store.revision == 1)
        await store.observe(snapshot)
        #expect(store.revision == 1)
        let reopened = NetworkDemandHistoryStore(url: url, now: { clock })
        #expect(try await reopened.report(in: range).observations == [NetworkDemandHistoryObservation(snapshot: snapshot)])
        #expect(reopened.revision == 0)
    }

    @Test("failed writes retry their original timestamps; read success cannot clear a write fault")
    func writeRetry() async throws {
        let writer = DemandTestWriter()
        writer.setFailing(true)
        let store = makeStore(writer)
        let first = NetworkCapacitySnapshot(models: [], capturedAt: instant.addingTimeInterval(-300))
        let second = NetworkCapacitySnapshot(models: [], capturedAt: instant)
        await store.observe(first)
        #expect(store.revision == 1)
        let fault = store.storageError
        _ = try await store.report(in: range)
        #expect(store.storageError == fault)
        #expect(store.revision == 1)
        writer.setFailing(false)
        await store.observe(second)
        #expect(writer.saved == [first, second])
        #expect(store.storageError == nil)
        #expect(store.revision == 2)
    }

    @Test("the retry backlog stays bounded and reports lost observations after recovery")
    func retryOverflow() async {
        let writer = DemandTestWriter()
        writer.setFailing(true)
        let store = makeStore(writer)
        for offset in 0..<121 {
            await store.observe(.init(models: [], capturedAt: instant.addingTimeInterval(Double(offset))))
        }
        #expect(store.storageError == "Some network demand samples could not be saved. Gaps remain unknown.")
        #expect(store.revision == 2)
        writer.setFailing(false)
        let last = NetworkCapacitySnapshot(models: [], capturedAt: instant.addingTimeInterval(121))
        await store.observe(last)
        #expect(writer.saved.count == 120)
        #expect(writer.saved.first?.capturedAt == instant.addingTimeInterval(2))
        #expect(writer.saved.last == last)
        #expect(store.storageError?.contains("Gaps remain unknown") == true)
    }

    @Test("pre-cancelled observation never enters the retry queue")
    func cancelledObservation() async {
        let writer = DemandTestWriter()
        let store = makeStore(writer)
        let cancelled = Task { await store.observe(.init(models: [], capturedAt: instant)) }
        cancelled.cancel()
        await cancelled.value
        await store.observe(.init(models: [], capturedAt: instant.addingTimeInterval(1)))
        #expect(writer.saved.count == 1)
        #expect(writer.saved.first?.capturedAt == instant.addingTimeInterval(1))
    }

    @Test("an observation cancelled during a failing write is not retried")
    func cancelledFailingWrite() async throws {
        let writer = DemandTestWriter(holdFirst: true)
        writer.setFailing(true)
        let store = makeStore(writer)
        let cancelled = Task { await store.observe(.init(models: [], capturedAt: instant)) }
        defer { writer.release() }
        for _ in 0..<200 {
            if writer.entered > 0 { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(writer.entered == 1)
        cancelled.cancel()
        writer.release()
        await cancelled.value
        #expect(store.storageError == nil)
        writer.setFailing(false)
        await store.observe(.init(models: [], capturedAt: instant.addingTimeInterval(1)))
        #expect(writer.saved.count == 1)
        #expect(writer.saved.first?.capturedAt == instant.addingTimeInterval(1))
    }

    @Test("successful repeated reads and repeated identical faults do not cycle revisions")
    func readRevisionAndFaultSeparation() async throws {
        let reader = DemandTestReader()
        let store = makeStore(DemandTestWriter(), reader: reader)
        await reader.prepare(failing: true)
        _ = try? await store.report(in: range)
        let fault = store.storageError
        #expect(fault?.contains("private detail") == false)
        #expect(store.revision == 1)
        _ = try? await store.report(in: range)
        #expect(store.revision == 1)
        await store.observe(.init(models: [], capturedAt: instant))
        #expect(store.storageError == fault)
        #expect(store.revision == 2)
        await reader.prepare()
        _ = try await store.report(in: range)
        #expect(store.storageError == nil)
        #expect(store.revision == 3)
        _ = try await store.report(in: range)
        #expect(store.revision == 3)
    }

    @Test("cancelled read rejects late success and ordinary errors without publishing a fault", arguments: [false, true])
    func cancelledRead(failing: Bool) async throws {
        let reader = DemandTestReader()
        let store = makeStore(DemandTestWriter(), reader: reader)
        await reader.prepare(held: true, failing: failing)
        let task = Task { try await store.report(in: range) }
        try await waitForRead(reader)
        task.cancel()
        await reader.release()
        do { _ = try await task.value; Issue.record("Cancelled read returned a result") }
        catch is CancellationError {} catch { Issue.record("Expected cancellation") }
        #expect(store.storageError == nil)
        #expect(store.revision == 0)
    }

    @Test("pre-cancelled reads skip dependencies and cancellation preserves existing faults")
    func readCancellationBoundaries() async throws {
        let reader = DemandTestReader()
        let store = makeStore(DemandTestWriter(), reader: reader)
        let cancelled = Task { try await store.report(in: range) }
        cancelled.cancel()
        _ = try? await cancelled.value
        #expect(await reader.entered == 0)
        await reader.prepare(failing: true)
        _ = try? await store.report(in: range)
        let fault = store.storageError
        let revision = store.revision
        await reader.prepare(held: true)
        let held = Task { try await store.report(in: range) }
        try await waitForRead(reader, count: 2)
        held.cancel()
        await reader.release()
        _ = try? await held.value
        #expect(store.storageError == fault)
        #expect(store.revision == revision)
    }

    private func makeStore(_ writer: DemandTestWriter, reader: DemandTestReader? = nil) -> NetworkDemandHistoryStore {
        let clock = instant
        return NetworkDemandHistoryStore(url: URL(fileURLWithPath: "/dev/null/history.sqlite3"),
            recordSnapshot: { try writer.record($0) },
            readReport: { range in
                if let reader { return try await reader.report(in: range) }
                return .init(range: range, readAt: clock, observations: [])
            })
    }
    private func waitForRead(_ reader: DemandTestReader, count: Int = 1) async throws {
        for _ in 0..<200 {
            if await reader.entered >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("History read did not enter")
        throw CancellationError()
    }
}

private struct DemandTestError: Error, LocalizedError {
    var errorDescription: String? { "private detail" }
}

private final class DemandTestWriter: @unchecked Sendable {
    private let lock = NSLock()
    private var failing = false
    private let holdFirst: Bool
    private let gate = DispatchSemaphore(value: 0)
    private var entries = 0
    init(holdFirst: Bool = false) { self.holdFirst = holdFirst }
    var entered: Int { lock.withLock { entries } }
    func release() { gate.signal() }
    private var snapshots: [NetworkCapacitySnapshot] = []
    var saved: [NetworkCapacitySnapshot] { lock.withLock { snapshots } }
    func setFailing(_ value: Bool) { lock.withLock { failing = value } }
    func record(_ snapshot: NetworkCapacitySnapshot) throws -> Bool {
        let entry = lock.withLock { entries += 1; return entries }
        if holdFirst, entry == 1 { gate.wait() }
        return try lock.withLock {
            if failing { throw DemandTestError() }
            let changed = snapshots.last != snapshot
            snapshots.append(snapshot)
            return changed
        }
    }
}

private actor DemandTestReader {
    private var held = false
    private var failing = false
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = 0
    func prepare(held: Bool = false, failing: Bool = false) {
        self.held = held
        self.failing = failing
    }
    func report(in range: DateInterval) async throws -> NetworkDemandHistoryReport {
        entered += 1
        if held { await withCheckedContinuation { continuation = $0 } }
        if failing { throw DemandTestError() }
        return .init(range: range, readAt: range.end, observations: [])
    }
    func release() {
        held = false
        continuation?.resume()
        continuation = nil
    }
}
