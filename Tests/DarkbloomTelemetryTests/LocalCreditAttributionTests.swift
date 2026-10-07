import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Local provider credit attribution")
@MainActor
struct LocalCreditAttributionTests {
    private var date: Date {
        Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_780_000_000)).addingTimeInterval(7_200)
    }

    @Test("account credits stay gross-only even with a matching model or a single provider ID", arguments: [false, true])
    func accountReportDoesNotAuthorizeLocalProfit(hasProviderID: Bool) async throws {
        let backend = LocalCreditBackend(date: date, accountProviderID: hasProviderID ? "local-looking-provider" : nil)
        let client = UnqualifiedAccountCreditClient(backend: backend)
        try await withStore(client) { store in
            await store.refreshEarnings()
            let context = try #require(store.financialContext)
            #expect(store.financialLedgerReady)
            #expect(store.earnings == .available(microUSD: 1_000_000))
            #expect(await backend.accountReportReads == 0)

            // A caller's filter is a request, not authenticated local identity.
            let filtered = try await client.financialReport(context: context,
                providerID: "local-looking-provider", model: "matching-local-model",
                in: hour(), unit: .hour, calendar: .current)
            #expect(filtered?.totals?.workMicroUSD == 1_000_000)
            #expect(filtered?.models == ["matching-local-model"])
            let gross = try await ActivityReadSnapshot.fetch(query: query(store, metric: .earnings), store: store)
            #expect(gross?.buckets.first?.totals?.workMicroUSD == 1_000_000)
            #expect(gross?.modelWorkByBucket.values.first?["matching-local-model"] == 1_000_000)
            let readsBeforeLocalCalculations = await backend.accountReportReads

            #expect(try await client.localProviderFinancialReport(context: context,
                in: hour(), unit: .hour, calendar: .current) == nil)
            #expect(try await store.localProviderFinancialReport(context: context,
                in: hour(), unit: .hour, calendar: .current) == nil)
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            await store.refreshModelServingProfitability()
            let profit = try await ActivityReadSnapshot.fetch(query: query(store, metric: .estimatedProfit),
                store: store, powerIntervals: energy().intervals)
            #expect(profit == nil)
            assertNoLocalProfit(store)
            #expect(store.earnings == .available(microUSD: 1_000_000))
            #expect(await backend.accountReportReads == readsBeforeLocalCalculations)
        }
    }

    @Test("an explicitly typed local report is accepted for its authenticated account")
    func qualifiedLocalReportFeedsLocalReaders() async throws {
        let backend = LocalCreditBackend(date: date)
        let client = QualifiedLocalCreditClient(backend: backend)
        try await withStore(client) { store in
            await store.refreshEarnings()
            let context = try #require(store.financialContext)
            let report = try #require(try await store.localProviderFinancialReport(context: context,
                in: hour(), unit: .hour, calendar: .current))
            #expect(report.accountScope == context.accountScope)
            #expect(report.totals?.workMicroUSD == 1_000_000)
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            #expect(store.energyEarnings?.earningsUSD == 1)
            #expect(store.modelServingProfitAverages.first?.model == "matching-local-model")
            #expect(store.profitSwitchEvidenceCapturedAt == date)
            let snapshot = try #require(try await ActivityReadSnapshot.fetch(
                query: query(store, metric: .estimatedProfit), store: store, powerIntervals: energy().intervals))
            #expect(snapshot.modelHourlyProfits.first?.grossUSD == 1)
            #expect(!snapshot.modelHourlyProfitAverages.isEmpty)
            #expect(await backend.localReportReads > 0)
            #expect(await backend.accountReportReads == 0)
        }
    }

    @Test("a typed local response for another account is rejected")
    func qualifiedReportStillRequiresMatchingAccount() async throws {
        let backend = LocalCreditBackend(date: date)
        let client = QualifiedLocalCreditClient(backend: backend)
        await backend.setWrongLocalScope(true)
        try await withStore(client) { store in
            _ = await store.synchronizeFinancialSession()
            let context = try #require(store.financialContext)
            await #expect(throws: AccountEarningsClientError.sessionChanged) {
                try await store.localProviderFinancialReport(context: context,
                    in: hour(), unit: .hour, calendar: .current)
            }
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            assertNoLocalProfit(store)
            #expect(store.earnings == .available(microUSD: 1_000_000))
            #expect(await backend.accountReportReads == 0)
        }
    }

    @Test("removing verified local attribution clears published profit within the same account")
    func localAttributionRemovalClearsPriorPublication() async throws {
        let backend = LocalCreditBackend(date: date)
        let client = QualifiedLocalCreditClient(backend: backend)
        try await withStore(client) { store in
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            let context = try #require(store.financialContext)
            let epoch = store.financialSessionEpoch
            #expect(store.energyEarnings != nil && !store.modelServingProfitAverages.isEmpty)
            #expect(store.profitSwitchEvidenceCapturedAt == date)

            await backend.removeLocalAttribution()
            _ = await store.synchronizeFinancialSession()
            #expect(store.financialContext == context && store.financialLedgerReady)
            #expect(store.financialSessionEpoch != epoch)
            assertNoLocalProfit(store)

            // Refreshing valid account money cannot resurrect the earlier local
            // energy cache or restore its authorization for automatic switching.
            await store.refreshEarnings()
            await store.updateEnergyEarnings(using: energy(), enabled: true, at: date)
            let gross = try await ActivityReadSnapshot.fetch(query: query(store, metric: .earnings), store: store)
            #expect(gross?.buckets.first?.totals?.workMicroUSD == 1_000_000)
            #expect(store.earnings == .available(microUSD: 1_000_000))
            #expect(try await ActivityReadSnapshot.fetch(query: query(store, metric: .estimatedProfit),
                store: store, powerIntervals: energy().intervals) == nil)
            assertNoLocalProfit(store)
        }
    }

    @Test("held local success or transport error cannot cross revocation or ledger readiness boundaries",
        arguments: LocalCreditBoundary.allCases, [false, true])
    func heldLocalReportRejectsObsoleteSession(boundary: LocalCreditBoundary, fails: Bool) async throws {
        let backend = LocalCreditBackend(date: date)
        let client = QualifiedLocalCreditClient(backend: backend)
        let hold = LocalCreditHold()
        try await withStore(client) { store in
            _ = await store.synchronizeFinancialSession()
            let context = try #require(store.financialContext)
            let epoch = store.financialSessionEpoch
            await backend.holdNextLocalReport(hold, fails: fails)
            let pending = Task {
                try await store.localProviderFinancialReport(context: context,
                    in: hour(), unit: .hour, calendar: .current)
            }
            do {
                try await waitUntil { await hold.entered }
                switch boundary {
                case .revocation:
                    await backend.revoke()
                    _ = await store.synchronizeFinancialSession()
                    #expect(store.financialContext == nil)
                case .readinessLoss, .readinessRestoration:
                    await backend.setLedgerReady(false)
                    _ = await store.synchronizeFinancialSession()
                    #expect(store.financialContext == context && !store.financialLedgerReady)
                    if boundary == .readinessRestoration {
                        await backend.setLedgerReady(true)
                        _ = await store.synchronizeFinancialSession()
                        #expect(store.financialContext == context && store.financialLedgerReady)
                    }
                }
                #expect(store.financialSessionEpoch != epoch)
                await hold.release()
                await #expect(throws: AccountEarningsClientError.sessionChanged) { try await pending.value }
                assertNoLocalProfit(store)
                #expect(await backend.localReportReads == 1)
                #expect(await backend.accountReportReads == 0)
            } catch {
                await hold.release()
                _ = await pending.result
                throw error
            }
        }
    }

    @Test("an attribution revision notifies automatic switching to discard copied financial evidence")
    func attributionRevisionInvalidatesAttachedSwitchStore() async throws {
        let backend = LocalCreditBackend(date: date)
        let client = QualifiedLocalCreditClient(backend: backend)
        let suite = "LocalCreditSwitchWiring-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "profitSwitch.enabled")
        let control = ProviderControlStore(controller: LocalCreditUnusedController())
        let profitSwitch = ProfitSwitchStore(control: control, defaults: defaults)
        do {
            try await withStore(client) { store in
                await store.refreshEarnings()
                #expect(!store.modelServingProfitAverages.isEmpty)
                store.profitSwitch = profitSwitch
                #expect(profitSwitch.status == "Waiting for fresh model and profit evidence.")
                let context = store.financialContext
                await backend.removeLocalAttribution()
                _ = await store.synchronizeFinancialSession()
                #expect(store.financialContext == context && store.financialLedgerReady)
                assertNoLocalProfit(store)
                #expect(profitSwitch.status == "Waiting for verified local profit evidence.")
                #expect(profitSwitch.lastAttempt == nil && !profitSwitch.hasPendingEvaluation)
            }
        } catch {
            await profitSwitch.stop()
            await control.cancelCurrentOperationAndWait()
            throw error
        }
        await profitSwitch.stop()
        await control.cancelCurrentOperationAndWait()
    }

    private func assertNoLocalProfit(_ store: MonitorStore) {
        #expect(store.energyEarnings == nil)
        #expect(store.modelServingProfitAverages.isEmpty)
        #expect(store.modelServingProfitCapturedAt == nil)
        #expect(store.profitSwitchEvidenceCapturedAt == nil)
    }

    private func query(_ store: MonitorStore, metric: ActivityChartMetric) -> ActivityQuery {
        ActivityQuery(period: .today, selectedDate: date, endDate: date, now: date, calendar: .current,
            model: nil, revision: store.activityRevision, refreshID: 0, metric: metric,
            context: store.financialContext, ledgerReady: store.financialLedgerReady,
            sessionEpoch: store.financialSessionEpoch)
    }

    private func withStore(_ client: any AccountEarningsFetching,
        operation: (MonitorStore) async throws -> Void) async throws {
        let suite = "LocalCreditAttribution-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "electricity.enabled")
        defaults.set("0.2", forKey: "electricity.usdPerKWh")
        let instant = date
        let store = MonitorStore(service: TelemetryService(source: LocalCreditUnusedSource()),
            initial: .unavailable(now: instant), initialEnergy: energy(), earningsClient: client,
            now: { instant }, energyPreferences: defaults)
        do { try await operation(store) }
        catch { await store.stop(); throw error }
        await store.stop()
    }

    private func waitUntil(_ condition: () async -> Bool) async throws {
        for _ in 0..<100 {
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        throw LocalCreditFixtureError.timeout
    }

    private func hour() -> DateInterval { DateInterval(start: date.addingTimeInterval(-3_600), duration: 3_600) }
    private func energy() -> EnergyRecordingSnapshot {
        let intervals: [EnergyInterval] = (0..<360).map { index in
            let start = hour().start.addingTimeInterval(Double(index) * 10)
            let busy = index >= 180
            return EnergyInterval(start: start, end: start.addingTimeInterval(10),
                kWh: busy ? 0.0002 : 0.0001, usdPerKWh: 0.2, source: "inert-local-credit-fixture",
                estimated: false, activeModelID: "matching-local-model", inferenceActive: busy)
        }
        return EnergyRecordingSnapshot(reading: .init(date: date, watts: 24,
            source: "inert-local-credit-fixture", estimated: false), intervals: intervals, issue: nil)
    }
}

