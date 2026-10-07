import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Overview earnings", .serialized)
@MainActor
struct OverviewEarningsViewTests {
    @Test("a completed Overview query reads exactly one unfiltered scoped report")
    func completedReadUsesAtomicReport() async throws {
        let client = OverviewCompletedReadClient()
        let store = MonitorStore(service: TelemetryService(source: OverviewUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: client)
        _ = await store.synchronizeFinancialSession()
        store.setDashboardVisible(true)
        let host = NSHostingController(rootView: OverviewEarningsView(store: store))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 350))
        window.orderBack(nil)
        defer { store.setDashboardVisible(false); window.close() }
        for _ in 0..<40 {
            if await client.reportReadCount() == 1 { break }
            try await Task.sleep(for: .milliseconds(25))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await client.reportReadCount() == 1)
        #expect(await client.legacyReadCount() == 0)
        #expect(await client.allRequestsUnfiltered())
        #expect(await client.lastContext() == store.financialContext)
    }

    @Test("Overview reads only visible local history, ignores telemetry ticks and cancels on hiding")
    func visibleReadLifecycle() async throws {
        let client = OverviewHeldReadClient()
        let store = MonitorStore(service: TelemetryService(source: OverviewUnusedSource()),
            initial: .unavailable(now: Date()), earningsClient: client)
        let host = NSHostingController(rootView: OverviewEarningsView(store: store))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 350))
        window.orderBack(nil)
        defer {
            store.setDashboardVisible(false)
            window.close()
        }
        try await Task.sleep(for: .milliseconds(200))
        #expect(await client.counts().started == 0)

        store.setDashboardVisible(true)
        try await waitForReads(client, started: 1, cancelled: 0)
        await store.accept(.unavailable(now: Date()))
        try await Task.sleep(for: .milliseconds(200))
        #expect(await client.counts().started == 1)

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
        #expect(await client.counts().otherReads == 0)
    }

    private func waitForReads(_ client: OverviewHeldReadClient, started: Int, cancelled: Int) async throws {
        for _ in 0..<80 {
            let counts = await client.counts()
            if counts.started == started, counts.cancelled == cancelled { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        let counts = await client.counts()
        #expect(counts.started == started)
        #expect(counts.cancelled == cancelled)
    }
}

private actor OverviewHeldReadClient: SyntheticAuthenticatedEarningsFixture {
    private var started = 0
    private var cancelled = 0
    private var otherReads = 0
    func counts() -> (started: Int, cancelled: Int, otherReads: Int) { (started, cancelled, otherReads) }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "Inert fixture") }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        try await validateFinancialContext(context)
        started += 1
        do { try await Task.sleep(for: .seconds(30)) }
        catch { cancelled += 1; throw error }
        try await validateFinancialContext(context)
        return SyntheticAccountCreditReport.make(context: context, providerID: providerID, model: model, range: range)
    }
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        otherReads += 1
        return []
    }
    func activityModels(in range: DateInterval) async throws -> [String] { otherReads += 1; return [] }
    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        otherReads += 1
        return []
    }
}

private struct OverviewUnusedSource: TelemetrySource {
    struct Unused: Error {}
    func readDaemonState() async throws -> DaemonState { throw Unused() }
    func readLoadedModels() async throws -> LoadedModelsState { throw Unused() }
    func readStatus() async throws -> StatusSnapshot { throw Unused() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw Unused() }
}

private actor OverviewCompletedReadClient: SyntheticAuthenticatedEarningsFixture {
    private var reports = 0
    private var legacyReads = 0
    private var unfiltered = true
    private var context: AccountEarningsContext?
    func reportReadCount() -> Int { reports }
    func legacyReadCount() -> Int { legacyReads }
    func allRequestsUnfiltered() -> Bool { unfiltered }
    func lastContext() -> AccountEarningsContext? { context }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "Inert fixture") }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        reports += 1
        unfiltered = unfiltered && model == nil && providerID == nil && unit == .hour
        self.context = context
        let intervals = try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar)
        let interval = try #require(intervals.first)
        return SyntheticAccountCreditReport.make(context: context, range: range,
            buckets: [.init(interval: interval,
                totals: .init(workMicroUSD: -10, rewardMicroUSD: 2, jobs: 1, promptTokens: 0, completionTokens: 0),
                coverage: .recorded)])
    }
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        legacyReads += 1; return []
    }
    func activityModels(in range: DateInterval) async throws -> [String] { legacyReads += 1; return [] }
    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        legacyReads += 1; return []
    }
}
