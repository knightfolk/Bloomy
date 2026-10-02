import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Bounded legacy log selection")
struct LegacyLogSelectionTests {
    @Test("the limit selects qualifying events, preserving file order and unknown dates")
    func selectsMatchingSuffix() {
        let text = """
        2026-10-01T12:00:00+0000 info provider: Started provider
        malformed line
        2026-10-01T12:01:00+0000 warning load: Older warning
        2026-10-01T12:02:00+0000 info metrics: heartbeat
        invalid-date error load: Missing timestamp
        2026-10-01T12:03:00+0000 notice coordinator: Connected to coordinator
        2026-10-01T12:04:00+0000 info metrics: loadingFactor sampled
        """
        let events = LegacyLogParser.parse(text, limit: 2)
        #expect(events.map(\.message) == ["Missing timestamp", "Connected to coordinator"])
        #expect(events.map(\.category) == ["load", "coordinator"])
        #expect(events.map(\.severity) == [.error, .notice])
        #expect(events.first?.timestamp == nil)
        #expect(events.last?.timestamp == Date(timeIntervalSince1970: 1_790_856_180))
        #expect(LegacyLogParser.parse(text, limit: 0).isEmpty)
        #expect(LegacyLogParser.parse(text, limit: -1).isEmpty)
        #expect(LegacyLogParser.parse(text, limit: 100).count == 4)
    }

    @Test("a long tail keeps the latest qualifying events across intervening noise")
    func handlesLongMixedTail() {
        let lines = (0..<1_000).map { index in
            let severity = index.isMultiple(of: 10) ? "warning" : "info"
            return "2026-10-01T12:00:00+0000 \(severity) metrics: event \(index)"
        }
        let events = LegacyLogParser.parse(lines.joined(separator: "\n"), limit: 3)
        #expect(events.map(\.message) == ["event 970", "event 980", "event 990"])
        #expect(events.allSatisfy { $0.timestamp != nil && $0.source == .legacy })
    }
}
