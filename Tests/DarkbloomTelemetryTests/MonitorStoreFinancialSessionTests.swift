import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Monitor financial session boundaries")
@MainActor
struct MonitorStoreFinancialSessionTests {
    private var date: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000)).addingTimeInterval(7_200)
    }

    @Test("the session observer starts at initialization and does not retain the store")
    func observerHasWeakStoreLifetime() async throws {
        let client = FinancialSessionFixture(date: date)
        let instant = date
        var store: MonitorStore? = MonitorStore(service: TelemetryService(source: FinancialSessionUnusedSource()),
            initial: .unavailable(now: instant), earningsClient: client, now: { instant })
        let reference = FinancialWeakStore(store)
        try await waitUntil { await client.observerCount > 0 }
        store = nil
        do { try await waitUntil { reference.value == nil } }
        catch { await reference.value?.stop(); throw error }
        #expect(reference.value == nil)
        await client.revoke()
        try await waitUntil { await client.observerCount == 0 }
    }

    @Test("A to B to A uses distinct generations and never revives the first A cache")
    func returningAccountNeedsNewGeneration() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            await store.refreshEarnings()
            let original = try #require(store.financialContext)
            #expect(store.earnings == .available(microUSD: 1_000_000))
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            assertCleared(store)
            await store.refreshEarnings()
            #expect(store.earnings == .available(microUSD: 2_000_000))
            await client.changeAccount("A")
            _ = await store.synchronizeFinancialSession()
            let returned = try #require(store.financialContext)
            #expect(returned.accountScope == original.accountScope && returned.generation != original.generation)
            assertCleared(store)
            await store.refreshEarnings()
            #expect(store.financialContext == returned && store.earnings == .available(microUSD: 1_000_000))
        }
    }

    @Test("revocation events clear populated financial values without another earnings refresh")
    func revocationClearsWithoutRefresh() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            try await waitUntil { await client.observerCount > 0 }
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.todayEarnings != nil && store.weekEarnings != nil)
            #expect(store.earningsPerHourUSD != nil)
            #expect(!store.modelEarnings.isEmpty && !store.modelWorkEarnings.isEmpty)
            #expect(!store.modelServingProfitAverages.isEmpty && store.energyEarnings != nil)
            let calls = await client.fetchCalls
            await client.revoke()
            try await waitUntil { store.financialContext == nil }
            #expect(!store.financialLedgerReady)
            assertCleared(store)
            #expect(await client.fetchCalls == calls)
        }
    }

    @Test("a failed B refresh cannot retain A scalar, summary, or model values")
    func failedNewAccountDoesNotRetainOldAccount() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            await store.refreshEarnings()
            #expect(store.todayEarnings != nil && !store.modelEarnings.isEmpty)
            await client.changeAccount("B")
            await client.setFetchFailure(true)
            await store.refreshEarnings()
            #expect(store.financialContext?.accountScope == "synthetic-account-B")
            assertCleared(store)
            await client.setFetchFailure(false)
            await store.refreshEarnings()
            #expect(store.earnings == .available(microUSD: 2_000_000))
            #expect(store.todayEarnings?.microUSD == 2_000_000)
            #expect(store.modelEarnings.first?.microUSD == 2_000_000)
        }
    }

    @Test("an older held session snapshot cannot restore A after a newer synchronization publishes B")
    func outOfOrderSnapshotsKeepNewestPublishedState() async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            try await waitUntil { await client.observerCount > 0 }
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            let original = try #require(store.financialContext)
            #expect(store.earnings == .available(microUSD: 1_000_000) && store.energyEarnings != nil)
            await client.holdNextSnapshot(hold)
            let older = Task { await store.synchronizeFinancialSession() }
            try await waitUntil { await hold.entered }
            await client.changeAccount("B")
            let latest = await store.synchronizeFinancialSession()
            let current = try #require(latest.context)
            #expect(current != original && current.accountScope == "synthetic-account-B")
            #expect(store.financialContext == current)
            assertCleared(store)
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.earnings == .available(microUSD: 2_000_000) && store.energyEarnings?.earningsUSD == 2)
            let modelEarnings = store.modelEarnings
            let workEarnings = store.modelWorkEarnings
            let today = store.todayEarnings
            let week = store.weekEarnings
            let energyValue = store.energyEarnings
            await hold.release()
            let obsoleteReturn = await older.value
            #expect(obsoleteReturn.context == current && obsoleteReturn.ledgerReady)
            #expect(store.financialContext == current && store.financialLedgerReady)
            #expect(store.earnings == .available(microUSD: 2_000_000))
            #expect(store.modelEarnings == modelEarnings && store.modelWorkEarnings == workEarnings)
            #expect(store.todayEarnings == today && store.weekEarnings == week && store.energyEarnings == energyValue)
        }
    }

    @Test("loss of ledger readiness clears values even when the authenticated context is unchanged")
    func sameContextReadinessLossClearsPresentation() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            try await waitUntil { await client.observerCount > 0 }
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            let context = try #require(store.financialContext)
            #expect(store.financialLedgerReady && store.earningsPerHourUSD != nil)
            #expect(store.energyEarnings != nil && !store.modelServingProfitAverages.isEmpty)
            let calls = await client.fetchCalls
            await client.setLedgerReady(false)
            try await waitUntil { !store.financialLedgerReady }
            #expect(store.financialContext == context)
            assertCleared(store)
            #expect(await client.fetchCalls == calls)
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.energyEarnings == nil)
            #expect(try await store.financialReport(context: context, in: hour(), unit: .hour, calendar: .current) == nil)
            await client.setLedgerReady(true)
            _ = await store.synchronizeFinancialSession()
            #expect(store.financialLedgerReady && store.financialContext == context)
            assertCleared(store)
            await store.refreshEarnings()
            #expect(store.earnings == .available(microUSD: 1_000_000))
        }
    }

    @Test("same-context network failures retain prior evidence only as stale")
    func sameContextRetainsStaleEvidence() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            await store.refreshEarnings()
            let context = store.financialContext
            let day = store.todayEarnings
            let week = store.weekEarnings
            await client.setFetchFailure(true)
            await store.refreshEarnings()
            #expect(store.financialContext == context)
            #expect(store.earnings == .stale(microUSD: 1_000_000, reason: FinancialSessionFixtureError.transport.localizedDescription))
            #expect(store.todayEarnings == day && store.weekEarnings == week)
            #expect(store.displayedTodayEarnings?.isRetained == true && store.displayedWeekEarnings?.isRetained == true)
            #expect(store.currentTodayEarnings == nil && store.currentWeekEarnings == nil)
            #expect(store.earningsPerHourUSD == nil && store.profitSwitchEvidenceCapturedAt == nil)
        }
    }

    @Test("a held same-context failure cannot restore values after ledger readiness is lost", arguments: [false, true])
    func heldFailureCannotRestoreUnreadyLedger(restoresReady: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            let context = try #require(store.financialContext)
            #expect(store.todayEarnings != nil && store.energyEarnings != nil)
            await client.holdNextFetch(hold, fails: true)
            let pending = Task { await store.refreshEarnings() }
            try await waitUntil { await hold.entered }
            await client.setLedgerReady(false)
            _ = await store.synchronizeFinancialSession()
            #expect(store.financialContext == context && !store.financialLedgerReady)
            assertCleared(store)
            if restoresReady {
                await client.setLedgerReady(true)
                _ = await store.synchronizeFinancialSession()
                #expect(store.financialContext == context && store.financialLedgerReady)
                assertCleared(store)
            }
            await hold.release()
            await pending.value
            #expect(store.financialContext == context && store.financialLedgerReady == restoresReady)
            assertCleared(store)
        }
    }

    @Test("older same-context profit success or error cannot relabel or clear newer profit", arguments: [false, true])
    func newerProfitSurvivesOldReport(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        let clock = FinancialSessionClock(date)
        try await withStore(client, clock: clock) { store in
            await store.refreshEarnings()
            let originalProfit = store.modelServingProfitAverages
            let context = store.financialContext
            #expect(!originalProfit.isEmpty && store.modelServingProfitCapturedAt == date)
            await client.holdNextReport(hold, fails: fails)
            let pending = Task { await store.refreshModelServingProfitability() }
            try await waitUntil { await hold.entered }
            await client.setAmount(3_000_000)
            clock.advance(10)
            await store.refreshEarnings()
            let newerProfit = store.modelServingProfitAverages
            let newerCapture = store.modelServingProfitCapturedAt
            #expect(store.financialContext == context && store.earnings == .available(microUSD: 3_000_000))
            #expect(!newerProfit.isEmpty && newerProfit != originalProfit)
            #expect(newerCapture == clock.now && newerCapture != date)
            #expect(store.profitSwitchEvidenceCapturedAt == newerCapture)
            await hold.release()
            await pending.value
            #expect(store.modelServingProfitAverages == newerProfit)
            #expect(store.modelServingProfitCapturedAt == newerCapture)
            #expect(store.profitSwitchEvidenceCapturedAt == newerCapture)
        }
    }

    @Test("older same-context energy success or error cannot clear or replace a newer energy result", arguments: [false, true])
    func newerEnergySurvivesOldReport(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        let clock = FinancialSessionClock(date)
        try await withStore(client, clock: clock) { store in
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.energyEarnings?.earningsUSD == 1)
            // A completed refresh invalidates the cached hourly report, so the
            // next energy read can be suspended independently of its caller.
            await store.refreshEarnings()
            await client.holdNextReport(hold, fails: fails)
            let pending = Task { await store.updateEnergyEarnings(using: energy(), enabled: true, at: date) }
            try await waitUntil { await hold.entered }
            await client.setAmount(3_000_000)
            clock.advance(10)
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: clock.now)
            let newerEnergy = store.energyEarnings
            let newerProfit = store.modelServingProfitAverages
            let newerCapture = store.modelServingProfitCapturedAt
            #expect(newerEnergy?.earningsUSD == 3 && newerCapture == clock.now)
            await hold.release()
            await pending.value
            #expect(store.energyEarnings == newerEnergy)
            #expect(store.modelServingProfitAverages == newerProfit && store.modelServingProfitCapturedAt == newerCapture)
        }
    }

    @Test("persisted journal rows remain replayable but cannot reappear in another account's visible history")
    func recommendationHistoryStaysInAcceptedSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("FinancialJournal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RecommendationJournal(url: directory.appendingPathComponent("recommendations.sqlite3"), limit: 10)
        let client = FinancialSessionFixture(date: date)
        let clock = FinancialSessionClock(date)
        try await withStore(client, clock: clock, journal: journal) { store in
            await store.refreshEarnings()
            await store.refreshRecommendation()
            let original = try #require(store.recommendationDecision)
            #expect(store.recommendationHistory.map(\.id) == [original.id])
            #expect(try await journal.recent(limit: 10).contains { $0.storedDecision.id == original.id })
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            #expect(store.recommendationDecision == nil && store.recommendationHistory.isEmpty)
            clock.advance(10)
            await store.refreshEarnings()
            await store.refreshRecommendation()
            let current = try #require(store.recommendationDecision)
            #expect(current.id != original.id)
            #expect(store.recommendationHistory.map(\.id) == [current.id])
            #expect(!store.recommendationHistory.contains { $0.id == original.id })
            #expect(try await journal.recent(limit: 10).contains { $0.storedDecision.id == original.id })
        }
    }

    @Test("held obsolete success and transport failure cannot publish or retain A", arguments: [false, true])
    func heldFetchCannotPublishAcrossAccountChange(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            await store.refreshEarnings()
            await client.holdNextFetch(hold, fails: fails)
            let pending = Task { await store.refreshEarnings() }
            try await waitUntil { await hold.entered }
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            await hold.release()
            await pending.value
            assertCleared(store)
            #expect(store.financialContext?.accountScope == "synthetic-account-B")
            await store.refreshEarnings()
            #expect(store.earnings == .available(microUSD: 2_000_000))
        }
    }

    @Test("a held summary cannot mix old account data into a newer context", arguments: [false, true])
    func heldSummaryCannotPublishAcrossAccountChange(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            await client.holdNextDay(hold, fails: fails)
            let pending = Task { await store.refreshEarnings() }
            try await waitUntil { await hold.entered }
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            await hold.release()
            await pending.value
            assertCleared(store)
            #expect(store.financialContext?.accountScope == "synthetic-account-B")
        }
    }

    @Test("coalesced held refresh callers both reject an obsolete A acquisition")
    func coalescedCallersRejectObsoleteResult() async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            _ = await store.synchronizeFinancialSession()
            await client.holdNextFetch(hold, fails: false)
            let first = Task { await store.refreshEarnings() }
            try await waitUntil { await hold.entered }
            let second = Task { await store.refreshEarnings() }
            try await waitUntil { store.earningsRefreshWaiterCount == 1 }
            #expect(await client.fetchCalls == 1)
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            await hold.release()
            await first.value
            await second.value
            #expect(await client.fetchCalls == 1)
            assertCleared(store)
        }
    }

    @Test("a B refresh drains obsolete A acquisition and then acquires B", arguments: [false, true])
    func changedAccountRefreshAcquiresCurrentAccount(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            _ = await store.synchronizeFinancialSession()
            await client.holdNextFetch(hold, fails: fails)
            let first = Task { await store.refreshEarnings() }
            try await waitUntil { await hold.entered }
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            let second = Task { await store.refreshEarnings() }
            try await waitUntil { store.earningsRefreshWaiterCount == 1 }
            #expect(await client.fetchCalls == 1)
            assertCleared(store)
            await hold.release()
            await first.value
            await second.value
            #expect(await client.fetchCalls == 2)
            #expect(store.financialContext?.accountScope == "synthetic-account-B")
            #expect(store.earnings == .available(microUSD: 2_000_000))
            #expect(store.todayEarnings?.microUSD == 2_000_000)
        }
    }

    @Test("held reports reject a lost and restored ledger in the same account", arguments: [false, true])
    func reportCannotEscapeAcrossReadinessRestoration(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            await store.refreshEarnings()
            let context = try #require(store.financialContext)
            let epoch = store.financialSessionEpoch
            await client.holdNextReport(hold, fails: fails)
            let pending = Task {
                try await store.financialReport(context: context, in: hour(), unit: .hour, calendar: .current)
            }
            try await waitUntil { await hold.entered }
            await client.setLedgerReady(false)
            _ = await store.synchronizeFinancialSession()
            await client.setLedgerReady(true)
            _ = await store.synchronizeFinancialSession()
            #expect(store.financialContext == context && store.financialLedgerReady)
            #expect(store.financialSessionEpoch > epoch)
            assertCleared(store)
            await hold.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await pending.value }
            assertCleared(store)
        }
    }

    @Test("a buffered readiness cycle invalidates values and held reports by revision alone", arguments: [false, true])
    func bufferedReadinessCycleInvalidatesEpoch(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            await store.refreshEarnings()
            let context = try #require(store.financialContext)
            let epoch = store.financialSessionEpoch
            await client.holdNextReport(hold, fails: fails)
            let pending = Task {
                try await store.financialReport(context: context, in: hour(), unit: .hour, calendar: .current)
            }
            try await waitUntil { await hold.entered }
            // The fixture emits only the restored state; the store never sees false.
            await client.cycleReadinessWithoutIntermediatePublication()
            _ = await store.synchronizeFinancialSession()
            #expect(store.financialContext == context && store.financialLedgerReady)
            #expect(store.financialSessionEpoch > epoch)
            assertCleared(store)
            await hold.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await pending.value }
            assertCleared(store)
        }
    }

    @Test("reports reject obsolete explicit context and mismatched returned account scope")
    func explicitReportContextAndScope() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            let original = try #require((await store.synchronizeFinancialSession()).context)
            await client.changeAccount("B")
            let before = await client.reportCalls
            await #expect(throws: AccountEarningsClientError.sessionChanged) {
                try await store.financialReport(context: original, in: hour(), unit: .hour, calendar: .current)
            }
            #expect(await client.reportCalls == before)
            let current = try #require((await store.synchronizeFinancialSession()).context)
            await client.setWrongReportScope(true)
            await #expect(throws: AccountEarningsClientError.sessionChanged) {
                try await store.financialReport(context: current, in: hour(), unit: .hour, calendar: .current)
            }
        }
    }

    @Test("an in-flight report success or error cannot escape after context revocation", arguments: [false, true])
    func heldReportCannotEscapeAfterRevocation(fails: Bool) async throws {
        let client = FinancialSessionFixture(date: date)
        let hold = FinancialSessionHold()
        try await withStore(client) { store in
            let context = try #require((await store.synchronizeFinancialSession()).context)
            await client.holdNextReport(hold, fails: fails)
            let pending = Task {
                try await store.financialReport(context: context, in: hour(), unit: .hour, calendar: .current)
            }
            try await waitUntil { await hold.entered }
            await client.revoke()
            _ = await store.synchronizeFinancialSession()
            await hold.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await pending.value }
            assertCleared(store)
        }
    }

    @Test("energy cache keys separate generations and reject held old-account energy reads")
    func energyCacheIsContextBound() async throws {
        let client = FinancialSessionFixture(date: date)
        try await withStore(client) { store in
            _ = await store.synchronizeFinancialSession()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.energyEarnings?.earningsUSD == 1)
            let firstReads = await client.reportCalls
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(await client.reportCalls == firstReads)
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            #expect(store.energyEarnings == nil)
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.energyEarnings?.earningsUSD == 2)
            #expect(await client.reportCalls == firstReads + 1)
            await client.changeAccount("A")
            _ = await store.synchronizeFinancialSession()
            let hold = FinancialSessionHold()
            await client.holdNextReport(hold, fails: false)
            let pending = Task { await store.updateEnergyEarnings(using: energy(), enabled: true, at: date) }
            try await waitUntil { await hold.entered }
            await client.changeAccount("B")
            _ = await store.synchronizeFinancialSession()
            await hold.release()
            await pending.value
            #expect(store.energyEarnings == nil)
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.energyEarnings?.earningsUSD == 2)
        }
    }

    private func assertCleared(_ store: MonitorStore) {
        if case .unavailable = store.earnings {} else { Issue.record("obsolete earnings remained visible") }
        #expect(store.todayEarnings == nil && store.weekEarnings == nil && store.jobSummary.value == nil)
        #expect(store.modelEarnings.isEmpty && store.modelWorkEarnings.isEmpty)
        #expect(store.modelServingProfitAverages.isEmpty && store.modelServingProfitCapturedAt == nil)
        #expect(store.energyEarnings == nil && store.earningsPerHourUSD == nil)
        #expect(store.profitSwitchEvidenceCapturedAt == nil)
    }

    private func withStore(_ client: FinancialSessionFixture, clock: FinancialSessionClock? = nil,
        journal: RecommendationJournal? = nil,
        operation: (MonitorStore) async throws -> Void) async throws {
        let suite = "FinancialSession-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "electricity.enabled")
        defaults.set("0.2", forKey: "electricity.usdPerKWh")
        let instant = date
        let sessionClock = clock ?? FinancialSessionClock(instant)
        let store = MonitorStore(service: TelemetryService(source: FinancialSessionUnusedSource()),
            initial: .unavailable(now: instant), initialEnergy: energy(), earningsClient: client,
            recommendationJournal: journal, now: { sessionClock.now }, energyPreferences: defaults)
        do { try await operation(store) }
        catch { await store.stop(); throw error }
        await store.stop()
        try await waitUntil { await client.observerCount == 0 }
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw FinancialSessionFixtureError.timeout
    }
    private func hour() -> DateInterval { DateInterval(start: date.addingTimeInterval(-3_600), duration: 3_600) }
    private func energy() -> EnergyRecordingSnapshot {
        let interval = hour()
        let intervals: [EnergyInterval] = (0..<360).map { index -> EnergyInterval in
            let offset = Double(index) * 10
            let start = interval.start.addingTimeInterval(offset)
            let end = start.addingTimeInterval(10)
            let busy = index >= 180
            let kWh: Double = busy ? 0.0002 : 0.0001
            return EnergyInterval(start: start, end: end, kWh: kWh, usdPerKWh: 0.2,
                source: "synthetic", estimated: false, activeModelID: "synthetic-model", inferenceActive: busy)
        }
        return EnergyRecordingSnapshot(reading: .init(date: date, watts: 24, source: "synthetic", estimated: false),
            intervals: intervals, issue: nil)
    }
}

