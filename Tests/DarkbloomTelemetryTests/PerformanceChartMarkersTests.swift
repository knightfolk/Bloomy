import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Performance chart observation symbols")
struct PerformanceChartMarkersTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("isolated symbols distinguish empty singleton and two-observation runs")
    func isolatedRuns() {
        let empty: [MarkerPoint] = []
        #expect(PerformanceChartMarkers.isolatedIDs(in: empty, id: \.id, run: \.run).isEmpty)
        let single = [point(0, offset: 0, value: 0)]
        #expect(PerformanceChartMarkers.isolatedIDs(in: single, id: \.id, run: \.run) == [0])
        let pair = single + [point(1, offset: 1, value: 10)]
        #expect(PerformanceChartMarkers.isolatedIDs(in: pair, id: \.id, run: \.run).isEmpty)

        // Reusing run 1 on either side of another run must not hide lone observations.
        let points = [point(0, offset: 0, value: 0, run: 1),
                      point(1, offset: 100, value: 10, run: 2),
                      point(2, offset: 101, value: 20, run: 2),
                      point(3, offset: 200, value: 0, run: 1),
                      point(4, offset: 300, value: 10, run: 3),
                      point(5, offset: 301, value: 20, run: 3)]
        let original = points
        let isolated = PerformanceChartMarkers.isolatedIDs(in: points, id: \.id, run: \.run)
        #expect(isolated == [0, 3])
        #expect(isolated.isSubset(of: Set(points.map(\.id))))
        #expect(points == original)
    }

    @Test("dense uniform observations retain spaced source symbols without altering points")
    func uniformHistory() {
        let points = (0...1_000).map { point($0, offset: Double($0), value: Double($0)) }
        let original = points
        let selected = retained(points, duration: 1_000)
        #expect(selected.count == 41)
        #expect(selected == Set(stride(from: 0, through: 1_000, by: 25)))
        #expect(selected.isSubset(of: Set(points.map(\.id))))
        #expect(points == original)
    }

    @Test("each dense run preserves actual endpoints and interior extrema")
    func runExtrema() {
        let points = (0..<200).map { index in
            let run = index < 100 ? 1 : 2
            let local = index % 100
            let value = local == 17 ? -20.0 : local == 33 ? 90.0 : 10.0
            return point(index, offset: Double(index), value: value, run: run)
        }
        let selected = retained(points, duration: 4_000)
        #expect(selected == [0, 17, 33, 99, 100, 117, 133, 199])
        #expect(selected.isSubset(of: Set(points.map(\.id))))
    }

    @Test("gaps preserve singleton two-point and repeated-label contiguous runs")
    func shortRunsAndGaps() {
        var points = (0..<80).map { point($0, offset: Double($0), value: 10, run: 1) }
        points += [point(80, offset: 200, value: 0, run: 2),
                   point(81, offset: 400, value: 5, run: 3),
                   point(82, offset: 401, value: 6, run: 3)]
        points += (83..<163).map { point($0, offset: Double($0) + 600, value: 10, run: 1) }
        let selected = retained(points, duration: 100_000)
        #expect(selected == [0, 79, 80, 81, 82, 83, 162])
        #expect(selected.isSubset(of: Set(points.map(\.id))))
    }

    @Test("temporal symbol spacing restarts at model or run boundaries")
    func spacingResets() {
        let points = (0..<100).map { index in
            point(index, offset: Double(index), value: 10, run: index < 50 ? 1 : 2)
        }
        #expect(retained(points, duration: 400) == [0, 10, 20, 30, 40, 49, 50, 60, 70, 80, 90, 99])
    }

    @Test("up to sixty observations keep all their symbols including empty history")
    func shortHistory() {
        for count in [0, 1, 2, 59, 60] {
            let points = (0..<count).map { point($0, offset: Double($0), value: 10) }
            #expect(retained(points, duration: 1_000) == Set(points.map(\.id)))
        }
    }

    @Test("zero and nonfinite visible ranges conservatively retain every source symbol")
    func invalidRanges() {
        let points = (0..<100).map { point($0, offset: Double($0), value: 10) }
        let ranges = [DateInterval(start: start, duration: 0),
                      DateInterval(start: start, duration: .infinity),
                      DateInterval(start: Date(timeIntervalSinceReferenceDate: .infinity), duration: 1)]
        for range in ranges {
            #expect(retained(points, range: range) == Set(points.map(\.id)))
        }
    }

    @Test("duplicate timestamps retain boundary and extremum evidence without a symbol pileup")
    func duplicateDates() {
        let points = (0..<100).map { index in
            point(index, offset: 0, value: index == 17 ? -5 : index == 33 ? 30 : 10)
        }
        #expect(retained(points, duration: 1_000) == [0, 17, 33, 99])
    }

    @Test("unexpected backward dates preserve symbols rather than silently hiding observations")
    func invalidChronology() {
        var points = (0..<100).map { point($0, offset: Double($0), value: 10) }
        points[50] = point(50, offset: 10, value: 10)
        #expect(retained(points, duration: 1_000) == Set(points.map(\.id)))
    }

    private func retained(_ points: [MarkerPoint], duration: TimeInterval) -> Set<Int> {
        retained(points, range: DateInterval(start: start, duration: duration))
    }

    private func retained(_ points: [MarkerPoint], range: DateInterval) -> Set<Int> {
        PerformanceChartMarkers.retainedIDs(in: points, id: \.id, date: \.date, value: \.value,
            run: \.run, visibleRange: range)
    }

    private func point(_ id: Int, offset: TimeInterval, value: Double, run: Int = 1) -> MarkerPoint {
        MarkerPoint(id: id, date: start.addingTimeInterval(offset), value: value, run: run)
    }
}

private struct MarkerPoint: Equatable {
    let id: Int
    let date: Date
    let value: Double
    let run: Int
}
