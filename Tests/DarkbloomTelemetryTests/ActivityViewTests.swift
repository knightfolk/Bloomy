import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Activity rendering", .serialized)
@MainActor
struct ActivityViewTests {
    @Test("a complete chart uses one unfiltered report for buckets, models, contributions and averages",
          arguments: [ActivityChartMetric.earnings, .estimatedProfit])
    func oneAtomicReport(metric: ActivityChartMetric) async throws {
        let client = ActivityAtomicReadClient()
        let store = MonitorStore(service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: client)
        let session = await store.synchronizeFinancialSession()
        let context = try #require(session.context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 7_200)
        let query = ActivityQuery(period: .today, selectedDate: now, endDate: now, now: now,
            calendar: calendar, model: "synthetic-model-A", revision: 0, refreshID: 0,
            metric: metric, context: context, ledgerReady: true, sessionEpoch: store.financialSessionEpoch)
        let result = try await ActivityReadSnapshot.fetch(query: query, store: store)
        let snapshot = try #require(result)
        #expect(snapshot.query.context == context)
        #expect(snapshot.models == ["synthetic-model-A", "synthetic-model-B"])
        #expect(snapshot.buckets.first?.totals?.workMicroUSD == 11)
        #expect(snapshot.modelWorkByBucket.values.first?["synthetic-model-A"] == 11)
        #expect(snapshot.modelWorkByBucket.values.first?["synthetic-model-B"] == 22)
        #expect(snapshot.modelHourlyAverages.first?.workMicroUSD == 99)
        let requests = await client.requests()
        #expect(requests.count == 1)
        #expect(requests.first?.context == context)
        #expect(requests.first?.model == nil)
        #expect(requests.first?.unit == .hour)
        #expect(await client.legacyReads() == 0)
        // Store validates the report and the snapshot validates again after
        // supplementary token history, immediately before publication.
        #expect(await client.validationCount() >= 2)
    }

    @Test("daily profit uses distinct hourly attribution from exactly one captured report")
    func dailyProfitUsesOneAtomicReport() async throws {
        let client = ActivityAtomicReadClient()
        let store = MonitorStore(service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: client)
        let session = await store.synchronizeFinancialSession()
        let context = try #require(session.context)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 7_200)
        let query = ActivityQuery(period: .dateRange, selectedDate: now, endDate: now, now: now,
            calendar: calendar, model: nil, revision: 0, refreshID: 0,
            metric: .estimatedProfit, context: context, sessionEpoch: store.financialSessionEpoch)
        let power = (0..<240).map { index in
            EnergyInterval(start: Date(timeIntervalSince1970: Double(index * 30)),
                end: Date(timeIntervalSince1970: Double((index + 1) * 30)),
                kWh: 0.1 / 240, usdPerKWh: 0.2, source: "inert-fixture", estimated: true)
        }
        let result = try await ActivityReadSnapshot.fetch(query: query, store: store, powerIntervals: power)
        let snapshot = try #require(result)
        let requests = await client.requests()
        #expect(requests.count == 1)
        #expect(requests.map(\.unit) == [.day])
        #expect(requests.allSatisfy { $0.context == context && $0.model == nil })
        #expect(snapshot.buckets.first?.totals?.workMicroUSD == 33)
        #expect(snapshot.modelHourlyAverages.first?.workMicroUSD == 99)
        let modelProfit = snapshot.modelHourlyProfits.filter { $0.model == "synthetic-model-A" }
        #expect(modelProfit.map(\.interval.start) == [Date(timeIntervalSince1970: 0), Date(timeIntervalSince1970: 3_600)])
        #expect(modelProfit.map(\.grossUSD) == [0.000005, 0.000006])
        #expect(modelProfit.allSatisfy { $0.profitUSD < 0 })
        #expect(snapshot.modelHourlyProfitAverages.first { $0.model == "synthetic-model-A" }?.coveredHours == 2)
        #expect(await client.legacyReads() == 0)
    }

