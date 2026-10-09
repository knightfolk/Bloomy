import Foundation

/// Selects symbols from actual observations without changing the line data.
enum PerformanceChartMarkers {
    /// A contiguous singleton has no line segment to keep it visible.
    /// Compare neighbors so a reused run label does not merge separate runs.
    static func isolatedIDs<Point, ID: Hashable, Run: Equatable>(
        in points: [Point],
        id: KeyPath<Point, ID>,
        run: KeyPath<Point, Run>
    ) -> Set<ID> {
        var isolated = Set<ID>()
        for index in points.indices {
            let runID = points[index][keyPath: run]
            let hasPrevious = index > points.startIndex && points[index - 1][keyPath: run] == runID
            let hasNext = index + 1 < points.endIndex && points[index + 1][keyPath: run] == runID
            if !hasPrevious && !hasNext { isolated.insert(points[index][keyPath: id]) }
        }
        return isolated
    }

    /// Points follow chronological observation order within each contiguous run.
    /// Run boundaries and extrema take priority over the approximate symbol budget.
    static func retainedIDs<Point, ID: Hashable, Value: Comparable, Run: Equatable>(
        in points: [Point],
        id: KeyPath<Point, ID>,
        date: KeyPath<Point, Date>,
        value: KeyPath<Point, Value>,
        run: KeyPath<Point, Run>,
        visibleRange: DateInterval
    ) -> Set<ID> {
        func allIDs() -> Set<ID> { Set(points.map { $0[keyPath: id] }) }
        guard points.count > 60 else { return allIDs() }
        let spacing = visibleRange.duration / 40
        guard visibleRange.start.timeIntervalSinceReferenceDate.isFinite,
              visibleRange.end.timeIntervalSinceReferenceDate.isFinite,
              spacing.isFinite, spacing > 0 else { return allIDs() }

        var retained = Set<ID>()
        var start = 0
        while start < points.count {
            let runID = points[start][keyPath: run]
            var minimum = start
            var maximum = start
            var last = start
            var markerDate = points[start][keyPath: date]
            guard markerDate.timeIntervalSinceReferenceDate.isFinite else { return allIDs() }
            retained.insert(points[start][keyPath: id])

            var next = start + 1
            while next < points.count, points[next][keyPath: run] == runID {
                let point = points[next]
                let observationDate = point[keyPath: date]
                // Conservatively keep all symbols if chronology cannot be trusted.
                guard observationDate.timeIntervalSinceReferenceDate.isFinite,
                      observationDate >= points[last][keyPath: date] else { return allIDs() }
                if point[keyPath: value] < points[minimum][keyPath: value] { minimum = next }
                if point[keyPath: value] > points[maximum][keyPath: value] { maximum = next }
                if observationDate.timeIntervalSince(markerDate) >= spacing {
                    retained.insert(point[keyPath: id])
                    markerDate = observationDate
                }
                last = next
                next += 1
            }

            retained.insert(points[last][keyPath: id])
            retained.insert(points[minimum][keyPath: id])
            retained.insert(points[maximum][keyPath: id])
            start = next
        }
        return retained
    }
}
