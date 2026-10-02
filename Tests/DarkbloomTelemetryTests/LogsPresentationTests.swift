import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Logs display presentation")
struct LogsPresentationTests {
    @Test("filtering preserves prior query semantics, source order, and duplicate occurrence selection")
    func queryAndIdentityParity() {
        let events = fixtures()
        let original = LogTableRow.make(events: events, query: LogsQuery())
        let selectedID = original[2].id
        for severity: LogSeverity? in [nil, .info, .notice, .warning, .error] {
            for source: LogSource? in [nil, .legacy, .unified] {
                for text in ["", "  qWeN  ", " LOAD ", "inference", "missing"] {
                    let query = LogsQuery(severity: severity, source: source, text: text)
                    let expected = reference(events, query: query)
                    let actual = LogsPresentation.make(events: events, query: query, selectedID: selectedID)
                    #expect(actual.rows.map(\.event) == expected)
                    #expect(query.apply(events) == expected)
                    let expectedIDs = original.filter { expected.contains($0.event) }.map(\.id)
                    #expect(actual.rowIDs == expectedIDs)
                    #expect(actual.selectedEvent == (expectedIDs.contains(selectedID) ? events[2] : nil))
                    #expect(actual.retainedSelection(selectedID) == (expectedIDs.contains(selectedID) ? selectedID : nil))
                }
            }
        }
        #expect(original[0].id != selectedID)
        #expect(original[0].event == original[2].event)
    }

    @Test("same-count corrections derive fresh payloads and never keep removed selection details")
    func correctedSnapshot() {
        let old = fixtures()
        let selected = LogTableRow.make(events: old, query: LogsQuery())[1].id
        let changed = event("Corrected message", timestamp: old[1].timestamp, severity: .error, category: "Correction")
        var updated = old
        updated[1] = changed
        #expect(updated.count == old.count)
        let before = LogsPresentation.make(events: old, query: LogsQuery(), selectedID: selected)
        #expect(before.selectedEvent == old[1])
        let after = LogsPresentation.make(events: updated, query: LogsQuery(), selectedID: selected)
        #expect(after.rows[1].event == changed)
        #expect(after.rows[1].id != selected)
        #expect(after.selectedEvent == nil)
        #expect(after.retainedSelection(selected) == nil)
        let newSelection = after.rows[1].id
        #expect(LogsPresentation.make(events: updated, query: LogsQuery(), selectedID: newSelection).selectedEvent == changed)
        #expect(LogsPresentation.make(events: [], query: LogsQuery(), selectedID: newSelection).selectedEvent == nil)
    }

