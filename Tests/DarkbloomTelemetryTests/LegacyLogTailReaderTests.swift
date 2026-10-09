import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Bounded legacy log metadata reuse")
struct LegacyLogTailReaderTests {
    @Test func unchangedReadsPreserveRawFieldsOrderAndInvalidDates() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let padding = String(repeating: "ordinary irrelevant line\n", count: 6000)
        let text = padding + """
        invalid WARNING Auth: Authorization: Bearer fixture-secret
        2026-10-09T10:00:00+0000 WARNING Inference: \u{1b}[31mDelayed café 👩🏽‍💻\u{1b}[0m
        2026-10-09T10:00:00+0000 WARNING Inference: duplicate
        2026-10-09T10:00:00+0000 WARNING Inference: duplicate
        2026-10-09T10:00:01+0000 INFO Lifecycle: Connected model\r\n
        2026-10-09T10:00:02+0000 ERROR Network: see https://example.invalid/private\u{2028}
        """
        var bytes = Data(text.utf8)
        bytes.append(contentsOf: Array("invalid ERROR Inference: invalid UTF8 ".utf8) + [0xFF, 0x0A])
        try bytes.write(to: fixture.url)
        let reader = LegacyLogTailReader(url: fixture.url)
        let expected = try fixture.reference(limit: 100)
        #expect(expected.first?.timestamp == nil)
        #expect(expected.first?.message == "Authorization: Bearer fixture-secret")
        #expect(expected.last?.timestamp == nil)
        for _ in 0..<30 { #expect(try await reader.read(limit: 100) == expected) }
        #expect(await reader.parsePassCount == 1)
        #expect(await reader.retainedPositionCount == expected.count)
    }

