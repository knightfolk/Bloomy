import Testing
import AppKit
import SwiftUI
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

struct LogsQueryTests {
    @Test("retention-cap eviction clears only removed selected details")
    func selectionAtCapacity() throws {
        let date = Date(timeIntervalSince1970: 100)
        let events = (0...100).map { index in
            LogEvent(timestamp: date, severity: .warning, category: "test",
                     message: "event \(index)", source: .legacy, processID: nil, processImage: nil)
        }
        var buffer = EventBuffer(capacity: 100)
        buffer.insert(Array(events.prefix(100)))
        let rows = LogTableRow.make(events: buffer.events, query: LogsQuery())
        let evictedID = try #require(rows.first(where: { $0.event == events[0] })?.id)
        let keptID = try #require(rows.first(where: { $0.event == events[99] })?.id)
        buffer.insert([events[100]])
        let evicted = LogsPresentation.make(events: buffer.events, query: LogsQuery(), selectedID: evictedID)
        #expect(evicted.rows.count == 100)
        #expect(evicted.selectedEvent == nil)
        #expect(evicted.retainedSelection(evictedID) == nil)
        let kept = LogsPresentation.make(events: buffer.events, query: LogsQuery(), selectedID: keptID)
        #expect(kept.selectedEvent == events[99])
        #expect(kept.retainedSelection(keptID) == keptID)
        #expect(kept.rows.first?.event == events[100])
    }

