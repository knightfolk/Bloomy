import Foundation

/// Pure projections of one atomic scoped report. No legacy database reads or
/// lifetime-balance deltas can enter these values. Counts remain credit records.
public extension AccountCreditReport {
    func activityBuckets(model selectedModel: String? = nil) -> [ActivityBucket] {
        guard let selectedModel else {
            return buckets.map { ActivityBucket(interval: $0.interval,
                totals: $0.totals.map(Self.activityTotals), coverage: $0.coverage) }
        }
        // A filtered report cannot establish another model's absence.
        guard model == nil || model == selectedModel, selectedModel != "base_reward" else {
            return buckets.map { ActivityBucket(interval: $0.interval, totals: nil, coverage: .unavailable) }
        }
        var byStart: [Date: AccountCreditTotals] = [:]
        for value in modelBuckets where value.model == selectedModel {
            byStart[value.interval.start] = value.totals
        }
        return buckets.map { bucket in
            let value = byStart[bucket.interval.start]
            let complete = reconciliation == .matched
                && observation.map { bucket.interval.end.timeIntervalSince1970 <= $0.balance.capturedAt.timeIntervalSince1970 } == true
            return ActivityBucket(interval: bucket.interval,
                totals: value.map(Self.activityTotals) ?? (complete ? Self.zeroActivity : nil),
                coverage: value != nil || complete ? .recorded : .unavailable)
        }
    }

    func recentModelEarnings() -> [ModelEarnings] { modelTotals }

    func modelWorkEarnings(calendar: Calendar) throws -> [ModelWorkEarnings] {
        guard queryCalendar == nil || queryCalendar == calendar else { throw ActivityCalendarError.invalidInterval }
        // A displayed day report may cover up to 744 calendar days. These hour
        // intervals are bounded independently and preserve repeated DST hours.
        let hours = try ActivityCalendar.intervals(in: range, unit: .hour, calendar: calendar,
            maximumBuckets: 744 * 25)
        let capturedAt = observation?.balance.capturedAt
        let complete = reconciliation == .matched
            && capturedAt.map { range.end.timeIntervalSince1970 <= $0.timeIntervalSince1970 } == true
        let hourStarts = Set(hours.compactMap { calendar.dateInterval(of: .hour, for: $0.start)?.start })
        return modelTotals.map { value in
            let earningHours = Set(modelEarningHourStarts[value.model] ?? [])
            let recorded = complete ? hours.count : earningHours.intersection(hourStarts).count
            return ModelWorkEarnings(model: value.model, queryPeriod: range, sourceCapturedAt: capturedAt,
                workMicroUSD: value.microUSD, jobs: value.jobs, recordedHours: recorded,
                unknownHours: hours.count - recorded, uncertainBoundaryHours: 0)
        }
    }

    func observedEarningsWindow(calendar: Calendar) throws -> ObservedEarningsWindow? {
        guard queryCalendar == nil || queryCalendar == calendar else { throw ActivityCalendarError.invalidInterval }
        guard let totals, let capture = observation?.balance.capturedAt,
              capture.timeIntervalSince1970 >= range.start.timeIntervalSince1970 else { return nil }
        let dayStart = calendar.startOfDay(for: capture)
        guard range.start == dayStart else { return nil }
        let complete = reconciliation == .matched
            && range.end.timeIntervalSince1970 == capture.timeIntervalSince1970
        return ObservedEarningsWindow(microUSD: try Self.totalMicroUSD(totals),
            observedSeconds: complete ? capture.timeIntervalSince(dayStart) : 0,
            calendarDayStart: dayStart, capturedAt: capture, coversDayToDate: complete)
    }

    func calendarWeekSummary(calendar: Calendar) throws -> CalendarWeekEarningsSummary? {
        guard queryCalendar == nil || queryCalendar == calendar else { throw ActivityCalendarError.invalidInterval }
        guard let totals, let capture = observation?.balance.capturedAt,
              capture.timeIntervalSince1970 >= range.start.timeIntervalSince1970,
              range.start == calendar.dateInterval(of: .weekOfYear, for: capture)?.start else { return nil }
        return CalendarWeekEarningsSummary(microUSD: try Self.totalMicroUSD(totals),
            isComplete: reconciliation == .matched
                && range.end.timeIntervalSince1970 == capture.timeIntervalSince1970,
            weekStart: range.start, capturedAt: capture)
    }

    private static func totalMicroUSD(_ value: AccountCreditTotals) throws -> Int64 {
        let (total, overflow) = value.workMicroUSD.addingReportingOverflow(value.rewardMicroUSD)
        guard !overflow else { throw EarningsDatabaseError.sqlite(message: "scoped credit total out of range") }
        return total
    }

    private static func activityTotals(_ value: AccountCreditTotals) -> ActivityTotals {
        ActivityTotals(workMicroUSD: value.workMicroUSD, rewardMicroUSD: value.rewardMicroUSD,
            jobs: value.workCreditCount, promptTokens: value.promptTokens, completionTokens: value.completionTokens)
    }

    private static var zeroActivity: ActivityTotals {
        ActivityTotals(workMicroUSD: 0, rewardMicroUSD: 0, jobs: 0, promptTokens: 0, completionTokens: 0)
    }
}