    @Test func changedBytesAndReadFailureRebuildWithoutRetainingOldMetadata() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let first = "2026-10-09T10:00:00+0000 WARNING Model: Loading A\n"
        try Data(first.utf8).write(to: fixture.url)
        let reader = LegacyLogTailReader(url: fixture.url)
        #expect(try await reader.read(limit: 100) == fixture.reference(limit: 100))
        #expect(try await reader.read(limit: 100) == fixture.reference(limit: 100))
        try Data((first + "invalid ERROR Model: Delayed\n").utf8).write(to: fixture.url)
        #expect(try await reader.read(limit: 100) == fixture.reference(limit: 100))
        try Data(first.utf8).write(to: fixture.url)
        #expect(try await reader.read(limit: 100) == fixture.reference(limit: 100))
        let replacement = first.replacingOccurrences(of: "Loading A", with: "Loading B")
        #expect(replacement.utf8.count == first.utf8.count)
        try Data(replacement.utf8).write(to: fixture.url, options: .atomic)
        #expect(try await reader.read(limit: 100) == fixture.reference(limit: 100))
        #expect(await reader.parsePassCount == 4)
        try FileManager.default.removeItem(at: fixture.url)
        await #expect(throws: (any Error).self) { try await reader.read(limit: 100) }
        #expect(await reader.retainedPositionCount == 0)
        try Data(replacement.utf8).write(to: fixture.url)
        #expect(try await reader.read(limit: 100) == fixture.reference(limit: 100))
        #expect(await reader.parsePassCount == 5)
        try Data().write(to: fixture.url)
        #expect(try await reader.read(limit: 100).isEmpty)
        #expect(try await reader.read(limit: 100).isEmpty)
        #expect(await reader.parsePassCount == 6)
    }

    @Test func requestedLimitsStayExactAndMetadataRemainsBounded() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data((0..<120).map { "invalid WARNING Model: Loading \($0)\n" }.joined().utf8).write(to: fixture.url)
        let reader = LegacyLogTailReader(url: fixture.url)
        for limit in [0, -1, 1, 100, 101, 2, 2] {
            #expect(try await reader.read(limit: limit) == fixture.reference(limit: limit))
            #expect(await reader.retainedPositionCount <= 100)
            if limit > 100 { #expect(await reader.retainedPositionCount == 0) }
        }
        #expect(await reader.parsePassCount == 4)
    }

    @Test func quietReadsAndFormatterContextChangesAreHandledWithoutGlobalPreferences() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data(String(repeating: "2026-10-09T10:00:00+0000 INFO Inference: idle observation\n", count: 2500).utf8).write(to: fixture.url)
        let context = FixtureContext()
        let reader = LegacyLogTailReader(url: fixture.url, makeFormatter: { context.formatter() })
        for _ in 0..<30 { #expect(try await reader.read(limit: 100).isEmpty) }
        #expect(await reader.parsePassCount == 1)
        #expect(await reader.retainedPositionCount == 0)
        context.changeTimeZone()
        #expect(try await reader.read(limit: 100).isEmpty)
        #expect(await reader.parsePassCount == 2)
        let dated = "2026-10-09T10:00:00+0000 WARNING Model: Loading dated model\n"
        try Data(dated.utf8).write(to: fixture.url)
        let first = try await reader.read(limit: 100)
        #expect(first.first?.timestamp != nil)
        #expect(first == LegacyLogParser.parse(dated, limit: 100, formatter: context.formatter()))
        context.changeTimeZone()
        let rebuilt = try await reader.read(limit: 100)
        #expect(rebuilt == LegacyLogParser.parse(dated, limit: 100, formatter: context.formatter()))
        #expect(await reader.parsePassCount == 4)
    }

    @Test func sourceCopiesAndConcurrentReadsShareOneSerializedCache() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try Data("invalid WARNING Model: Loading synthetic\n".utf8).write(to: fixture.url)
        let reader = LegacyLogTailReader(url: fixture.url)
        let expected = try fixture.reference(limit: 100)
        try await withThrowingTaskGroup(of: [LogEvent].self) { group in
            for _ in 0..<30 { group.addTask { try await reader.read(limit: 100) } }
            for try await result in group { #expect(result == expected) }
        }
        #expect(await reader.parsePassCount == 1)
        let source = LocalTelemetrySource(policy: fixture.policy, runner: CappedProcessRunner())
        let copy = source
        #expect(try await source.readLegacyEvents(limit: 100) == expected)
        #expect(try await copy.readLegacyEvents(limit: 100) == expected)
    }

    @Test func cacheHitsRenewFreshnessRetainUnifiedEventsAndRecoverFromFailure() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let bytes = Data("invalid WARNING Auth: Authorization: Bearer fixture-secret\n".utf8)
        try bytes.write(to: fixture.url)
        let context = FixtureContext()
        let service = TelemetryService(source: LocalTelemetrySource(policy: fixture.policy, runner: CappedProcessRunner()), now: { context.date })
        let first = await service.refreshNow()
        #expect(first.eventFeed.value?.legacyReadAt == context.date)
        #expect(first.eventFeed.value?.events.first?.message == "[Sensitive log field withheld]")
        let unified = LogEvent(timestamp: context.date, severity: .warning, category: "Synthetic",
                               message: "Loading unified model", source: .unified, processID: 42, processImage: nil)
        await service.ingestUnifiedEvent(unified)
        context.advance()
        let hit = await service.refreshNow()
        #expect(hit.eventFeed.value?.legacyReadAt == context.date)
        #expect(hit.eventFeed.value?.events.contains(unified) == true)
        try FileManager.default.removeItem(at: fixture.url)
        let failed = await service.refreshNow()
        #expect(failed.diagnostics.contains { $0.source == "provider.log" })
        try bytes.write(to: fixture.url)
        context.advance()
        let recovered = await service.refreshNow()
        #expect(recovered.eventFeed.value?.legacyReadAt == context.date)
        #expect(recovered.eventFeed.value?.events == hit.eventFeed.value?.events)
        #expect(!recovered.diagnostics.contains { $0.source == "provider.log" })
        await service.stop()
    }

    private struct Fixture {
        let root: URL
        let policy: DarkbloomSourcePolicy
        var url: URL { policy.legacyLog }
        init() throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyLegacyTail-\(UUID())")
            policy = .init(homeDirectory: root, environmentPath: "")
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        func reference(limit: Int) throws -> [LogEvent] {
            LegacyLogParser.parse(String(decoding: try BoundedFileTail.read(url: url, maxBytes: DarkbloomSourcePolicy.legacyLogByteLimit), as: UTF8.self), limit: limit)
        }
        func remove() { try? FileManager.default.removeItem(at: root) }
    }
}

private final class FixtureContext: @unchecked Sendable {
    private let lock = NSLock()
    private var timeZone = TimeZone(secondsFromGMT: 0)!
    private var instant = Date(timeIntervalSince1970: 2_000_000)
    var date: Date { lock.withLock { instant } }
    func advance() { lock.withLock { instant.addTimeInterval(5) } }
    func changeTimeZone() {
        lock.withLock { timeZone = TimeZone(secondsFromGMT: timeZone.secondsFromGMT() == 0 ? 7200 : 0)! }
    }
    func formatter() -> DateFormatter {
        let formatter = LegacyLogParser.dateFormatter()
        formatter.timeZone = lock.withLock { timeZone }
        return formatter
    }
}