// This conformance deliberately inherits the production protocol's nil local
// report. It must never adopt SyntheticAuthenticatedEarningsFixture.
private struct UnqualifiedAccountCreditClient: AccountEarningsFetching {
    let backend: LocalCreditBackend
    func financialSessionState() async -> AccountEarningsSessionState { await backend.snapshot() }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .available(microUSD: 1_000_000) }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        await backend.accountReport(context: context, providerID: providerID, model: model, range: range)
    }
}

private struct QualifiedLocalCreditClient: AccountEarningsFetching {
    let backend: LocalCreditBackend
    func financialSessionState() async -> AccountEarningsSessionState { await backend.snapshot() }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .available(microUSD: 1_000_000) }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        await backend.accountReport(context: context, providerID: providerID, model: model, range: range)
    }
    func localProviderFinancialReport(context: AccountEarningsContext, in range: DateInterval,
        unit: ActivityCalendarUnit, calendar: Calendar) async throws -> LocalProviderCreditReport? {
        try await backend.localReport(context: context, range: range)
    }
}

private actor LocalCreditBackend {
    private let date: Date
    private let accountProviderID: String?
    private var state = AccountEarningsSessionState(context: .init(accountScope: "inert-attribution-account",
        generation: UUID()), ledgerReady: true, revision: UUID())
    private var wrongLocalScope = false
    private var localAttributionEnabled = true
    private var nextLocalHold: (LocalCreditHold, Bool)?
    private(set) var accountReportReads = 0
    private(set) var localReportReads = 0

    init(date: Date, accountProviderID: String? = nil) {
        self.date = date
        self.accountProviderID = accountProviderID
    }
    func snapshot() -> AccountEarningsSessionState { state }
    func revoke() { state = .init(context: nil, ledgerReady: false, revision: UUID()) }
    func setLedgerReady(_ ready: Bool) { state = .init(context: state.context, ledgerReady: ready, revision: UUID()) }
    func setWrongLocalScope(_ wrong: Bool) { wrongLocalScope = wrong }
    func removeLocalAttribution() {
        localAttributionEnabled = false
        state = .init(context: state.context, ledgerReady: state.ledgerReady, revision: UUID())
    }
    func holdNextLocalReport(_ hold: LocalCreditHold, fails: Bool) { nextLocalHold = (hold, fails) }

    func accountReport(context: AccountEarningsContext, providerID: String?, model: String?,
        range: DateInterval) -> AccountCreditReport {
        accountReportReads += 1
        return makeReport(context: context, providerID: providerID ?? accountProviderID, model: model, range: range)
    }

    func localReport(context: AccountEarningsContext, range: DateInterval) async throws -> LocalProviderCreditReport? {
        localReportReads += 1
        guard localAttributionEnabled else { return nil }
        let returnedContext = wrongLocalScope
            ? AccountEarningsContext(accountScope: "inert-other-account", generation: context.generation) : context
        let report = LocalProviderCreditReport(report: makeReport(context: returnedContext,
            providerID: "fixture-proven-local-provider", model: nil, range: range))
        let held = nextLocalHold
        nextLocalHold = nil
        if let held {
            await held.0.hold()
            if held.1 { throw LocalCreditFixtureError.transport }
        }
        return report
    }

    private func makeReport(context: AccountEarningsContext, providerID: String?, model: String?,
        range: DateInterval) -> AccountCreditReport {
        let interval = DateInterval(start: date.addingTimeInterval(-3_600), duration: 3_600)
        let totals = ActivityTotals(workMicroUSD: 1_000_000, rewardMicroUSD: 0, jobs: 1,
            promptTokens: 10, completionTokens: 20)
        let modelActivity = ModelActivityBucket(interval: interval, model: "matching-local-model", workMicroUSD: 1_000_000)
        return SyntheticAccountCreditReport.make(context: context, providerID: providerID, model: model,
            range: range, buckets: [.init(interval: interval, totals: totals, coverage: .recorded)],
            models: ["matching-local-model"], modelActivity: [modelActivity],
            modelBuckets: [.init(interval: interval, model: "matching-local-model", totals: SyntheticAccountCreditReport.totals(totals))],
            modelHourlyActivity: [modelActivity])
    }
}

enum LocalCreditBoundary: CaseIterable, Sendable {
    case revocation, readinessLoss, readinessRestoration
}

/// A failed assertion cannot leave a suspended fixture indefinitely.
private actor LocalCreditHold {
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

private enum LocalCreditFixtureError: Error { case transport, timeout }
private struct LocalCreditUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw LocalCreditFixtureError.transport }
    func readLoadedModels() async throws -> LoadedModelsState { throw LocalCreditFixtureError.transport }
    func readStatus() async throws -> StatusSnapshot { throw LocalCreditFixtureError.transport }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}

private struct LocalCreditUnusedController: ProviderControlling {
    func refresh() async throws -> ProviderControlSnapshot { throw LocalCreditFixtureError.transport }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw LocalCreditFixtureError.transport }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {
        throw LocalCreditFixtureError.transport
    }
    func delete(_ localModelID: String) async throws { throw LocalCreditFixtureError.transport }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        throw LocalCreditFixtureError.transport
    }
    func performSingleModelSwitch(modelID: String, onPhase: ProviderMutationPhaseObserver?) async throws -> ProviderMutationCompletion {
        throw LocalCreditFixtureError.transport
    }
}