/// Deliberately returns captured obsolete results after suspension. The store,
/// rather than a cooperative mock, must enforce final publication boundaries.
private actor FinancialSessionFixture: AccountEarningsFetching {
    private let date: Date
    private var state: AccountEarningsSessionState
    private var observers: [UUID: AsyncStream<AccountEarningsSessionState>.Continuation] = [:]
    private var fetchFailure = false
    private var wrongReportScope = false
    private var overriddenAmount: Int64?
    private var nextFetch: (FinancialSessionHold, Bool)?
    private var nextDay: (FinancialSessionHold, Bool)?
    private var nextReport: (FinancialSessionHold, Bool)?
    private var nextSnapshot: FinancialSessionHold?
    private(set) var fetchCalls = 0
    private(set) var reportCalls = 0
    var observerCount: Int { observers.count }

    init(date: Date) {
        self.date = date
        state = .init(context: .init(accountScope: "synthetic-account-A", generation: UUID()),
            ledgerReady: true, revision: UUID())
    }
    func changeAccount(_ name: String) {
        state = .init(context: .init(accountScope: "synthetic-account-\(name)", generation: UUID()),
            ledgerReady: true, revision: UUID())
        publish()
    }
    func revoke() { state = .init(context: nil, ledgerReady: false, revision: UUID()); publish() }
    func setLedgerReady(_ value: Bool) {
        state = .init(context: state.context, ledgerReady: value, revision: UUID())
        publish()
    }
    func cycleReadinessWithoutIntermediatePublication() {
        state = .init(context: state.context, ledgerReady: false, revision: UUID())
        state = .init(context: state.context, ledgerReady: true, revision: UUID())
        publish()
    }
    private func publish() { for observer in observers.values { observer.yield(state) } }
    func financialSessionState() async -> AccountEarningsSessionState {
        let captured = state
        let held = nextSnapshot
        nextSnapshot = nil
        if let held { await held.hold() }
        return captured
    }
    func financialSessionChanges() -> AsyncStream<AccountEarningsSessionState> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AccountEarningsSessionState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in Task { await self?.removeObserver(id) } }
        return stream
    }
    private func removeObserver(_ id: UUID) { observers[id] = nil }
    func validateFinancialContext(_ context: AccountEarningsContext) throws {
        try Task.checkCancellation()
        guard state.context == context else { throw AccountEarningsClientError.sessionChanged }
    }
    func setFetchFailure(_ value: Bool) { fetchFailure = value }
    func setWrongReportScope(_ value: Bool) { wrongReportScope = value }
    func setAmount(_ value: Int64) { overriddenAmount = value }
    func holdNextFetch(_ hold: FinancialSessionHold, fails: Bool) { nextFetch = (hold, fails) }
    func holdNextDay(_ hold: FinancialSessionHold, fails: Bool) { nextDay = (hold, fails) }
    func holdNextReport(_ hold: FinancialSessionHold, fails: Bool) { nextReport = (hold, fails) }
    func holdNextSnapshot(_ hold: FinancialSessionHold) { nextSnapshot = hold }
    private func amount(for context: AccountEarningsContext) -> Int64 {
        if let overriddenAmount { return overriddenAmount }
        return context.accountScope == "synthetic-account-A" ? 1_000_000 : 2_000_000
    }
    private func current() throws -> AccountEarningsContext {
        guard let context = state.context else { throw AccountEarningsClientError.missingToken }
        return context
    }
    func fetch(now: Date) async throws -> EarningsPresentationValue { try await fetchWithContext(now: now).value }
    func fetchWithContext(now: Date) async throws -> AccountEarningsFetchResult {
        fetchCalls += 1
        let context = try current()
        let value = amount(for: context)
        let held = nextFetch
        nextFetch = nil
        if let held {
            await held.0.hold()
            if held.1 { throw FinancialSessionFixtureError.transport }
        }
        if fetchFailure { throw FinancialSessionFixtureError.transport }
        return .init(context: context, value: .available(microUSD: value))
    }
    func todayEarningsSummary(now: Date, calendar: Calendar) async throws -> ObservedEarningsWindow? {
        let context = try current()
        let dayStart = calendar.startOfDay(for: date)
        let value = ObservedEarningsWindow(microUSD: amount(for: context), observedSeconds: date.timeIntervalSince(dayStart),
            calendarDayStart: dayStart, capturedAt: date, coversDayToDate: true)
        let held = nextDay
        nextDay = nil
        if let held { await held.0.hold(); if held.1 { throw FinancialSessionFixtureError.transport } }
        return value
    }
    func weekEarningsSummary(now: Date, calendar: Calendar) throws -> CalendarWeekEarningsSummary? {
        CalendarWeekEarningsSummary(microUSD: amount(for: try current()), isComplete: false,
            weekStart: calendar.dateInterval(of: .weekOfYear, for: date)?.start, capturedAt: date)
    }
    func jobCompletionSummary(now: Date, calendar: Calendar) throws -> JobCompletionSummary? {
        _ = try current()
        return .init(completedToday: 1, averagePerDay: 1, averagingDays: 1,
            dayStart: calendar.startOfDay(for: date), capturedAt: date)
    }
    func modelEarnings(since: Date) throws -> [ModelEarnings] {
        [.init(model: "synthetic-model", microUSD: amount(for: try current()), jobs: 1)]
    }
    func modelWorkEarnings(in range: DateInterval, calendar: Calendar) throws -> [ModelWorkEarnings] {
        [.init(model: "synthetic-model", queryPeriod: range, sourceCapturedAt: date,
            workMicroUSD: amount(for: try current()), jobs: 1, recordedHours: 1, unknownHours: 0, uncertainBoundaryHours: 0)]
    }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        reportCalls += 1
        let credit = amount(for: context)
        let interval = DateInterval(start: date.addingTimeInterval(-3_600), duration: 3_600)
        let totals = ActivityTotals(workMicroUSD: credit, rewardMicroUSD: 0, jobs: 1, promptTokens: 10, completionTokens: 20)
        let returnedContext = wrongReportScope
            ? AccountEarningsContext(accountScope: "synthetic-mismatched-account", generation: context.generation) : context
        let report = SyntheticAccountCreditReport.make(context: returnedContext, providerID: providerID, model: model,
            range: range, buckets: [.init(interval: interval, totals: totals, coverage: .recorded)],
            models: ["synthetic-model"], modelActivity: [.init(interval: interval, model: "synthetic-model", workMicroUSD: credit)],
            modelBuckets: [.init(interval: interval, model: "synthetic-model", totals: SyntheticAccountCreditReport.totals(totals))])
        let held = nextReport
        nextReport = nil
        if let held { await held.0.hold(); if held.1 { throw FinancialSessionFixtureError.transport } }
        return report
    }
}