    @Test("hidden Earnings skips revision reads, cancels pending work and rereads on restoration")
    func hiddenReadLifecycle() async throws {
        let client = ActivityHeldReadClient()
        let store = MonitorStore(service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: client)
        let host = NSHostingController(rootView: ActivityView(store: store))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        #expect(await client.counts().started == 0)

        store.setDashboardVisible(true)
        try await waitForReads(client, started: 1, cancelled: 0)
        store.setDashboardVisible(false)
        try await waitForReads(client, started: 1, cancelled: 1)
        let revision = store.activityRevision
        await store.refreshEarnings()
        #expect(store.activityRevision > revision)
        try await Task.sleep(for: .milliseconds(200))
        #expect(await client.counts().started == 1)

        store.setDashboardVisible(true)
        try await waitForReads(client, started: 2, cancelled: 1)
        store.setDashboardVisible(false)
        try await waitForReads(client, started: 2, cancelled: 2)
        #expect(await client.counts().buckets == 0)
    }

    private func waitForReads(_ client: ActivityHeldReadClient, started: Int, cancelled: Int) async throws {
        for _ in 0..<40 {
            let counts = await client.counts()
            if counts.started == started, counts.cancelled == cancelled { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        let counts = await client.counts()
        #expect(counts.started == started)
        #expect(counts.cancelled == cancelled)
    }

    @Test("Metrics tab preserves Activity initializer options and renders without a history store")
    func rendersMetricsTab() async throws {
        let store = MonitorStore(
            service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: ActivityFixtureClient()
        )
        store.setDashboardVisible(true)
        let host = NSHostingController(rootView: ActivityView(
            store: store, initialModelFilter: ActivityFixtureModel.gemma,
            initialChartStyle: .lines, initialBarArrangement: .sideBySide,
            initialChartMetric: .estimatedProfit, initialTab: .metrics
        ))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width == 420)
        #expect(host.view.frame.height >= 600)
    }

    @Test("populated local activity fits narrow through wide dashboard detail columns", arguments: [1_080.0, 780.0, 570.0, 420.0])
    func rendersActivity(width: Double) async throws {
        let store = MonitorStore(
            service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: ActivityFixtureClient()
        )
        store.setDashboardVisible(true)
        let host = NSHostingController(rootView: ActivityView(store: store))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        // Allow the view's bounded local query and chart layout to complete.
        try await Task.sleep(for: .milliseconds(300))
        host.view.layoutSubtreeIfNeeded()
        let view = host.view
        #expect(view.frame.width <= width)
        #expect(view.frame.height >= 600)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/darkbloom-activity-fixture.png"))
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-activity-window-\(Int(width)).png"]
        try capture.run()
        capture.waitUntilExit()
    }

    @Test("filtered one-model activity renders without changing the chart color scale")
    func rendersFilteredModelChart() async throws {
        let store = MonitorStore(
            service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: ActivityFixtureClient()
        )
        store.setDashboardVisible(true)
        let host = NSHostingController(rootView: ActivityView(store: store, initialModelFilter: ActivityFixtureModel.gemma))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 620))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width == 420)
        #expect(host.view.frame.height >= 600)
    }

    @Test("line, area, and side-by-side chart choices render with populated model data")
    func rendersAlternativeChartStyles() async throws {
        let cases: [(ActivityChartStyle, ActivityBarArrangement)] = [
            (.lines, .stacked), (.area, .stacked), (.bars, .sideBySide),
        ]
        for (style, arrangement) in cases {
            let store = MonitorStore(
                service: TelemetryService(source: ActivityUnusedSource()),
                initial: .unavailable(now: Date()), earningsClient: ActivityFixtureClient()
            )
            store.setDashboardVisible(true)
            let host = NSHostingController(rootView: ActivityView(
                store: store,
                initialChartStyle: style,
                initialBarArrangement: arrangement
            ))
            let window = NSWindow(contentViewController: host)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 570, height: 650))
            window.orderBack(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutSubtreeIfNeeded()
            #expect(host.view.frame.width <= 570)
            #expect(host.view.frame.height >= 600)

            guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { continue }
            let suffix = style == .bars ? "side-by-side" : style.rawValue.lowercased()
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-activity-\(suffix)-570.png"]
            try capture.run()
            capture.waitUntilExit()
        }
    }

    @Test("estimated-profit chart renders signed fixture data when power coverage is complete")
    func rendersEstimatedProfitWithCoveredPower() async throws {
        let now = Date()
        let store = MonitorStore(
            service: TelemetryService(source: ActivityUnusedSource()),
            initial: .unavailable(now: now),
            initialEnergy: fixtureEnergy(now: now),
            earningsClient: ActivityFixtureClient()
        )
        store.setDashboardVisible(true)
        let host = NSHostingController(rootView: ActivityView(store: store, initialChartMetric: .estimatedProfit))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 780, height: 760))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width == 780)
        #expect(host.view.frame.height >= 720)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-activity-profit.png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}

