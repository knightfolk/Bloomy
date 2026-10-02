import Combine
import Foundation
import Testing
@testable import DarkbloomMonitor

/// Every read is injected. These tests never enumerate the real IORegistry.
@Suite("GPU sampler cancellation", .serialized)
@MainActor
struct SystemGPUUsageStoreTests {
    @Test("stopping a queued sampler prevents its first read and keeps cleared readings unavailable")
    func immediateQueuedStop() async throws {
        var reads = 0
        let store = SystemGPUUsageStore(interval: .seconds(3_600), read: {
            reads += 1
            return 42
        })
        store.start()
        store.stop()
        try await Task.sleep(for: .milliseconds(60))
        #expect(reads == 0)
        expectCleared(store)
    }

    @Test("rapid stop and restart permits only the current sampler's initial read")
    func rapidRestart() async throws {
        var reads = 0
        let store = SystemGPUUsageStore(interval: .seconds(3_600), read: {
            reads += 1
            return 64
        })
        defer { store.stop() }
        store.start()
        store.stop()
        store.start()
        try await Task.sleep(for: .milliseconds(60))
        #expect(reads == 1)
        #expect(store.percentage == 64)
        #expect(store.sampledAt != nil)
        #expect(store.lastGoodPercentage == 64)
        #expect(store.lastGoodSampledAt == store.sampledAt)
    }

    @Test("stopping an active sampler prevents later reads and publications")
    func activeStop() async throws {
        var reads = 0
        let (secondRead, signalSecondRead) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let store = SystemGPUUsageStore(interval: .milliseconds(20), read: {
            reads += 1
            if reads == 2 { signalSecondRead.yield(()) }
            return 55
        })
        var publications = 0
        let observation = store.objectWillChange.sink { publications += 1 }
        defer { signalSecondRead.finish(); observation.cancel(); store.stop() }
        store.start()
        // AppKit rendering in parallel suites can hold the main actor for
        // several seconds. Await the actual injected read, not a polling turn.
        let secondReadArrived = await waitForSecondRead(secondRead)
        try #require(secondReadArrived, "The injected second read did not arrive within 15 monotonic seconds; reads=\(reads)")
        try #require(reads >= 2, "The injected sampler must actually run before testing its stop")
        store.stop()
        let readsAtStop = reads
        let publicationsAtStop = publications
        expectCleared(store)
        try await Task.sleep(for: .milliseconds(100))
        #expect(reads == readsAtStop)
        #expect(publications == publicationsAtStop)
        expectCleared(store)
    }

    private func waitForSecondRead(_ stream: AsyncStream<Void>) async -> Bool {
        await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stream { return true }
                return false
            }
            group.addTask {
                do { try await ContinuousClock().sleep(for: .seconds(15)) }
                catch { return false }
                return false
            }
            let arrived = await group.next() ?? false
            group.cancelAll()
            return arrived
        }
    }

    private func expectCleared(_ store: SystemGPUUsageStore) {
        #expect(store.percentage == nil)
        #expect(store.sampledAt == nil)
        #expect(store.lastGoodPercentage == nil)
        #expect(store.lastGoodSampledAt == nil)
        #expect(store.reading() == .unavailable)
    }
}
