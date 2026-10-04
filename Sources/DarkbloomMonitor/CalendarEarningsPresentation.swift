import DarkbloomTelemetry
import Foundation

/// Retained calendar observations are display evidence, never current values.
struct CalendarEarningsReading<Value> {
    let value: Value
    let isRetained: Bool
}

enum CalendarEarningsPresentation {
    static func day(_ reading: SourceAvailability<ObservedEarningsWindow>, now: Date,
                    calendar: Calendar) -> CalendarEarningsReading<ObservedEarningsWindow>? {
        guard now.timeIntervalSince1970.isFinite, let value = reading.value,
              value.microUSD >= 0, value.observedSeconds.isFinite, value.observedSeconds > 0,
              let start = value.calendarDayStart, let captured = value.capturedAt,
              start == calendar.startOfDay(for: now), validCapture(captured, since: start, now: now)
        else { return nil }
        let current: Bool
        if case .available = reading,
           case .day = EarningsPresentationValue.calendarDay(value, now: now, calendar: calendar) {
            current = true
        } else { current = false }
        return .init(value: value, isRetained: !current)
    }

    static func week(_ reading: SourceAvailability<CalendarWeekEarningsSummary>, now: Date,
                     calendar: Calendar) -> CalendarEarningsReading<CalendarWeekEarningsSummary>? {
        guard now.timeIntervalSince1970.isFinite, let value = reading.value, value.microUSD >= 0,
              let start = value.weekStart, let captured = value.capturedAt,
              start == calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              validCapture(captured, since: start, now: now) else { return nil }
        let current: Bool
        if case .available = reading { current = value.isCurrent(at: now, calendar: calendar) }
        else { current = false }
        return .init(value: value, isRetained: !current)
    }

    private static func validCapture(_ captured: Date, since start: Date, now: Date) -> Bool {
        captured.timeIntervalSince1970.isFinite && captured >= start
            && now.timeIntervalSince(captured).isFinite && captured <= now
    }
}
