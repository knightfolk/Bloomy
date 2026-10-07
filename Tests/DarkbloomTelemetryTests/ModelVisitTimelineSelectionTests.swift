import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Timeline inspected moment")
struct ModelVisitTimelineSelectionTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    var range: DateInterval { .init(start: base, duration: 120) }

    @Test("shared boundary belongs to the next band and exact coincident points")
    func boundaries() {
        let before = visit(0, 30), after = visit(30, 60)
        let pointA = visit(30, 30), pointB = visit(30, 30)
        let pointC = visit(30, 30), pointD = visit(30, 30)
        let data = ModelVisitTimelineData(visits: [before, after, pointA, pointB, pointC, pointD], range: range)
        let exact = ModelVisitTimelineSelection(date: base.addingTimeInterval(30), data: data, activity: nil)
        #expect(exact?.visits.map(\.id) == [after.id, pointA.id, pointB.id, pointC.id, pointD.id])
        #expect(ModelVisitTimelineSelection(date: base.addingTimeInterval(30.001), data: data, activity: nil)?.visits.map(\.id) == [after.id])
        #expect(ModelVisitTimelineSelection(date: base.addingTimeInterval(60), data: data, activity: nil)?.visits.isEmpty == true)
    }

    @Test("gaps have no visit or provider bracket instead of nearest inference")
    func gaps() {
        let activity = history()
        let data = ModelVisitTimelineData(visits: [visit(0, 30), visit(90, 120)], range: range)
        let selection = ModelVisitTimelineSelection(date: base.addingTimeInterval(60), data: data, activity: activity)
        #expect(selection != nil)
        #expect(selection?.visits.isEmpty == true)
        #expect(selection?.activity == nil)
        #expect(ModelVisitTimelineSelection(date: base.addingTimeInterval(30), data: data, activity: activity)?.activity == nil)
    }

    @Test("range moves and clear do not clamp to a different moment")
    func invalidSelection() {
        let data = ModelVisitTimelineData(visits: [visit(0, 60)], range: range)
        for date in [nil, base.addingTimeInterval(-1), range.end, base.addingTimeInterval(121)] {
            #expect(ModelVisitTimelineSelection(date: date, data: data, activity: nil) == nil)
        }
        let moved = ModelVisitTimelineData(visits: [], range: .init(start: base.addingTimeInterval(60), duration: 120))
        #expect(ModelVisitTimelineSelection(date: base.addingTimeInterval(30), data: moved, activity: nil) == nil)
    }

    @Test("current filtered evidence replaces selected rows while global activity stays")
    func replacement() {
        let date = base.addingTimeInterval(15)
        let row = visit(0, 30)
        let all = ModelVisitTimelineData(visits: [row], range: range)
        let filtered = ModelVisitTimelineData(visits: [], range: range)
        #expect(ModelVisitTimelineSelection(date: date, data: all, activity: history())?.visits.count == 1)
        let fresh = ModelVisitTimelineSelection(date: date, data: filtered, activity: history())
        #expect(fresh?.visits.isEmpty == true)
        #expect(fresh?.activity?.evidence == .active)
    }

    private func history() -> PerformanceActivityHistory {
        PerformanceActivityHistory(samples: [sample(0), sample(30), sample(90, quality: .stale), sample(120)], period: range)
    }
    private func sample(_ time: Double, quality: PerformanceSampleQuality = .current) -> PerformanceSample {
        PerformanceSample(observedAt: base.addingTimeInterval(time), sourceCapturedAt: base.addingTimeInterval(time),
            quality: quality, providerSession: "123:1", inferenceActive: true)
    }
    private func visit(_ from: Double, _ to: Double) -> ModelVisit {
        ModelVisit(id: UUID(), model: "qwen", observedStart: base.addingTimeInterval(from),
            observedEnd: base.addingTimeInterval(to), coveredSeconds: to-from, observedIdleSeconds: 0,
            workEvidence: .observedWork, outcome: .worked, startReason: .modelChanged, endReason: .modelChanged,
            isStartTruncated: false, isEndTruncated: false, isOpen: false, sampleCount: 2)
    }
}