/// Every hold auto-releases after thirty seconds, including a failed test path.
/// The bound accommodates the full suite's concurrent MainActor rendering.
private actor FinancialSessionHold {
    private(set) var entered = false
    private var continuation: CheckedContinuation<Void, Never>?
    private var deadline: Task<Void, Never>?
    func hold() async {
        entered = true
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            await self?.release()
        }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        deadline?.cancel()
        deadline = nil
        continuation?.resume()
        continuation = nil
    }
}
private enum FinancialSessionFixtureError: LocalizedError {
    case transport, timeout
    var errorDescription: String? {
        switch self { case .transport: "Synthetic network unavailable"; case .timeout: "Synthetic hold did not start" }
    }
}
private struct FinancialSessionUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw FinancialSessionFixtureError.transport }
    func readLoadedModels() async throws -> LoadedModelsState { throw FinancialSessionFixtureError.transport }
    func readStatus() async throws -> StatusSnapshot { throw FinancialSessionFixtureError.transport }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw FinancialSessionFixtureError.transport }
}

private final class FinancialSessionClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    var now: Date { lock.lock(); defer { lock.unlock() }; return date }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; date = date.addingTimeInterval(seconds) }
}

@MainActor
private final class FinancialWeakStore {
    weak var value: MonitorStore?
    init(_ value: MonitorStore?) { self.value = value }
}
