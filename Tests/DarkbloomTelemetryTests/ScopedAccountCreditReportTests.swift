import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Scoped account credit reports")
struct ScopedAccountCreditReportTests {
    private let start = Date(timeIntervalSince1970: 1_800_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private var range: DateInterval { DateInterval(start: start, duration: 10_800) }

    @Test func correctionsMoveExactCreditsBetweenModelsProvidersHoursAndRewards() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([credit(1, amount: 100), credit(3, amount: 300)], total: 400), capturedAt: range.end)
        let corrected = credit(1, amount: -20, provider: "provider-B", model: "base_reward", at: start.addingTimeInterval(3_600))
        try await database.ingest(page([corrected, credit(2, amount: 0), credit(3, amount: 300)], total: 280), capturedAt: range.end.addingTimeInterval(1))
        let all = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(all.reconciliation == .matched)
        #expect(all.totals?.workMicroUSD == 300 && all.totals?.rewardMicroUSD == -20)
        #expect(all.totals?.workCreditCount == 2 && all.totals?.rewardCreditCount == 1)
        #expect(all.models == ["qwen"] && all.modelActivity.count == 1)
        #expect(all.modelActivity.first?.workMicroUSD == 300)
        #expect(all.buckets[0].totals?.workCreditCount == 2)
        #expect(all.buckets[1].totals?.workCreditCount == 0 && all.buckets[1].totals?.rewardCreditCount == 1)
        #expect(all.buckets[2].totals?.workMicroUSD == 0)
        let filtered = try await database.accountCreditReport(accountID: "account-A", providerID: "provider-B", in: range, unit: .hour, calendar: calendar)
        #expect(filtered.reconciliation == .matched) // Reconciliation is account-wide.
        #expect(filtered.totals?.workCreditCount == 0 && filtered.totals?.rewardMicroUSD == -20)
        let model = try await database.accountCreditReport(accountID: "account-A", model: "qwen", in: range, unit: .hour, calendar: calendar)
        #expect(model.totals?.rewardMicroUSD == 0 && model.totals?.workMicroUSD == 300)
    }

    @Test func accountSwitchesRemainIsolatedAcrossReopen() async throws {
        let path = url()
        do {
            let database = try EarningsDatabase(url: path)
            try await database.ingest(page([credit(1, amount: 10)], total: 10), capturedAt: range.end)
            try await database.ingest(page([credit(1, amount: 50)], account: "account-B", total: 50), capturedAt: range.end)
            try await database.ingest(page([credit(1, amount: -5)], total: -5), capturedAt: range.end.addingTimeInterval(1))
        }
        let database = try EarningsDatabase(url: path)
        let a = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        let b = try await database.accountCreditReport(accountID: "account-B", in: range, unit: .hour, calendar: calendar)
        #expect(a.accountScope != b.accountScope && !a.accountScope.contains("account-A"))
        #expect(a.totals?.workMicroUSD == -5 && b.totals?.workMicroUSD == 50)
        #expect(a.observation?.balance.lifetimeMicroUSD == -5 && b.observation?.balance.lifetimeMicroUSD == 50)
        #expect(a.reconciliation == .matched && b.reconciliation == .matched)
        let unknown = try await database.accountCreditReport(accountID: "unknown", in: range, unit: .hour, calendar: calendar)
        #expect(unknown.totals == nil && unknown.observation == nil && unknown.reconciliation == .unavailable)
        #expect(unknown.buckets.allSatisfy { $0.coverage == .unavailable })
    }

    @Test func partialAndMismatchedHistoryNeverInventZeroHours() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([credit(1, amount: 10)], total: 100, count: 10), capturedAt: range.end)
        var report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .incomplete(observedCount: 1, observedMicroUSD: 10))
        #expect(report.buckets[0].totals?.workMicroUSD == 10)
        #expect(report.buckets[1].totals == nil && report.buckets[2].totals == nil)
        try await database.ingest(page([credit(1, amount: 10)], total: 100), capturedAt: range.end.addingTimeInterval(1))
        report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .mismatch(observedCount: 1, observedMicroUSD: 10))
        #expect(report.buckets[1].totals == nil)
        try await database.ingest(page([credit(1, amount: 10)], total: 10), capturedAt: range.end.addingTimeInterval(2))
        report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .matched)
        #expect(report.buckets.allSatisfy { $0.totals != nil })
        // A later partial page does not inherit an earlier completeness claim.
        try await database.ingest(page([], total: 10, count: 1), capturedAt: range.end.addingTimeInterval(3))
        report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .incomplete(observedCount: 1, observedMicroUSD: 10))
        #expect(report.buckets[1].totals == nil)
    }

    @Test func duplicateRowsCannotEstablishCompletenessAndRetainedExtraIDsMismatch() async throws {
        let database = try EarningsDatabase(url: url())
        let row = credit(1, amount: 10)
        try await database.ingest(page([row, row], total: 20, count: 2), capturedAt: range.end)
        var report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.observation?.pageCreditCount == 1 && report.observation?.isFullReportedPage == false)
        #expect(report.totals?.workCreditCount == 1)
        try await database.ingest(page([credit(2, amount: 10)], total: 10), capturedAt: range.end.addingTimeInterval(1))
        report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .mismatch(observedCount: 2, observedMicroUSD: 20))
        #expect(report.buckets[1].totals == nil) // Never silently delete old IDs to reconcile.
    }

    @Test func fullyReportedEmptyAccountHasZeroPastButUnknownFuture() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([], total: 0), capturedAt: start.addingTimeInterval(3_600))
        let report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .matched)
        #expect(report.buckets[0].totals?.workMicroUSD == 0)
        #expect(report.buckets[1].totals == nil && report.buckets[2].totals == nil)
        #expect(report.totals == nil)
    }

    @Test func exactHalfOpenTimeBoundariesWorkForHalfHourTimeZones() async throws {
        var local = calendar
        local.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let day = try #require(local.dateInterval(of: .day, for: start))
        let rows = [credit(1, amount: 5, at: day.start.addingTimeInterval(-0.25)),
                    credit(2, amount: 10, at: day.start),
                    credit(3, amount: 20, at: day.start.addingTimeInterval(3_599.75)),
                    credit(4, amount: 30, at: day.end)]
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page(rows, total: 65), capturedAt: day.end.addingTimeInterval(1))
        let report = try await database.accountCreditReport(accountID: "account-A", in: day, unit: .hour, calendar: local)
        #expect(report.buckets.count == 24)
        #expect(report.buckets[0].coverage == .recorded && report.buckets[0].totals?.workMicroUSD == 30)
        #expect(report.totals?.workMicroUSD == 30 && report.totals?.workCreditCount == 2)
        #expect(report.buckets[23].totals?.workMicroUSD == 0)
    }

    @Test func observationsKeepFirstAndLatestSamplesWithoutFabricatedRates() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([], total: 0), capturedAt: start)
        try await database.ingest(page([credit(1, amount: 10)], total: 10), capturedAt: start.addingTimeInterval(60))
        try await database.ingest(page([credit(1, amount: -5)], total: -5), capturedAt: start.addingTimeInterval(120))
        try await database.ingest(page([credit(1, amount: -5)], total: -5), capturedAt: start.addingTimeInterval(180))
        let report = try await database.accountCreditReport(accountID: "account-A", in: DateInterval(start: start, duration: 180), unit: .hour, calendar: calendar)
        #expect(report.lifetimeBalanceChange?.first.capturedAt == start)
        #expect(report.lifetimeBalanceChange?.latest.capturedAt == start.addingTimeInterval(180))
        #expect(report.lifetimeBalanceChange?.lifetimeDeltaMicroUSD == -5)
        #expect(report.lifetimeBalanceChange?.lifetimeCountDelta == 1)
        #expect(report.observation?.balance.capturedAt == start.addingTimeInterval(180))
        #expect(report.totals?.workMicroUSD == -5)
    }

    @Test func staleAndContradictoryObservationsCannotAdvanceScopedState() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([credit(10, amount: 10)], total: 10), capturedAt: range.end)
        try await database.ingest(page([credit(1, amount: 5), credit(10, amount: 99)], total: 104), capturedAt: range.end.addingTimeInterval(-1))
        var report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.observation?.balance.lifetimeMicroUSD == 10)
        #expect(report.reconciliation == .mismatch(observedCount: 2, observedMicroUSD: 15))
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(0, amount: 20), credit(10, amount: 10)], total: 30), capturedAt: range.end)
        }
        report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.totals?.workMicroUSD == 15 && report.observation?.balance.lifetimeMicroUSD == 10)
        #expect(try await database.accountCreditRecords(accountID: "account-A").count == 2)
    }

    @Test func overflowingIngestionRollsBackObservationsAndBalanceSamples() async throws {
        let database = try EarningsDatabase(url: url())
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(1, amount: .max), credit(2, amount: 1)], total: 0), capturedAt: range.end)
        }
        let report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.observation == nil && report.lifetimeBalanceChange == nil && report.totals == nil)
        #expect(report.reconciliation == .unavailable)
    }

    @Test func queryOverflowThrowsAndReleasesReadTransaction() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([credit(1, amount: .max)], total: .max), capturedAt: range.end)
        try await database.ingest(page([credit(2, amount: .max, at: start.addingTimeInterval(3_600))], total: 0, count: 2), capturedAt: range.end.addingTimeInterval(1))
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        }
        // A failed query must not leave a transaction open and block later ingestion.
        try await database.ingest(page([credit(1, amount: 1), credit(2, amount: 2, at: start.addingTimeInterval(3_600))], total: 3), capturedAt: range.end.addingTimeInterval(2))
        #expect(try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar).totals?.workMicroUSD == 3)
    }

    @Test func modelAndBucketBoundsFailWithoutPartialTotals() async throws {
        let database = try EarningsDatabase(url: url())
        let rows = (1...129).map { credit(Int64($0), amount: 1, model: "model-\($0)") }
        try await database.ingest(page(rows, total: 129), capturedAt: range.end)
        await #expect(throws: ActivityCalendarError.self) {
            try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        }
        await #expect(throws: ActivityCalendarError.self) {
            try await database.accountCreditReport(accountID: "account-A", in: DateInterval(start: start, duration: 745 * 3_600), unit: .hour, calendar: calendar)
        }
        #expect(try await database.accountCreditReport(accountID: "account-A", model: "model-1", in: range, unit: .hour, calendar: calendar).totals?.workMicroUSD == 1)
    }

    @Test func consistentEqualTimePagesCanAddStrongerEvidence() async throws {
        let database = try EarningsDatabase(url: url())
        let rows = [credit(1, amount: 10), credit(2, amount: 20)]
        try await database.ingest(page([rows[0]], total: 30, count: 2), capturedAt: range.end)
        try await database.ingest(page([rows[1]], total: 30, count: 2), capturedAt: range.end)
        var report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .incomplete(observedCount: 2, observedMicroUSD: 30))
        try await database.ingest(page(rows, total: 30), capturedAt: range.end)
        try await database.ingest(page([rows[0]], total: 30, count: 2), capturedAt: range.end)
        report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.reconciliation == .matched)
        #expect(report.observation?.pageCreditCount == 2 && report.observation?.isFullReportedPage == true)
        #expect(report.totals?.workCreditCount == 2)
    }

    @Test func recordLimitNeverReturnsTruncatedMoneyAndCancelledReadsReleaseTheirTransaction() async throws {
        let path = url()
        let database = try EarningsDatabase(url: path)
        try await database.ingest(page([], total: 250_001, count: 250_001), capturedAt: range.end)
        let scope = try CreditLedgerPersistence.scope("account-A")
        var pointer: OpaquePointer?
        #expect(sqlite3_open(path.path, &pointer) == SQLITE_OK)
        let writer = try #require(pointer)
        defer { sqlite3_close(writer) }
        let sql = """
            WITH RECURSIVE entries(id) AS (VALUES(1) UNION ALL SELECT id + 1 FROM entries WHERE id < 250001)
            INSERT INTO account_credit_records
            SELECT '\(scope)', id, 'provider-A', 'qwen', 1, 0, 0,
                   \(start.timeIntervalSince1970), \(range.end.timeIntervalSince1970), \(range.end.timeIntervalSince1970)
            FROM entries;
            """
        #expect(sqlite3_exec(writer, sql, nil, nil, nil) == SQLITE_OK)
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        }
        let (signal, continuation) = AsyncStream<Void>.makeStream()
        let cancelled = Task {
            for await _ in signal { break }
            return try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        }
        cancelled.cancel()
        continuation.finish()
        await #expect(throws: CancellationError.self) { try await cancelled.value }
        let empty = try await database.accountCreditReport(accountID: "account-A", model: "missing", in: range, unit: .hour, calendar: calendar)
        #expect(empty.totals == nil && empty.reconciliation == .readLimitExceeded)
        // The cancelled and oversized reads cannot leave a progress handler or
        // transaction behind to interrupt a later ordinary write/read.
        try await database.ingest(page([credit(250_002, amount: 5, model: "bounded")], total: 250_006, count: 250_002), capturedAt: range.end.addingTimeInterval(1))
        #expect(try await database.accountCreditReport(accountID: "account-A", model: "bounded", in: range, unit: .hour, calendar: calendar).totals?.workMicroUSD == 5)
    }

    @Test func inFlightSQLiteCancellationStopsAndCleansUp() async throws {
        let database = try EarningsDatabase(url: url())
        let rows = (1...1_000).map { credit(Int64($0), amount: 1) }
        try await database.ingest(page(rows, total: 1_000), capturedAt: range.end)
        let gate = ReadGate()
        let task = Task {
            try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour,
                calendar: calendar, onReadProgress: { gate.observe() })
        }
        let entered = await Task.detached { gate.waitForEntry() }.value
        task.cancel()
        gate.release.signal()
        #expect(entered) // Witness a live SQLite scan, not cancellation at entry.
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(gate.callCount == 1) // SQLite stopped at the interrupted checkpoint.
        try await database.ingest(page([credit(1_001, amount: 5)], total: 1_005, count: 1_001), capturedAt: range.end.addingTimeInterval(1))
        let report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.totals?.workMicroUSD == 1_005)
    }

    @Test func secondConnectionCommitCannotMixReportSnapshots() async throws {
        let path = url()
        let database = try EarningsDatabase(url: path)
        let rows = (1...1_000).map { credit(Int64($0), amount: $0 == 1 ? 1 : 0) }
        try await database.ingest(page(rows, total: 1), capturedAt: range.end)
        let gate = ReadGate()
        let task = Task {
            try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour,
                calendar: calendar, onReadProgress: { gate.observe() })
        }
        let entered = await Task.detached { gate.waitForEntry() }.value
        guard entered else {
            task.cancel(); gate.release.signal(); _ = try? await task.value
            throw EarningsDatabaseError.sqlite(message: "snapshot fixture did not enter SQLite scan")
        }
        let scope = try CreditLedgerPersistence.scope("account-A")
        do {
            try execute(path, """
                BEGIN IMMEDIATE;
                UPDATE account_credit_records SET amount_micro_usd = 2, changed_at = \(range.end.timeIntervalSince1970 + 1)
                    WHERE account_scope = '\(scope)' AND earning_id = 1;
                UPDATE scoped_credit_observations SET lifetime_micro_usd = 2, captured_at = \(range.end.timeIntervalSince1970 + 1)
                    WHERE account_scope = '\(scope)';
                UPDATE scoped_balance_samples SET lifetime_micro_usd = 2, captured_at = \(range.end.timeIntervalSince1970 + 1)
                    WHERE account_scope = '\(scope)' AND sample_kind = 1;
                COMMIT;
                """)
        } catch { task.cancel(); gate.release.signal(); _ = try? await task.value; throw error }
        gate.release.signal()
        let old = try await task.value
        #expect(old.totals?.workMicroUSD == 1 && old.observation?.balance.lifetimeMicroUSD == 1)
        #expect(old.reconciliation == .matched)
        let current = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(current.totals?.workMicroUSD == 2 && current.observation?.balance.lifetimeMicroUSD == 2)
        #expect(current.reconciliation == .matched)
    }

    @Test func futureCreditsAndFractionalReplayHaveHonestCoverage() async throws {
        let database = try EarningsDatabase(url: url())
        let captured = range.end.addingTimeInterval(0.000003)
        let row = credit(1, amount: 10, at: captured.addingTimeInterval(60))
        try await database.ingest(page([row], total: 10), capturedAt: captured)
        try await database.ingest(page([row], total: 10), capturedAt: captured)
        let report = try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        #expect(report.observation?.balance.capturedAt.timeIntervalSince1970 == captured.timeIntervalSince1970)
        #expect(report.observation?.isFullReportedPage == false)
        #expect(report.reconciliation == .incomplete(observedCount: 1, observedMicroUSD: 10))
        #expect(report.buckets.allSatisfy { $0.totals == nil })
    }

    @Test func balanceDeltaOverflowDoesNotLeaveTheReadTransactionOpen() async throws {
        let database = try EarningsDatabase(url: url())
        try await database.ingest(page([], total: .min, count: 1), capturedAt: start)
        try await database.ingest(page([], total: .max, count: 1), capturedAt: start.addingTimeInterval(60))
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.accountCreditReport(accountID: "account-A", in: range, unit: .hour, calendar: calendar)
        }
        try await database.ingest(page([], total: 0, count: 1), capturedAt: start.addingTimeInterval(120))
        // A narrower range excludes the unrepresentable first endpoint.
        let report = try await database.accountCreditReport(accountID: "account-A", in: DateInterval(start: start.addingTimeInterval(60), duration: 60), unit: .hour, calendar: calendar)
        #expect(report.lifetimeBalanceChange == nil) // Intermediate samples are not invented.
        #expect(report.observation?.balance.lifetimeMicroUSD == 0)
    }

    private func execute(_ path: URL, _ sql: String) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open(path.path, &pointer) == SQLITE_OK, let pointer else { throw EarningsDatabaseError.sqlite(message: "fixture open failed") }
        defer { sqlite3_close(pointer) }
        sqlite3_busy_timeout(pointer, 2_000)
        guard sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK else { throw EarningsDatabaseError.sqlite(message: "fixture write failed") }
    }
    private final class ReadGate: @unchecked Sendable {
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var calls = 0
        var callCount: Int { lock.lock(); defer { lock.unlock() }; return calls }
        func waitForEntry() -> Bool { entered.wait(timeout: .now() + 10) == .success }
        func observe() {
            lock.lock()
            calls += 1
            let first = calls == 1
            lock.unlock()
            if first { entered.signal(); _ = release.wait(timeout: .now() + 10) }
        }
    }

    private func url() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("bloomy-scoped-report-\(UUID()).sqlite3") }
    private func credit(_ id: Int64, amount: Int64, provider: String = "provider-A", model: String = "qwen", at date: Date? = nil) -> AccountEarning {
        AccountEarning(id: id, providerID: provider, providerKey: "secret-scoped-canary", model: model,
                       amountMicroUSD: amount, promptTokens: 10, completionTokens: 20, createdAt: date ?? start)
    }
    private func page(_ rows: [AccountEarning], account: String = "account-A", total: Int64, count: Int64? = nil) -> AccountEarningsResponse {
        AccountEarningsResponse(accountID: account, earnings: rows, count: count ?? Int64(rows.count), historyLimit: 100,
                               recentCount: rows.count, totalMicroUSD: total, availableBalanceMicroUSD: total,
                               withdrawableBalanceMicroUSD: total)
    }
}
