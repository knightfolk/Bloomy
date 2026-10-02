import SwiftUI

/// Retained hidden views get a current date without requesting recurring
/// display updates. Showing the view starts with the new current date and
/// then follows the original schedule, including calendar-based alignment.
struct VisibilityTimelineSchedule<Base: TimelineSchedule>: TimelineSchedule {
    let base: Base
    let isVisible: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(
            initialDate: startDate,
            iterator: isVisible ? base.entries(from: startDate, mode: mode).makeIterator() : nil
        )
    }

    struct Entries: Sequence, IteratorProtocol {
        var initialDate: Date?
        var iterator: Base.Entries.Iterator?
        private var lastDate: Date?

        init(initialDate: Date, iterator: Base.Entries.Iterator?) {
            self.initialDate = initialDate
            self.iterator = iterator
        }

        mutating func next() -> Date? {
            if let date = initialDate {
                initialDate = nil
                lastDate = date
                return date
            }
            while let date = iterator?.next() {
                // Some schedules include the initial date, or a preceding
                // calendar boundary. Do not render that date a second time.
                if let lastDate, date <= lastDate { continue }
                lastDate = date
                return date
            }
            return nil
        }
    }
}
