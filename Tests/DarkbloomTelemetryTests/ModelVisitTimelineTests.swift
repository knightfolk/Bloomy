import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Observed model residence timeline")
struct ModelVisitTimelineTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("point observations retain zero duration and right edge is exclusive")
    func points() {
        let range = DateInterval(start: start, duration: 60)
        let atStart = visit(from: 0, to: 0, outcome: .stillLoaded)
        let atEnd = visit(from: 60, to: 60, outcome: .stillLoaded)
        let preceding = visit(from: -30, to: 0)
        let data = ModelVisitTimelineData(visits: [atStart, atEnd, preceding], range: range)
        #expect(data.entries.count == 1)
        #expect(data.entries.first?.isPoint == true)
        #expect(data.entries.first?.start == start)
        #expect(data.entries.first?.end == start)
        #expect(data.range == range)
    }

    @Test("clipping preserves original evidence and never fills gaps")
    func clipping() {
        let early = visit(from: -30, to: 10, outcome: .worked, idle: 30)
        let late = visit(from: 50, to: 90, outcome: .unknown)
        let data = ModelVisitTimelineData(visits: [early, late], range: .init(start: start, duration: 60))
        #expect(data.entries.map(\.start) == [start, start.addingTimeInterval(50)])
        #expect(data.entries.map(\.end) == [start.addingTimeInterval(10), start.addingTimeInterval(60)])
        #expect(data.entries.map(\.visit) == [early, late])
        #expect(data.entries.first?.visit.observedIdleSeconds == 30)
        #expect(data.entries.first?.visit.workEvidence == .observedWork)
        #expect(data.models == ["qwen"])
    }

    @Test("all four outcomes have separate color-independent symbols")
    func styles() {
        let outcomes: [ModelVisitOutcome] = [.worked, .noObservedWork, .unknown, .stillLoaded]
        let styles = outcomes.map { ModelVisitEvidenceStyle(visit(from: 0, to: 30, outcome: $0)) }
        #expect(Set(styles).count == 4)
        #expect(Set(styles.map(\.symbol)).count == 4)
        #expect(styles.last?.title == "Last loaded")
    }

    @Test("calendar domain retains 23 and 25 hour days", arguments: ["2026-03-08", "2026-11-01"])
    func daylightSaving(day: String) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let parts = day.split(separator: "-").compactMap { Int($0) }
        let date = try #require(calendar.date(from: .init(year: parts[0], month: parts[1], day: parts[2])))
        let range = try #require(calendar.dateInterval(of: .day, for: date))
        let data = ModelVisitTimelineData(visits: [], range: range)
        #expect(data.range.duration == (day.contains("03-08") ? 23 : 25) * 3_600)
        #expect(data.entries.isEmpty)
    }

    @Test("invalid intervals do not become minimum-width residence")
    func invalidAndEmpty() {
        let backwards = visit(from: 30, to: 0)
        #expect(ModelVisitTimelineData(visits: [backwards], range: .init(start: start, duration: 60)).entries.isEmpty)
        #expect(ModelVisitTimelineData(visits: [visit(from: 0, to: 0)], range: .init(start: start, duration: 0)).entries.isEmpty)
        #expect(ModelVisitTimelineData.inferredRange(visits: [visit(from: 0, to: 0)]) == nil)
    }

    @Test("distinct full identifiers keep distinct rows even when display aliases match")
    func distinctModels() {
        let first = visit(from: 0, to: 10, model: "org-a/qwen3.8-27b")
        let second = visit(from: 10, to: 20, model: "org-b/qwen3.8-27b")
        let data = ModelVisitTimelineData(visits: [first, second, first], range: .init(start: start, duration: 60))
        #expect(data.models == [first.model, second.model])
        #expect(data.modelPositions[first.model] == 0)
        #expect(data.modelPositions[second.model] == 1)
    }

    private func visit(from: TimeInterval, to: TimeInterval, outcome: ModelVisitOutcome = .unknown,
                       idle: TimeInterval = 0, model: String = "qwen") -> ModelVisit {
        ModelVisit(id: UUID(), model: model, observedStart: start.addingTimeInterval(from),
            observedEnd: start.addingTimeInterval(to), coveredSeconds: max(0, to - from),
            observedIdleSeconds: idle, workEvidence: outcome == .worked ? .observedWork : .unknown,
            outcome: outcome, startReason: .historyBoundary, endReason: .historyBoundary,
            isStartTruncated: true, isEndTruncated: true, isOpen: outcome == .stillLoaded, sampleCount: 2)
    }
}