    @Test("compact and UTC output match prior formatting across injected locales and time zones")
    func formattingParity() {
        let dates: [Date?] = [nil, Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 1_710_060_000),
            Date(timeIntervalSince1970: 1_730_620_800)]
        let events = dates.map { event("Synthetic", timestamp: $0) }
        for locale in ["en_US", "fr_FR", "th_TH@calendar=buddhist"] {
            for zone in ["UTC", "America/Los_Angeles", "Asia/Kathmandu"] {
                let factory = {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: locale)
                    formatter.timeZone = TimeZone(identifier: zone)!
                    return formatter
                }
                let actual = LogsPresentation.make(events: events, query: LogsQuery(), selectedID: nil,
                    sourceCapturedAt: dates[2], makeFormatter: factory)
                #expect(actual.rows.map(\.compactTimestamp) == dates.map { originalCompact($0, factory: factory) })
                #expect(actual.rows.map(\.fullTimestamp) == dates.map { originalFull($0, factory: factory) })
                #expect(actual.sourceTimestamp == originalFull(dates[2], factory: factory))
            }
        }
    }

    @Test("default formatting preserves the current system behavior and exact UTC helper output")
    func currentFormattingParity() {
        let events = fixtures()
        let actual = LogsPresentation.make(events: events, query: LogsQuery(), selectedID: nil)
        #expect(actual.rows.map(\.compactTimestamp) == events.map { originalCompact($0.timestamp) })
        #expect(actual.rows.map(\.fullTimestamp) == events.map { TelemetryFormatting.timestamp($0.timestamp) })
    }

    @Test("formatter creation is bounded per snapshot and unknown or excluded rows need none")
    func boundedFormatters() {
        var count = 0
        let factory = { count += 1; return DateFormatter() }
        let known = (0..<100).map { event("Synthetic \($0)", timestamp: Date(timeIntervalSince1970: Double($0))) }
        let actual = LogsPresentation.make(events: known, query: LogsQuery(), selectedID: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 1_800_000_000), makeFormatter: factory)
        #expect(actual.rows.count == 100)
        #expect(count == 2)
        count = 0
        let unknown = LogsPresentation.make(events: [event("Unknown", timestamp: nil)], query: LogsQuery(),
            selectedID: nil, makeFormatter: factory)
        #expect(unknown.rows.first?.compactTimestamp == "Unknown")
        #expect(unknown.rows.first?.fullTimestamp == "Unavailable — Timestamp unavailable")
        #expect(count == 0)
        _ = LogsPresentation.make(events: known, query: LogsQuery(text: "excluded"), selectedID: nil, makeFormatter: factory)
        #expect(count == 0)
        _ = LogsPresentation.make(events: [], query: LogsQuery(), selectedID: nil,
            sourceCapturedAt: Date(timeIntervalSince1970: 1), makeFormatter: factory)
        #expect(count == 1)
    }

    @Test("a new derivation uses new time-zone evidence even when every row ID is unchanged")
    func changedFormattingContext() {
        let events = [event("Synthetic", timestamp: Date(timeIntervalSince1970: 1_800_000_000))]
        func derive(_ offset: Int) -> LogsPresentation {
            LogsPresentation.make(events: events, query: LogsQuery(), selectedID: nil,
                sourceCapturedAt: events[0].timestamp, makeFormatter: {
                    let formatter = DateFormatter()
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    formatter.timeZone = TimeZone(secondsFromGMT: offset)!
                    return formatter
                })
        }
        let first = derive(0)
        let second = derive(9 * 3_600)
        #expect(first.rowIDs == second.rowIDs)
        #expect(first.rows[0].compactTimestamp != second.rows[0].compactTimestamp)
        #expect(first.rows[0].fullTimestamp == second.rows[0].fullTimestamp)
        #expect(first.sourceTimestamp == second.sourceTimestamp)
    }

    private func fixtures() -> [LogEvent] {
        let duplicate = event("Qwen load warning", timestamp: Date(timeIntervalSince1970: 1_800_000_000),
            severity: .warning, category: "Inference")
        return [duplicate, event("Other failure", timestamp: nil, severity: .error, source: .legacy), duplicate,
            event("Provider ready", timestamp: Date(timeIntervalSince1970: 1), severity: .notice)]
    }
    private func event(_ message: String, timestamp: Date?, severity: LogSeverity = .info,
                       category: String = "Synthetic", source: LogSource = .unified) -> LogEvent {
        .init(timestamp: timestamp, severity: severity, category: category, message: message,
            source: source, processID: 12, processImage: "inert-worker")
    }
    private func reference(_ events: [LogEvent], query: LogsQuery) -> [LogEvent] {
        let search = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter {
            (query.severity == nil || $0.severity == query.severity)
                && (query.source == nil || $0.source == query.source)
                && (search.isEmpty || $0.message.localizedCaseInsensitiveContains(search)
                    || $0.category.localizedCaseInsensitiveContains(search))
        }
    }
    private func originalCompact(_ date: Date?, factory: () -> DateFormatter = { DateFormatter() }) -> String {
        guard let date else { return "Unknown" }
        let formatter = factory()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }
    private func originalFull(_ date: Date?, factory: () -> DateFormatter = { DateFormatter() }) -> String {
        guard let date else { return "Unavailable — Timestamp unavailable" }
        let formatter = factory()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
        return formatter.string(from: date)
    }
}
