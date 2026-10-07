import DarkbloomTelemetry
import Foundation

/// Membership in the displayed evidence only; no nearest-neighbor interpolation.
struct ModelVisitTimelineSelection {
    let date: Date
    let visits: [ModelVisitTimelineData.Entry]
    let activity: PerformanceActivityHistory.Segment?

    init?(date: Date?, data: ModelVisitTimelineData, activity: PerformanceActivityHistory?) {
        guard let date, date >= data.range.start, date < data.range.end else { return nil }
        self.date = date
        visits = data.entries.filter {
            $0.isPoint ? $0.start == date : $0.start <= date && date < $0.end
        }
        self.activity = activity?.segments.first { $0.start <= date && date < $0.end }
    }
}
