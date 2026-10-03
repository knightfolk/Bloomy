import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Completed Earnings reads")
struct ActivityReadStateTests {
    private let now = Date(timeIntervalSince1970: 86_399)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        value.locale = Locale(identifier: "en_US")
        return value
    }

    private func query(model: String? = nil, metric: ActivityChartMetric = .earnings,
                       revision: UInt64 = 0, refresh: Int = 0,
                       now: Date? = nil, period: ActivityPeriod = .today,
                       calendar: Calendar? = nil, energy: Date? = nil) -> ActivityQuery {
        ActivityQuery(period: period, selectedDate: self.now, endDate: self.now,
                      now: now ?? self.now, calendar: calendar ?? self.calendar,
                      model: model, revision: revision, refreshID: refresh,
                      metric: metric, energyRevision: energy)
    }

    private func report(_ query: ActivityQuery) -> ActivityReadSnapshot {
        let interval = DateInterval(start: now.addingTimeInterval(-3_600), duration: 3_600)
        let totals = ActivityTotals(workMicroUSD: 3, rewardMicroUSD: 1, jobs: 1,
                                    promptTokens: 2, completionTokens: 4)
        return ActivityReadSnapshot(query: query, capturedAt: now,
            buckets: [ActivityBucket(interval: interval, totals: totals, coverage: .recorded)],
            models: ["qwen3.8-27b"], modelWorkByBucket: [interval.start: ["qwen3.8-27b": 3]],
            modelHourlyAverages: [.init(model: "qwen3.8-27b", workMicroUSD: 3, earningHours: 1)])
    }

    @Test("a pending or failed first read never supplies an empty report")
    func firstRead() {
        var read = ActivityReadState()
        let ticket = read.begin(query())
        #expect(read.completed == nil)
        #expect(read.pending == ticket)
        #expect(read.status == "Reading local history…")
        read.fail("History unavailable", for: ticket)
        #expect(read.completed == nil)
        #expect(read.pending == nil)
        #expect(read.status == "History unavailable")
    }

    @Test("refresh retains the complete prior report until a successful replacement")
    func refreshRetainsReport() {
        var read = ActivityReadState()
        let first = query()
        read.finish(report(first), for: read.begin(first))
        let next = query(revision: 5, refresh: 2)
        let ticket = read.begin(next)
        #expect(read.status == "Refreshing local history…")
        #expect(read.completed?.query == first)
        #expect(read.completed?.capturedAt == now)
        #expect(read.completed?.buckets.first?.totals?.workMicroUSD == 3)
        #expect(read.completed?.modelWorkByBucket.values.first?["qwen3.8-27b"] == 3)
        #expect(read.completed?.modelHourlyAverages.first?.workMicroUSD == 3)
        read.finish(report(next), for: ticket)
        #expect(read.completed?.query == next)
        #expect(read.pending == nil)
        #expect(read.message == nil)
    }

    @Test("a changed pending scope and failure cannot relabel the old report")
    func changedScopeFailure() {
        var read = ActivityReadState()
        let first = query(model: "qwen3.8-27b")
        read.finish(report(first), for: read.begin(first))
        let next = query(model: "gemma-4-26b", metric: .estimatedProfit,
                         now: now.addingTimeInterval(86_400), period: .thisWeek)
        let ticket = read.begin(next)
        #expect(read.status.contains("previous results remain visible"))
        #expect(read.completed?.query == first)
        read.fail("Could not read history.", for: ticket)
        #expect(read.completed?.query == first)
        #expect(read.completed?.buckets.count == 1)
        #expect(read.status.contains("Showing the last completed read"))
    }

    @Test("only a successful empty read replaces recorded results with empty history")
    func successfulEmpty() {
        var read = ActivityReadState()
        let first = query()
        read.finish(report(first), for: read.begin(first))
        let next = query(refresh: 1)
        let ticket = read.begin(next)
        read.finish(ActivityReadSnapshot(query: next, capturedAt: now), for: ticket)
        #expect(read.completed?.query == next)
        #expect(read.completed?.buckets.isEmpty == true)
        #expect(read.completed?.models.isEmpty == true)
        #expect(read.completed?.modelWorkByBucket.isEmpty == true)
        #expect(read.message == nil)
    }

    @Test("superseded callbacks and mismatched responses cannot clear or overwrite a newer read", arguments: [false, true])
    func supersededReads(identicalScope: Bool) {
        var read = ActivityReadState()
        let first = query()
        let old = read.begin(first)
        let next = identicalScope ? first : query(model: "gemma-4-26b")
        let current = read.begin(next)
        read.finish(report(first), for: old)
        read.fail("Old error", for: old)
        read.cancel(old)
        read.finish(report(query(model: "mismatched-model")), for: current)
        #expect(read.pending == current)
        #expect(read.completed == nil)
        #expect(read.message == nil)
        read.finish(report(next), for: current)
        read.fail("Late error", for: old)
        #expect(read.completed?.query == next)
        #expect(read.pending == nil)
        #expect(read.message == nil)
    }

    @Test("cancellation preserves the completed report and rejects late completion")
    func cancellation() {
        var read = ActivityReadState()
        let first = query()
        read.finish(report(first), for: read.begin(first))
        let next = query(refresh: 1)
        let ticket = read.begin(next)
        read.cancel(ticket)
        read.finish(ActivityReadSnapshot(query: next), for: ticket)
        #expect(read.completed?.query == first)
        #expect(read.pending == nil)
        #expect(read.message == nil)
    }

    @Test("scope ignores read revisions but respects dates, model, metric and calendar")
    func scopeIdentity() {
        let first = query()
        #expect(first.hasSameScope(as: query(revision: 1, refresh: 3, energy: now)))
        #expect(!first.hasSameScope(as: query(model: "qwen3.8-27b")))
        #expect(!first.hasSameScope(as: query(metric: .estimatedProfit)))
        #expect(!first.hasSameScope(as: query(now: now.addingTimeInterval(1))))
        #expect(!first.hasSameScope(as: query(period: .thisWeek)))
        var otherCalendar = calendar
        otherCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 3_600)!
        #expect(!first.hasSameScope(as: query(calendar: otherCalendar)))
    }

    @Test("captured scope states resolved dates rather than a rolling Today label")
    func capturedScope() {
        let yesterday = query(model: "qwen3.8-27b")
        let today = query(model: "qwen3.8-27b", now: now.addingTimeInterval(1))
        #expect(yesterday.scopeSummary != today.scopeSummary)
        #expect(!yesterday.scopeSummary.contains("Today"))
        #expect(yesterday.scopeSummary.contains("Qwen"))
        #expect(yesterday.scopeSummary.contains(ActivityChartMetric.earnings.rawValue))
        #expect(yesterday.dateFormat.timeZone == calendar.timeZone)
        #expect(yesterday.dateAndTimeFormat.timeZone == calendar.timeZone)
        let hour = yesterday.dateFormat.hour(.twoDigits(amPM: .omitted))
        var otherCalendar = calendar
        otherCalendar.timeZone = TimeZone(secondsFromGMT: -7 * 3_600)!
        let otherHour = query(calendar: otherCalendar).dateFormat.hour(.twoDigits(amPM: .omitted))
        #expect(now.formatted(hour) != now.formatted(otherHour))
    }
}
