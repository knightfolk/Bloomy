import DarkbloomTelemetry
import Foundation

/// Journal observations grouped on a bounded time grid. Buckets describe where
/// actions were recorded, never command duration, inference, or paid work.
struct ActionTimelineData: Sendable {
    struct Bucket: Identifiable, Sendable {
        let id: Int
        let start: Date
        let end: Date
        let events: [ActionHistoryEvent]
        var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }

    let range: DateInterval
    /// Only populated grid intervals are retained; empty time remains a gap.
    let buckets: [Bucket]

    init(events: [ActionHistoryEvent], range: DateInterval, model: String? = nil,
         maximumBuckets: Int = 96) {
        self.range = range
        guard Self.isFinite(range.start), Self.isFinite(range.end),
              range.duration.isFinite, range.duration > 0 else {
            buckets = []
            return
        }
        let count = min(96, max(1, maximumBuckets))
        // Search the actual Date boundaries rather than rounding a ratio. This
        // keeps an observation exactly on a boundary in the following interval.
        let boundaries = (0...count).map { index in
            index == count ? range.end
                : range.start.addingTimeInterval(range.duration * (Double(index) / Double(count)))
        }
        var grouped = Array(repeating: [ActionHistoryEvent](), count: count)
        for event in events {
            guard event.action != .job, event.action != .baseReward, event.job == nil,
                  Self.isFinite(event.occurredAt), Self.isFinite(event.updatedAt),
                  event.occurredAt >= range.start, event.occurredAt < range.end,
                  model == nil || event.model == nil || event.model == model else { continue }
            let index = Self.index(at: event.occurredAt, boundaries: boundaries)
            grouped[index].append(event)
        }
        buckets = grouped.indices.compactMap { index in
            guard !grouped[index].isEmpty else { return nil }
            let ordered = grouped[index].sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                return $0.id.uuidString < $1.id.uuidString
            }
            return Bucket(id: index, start: boundaries[index], end: boundaries[index + 1], events: ordered)
        }
    }

    func bucket(at date: Date) -> Bucket? {
        guard Self.isFinite(date), date >= range.start, date < range.end else { return nil }
        return buckets.first { $0.start <= date && date < $0.end }
    }

    private static func isFinite(_ date: Date) -> Bool { date.timeIntervalSinceReferenceDate.isFinite }

    private static func index(at date: Date, boundaries: [Date]) -> Int {
        var lower = 0
        var upper = boundaries.count - 1
        while lower < upper {
            let middle = (lower + upper + 1) / 2
            if boundaries[middle] <= date { lower = middle } else { upper = middle - 1 }
        }
        return lower
    }
}
