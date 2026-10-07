import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Account credit presentation projections")
struct AccountCreditPresentationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var range: DateInterval { DateInterval(start: start, duration: 10_800) }

    @Test("selected model projections preserve exact credit counts and tokens and exclude rewards")
    func exactModelCountsAndTokens() async throws {
        let database = try EarningsDatabase(url: url())
        let rows = [
            credit(1, amount: 100_000, model: "gemma", prompt: 2, completion: 3),
            credit(2, amount: -25_000, model: "gemma", prompt: 5, completion: 7,
                at: start.addingTimeInterval(120)),
            credit(3, amount: 200_000, model: "qwen", prompt: 11, completion: 13),
            credit(4, amount: 50_000, model: "base_reward", prompt: 0, completion: 0),
            credit(5, amount: 0, model: "gemma", prompt: 17, completion: 19,
                at: start.addingTimeInterval(3_600)),
        ]
        try await database.ingest(page(rows, total: 325_000), capturedAt: range.end)
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: range, unit: .hour, calendar: calendar)
        let selected = report.activityBuckets(model: "gemma")
        #expect(selected.count == 3)
        #expect(selected[0].totals == ActivityTotals(workMicroUSD: 75_000, rewardMicroUSD: 0,
            jobs: 2, promptTokens: 7, completionTokens: 10))
        #expect(selected[1].totals == ActivityTotals(workMicroUSD: 0, rewardMicroUSD: 0,
            jobs: 1, promptTokens: 17, completionTokens: 19))
        #expect(selected[2].totals == ActivityTotals(workMicroUSD: 0, rewardMicroUSD: 0,
            jobs: 0, promptTokens: 0, completionTokens: 0))
        #expect(report.modelBuckets.filter { $0.model == "gemma" }.map(\.totals.workCreditCount) == [2, 1])
        #expect(report.activityBuckets()[0].totals?.rewardMicroUSD == 50_000)
        #expect(report.activityBuckets()[0].totals?.jobs == 3)
        #expect(report.activityBuckets()[0].totals?.promptTokens == 18)
        #expect(report.activityBuckets()[0].totals?.completionTokens == 23)
        let recent = report.recentModelEarnings()
        #expect(recent.first { $0.model == "gemma" } == ModelEarnings(model: "gemma", microUSD: 75_000, jobs: 3))
        #expect(recent.first { $0.model == "qwen" } == ModelEarnings(model: "qwen", microUSD: 200_000, jobs: 1))
        #expect(!recent.contains { $0.model == "base_reward" })
        let work = try #require(try report.modelWorkEarnings(calendar: calendar).first { $0.model == "gemma" })
        #expect(work.workMicroUSD == 75_000 && work.jobs == 3)
        #expect(work.queryPeriod == range && work.sourceCapturedAt == range.end)
        #expect(work.unknownHours == 0 && work.uncertainBoundaryHours == 0)
        #expect(report.hourlyEarningsAverages.first { $0.model == "gemma" }
            == ModelHourlyEarningsAverage(model: "gemma", workMicroUSD: 75_000, earningHours: 2))
    }

    @Test("signed corrections move projected credits without retaining the old hour or token totals")
    func correctionsReplaceProjectedValues() async throws {
        let database = try EarningsDatabase(url: url())
        let other = credit(2, amount: 300_000, model: "qwen", prompt: 30, completion: 40,
            at: start.addingTimeInterval(3_600))
        try await database.ingest(page([credit(1, amount: 100_000, model: "gemma"), other], total: 400_000),
            capturedAt: range.end)
        let corrected = credit(1, amount: -50_000, model: "gemma", prompt: 4, completion: 6,
            at: start.addingTimeInterval(7_200))
        try await database.ingest(page([corrected, other], total: 250_000),
            capturedAt: range.end.addingTimeInterval(1))
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: range, unit: .hour, calendar: calendar)
        let selected = report.activityBuckets(model: "gemma")
        #expect(selected[0].totals?.workMicroUSD == 0 && selected[0].totals?.jobs == 0)
        #expect(selected[0].totals?.promptTokens == 0 && selected[0].totals?.completionTokens == 0)
        #expect(selected[2].totals == ActivityTotals(workMicroUSD: -50_000, rewardMicroUSD: 0,
            jobs: 1, promptTokens: 4, completionTokens: 6))
        #expect(report.recentModelEarnings().first { $0.model == "gemma" }
            == ModelEarnings(model: "gemma", microUSD: -50_000, jobs: 1))
        #expect(report.hourlyEarningsAverages.first { $0.model == "gemma" }
            == ModelHourlyEarningsAverage(model: "gemma", workMicroUSD: -50_000, earningHours: 1))
    }

    @Test("another model's observed hour does not establish selected-model zero without reconciliation")
    func selectedModelUnknownVersusMatchedZero() async throws {
        let database = try EarningsDatabase(url: url())
        let rows = [credit(1, amount: 100, model: "gemma"),
            credit(2, amount: 200, model: "qwen", at: start.addingTimeInterval(3_600))]
        try await database.ingest(page(rows, total: 1_000, count: 3), capturedAt: range.end)
        let partial = try await database.accountCreditReport(accountID: "presentation-account",
            in: range, unit: .hour, calendar: calendar)
        #expect(partial.activityBuckets()[1].totals?.workMicroUSD == 200)
        let selected = partial.activityBuckets(model: "gemma")
        #expect(selected[0].totals?.workMicroUSD == 100)
        #expect(selected[1].totals == nil && selected[1].coverage == .unavailable)
        #expect(selected[2].totals == nil && selected[2].coverage == .unavailable)
        #expect(partial.activityBuckets(model: "missing").allSatisfy { $0.totals == nil })
        let work = try #require(try partial.modelWorkEarnings(calendar: calendar).first { $0.model == "gemma" })
        #expect(work.workMicroUSD == 100 && work.jobs == 1 && work.unknownHours == 2)

        try await database.ingest(page(rows, total: 300), capturedAt: range.end.addingTimeInterval(1))
        let matched = try await database.accountCreditReport(accountID: "presentation-account",
            in: range, unit: .hour, calendar: calendar)
        #expect(matched.reconciliation == .matched)
        #expect(matched.activityBuckets(model: "gemma")[1].totals?.workMicroUSD == 0)
        #expect(matched.activityBuckets(model: "gemma")[1].totals?.jobs == 0)
        #expect(matched.activityBuckets(model: "missing").allSatisfy {
            $0.coverage == .recorded && $0.totals?.workMicroUSD == 0 && $0.totals?.jobs == 0
        })
        let future = try await database.accountCreditReport(accountID: "presentation-account",
            in: DateInterval(start: range.end.addingTimeInterval(3_600), duration: 3_600),
            unit: .hour, calendar: calendar)
        #expect(future.activityBuckets(model: "gemma").allSatisfy { $0.totals == nil && $0.coverage == .unavailable })
    }

    @Test("earning-hour averages use exact row hours even when the displayed report uses days")
    func averagesDoNotCountDisplayBuckets() async throws {
        let database = try EarningsDatabase(url: url())
        let dayStart = calendar.startOfDay(for: start)
        let period = DateInterval(start: dayStart, duration: 2 * 86_400)
        let rows = [
            credit(1, amount: 100_000, model: "gemma", at: dayStart),
            credit(2, amount: 50_000, model: "gemma", at: dayStart.addingTimeInterval(120)),
            credit(3, amount: 250_000, model: "gemma", at: dayStart.addingTimeInterval(3_600)),
            credit(4, amount: -100_000, model: "gemma", at: dayStart.addingTimeInterval(90_000)),
            credit(5, amount: 200_000, model: "qwen", at: dayStart),
            credit(6, amount: 1_000_000, model: "base_reward", prompt: 0, completion: 0, at: dayStart),
        ]
        try await database.ingest(page(rows, total: 1_500_000), capturedAt: period.end)
        let hours = try await database.accountCreditReport(accountID: "presentation-account",
            in: period, unit: .hour, calendar: calendar)
        let days = try await database.accountCreditReport(accountID: "presentation-account",
            in: period, unit: .day, calendar: calendar)
        #expect(hours.buckets.count == 48 && days.buckets.count == 2)
        #expect(days.hourlyEarningsAverages == hours.hourlyEarningsAverages)
        let gemma = try #require(days.hourlyEarningsAverages.first { $0.model == "gemma" })
        #expect(gemma.workMicroUSD == 300_000 && gemma.earningHours == 3)
        #expect(abs(gemma.averageWorkUSDPerEarningHour - 0.1) < 0.000_001)
        #expect(days.recentModelEarnings() == hours.recentModelEarnings())
        #expect(!days.hourlyEarningsAverages.contains { $0.model == "base_reward" })
    }

    @Test("repeated local DST hours remain distinct earning hours in daily and hourly reports")
    func repeatedDaylightSavingHours() async throws {
        var local = calendar
        local.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let formatter = ISO8601DateFormatter()
        let first = try #require(formatter.date(from: "2026-11-01T08:15:00Z"))
        let second = try #require(formatter.date(from: "2026-11-01T09:15:00Z"))
        let day = try #require(local.dateInterval(of: .day, for: first))
        #expect(day.duration == 25 * 3_600)
        #expect(local.component(.hour, from: first) == 1 && local.component(.hour, from: second) == 1)
        let database = try EarningsDatabase(url: url())
        let rows = [credit(1, amount: 100_000, model: "gemma", at: first),
            credit(2, amount: 50_000, model: "gemma", at: first.addingTimeInterval(1_800)),
            credit(3, amount: 300_000, model: "gemma", at: second)]
        try await database.ingest(page(rows, total: 450_000), capturedAt: day.end)
        let hours = try await database.accountCreditReport(accountID: "presentation-account",
            in: day, unit: .hour, calendar: local)
        let days = try await database.accountCreditReport(accountID: "presentation-account",
            in: day, unit: .day, calendar: local)
        let repeated = hours.activityBuckets(model: "gemma").filter { local.component(.hour, from: $0.interval.start) == 1 }
        #expect(hours.buckets.count == 25 && repeated.count == 2)
        #expect(repeated[0].interval.start != repeated[1].interval.start)
        #expect(repeated.map { $0.totals?.workMicroUSD } == [150_000, 300_000])
        #expect(repeated.map { $0.totals?.jobs } == [2, 1])
        #expect(days.hourlyEarningsAverages == hours.hourlyEarningsAverages)
        #expect(days.hourlyEarningsAverages == [
            ModelHourlyEarningsAverage(model: "gemma", workMicroUSD: 450_000, earningHours: 2),
        ])
    }

    @Test("partial account history cannot establish a complete calendar-day rate")
    func partialHistoryHasNoCompleteDayRate() async throws {
        let database = try EarningsDatabase(url: url())
        let dayStart = calendar.startOfDay(for: start)
        let captured = dayStart.addingTimeInterval(12 * 3_600)
        let rows = [credit(1, amount: 100_000, model: "gemma", at: dayStart.addingTimeInterval(3_600)),
            credit(2, amount: 20_000, model: "base_reward", prompt: 0, completion: 0, at: dayStart.addingTimeInterval(3_600))]
        try await database.ingest(page(rows, total: 2_000_000, count: 10), capturedAt: captured)
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: DateInterval(start: dayStart, end: captured), unit: .hour, calendar: calendar)
        let summary = try #require(try report.observedEarningsWindow(calendar: calendar))
        #expect(summary.microUSD == 120_000)
        #expect(!summary.coversDayToDate && summary.observedSeconds == 0)
        #expect(summary.calendarDayStart == dayStart && summary.capturedAt == captured)
        #expect(report.activityBuckets().contains { $0.totals == nil && $0.coverage == .unavailable })
    }

    @Test("a reconciled day preserves signed work corrections and keeps selected-model rewards out")
    func completeDayKeepsSignedSubtotal() async throws {
        let database = try EarningsDatabase(url: url())
        let dayStart = calendar.startOfDay(for: start)
        let captured = dayStart.addingTimeInterval(12 * 3_600)
        let rows = [credit(1, amount: -50_000, model: "gemma", at: dayStart.addingTimeInterval(3_600)),
            credit(2, amount: 20_000, model: "base_reward", prompt: 0, completion: 0, at: dayStart.addingTimeInterval(3_600))]
        try await database.ingest(page(rows, total: -30_000), capturedAt: captured)
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: DateInterval(start: dayStart, end: captured), unit: .hour, calendar: calendar)
        let summary = try #require(try report.observedEarningsWindow(calendar: calendar))
        #expect(summary.microUSD == -30_000 && summary.coversDayToDate)
        #expect(summary.observedSeconds == 12 * 3_600)
        #expect(report.activityBuckets(model: "gemma").compactMap(\.totals).reduce(0) { $0 + $1.workMicroUSD } == -50_000)
        #expect(report.activityBuckets(model: "gemma").compactMap(\.totals).allSatisfy { $0.rewardMicroUSD == 0 })
    }

    @Test("fractional persisted capture endpoints retain matched day completeness", arguments: [0.000003, 0.000004])
    func fractionalCaptureKeepsDayComplete(captureFraction: TimeInterval) async throws {
        let database = try EarningsDatabase(url: url())
        let occurred = Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(0.000002)
        let captured = occurred.addingTimeInterval(5).addingTimeInterval(captureFraction)
        try await database.ingest(page([credit(1, amount: 10, model: "gemma", at: occurred)], total: 10),
            capturedAt: captured)
        let persisted = try #require(try await database.accountCreditRecords(accountID: "presentation-account").first)
        #expect(persisted.createdAt != occurred)
        #expect(persisted.createdAt.timeIntervalSince1970 == occurred.timeIntervalSince1970)
        let period = DateInterval(start: calendar.startOfDay(for: captured), end: captured)
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: period, unit: .hour, calendar: calendar)
        let persistedCapture = try #require(report.observation?.balance.capturedAt)
        #expect(persistedCapture.timeIntervalSince1970 == captured.timeIntervalSince1970)
        if captureFraction == 0.000004 { #expect(persistedCapture != captured) }
        #expect(report.reconciliation == .matched)
        let day = try #require(try report.observedEarningsWindow(calendar: calendar))
        #expect(day.microUSD == 10 && day.coversDayToDate && day.observedSeconds > 0)
        #expect(day.capturedAt?.timeIntervalSince1970 == captured.timeIntervalSince1970)
    }

    @Test("fractional persisted capture endpoints retain matched week completeness", arguments: [0.000003, 0.000004])
    func fractionalCaptureKeepsWeekComplete(captureFraction: TimeInterval) async throws {
        let database = try EarningsDatabase(url: url())
        let occurred = Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(0.000002)
        let captured = occurred.addingTimeInterval(5).addingTimeInterval(captureFraction)
        try await database.ingest(page([credit(1, amount: 10, model: "gemma", at: occurred)], total: 10),
            capturedAt: captured)
        let persisted = try #require(try await database.accountCreditRecords(accountID: "presentation-account").first)
        #expect(persisted.createdAt != occurred)
        #expect(persisted.createdAt.timeIntervalSince1970 == occurred.timeIntervalSince1970)
        let weekStart = try #require(calendar.dateInterval(of: .weekOfYear, for: captured)?.start)
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: DateInterval(start: weekStart, end: captured), unit: .day, calendar: calendar)
        let persistedCapture = try #require(report.observation?.balance.capturedAt)
        #expect(persistedCapture.timeIntervalSince1970 == captured.timeIntervalSince1970)
        if captureFraction == 0.000004 { #expect(persistedCapture != captured) }
        #expect(report.reconciliation == .matched)
        let week = try #require(try report.calendarWeekSummary(calendar: calendar))
        #expect(week.microUSD == 10 && week.isComplete && week.weekStart == weekStart)
        #expect(week.capturedAt?.timeIntervalSince1970 == captured.timeIntervalSince1970)
    }

    @Test("calendar-sensitive projections reject a calendar different from the query")
    func mismatchedProjectionCalendar() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([credit(1, amount: 10, model: "gemma")], total: 10), capturedAt: range.end)
        let report = try await database.accountCreditReport(accountID: "presentation-account",
            in: range, unit: .hour, calendar: calendar)
        var other = calendar
        other.timeZone = try #require(TimeZone(identifier: "Asia/Kolkata"))
        #expect(throws: ActivityCalendarError.invalidInterval) { try report.modelWorkEarnings(calendar: other) }
        #expect(throws: ActivityCalendarError.invalidInterval) { try report.observedEarningsWindow(calendar: other) }
        #expect(throws: ActivityCalendarError.invalidInterval) { try report.calendarWeekSummary(calendar: other) }
    }

    private func url() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bloomy-credit-presentation-\(UUID()).sqlite3")
    }
    private func credit(_ id: Int64, amount: Int64, model: String, prompt: Int = 10,
        completion: Int = 20, at date: Date? = nil) -> AccountEarning {
        AccountEarning(id: id, providerID: "synthetic-provider", providerKey: "synthetic-key",
            model: model, amountMicroUSD: amount, promptTokens: prompt, completionTokens: completion,
            createdAt: date ?? start)
    }
    private func page(_ rows: [AccountEarning], total: Int64, count: Int64? = nil) -> AccountEarningsResponse {
        AccountEarningsResponse(accountID: "presentation-account", earnings: rows,
            count: count ?? Int64(rows.count), historyLimit: 100, recentCount: rows.count,
            totalMicroUSD: total, availableBalanceMicroUSD: total, withdrawableBalanceMicroUSD: total)
    }
}
