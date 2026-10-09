import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Accepted network demand history", .serialized)
@MainActor
struct NetworkDemandHistoryAcceptanceTests {
    private let instant = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("only fresh, monotonic accepted snapshots reach the journal")
    func acceptedObservationsOnly() async throws {
        let first = sample(at: instant.addingTimeInterval(-2))
        let newest = sample(at: instant.addingTimeInterval(-1))
        let client = AcceptanceCapacityClient(first)
        let writer = AcceptanceWriter()
        let store = makeStore(client, writer: writer)
        await store.refreshNetworkCapacity()
        await client.set(.success(sample(at: instant.addingTimeInterval(-3))))
        await store.refreshNetworkCapacity()
        await client.set(.success(sample(at: instant.addingTimeInterval(-NetworkCapacitySnapshot.maximumAge - 1))))
        await store.refreshNetworkCapacity()
        await client.set(.success(sample(at: instant.addingTimeInterval(NetworkCapacitySnapshot.maximumFutureSkew + 1))))
        await store.refreshNetworkCapacity()
        await client.set(.failure(AcceptanceError.failed))
        await store.refreshNetworkCapacity()
        await client.set(.failure(CancellationError()))
        await store.refreshNetworkCapacity()
        await client.set(.success(newest))
        await store.refreshNetworkCapacity()
        #expect(writer.saved == [first, newest])
        #expect(store.networkCapacity.value == newest)
        await store.stop()
    }

    @Test("superseded and cancelled fetch completions never enter history", arguments: [false, true])
    func obsoleteFetch(cancelled: Bool) async throws {
        let older = sample(at: instant.addingTimeInterval(-2))
        let newer = sample(at: instant.addingTimeInterval(-1))
        let client = AcceptanceHeldCapacityClient(older: older, newer: newer)
        let writer = AcceptanceWriter()
        let store = makeStore(client, writer: writer)
        let obsolete = Task { await store.refreshNetworkCapacity() }
        try await waitUntil { await client.entered }
        if cancelled { obsolete.cancel() }
        await store.refreshNetworkCapacity()
        await client.release()
        await obsolete.value
        #expect(writer.saved == [newer])
        #expect(store.networkCapacity.value == newer)
        await store.stop()
    }

    @Test("a cancelled fetch with a late ordinary error cannot record or replace current data")
    func cancelledLateError() async throws {
        let client = AcceptanceHeldCapacityClient(older: sample(at: instant), newer: sample(at: instant), failHeld: true)
        let writer = AcceptanceWriter()
        let store = makeStore(client, writer: writer)
        let refresh = Task { await store.refreshNetworkCapacity() }
        try await waitUntil { await client.entered }
        refresh.cancel()
        await client.release()
        await refresh.value
        #expect(writer.saved.isEmpty)
        #expect(store.networkCapacity == .unavailable(reason: "Waiting for network model demand"))
        await store.stop()
    }

    @Test("a journal failure leaves the accepted capacity available")
    func journalFailureIsolated() async {
        let snapshot = sample(at: instant)
        let writer = AcceptanceWriter(failing: true)
        let store = makeStore(AcceptanceCapacityClient(snapshot), writer: writer)
        await store.refreshNetworkCapacity()
        #expect(store.networkCapacity == .available(value: snapshot, capturedAt: snapshot.capturedAt))
        #expect(store.networkDemandHistory?.storageError != nil)
        #expect(writer.saved.isEmpty)
        await store.stop()
    }

    @Test("stop joins a manual refresh's write and closes the recording boundary")
    func stopJoinsManualWrite() async throws {
        let writer = AcceptanceWriter(held: true)
        let client = AcceptanceCapacityClient(sample(at: instant))
        let store = makeStore(client, writer: writer)
        let refresh = Task { await store.refreshNetworkCapacity() }
        do {
            try await waitUntil { writer.entered }
        } catch {
            writer.release()
            await refresh.value
            await store.stop()
            throw error
        }
        // The current capacity is visible while its off-actor write is held.
        #expect(store.networkCapacity.value == sample(at: instant))
        var stopped = false
        let stop = Task { await store.stop(); stopped = true }
        for _ in 0..<10 { await Task.yield() }
        #expect(!stopped)
        writer.release()
        await stop.value
        await refresh.value
        #expect(stopped)
        await store.refreshNetworkCapacity()
        #expect(writer.saved.count == 1)
    }