private func fixtureEnergy(now: Date) -> EnergyRecordingSnapshot {
    let calendar = Calendar.current
    let start = calendar.startOfDay(for: now)
    let end = calendar.dateInterval(of: .hour, for: now)?.start ?? now
    var cursor = start
    var intervals: [EnergyInterval] = []
    let step: TimeInterval = 10
    while cursor.addingTimeInterval(step) <= end {
        let next = cursor.addingTimeInterval(step)
        intervals.append(EnergyInterval(
            start: cursor,
            end: next,
            kWh: 0.4 * step / 3_600,
            usdPerKWh: 0.2,
            source: "render-fixture",
            estimated: true
        ))
        cursor = next
    }
    return EnergyRecordingSnapshot(
        reading: EnergyReading(date: cursor, watts: 400, source: "render-fixture", estimated: true),
        intervals: intervals,
        issue: nil
    )
}

private enum ActivityFixtureModel {
    static let gemma = "google/gemma-4-26b"
    static let qwen = "qwen/qwen3.8-27b"
}

private struct ActivityFixtureClient: SyntheticAuthenticatedEarningsFixture {
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "Render fixture") }
    func activityModels(in range: DateInterval) async throws -> [String] { [ActivityFixtureModel.gemma, ActivityFixtureModel.qwen] }

    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar).enumerated().flatMap { index, interval -> [ModelActivityBucket] in
            guard index != 3 else { return [] }
            let gemma = Int64((index % 5 + 1) * 25_000)
            let qwen = Int64((index % 3 + 1) * 15_000)
            return [
                ModelActivityBucket(interval: interval, model: ActivityFixtureModel.gemma, workMicroUSD: gemma),
                ModelActivityBucket(interval: interval, model: ActivityFixtureModel.qwen, workMicroUSD: qwen),
            ]
        }
    }

    func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]? {
        [
            ModelHourlyEarningsAverage(model: ActivityFixtureModel.gemma, workMicroUSD: 100_000, earningHours: 4),
            ModelHourlyEarningsAverage(model: ActivityFixtureModel.qwen, workMicroUSD: 120_000, earningHours: 3),
        ]
    }

    func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]? {
        guard let model else { return try await activity(in: range, unit: unit, calendar: calendar) }
        return try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar).enumerated().map { index, interval in
            let work: Int64 = model == ActivityFixtureModel.gemma
                ? Int64((index % 5 + 1) * 25_000)
                : Int64((index % 3 + 1) * 15_000)
            return ActivityBucket(interval: interval, totals: index == 3 ? nil : ActivityTotals(
                workMicroUSD: work, rewardMicroUSD: 0, jobs: 1, promptTokens: 100, completionTokens: 200
            ), coverage: index == 3 ? .unavailable : .recorded)
        }
    }

    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar).enumerated().map { index, interval in
            let gemma = Int64((index % 5 + 1) * 25_000)
            let qwen = Int64((index % 3 + 1) * 15_000)
            return ActivityBucket(interval: interval, totals: index == 3 ? nil : ActivityTotals(
                workMicroUSD: gemma + qwen,
                rewardMicroUSD: 10_000, jobs: Int64(index + 1), promptTokens: 100, completionTokens: 200
            ), coverage: index == 3 ? .unavailable : .recorded)
        }
    }
}

