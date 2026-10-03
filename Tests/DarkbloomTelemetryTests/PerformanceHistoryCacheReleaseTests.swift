import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Metrics cache release integration", .serialized)
@MainActor
struct PerformanceHistoryCacheReleaseTests {
    @Test("releasing an unopened journal creates no files or recording errors")
    func unopenedJournal() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("metrics-cache-unopened-\(UUID())")
        let store = PerformanceHistoryStore(url: root.appendingPathComponent("metrics.sqlite3"))
        await store.releaseReadCache()
        #expect(!FileManager.default.fileExists(atPath: root.path))
        #expect(store.revision == 0)
        #expect(store.recordingStartedAt == nil)
        #expect(store.storageError == nil)
    }

    @Test("releasing display reuse preserves recorded rows and subsequent observations")
    func recordingContinues() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("metrics-cache-recording-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PerformanceHistoryStore(url: root.appendingPathComponent("metrics.sqlite3"))
        let now = Date()
        let first = PerformanceSample(observedAt: now, quality: .current, model: "qwen", inferenceActive: false)
        let second = PerformanceSample(observedAt: now.addingTimeInterval(30), quality: .current, model: "gemma", inferenceActive: true)
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(60))
        await store.observe(first)
        #expect(try await store.samples(in: range) == [first])
        let revision = store.revision
        let start = store.recordingStartedAt
        await store.releaseReadCache()
        #expect(store.revision == revision)
        #expect(store.recordingStartedAt == start)
        #expect(try await store.samples(in: range) == [first])
        await store.observe(second)
        #expect(try await store.samples(in: range) == [first, second])
        #expect(store.storageError == nil)
    }

    @Test("injected cache cleanup neither reads nor clears an existing storage fault")
    func injectedCleanupPreservesFault() async {
        let probe = CacheCleanupProbe()
        let store = PerformanceHistoryStore(url: URL(fileURLWithPath: "/dev/null/metrics.sqlite3"),
            readSamples: { _ in await probe.read(); throw CacheCleanupFailure.synthetic },
            clearReadCache: { await probe.clear() })
        let now = Date()
        _ = try? await store.samples(in: .init(start: now.addingTimeInterval(-60), end: now))
        let fault = store.storageError
        #expect(fault != nil)
        await store.releaseReadCache()
        #expect(await probe.reads == 1)
        #expect(await probe.clears == 1)
        #expect(store.storageError == fault)
        #expect(store.revision == 0)
    }
}

private actor CacheCleanupProbe {
    var reads = 0
    var clears = 0
    func read() { reads += 1 }
    func clear() { clears += 1 }
}

private enum CacheCleanupFailure: Error { case synthetic }
