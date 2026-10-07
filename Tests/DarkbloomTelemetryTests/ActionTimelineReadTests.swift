import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Action timeline scope and selection")
struct ActionTimelineReadTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    var range: DateInterval { .init(start: base, duration: 120) }

    @Test("a same-ID outcome correction cannot expose an obsolete completed read")
    func correctedOutcome() {
        let id = UUID()
        let before = ActionHistoryEvent(id: id, occurredAt: base, action: .nudge, trigger: .automatic, outcome: .started)
        let after = ActionHistoryEvent(id: id, occurredAt: base, updatedAt: base.addingTimeInterval(30),
            action: .nudge, trigger: .automatic, outcome: .failed, reason: .requestFailed)
        let query = ActionTimelineQuery(events: [before], range: range, model: nil, isVisible: true)
        let read = ActionTimelineRead(query: query, data: .init(events: [before], range: range))
        #expect(read.presentation(for: query)?.buckets.first?.events.first?.outcome == .started)
        #expect(read.presentation(for: .init(events: [after], range: range, model: nil, isVisible: true)) == nil)
    }

    @Test("period, model and hidden state never reuse another action scope")
    func scopeReplacement() {
        let event = ActionHistoryEvent(occurredAt: base, action: .swap, trigger: .manual, outcome: .succeeded, model: "qwen")
        let query = ActionTimelineQuery(events: [event], range: range, model: nil, isVisible: true)
        let read = ActionTimelineRead(query: query, data: .init(events: query.events, range: range))
        #expect(read.presentation(for: .init(events: [event], range: range, model: "gemma", isVisible: true)) == nil)
        #expect(read.presentation(for: .init(events: [event], range: .init(start: base, duration: 240), model: nil, isVisible: true)) == nil)
        #expect(read.presentation(for: .init(events: [event], range: range, model: nil, isVisible: false)) == nil)
        #expect(read.presentation(for: .init(events: [], range: range, model: nil, isVisible: true)) == nil)
    }

    @Test("action group membership is independent of displayed residence and cannot bridge a gap")
    func selectionScope() throws {
        let first = ActionHistoryEvent(occurredAt: base.addingTimeInterval(2), action: .nudge, trigger: .automatic, outcome: .succeeded)
        let second = ActionHistoryEvent(occurredAt: base.addingTimeInterval(3), action: .stopProvider, trigger: .manual, outcome: .succeeded)
        let actions = ActionTimelineData(events: [first, second], range: range, maximumBuckets: 12)
        let visits = ModelVisitTimelineData(visits: [], range: range)
        let selection = try #require(ModelVisitTimelineSelection(date: base.addingTimeInterval(8), data: visits, activity: nil, actions: actions))
        #expect(selection.visits.isEmpty)
        #expect(selection.actionBucket?.events.map(\.id) == [first.id, second.id])
        #expect(ModelVisitTimelineSelection(date: base.addingTimeInterval(10), data: visits, activity: nil, actions: actions)?.actionBucket == nil)
        #expect(ModelVisitTimelineSelection(date: range.end, data: visits, activity: nil, actions: actions) == nil)
        let otherScope = ActionTimelineData(events: [first], range: .init(start: base, duration: 240))
        #expect(ModelVisitTimelineSelection(date: base.addingTimeInterval(2), data: visits, activity: nil, actions: otherScope)?.actionBucket == nil)
    }
}