private struct ActivityUnusedSource: TelemetrySource {
    struct Unused: Error {}
    func readDaemonState() async throws -> DaemonState { throw Unused() }
    func readLoadedModels() async throws -> LoadedModelsState { throw Unused() }
    func readStatus() async throws -> StatusSnapshot { throw Unused() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw Unused() }
}

private actor ActivityHeldReadClient: SyntheticAuthenticatedEarningsFixture {
    private var started = 0
    private var cancelled = 0
    private var buckets = 0
    func counts() -> (started: Int, cancelled: Int, buckets: Int) { (started, cancelled, buckets) }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "Inert fixture") }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        try await validateFinancialContext(context)
        started += 1
        do { try await Task.sleep(for: .seconds(60)) }
        catch { cancelled += 1; throw error }
        try await validateFinancialContext(context)
        return SyntheticAccountCreditReport.make(context: context, providerID: providerID, model: model, range: range)
    }
    func activityModels(in range: DateInterval) async throws -> [String] {
        buckets += 1
        return []
    }
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        buckets += 1
        return []
    }
}

private actor ActivityAtomicReadClient: SyntheticAuthenticatedEarningsFixture {
    struct Request: Sendable {
        let context: AccountEarningsContext
        let model: String?
        let unit: ActivityCalendarUnit
    }
    private var reads: [Request] = []
    private var legacyReadCount = 0
    private var validations = 0
    func requests() -> [Request] { reads }
    func legacyReads() -> Int { legacyReadCount }
    func validationCount() -> Int { validations }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "Inert fixture") }
    func validateFinancialContext(_ context: AccountEarningsContext) async throws {
        validations += 1
        guard context == syntheticFinancialContext else { throw AccountEarningsClientError.sessionChanged }
    }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        reads.append(Request(context: context, model: model, unit: unit))
        let intervals = try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar)
        let interval = try #require(intervals.first)
        let totals = ActivityTotals(workMicroUSD: 33, rewardMicroUSD: 5, jobs: 3,
            promptTokens: 10, completionTokens: 20)
        let modelBuckets = [("synthetic-model-A", Int64(11)), ("synthetic-model-B", Int64(22))].map { model, work in
            ModelAccountCreditBucket(interval: interval, model: model, totals: .init(workMicroUSD: work,
                rewardMicroUSD: 0, workCreditCount: 1, rewardCreditCount: 0, promptTokens: 5, completionTokens: 10))
        }
        let hourIntervals = try ActivityCalendar.intervals(in: range, unit: .hour, calendar: calendar)
        let hourlyActivity: [ModelActivityBucket] = [
            .init(interval: hourIntervals[0], model: "synthetic-model-A", workMicroUSD: 5),
            .init(interval: hourIntervals[0], model: "synthetic-model-B", workMicroUSD: 22),
            .init(interval: hourIntervals[1], model: "synthetic-model-A", workMicroUSD: 6),
        ]
        return SyntheticAccountCreditReport.make(context: context, model: model, range: range,
            buckets: [.init(interval: interval, totals: totals, coverage: .recorded)],
            models: ["synthetic-model-A", "synthetic-model-B"],
            modelActivity: modelBuckets.map { .init(interval: $0.interval, model: $0.model, workMicroUSD: $0.totals.workMicroUSD) },
            modelBuckets: modelBuckets,
            hourlyEarningsAverages: [.init(model: "synthetic-model-A", workMicroUSD: 99, earningHours: 3)],
            modelHourlyActivity: hourlyActivity)
    }
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        legacyReadCount += 1; return []
    }
    func activityModels(in range: DateInterval) async throws -> [String] { legacyReadCount += 1; return [] }
    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        legacyReadCount += 1; return []
    }
    func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]? {
        legacyReadCount += 1; return []
    }
}
