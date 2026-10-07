import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Retained calendar earnings")
@MainActor
struct RetainedCalendarEarningsTests {
    @Test("account failure retains successful observations without current-value eligibility")
    func accountFailure() async {
        let now = Date()
        let client = CalendarHistoryClient(at: now)
        let store = MonitorStore(service: TelemetryService(source: CalendarHistoryEmptySource()),
            initial: .unavailable(now: now), earningsClient: client, now: { now })
        await store.refreshEarnings()
        let day = store.todayEarnings
        let week = store.weekEarnings
        #expect(day != nil && week != nil)
        await client.setMode(.accountFailure)
        await store.refreshEarnings()
        #expect(store.todayEarnings == day)
        #expect(store.weekEarnings == week)
        #expect(store.currentTodayEarnings == nil)
        #expect(store.currentWeekEarnings == nil)
        #expect(store.earningsPerHourUSD == nil)
        #expect(store.displayedTodayEarnings?.isRetained == true)
        #expect(store.displayedWeekEarnings?.isRetained == true)
        #expect(store.menuPresentation(mode: .earnings).metricText == nil)
    }

    @Test("day and week failures keep independent freshness and recover with corrected zeros")
    func independentFailureAndRecovery() async {
        let now = Date()
        let client = CalendarHistoryClient(at: now)
        let store = MonitorStore(service: TelemetryService(source: CalendarHistoryEmptySource()),
            initial: .unavailable(now: now), earningsClient: client, now: { now })
        await store.refreshEarnings()
        await client.setMode(.dayFailure)
        await store.refreshEarnings()
        #expect(store.displayedTodayEarnings?.isRetained == true)
        #expect(store.currentTodayEarnings == nil)
        #expect(store.earningsPerHourUSD == nil)
        #expect(store.currentWeekEarnings != nil)
        await client.setMode(.weekFailure)
        await store.refreshEarnings()
        #expect(store.currentTodayEarnings != nil)
        #expect(store.displayedWeekEarnings?.isRetained == true)
        #expect(store.currentWeekEarnings == nil)
        await client.setMode(.zero)
        await store.refreshEarnings()
        #expect(store.currentTodayEarnings?.microUSD == 0)
        #expect(store.currentWeekEarnings?.microUSD == 0)
        #expect(store.displayedTodayEarnings?.isRetained == false)
        #expect(store.displayedWeekEarnings?.isRetained == false)
        #expect(store.earningsPerHourUSD == 0)
    }

    @Test("successful nil summaries clear retained values and later failures cannot resurrect them")
    func emptyReplacement() async {
        let now = Date()
        let client = CalendarHistoryClient(at: now)
        let store = MonitorStore(service: TelemetryService(source: CalendarHistoryEmptySource()),
            initial: .unavailable(now: now), earningsClient: client, now: { now })
        await store.refreshEarnings()
        await client.setMode(.accountFailure)
        await store.refreshEarnings()
        #expect(store.displayedTodayEarnings != nil)
        await client.setMode(.empty)
        await store.refreshEarnings()
        await client.setMode(.accountFailure)
        await store.refreshEarnings()
        #expect(store.todayEarnings == nil)
        #expect(store.weekEarnings == nil)
        #expect(store.displayedTodayEarnings == nil)
        #expect(store.displayedWeekEarnings == nil)
    }

