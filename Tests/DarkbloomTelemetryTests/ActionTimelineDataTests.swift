import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Action timeline evidence buckets")
struct ActionTimelineDataTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private var range: DateInterval { .init(start: base, duration: 120) }

    @Test("half-open boundaries preserve gaps instead of finding a nearby action")
    func boundaries() {
        let rows = [event(-1), event(0), event(30), event(119), event(120)]
        let data = ActionTimelineData(events: rows, range: range, maximumBuckets: 4)
        #expect(data.buckets.map(\.id) == [0, 1, 3])
        #expect(data.bucket(at: base)?.events == [rows[1]])
        #expect(data.bucket(at: base.addingTimeInterval(30))?.events == [rows[2]])
        #expect(data.bucket(at: base.addingTimeInterval(60)) == nil)
        #expect(data.bucket(at: range.end) == nil)
        #expect(data.bucket(at: base.addingTimeInterval(-1)) == nil)
        #expect(data.buckets.last?.end == range.end)
        #expect(data.buckets.first?.midpoint == base.addingTimeInterval(15))
    }

    @Test("fractional grid boundaries use the actual stored Date intervals")
    func fractionalBoundaries() {
        let period = DateInterval(start: base, duration: 100)
        let boundary = base.addingTimeInterval(100.0 / 3)
        let row = ActionHistoryEvent(occurredAt: boundary, action: .swap,
            trigger: .automatic, outcome: .started)
        let data = ActionTimelineData(events: [event(0), row], range: period, maximumBuckets: 3)
        #expect(data.buckets.map(\.id) == [0, 1])
        #expect(data.bucket(at: boundary)?.events == [row])
        #expect(data.bucket(at: boundary)?.start == boundary)
    }

    @Test("simultaneous actions use deterministic UUID order after timestamp order")
    func ordering() {
        let a = event(10, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let b = event(10, id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        let earlier = event(5), later = event(20)
        for rows in [[b, later, a, earlier], [earlier, a, later, b]] {
            #expect(ActionTimelineData(events: rows, range: range, maximumBuckets: 1).buckets.first?.events
                    == [earlier, a, b, later])
        }
    }

    @Test("same-ID outcome corrections replace payload without changing geometry")
    func correctedOutcome() {
        let original = event(10, outcome: .started)
        let corrected = event(10, id: original.id, updated: 110, outcome: .failed)
        let before = ActionTimelineData(events: [original], range: range, maximumBuckets: 4)
        let after = ActionTimelineData(events: [corrected], range: range, maximumBuckets: 4)
        #expect(before.buckets.first?.id == after.buckets.first?.id)
        #expect(before.buckets.first?.start == after.buckets.first?.start)
        #expect(before.buckets.first?.end == after.buckets.first?.end)
        #expect(after.buckets.first?.events == [corrected])
        #expect(after.bucket(at: base.addingTimeInterval(110)) == nil)
    }

    @Test("canonical model filtering retains global actions and excludes alias matches")
    func modelScope() {
        let global = event(0), matching = event(1, model: "org-a/qwen")
        let other = event(2, model: "org-b/qwen"), alias = event(3, model: "qwen")
        let rows = [global, matching, other, alias]
        let filtered = ActionTimelineData(events: rows, range: range, model: "org-a/qwen", maximumBuckets: 1)
        #expect(filtered.buckets.first?.events == [global, matching])
        #expect(ActionTimelineData(events: rows, range: range, maximumBuckets: 1).buckets.first?.events == rows)
    }

    @Test("all nonfinancial metadata actions survive regardless of trigger or outcome")
    func metadataActions() {
        let actions = ActionHistoryAction.allCases.filter { $0 != .job && $0 != .baseReward }
        let rows = actions.enumerated().map { index, action in
            ActionHistoryEvent(occurredAt: base.addingTimeInterval(Double(index)), action: action,
                trigger: ActionHistoryTrigger.allCases[index % ActionHistoryTrigger.allCases.count],
                outcome: ActionHistoryOutcome.allCases[index % ActionHistoryOutcome.allCases.count])
        }
        #expect(ActionTimelineData(events: rows, range: range, maximumBuckets: 1).buckets.first?.events == rows)
    }

    @Test("job and base reward records never become action evidence")
    func financialExclusion() {
        let metadata = event(0)
        let job = ActionHistoryJob(earningID: 1, promptTokens: 1, completionTokens: 2, amountMicroUSD: 3)
        let rows = [metadata, event(1, action: .job), event(2, action: .baseReward), event(3, job: job)]
        #expect(ActionTimelineData(events: rows, range: range, maximumBuckets: 1).buckets.first?.events == [metadata])
    }

    @Test("invalid dates and empty ranges produce no evidence")
    func invalidDates() {
        let invalid = Date(timeIntervalSinceReferenceDate: .nan)
        let infinite = Date(timeIntervalSinceReferenceDate: .infinity)
        for badRange in [DateInterval(start: base, duration: 0), DateInterval(start: invalid, duration: 60),
                         DateInterval(start: base, duration: .infinity)] {
            #expect(ActionTimelineData(events: [event(0)], range: badRange).buckets.isEmpty)
        }
        let rows = [ActionHistoryEvent(occurredAt: invalid, action: .nudge, trigger: .manual, outcome: .started),
                    ActionHistoryEvent(occurredAt: infinite, action: .swap, trigger: .manual, outcome: .failed),
                    ActionHistoryEvent(occurredAt: base, updatedAt: invalid, action: .watcher, trigger: .system, outcome: .succeeded)]
        #expect(ActionTimelineData(events: rows, range: range).buckets.isEmpty)
        #expect(ActionTimelineData(events: [], range: range).bucket(at: invalid) == nil)
    }

    @Test("bucket count is clamped and updated time never supplies duration")
    func boundedGrid() {
        let day = DateInterval(start: base, duration: 96 * 60)
        let rows = (0..<96).map { event(Double($0 * 60), updated: 1_000_000) }
        let capped = ActionTimelineData(events: rows, range: day, maximumBuckets: .max)
        #expect(capped.buckets.count == 96)
        #expect(capped.buckets.map(\.id) == Array(0..<96))
        #expect(capped.buckets.allSatisfy { $0.end.timeIntervalSince($0.start) == 60 })
        for limit in [0, -1, Int.min] {
            let single = ActionTimelineData(events: rows, range: day, maximumBuckets: limit)
            #expect(single.buckets.count == 1)
            #expect(single.buckets.first?.start == day.start)
            #expect(single.buckets.first?.end == day.end)
            #expect(single.buckets.first?.events.count == 96)
        }
    }

    private func event(_ seconds: Double, id: UUID = UUID(), updated: Double? = nil,
                       action: ActionHistoryAction = .nudge, outcome: ActionHistoryOutcome = .succeeded,
                       model: String? = nil, job: ActionHistoryJob? = nil) -> ActionHistoryEvent {
        ActionHistoryEvent(id: id, occurredAt: base.addingTimeInterval(seconds),
            updatedAt: updated.map { base.addingTimeInterval($0) }, action: action, trigger: .manual,
            outcome: outcome, model: model, job: job)
    }
}