    @Test("a manual fetch released after stop cannot publish or record")
    func stopRejectsPendingFetch() async throws {
        let snapshot = sample(at: instant)
        let client = AcceptanceHeldCapacityClient(older: snapshot, newer: snapshot)
        let writer = AcceptanceWriter()
        let store = makeStore(client, writer: writer)
        let refresh = Task { await store.refreshNetworkCapacity() }
        try await waitUntil { await client.entered }
        await store.stop()
        await client.release()
        await refresh.value
        #expect(writer.saved.isEmpty)
        #expect(store.networkCapacity == .unavailable(reason: "Waiting for network model demand"))
    }

    private func sample(at date: Date) -> NetworkCapacitySnapshot {
        .init(models: [], capturedAt: date)
    }
    private func makeStore(_ client: any NetworkCapacityFetching, writer: AcceptanceWriter) -> MonitorStore {
        let clock = instant
        return MonitorStore(service: TelemetryService(source: AcceptanceUnusedSource()),
            initial: .unavailable(now: clock), earningsClient: AcceptanceUnusedEarnings(),
            networkCapacityClient: client,
            networkDemandHistory: NetworkDemandHistoryStore(url: URL(fileURLWithPath: "/dev/null/history.sqlite3"),
                recordSnapshot: { try writer.record($0) }), now: { clock })
    }
    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<200 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Controlled network observation did not enter")
        throw CancellationError()
    }
}

private enum AcceptanceError: Error { case failed }
private actor AcceptanceCapacityClient: NetworkCapacityFetching {
    private var result: Result<NetworkCapacitySnapshot, Error>
    init(_ snapshot: NetworkCapacitySnapshot) { result = .success(snapshot) }
    func set(_ result: Result<NetworkCapacitySnapshot, Error>) { self.result = result }
    func fetch(at capturedAt: Date) throws -> NetworkCapacitySnapshot { try result.get() }
}
private actor AcceptanceHeldCapacityClient: NetworkCapacityFetching {
    private let older: NetworkCapacitySnapshot
    private let newer: NetworkCapacitySnapshot
    private let failHeld: Bool
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var entered = false
    init(older: NetworkCapacitySnapshot, newer: NetworkCapacitySnapshot, failHeld: Bool = false) {
        self.older = older
        self.newer = newer
        self.failHeld = failHeld
    }
    func fetch(at capturedAt: Date) async throws -> NetworkCapacitySnapshot {
        if entered { return newer }
        entered = true
        await withCheckedContinuation { continuation = $0 }
        if failHeld { throw AcceptanceError.failed }
        return older
    }
    func release() { continuation?.resume(); continuation = nil }
}
private final class AcceptanceWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private let held: Bool
    private let failing: Bool
    private var didEnter = false
    private var snapshots: [NetworkCapacitySnapshot] = []
    init(held: Bool = false, failing: Bool = false) { self.held = held; self.failing = failing }
    var entered: Bool { lock.withLock { didEnter } }
    var saved: [NetworkCapacitySnapshot] { lock.withLock { snapshots } }
    func record(_ snapshot: NetworkCapacitySnapshot) throws -> Bool {
        lock.withLock { didEnter = true }
        if held { gate.wait() }
        if failing { throw AcceptanceError.failed }
        lock.withLock { snapshots.append(snapshot) }
        return true
    }
    func release() { gate.signal() }
}
private struct AcceptanceUnusedEarnings: AccountEarningsFetching {
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "unused") }
}
private struct AcceptanceUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw AcceptanceError.failed }
    func readLoadedModels() async throws -> LoadedModelsState { throw AcceptanceError.failed }
    func readStatus() async throws -> StatusSnapshot { throw AcceptanceError.failed }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}