    @Test("expiry retains same-period evidence while day and week rollover reject it")
    func expiryAndRollover() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        calendar.firstWeekday = 2
        let now = Date(timeIntervalSince1970: 1_791_072_000) // Sunday, midnight UTC.
        let day = ObservedEarningsWindow(microUSD: 1, observedSeconds: 60,
            calendarDayStart: calendar.startOfDay(for: now), capturedAt: now)
        let week = CalendarWeekEarningsSummary(microUSD: 2, isComplete: true,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: now)?.start, capturedAt: now)
        let dayRead = SourceAvailability.available(value: day, capturedAt: now)
        let weekRead = SourceAvailability.available(value: week, capturedAt: now)
        #expect(CalendarEarningsPresentation.day(dayRead, now: now.addingTimeInterval(600), calendar: calendar)?.isRetained == false)
        #expect(CalendarEarningsPresentation.day(dayRead, now: now.addingTimeInterval(601), calendar: calendar)?.isRetained == true)
        #expect(CalendarEarningsPresentation.week(weekRead, now: now.addingTimeInterval(601), calendar: calendar)?.isRetained == true)
        let tomorrow = try #require(calendar.date(byAdding: .day, value: 1, to: now))
        #expect(CalendarEarningsPresentation.day(dayRead, now: tomorrow, calendar: calendar) == nil)
        #expect(CalendarEarningsPresentation.week(weekRead, now: tomorrow, calendar: calendar) == nil)
        #expect(CalendarEarningsPresentation.day(dayRead, now: now.addingTimeInterval(-1), calendar: calendar) == nil)
        #expect(CalendarEarningsPresentation.week(weekRead, now: now.addingTimeInterval(-1), calendar: calendar) == nil)
    }

    @Test("invalid, undated and unknown summaries never become retained numbers")
    func invalidEvidence() {
        let now = Date()
        for duration in [Double.nan, .infinity, -1, 0] {
            let value = ObservedEarningsWindow(microUSD: 5, observedSeconds: duration,
                calendarDayStart: Calendar.current.startOfDay(for: now), capturedAt: now)
            #expect(CalendarEarningsPresentation.day(.stale(value: value, capturedAt: now, reason: "failed"),
                now: now, calendar: .current) == nil)
        }
        let undated = ObservedEarningsWindow(microUSD: 5, observedSeconds: 60)
        #expect(CalendarEarningsPresentation.day(.available(value: undated, capturedAt: now), now: now, calendar: .current) == nil)
        #expect(CalendarEarningsPresentation.week(.unavailable(reason: "missing"), now: now, calendar: .current) == nil)
    }
}

private actor CalendarHistoryClient: SyntheticAuthenticatedEarningsFixture {
    enum Mode { case normal, accountFailure, dayFailure, weekFailure, empty, zero }
    private var mode = Mode.normal
    let day: ObservedEarningsWindow
    let week: CalendarWeekEarningsSummary
    init(at date: Date) {
        day = ObservedEarningsWindow(microUSD: 1_230_000, observedSeconds: 3_600,
            calendarDayStart: Calendar.current.startOfDay(for: date), capturedAt: date)
        week = CalendarWeekEarningsSummary(microUSD: 7_000_000, isComplete: false,
            weekStart: Calendar.current.dateInterval(of: .weekOfYear, for: date)?.start, capturedAt: date)
    }
    func setMode(_ value: Mode) { mode = value }
    func fetch(now: Date) async throws -> EarningsPresentationValue {
        if mode == .accountFailure { throw CalendarHistoryFailure.unavailable }
        return .available(microUSD: 9_000_000)
    }
    func todayEarningsSummary(now: Date, calendar: Calendar) async throws -> ObservedEarningsWindow? {
        if mode == .dayFailure { throw CalendarHistoryFailure.unavailable }
        if mode == .empty { return nil }
        return mode == .zero ? ObservedEarningsWindow(microUSD: 0, observedSeconds: 3_600,
            calendarDayStart: day.calendarDayStart, capturedAt: day.capturedAt) : day
    }
    func weekEarningsSummary(now: Date, calendar: Calendar) async throws -> CalendarWeekEarningsSummary? {
        if mode == .weekFailure { throw CalendarHistoryFailure.unavailable }
        if mode == .empty { return nil }
        return mode == .zero ? CalendarWeekEarningsSummary(microUSD: 0, isComplete: false,
            weekStart: week.weekStart, capturedAt: week.capturedAt) : week
    }
}

private enum CalendarHistoryFailure: Error { case unavailable }
private struct CalendarHistoryEmptySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw CalendarHistoryFailure.unavailable }
    func readLoadedModels() async throws -> LoadedModelsState { throw CalendarHistoryFailure.unavailable }
    func readStatus() async throws -> StatusSnapshot { throw CalendarHistoryFailure.unavailable }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw CalendarHistoryFailure.unavailable }
}