    @Test("selected log details survive new arrivals and reordered snapshots")
    func retainsSelectionAcrossFeedChanges() {
        let first = event(.error, .unified, "Inference", "First failure")
        let selected = event(.warning, .legacy, "Memory", "Pressure")
        let incoming = event(.notice, .unified, "Provider", "New arrival")
        let selectedID = LogTableRow.make(events: [first, selected], query: LogsQuery())[1].id

        for snapshot in [[incoming, first, selected], [selected, incoming, first], [selected]] {
            let rows = LogTableRow.make(events: snapshot, query: LogsQuery())
            #expect(LogTableRow.retainedSelection(selectedID, in: rows) == selectedID)
            #expect(rows.first(where: { $0.id == selectedID })?.event == selected)
        }
        #expect(LogTableRow.retainedSelection(selectedID,
            in: LogTableRow.make(events: [incoming, first], query: LogsQuery())) == nil)
        #expect(LogTableRow.retainedSelection(selectedID, in: []) == nil)
    }

    @Test("matching filters preserve selection and excluding filters clear it")
    func selectionFollowsVisibleEvents() {
        let selected = event(.error, .unified, "Inference", "Qwen failed")
        let other = event(.warning, .legacy, "Memory", "Pressure")
        let events = [other, selected]
        let selectedID = LogTableRow.make(events: events, query: LogsQuery())[1].id
        let matching = LogsQuery(severity: .error, source: .unified, text: " qWeN ")
        let matchingRows = LogTableRow.make(events: events, query: matching)
        #expect(LogTableRow.retainedSelection(selectedID, in: matchingRows) == selectedID)
        #expect(LogTableRow.retainedSelection(selectedID,
            in: LogTableRow.make(events: events, query: LogsQuery())) == selectedID)
        for query in [LogsQuery(severity: .warning), LogsQuery(source: .legacy), LogsQuery(text: "missing")] {
            #expect(LogTableRow.retainedSelection(selectedID,
                in: LogTableRow.make(events: events, query: query)) == nil)
        }
    }

    @Test("duplicate occurrences stay separate while arrivals preserve existing selection")
    func duplicateSelectionIdentity() {
        let duplicate = event(.error, .unified, "Inference", "Repeated failure")
        let other = event(.warning, .legacy, "Memory", "Pressure")
        let original = LogTableRow.make(events: [duplicate, other, duplicate], query: LogsQuery())
        let firstID = original[0].id
        let secondID = original[2].id
        #expect(firstID != secondID)
        #expect(Set(original.map(\.id)).count == 3)

        let reordered = LogTableRow.make(events: [other, duplicate, duplicate], query: LogsQuery())
        #expect(reordered[1].id == firstID)
        #expect(reordered[2].id == secondID)
        let filtered = LogTableRow.make(events: [other, duplicate, duplicate], query: LogsQuery(source: .unified))
        #expect(filtered.map(\.id) == [firstID, secondID])
        #expect(filtered.map(\.event) == [duplicate, duplicate])
        #expect(LogTableRow.retainedSelection(secondID, in: filtered) == secondID)

        let added = LogTableRow.make(events: [duplicate, other, duplicate, duplicate], query: LogsQuery())
        #expect(added.count == 4)
        #expect(Set(added.map(\.id)).count == 4)
        #expect(LogTableRow.retainedSelection(firstID, in: added) == firstID)
        #expect(LogTableRow.retainedSelection(secondID, in: added) == secondID)
        let removed = LogTableRow.make(events: [other, duplicate], query: LogsQuery())
        #expect(LogTableRow.retainedSelection(firstID, in: removed) == firstID)
        #expect(LogTableRow.retainedSelection(secondID, in: removed) == nil)
        let otherAdded = LogTableRow.make(events: [other, other, duplicate, duplicate], query: LogsQuery())
        #expect(LogTableRow.retainedSelection(secondID, in: otherAdded) == secondID)
    }

    @Test("log identity includes every immutable event field and preserves input order")
    func distinguishesEventFields() {
        func row(timestamp: Date? = nil, severity: LogSeverity = .error, category: String = "Inference",
                 message: String = "Load failed", source: LogSource = .unified, pid: Int32? = nil,
                 image: String? = nil) -> LogEvent {
            LogEvent(timestamp: timestamp, severity: severity, category: category, message: message,
                source: source, processID: pid, processImage: image)
        }
        let events = [row(), row(timestamp: Date(timeIntervalSince1970: 1)), row(severity: .warning),
                      row(category: "Memory"), row(message: "Other failure"), row(source: .legacy),
                      row(pid: 12), row(image: "worker")]
        let rows = LogTableRow.make(events: events, query: LogsQuery())
        #expect(Set(rows.map(\.id)).count == events.count)
        #expect(rows.map(\.event) == events)
        let reversed = LogTableRow.make(events: Array(events.reversed()), query: LogsQuery())
        #expect(reversed.map(\.id) == Array(rows.map(\.id).reversed()))
        let query = LogsQuery(source: .unified, text: "failure")
        #expect(LogTableRow.make(events: events, query: query).map(\.event) == query.apply(events))
    }

    @Test("identical messages from distinct sources and processes survive retention and filtering")
    func retainsEventOrigins() {
        let at = Date(timeIntervalSince1970: 1000)
        func row(_ source: LogSource, _ pid: Int32?, _ image: String?) -> LogEvent {
            LogEvent(timestamp: at, severity: .error, category: "Inference", message: "Load failed",
                source: source, processID: pid, processImage: image)
        }
        let legacy = row(.legacy, nil, nil)
        let first = row(.unified, 10, "worker-a")
        let second = row(.unified, 11, "worker-a")
        let otherImage = row(.unified, 11, "worker-b")
        var buffer = EventBuffer(capacity: 100)
        buffer.insert([legacy, first, second, otherImage, first])
        #expect(buffer.events.count == 4)
        #expect(LogsQuery(source: .legacy).apply(buffer.events) == [legacy])
        let unified = LogsQuery(source: .unified).apply(buffer.events)
        #expect(unified.count == 3)
        #expect(unified.contains(first))
        #expect(unified.contains(second))
        #expect(unified.contains(otherImage))
    }
    @MainActor
    @Test("log rows render within a narrow dashboard detail column")
    func render() async throws {
        var buffer = EventBuffer(capacity: 100)
        buffer.insert([
            event(.warning, .unified, "Inference", "Example model load delayed; waiting for memory headroom."),
            event(.error, .legacy, "Authentication", "Authorization: Bearer fixture-secret")
        ])
        let feed = EventFeed(events: buffer.events, legacyReadAt: nil, unifiedActivityAt: Date())
        let host = NSHostingController(rootView: LogsView(feed: .available(value: feed, capturedAt: Date())))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        #expect(host.view.frame.width <= 570)
        if ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" {
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-dashboard-logs.png"]
            try capture.run()
            capture.waitUntilExit()
            #expect(capture.terminationStatus == 0)
        }
    }

    @Test("log filters intersect severity source and case-insensitive text without altering events")
    func filters() {
        let events = [
            event(.error, .unified, "Inference", "Qwen failed"),
            event(.warning, .unified, "Inference", "Qwen slow"),
            event(.error, .legacy, "Inference", "Qwen failed"),
            event(.error, .unified, "Memory", "Pressure")
        ]
        #expect(LogsQuery(severity: .error, source: .unified, text: " qWeN ").apply(events) == [events[0]])
        #expect(LogsQuery(text: "MEMORY").apply(events) == [events[3]])
        #expect(LogsQuery().apply(events) == events)
        #expect(LogsQuery(text: "missing").apply(events).isEmpty)
    }

    private func event(_ severity: LogSeverity, _ source: LogSource, _ category: String, _ message: String) -> LogEvent {
        LogEvent(timestamp: nil, severity: severity, category: category, message: message,
                 source: source, processID: nil, processImage: nil)
    }
}
