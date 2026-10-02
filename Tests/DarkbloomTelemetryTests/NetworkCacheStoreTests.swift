import Combine
import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Network cache health collector")
@MainActor
struct NetworkCacheStoreTests {
    @Test func failedRefreshKeepsExplicitlyStaleEvidence() async throws {
        let client = CacheFixtureClient()
        let store = NetworkCacheStore(client: client)
        await store.refresh()
        guard case .available = store.source else { Issue.record("Expected fresh source"); return }
        await client.fail()
        await store.refresh()
        guard case .stale(let value, _, _) = store.source else { Issue.record("Expected stale source"); return }
        #expect(value.plannerReady == true)
    }

    @Test func cancellationDoesNotPublishLateData() async {
        let store = NetworkCacheStore(client: CacheFixtureClient())
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; await store.refresh() }
        await task.value
        #expect(store.source.value == nil)
    }

    @Test func restoredObserverJoinsCancelledReadBeforeRefreshing() async throws {
        let client = GatedCacheClient(heldReads: [1, 2])
        let sleeps = CacheSleepRecorder()
        let store = NetworkCacheStore(client: client, sleep: { try await sleeps.sleep($0) })
        var publications = 0
        let subscription = store.$source.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        let first = Task { await store.observeWhileVisible() }
        defer { first.cancel() }
        try await waitUntil { await client.readCount == 1 }
        first.cancel()
        var restoredStarted = false
        let restored = Task { restoredStarted = true; await store.observeWhileVisible() }
        defer { restored.cancel() }
        try await waitUntil { restoredStarted }
        // The restored task has reached its first suspension before the old
        // noncooperative fetch is released. It must join, not skip and sleep.
        #expect(await client.readCount == 1)
        await client.release(1)
        try await waitUntil { await client.readCount == 2 }
        #expect(publications == 0)
        #expect(store.source.value == nil)
        #expect(await sleeps.delays.isEmpty)
        #expect(await client.maximumConcurrentReads == 1)
        await client.release(2)
        try await waitUntil { await sleeps.delays.count == 1 }
        #expect(publications == 1)
        #expect(store.source.value?.routingMode == .on)
        #expect(await sleeps.delays == [.seconds(60)])
        restored.cancel()
        await first.value
        await restored.value
        #expect(await client.readCount == 2)
    }

    @Test func cancelledReadDoesNotAdvanceFailureBackoff() async throws {
        let client = GatedCacheClient(heldReads: [2], failedReads: [1, 2, 3])
        let sleeps = CacheSleepRecorder()
        let store = NetworkCacheStore(client: client, sleep: { try await sleeps.sleep($0) })
        await store.refresh() // One real failure: the next failure should yield 240s.
        let first = Task { await store.observeWhileVisible() }
        defer { first.cancel() }
        try await waitUntil { await client.readCount == 2 }
        first.cancel()
        var restoredStarted = false
        let restored = Task { restoredStarted = true; await store.observeWhileVisible() }
        defer { restored.cancel() }
        try await waitUntil { restoredStarted }
        await client.release(2) // Throws an ordinary error after cancellation.
        try await waitUntil { await sleeps.delays.count == 1 }
        #expect(await client.readCount == 3)
        #expect(await sleeps.delays == [.seconds(240)])
        #expect(await client.maximumConcurrentReads == 1)
        restored.cancel()
        await first.value
        await restored.value
    }

    @Test("cancelled in-flight manual refresh retains evidence and coalesces busy calls", arguments: [false, true])
    func cancelledInFlightRefresh(fails: Bool) async throws {
        let client = GatedCacheClient(heldReads: [2], failedReads: fails ? [2] : [])
        let store = NetworkCacheStore(client: client)
        await store.refresh()
        let original = try #require(store.source.value)
        var publications = 0
        let subscription = store.$source.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        let reading = Task { await store.refresh() }
        defer { reading.cancel() }
        try await waitUntil { await client.readCount == 2 }
        await store.refresh()
        #expect(await client.readCount == 2)
        reading.cancel()
        await client.release(2)
        await reading.value
        #expect(publications == 0)
        #expect(store.source.value == original)
        guard case .available = store.source else { Issue.record("Cancellation changed retained evidence"); return }
        #expect(await client.maximumConcurrentReads == 1)
    }

    private func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(await condition(), "Finite cache fixture did not reach the expected lifecycle state")
    }
}

private actor CacheSleepRecorder {
    private(set) var delays: [Duration] = []
    func sleep(_ delay: Duration) async throws {
        delays.append(delay)
        // Do not actually wait for production backoff. Cancellation ends this
        // finite fixture sleep; its recorded argument proves the cadence.
        try await Task.sleep(for: .seconds(10))
    }
}

private actor GatedCacheClient: NetworkCacheFetching {
    private let heldReads: Set<Int>
    private let failedReads: Set<Int>
    private var pending: [Int: CheckedContinuation<Void, Error>] = [:]
    private var deadlines: [Int: Task<Void, Never>] = [:]
    private var concurrentReads = 0
    private(set) var readCount = 0
    private(set) var maximumConcurrentReads = 0

    init(heldReads: Set<Int>, failedReads: Set<Int> = []) {
        self.heldReads = heldReads; self.failedReads = failedReads
    }

    func fetch(at capturedAt: Date) async throws -> NetworkCacheSnapshot {
        readCount += 1
        let read = readCount
        concurrentReads += 1
        maximumConcurrentReads = max(maximumConcurrentReads, concurrentReads)
        defer { concurrentReads -= 1 }
        if heldReads.contains(read) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                pending[read] = continuation
                // Deliberately ignore caller cancellation to reproduce delayed
                // transport unwinding, but never leave a test suspended forever.
                deadlines[read] = Task {
                    do { try await Task.sleep(for: .seconds(10)) }
                    catch { return }
                    expire(read)
                }
            }
        }
        if failedReads.contains(read) { throw NetworkCapacityError.invalidResponse }
        let mode = read == 1 ? "off" : "on"
        return try NetworkCacheSnapshot.parse(Data("{\"routing_mode\":\"\(mode)\",\"sidecar\":{\"ready\":true}}".utf8), capturedAt: capturedAt)
    }

    func release(_ read: Int) {
        deadlines.removeValue(forKey: read)?.cancel()
        pending.removeValue(forKey: read)?.resume()
    }

    private func expire(_ read: Int) {
        deadlines.removeValue(forKey: read)
        pending.removeValue(forKey: read)?.resume(throwing: CacheGateTimeout())
    }
}

private struct CacheGateTimeout: Error {}

private actor CacheFixtureClient: NetworkCacheFetching {
    var shouldFail = false
    func fail() { shouldFail = true }
    func fetch(at capturedAt: Date) async throws -> NetworkCacheSnapshot {
        if shouldFail { throw NetworkCapacityError.invalidResponse }
        return try NetworkCacheSnapshot.parse(Data(#"{"routing_mode":"on","sidecar":{"ready":true}}"#.utf8), capturedAt: capturedAt)
    }
}
