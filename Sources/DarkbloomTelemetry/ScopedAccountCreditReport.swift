import Foundation
import SQLite3

/// Counts refer to credit records, not proof of completed serving requests.
public struct AccountCreditTotals: Equatable, Sendable {
    public let workMicroUSD: Int64
    public let rewardMicroUSD: Int64
    public let workCreditCount: Int64
    public let rewardCreditCount: Int64
    public let promptTokens: Int64
    public let completionTokens: Int64
}

public struct AccountCreditBucket: Equatable, Sendable, Identifiable {
    public let interval: DateInterval
    public let totals: AccountCreditTotals?
    public let coverage: ActivityCoverage
    public var id: Date { interval.start }
}

public struct AccountCreditObservation: Equatable, Sendable {
    public let balance: AccountBalanceSample
    public let pageCreditCount: Int64
    public let isFullReportedPage: Bool
}

/// A change in authoritative lifetime balance between captured observations.
/// A decrease can reflect a correction; this is not an earned-income rate.
public struct AccountLifetimeBalanceChange: Equatable, Sendable {
    public let first: AccountBalanceSample
    public let latest: AccountBalanceSample
    public let lifetimeDeltaMicroUSD: Int64
    public let lifetimeCountDelta: Int64
}

public enum AccountCreditReconciliation: Equatable, Sendable {
    case unavailable
    /// Reconciliation was deferred, never computed from a truncated lifetime sum.
    case readLimitExceeded
    /// A partial page cannot prove that the retained ledger covers all history.
    case incomplete(observedCount: Int64, observedMicroUSD: Int64)
    case mismatch(observedCount: Int64, observedMicroUSD: Int64)
    /// All retained records match a full reported page's count and lifetime sum.
    case matched
}

/// One actor-isolated read, with account-wide reconciliation and filtered results.
/// Signed observed subtotals are not necessarily a lower bound. A provider ID
/// filter is caller-selected; this value does not identify this Mac's provider.
public struct AccountCreditReport: Equatable, Sendable {
    public let accountScope: String
    public let providerID: String?
    public let model: String?
    public let range: DateInterval
    public let observation: AccountCreditObservation?
    public let reconciliation: AccountCreditReconciliation
    public let lifetimeBalanceChange: AccountLifetimeBalanceChange?
    public let totals: AccountCreditTotals?
    public let buckets: [AccountCreditBucket]
    public let models: [String]
    public let modelActivity: [ModelActivityBucket]
}

/// Synchronous work, owned by EarningsDatabase's actor and transaction.
enum ScopedCreditReadPersistence {
    private typealias SQL = CreditLedgerPersistence

    static func createSchema(_ database: OpaquePointer) throws {
        let statements = """
            CREATE INDEX IF NOT EXISTS credit_scope_model_time
                ON account_credit_records(account_scope, model, created_at, earning_id);
            CREATE TABLE IF NOT EXISTS scoped_credit_observations (
                account_scope TEXT PRIMARY KEY,
                captured_at REAL NOT NULL,
                lifetime_micro_usd INTEGER NOT NULL CHECK(typeof(lifetime_micro_usd) = 'integer'),
                available_micro_usd INTEGER NOT NULL CHECK(typeof(available_micro_usd) = 'integer'),
                withdrawable_micro_usd INTEGER NOT NULL CHECK(typeof(withdrawable_micro_usd) = 'integer'),
                lifetime_count INTEGER NOT NULL CHECK(typeof(lifetime_count) = 'integer' AND lifetime_count >= 0),
                page_count INTEGER NOT NULL CHECK(typeof(page_count) = 'integer' AND page_count >= 0),
                full_page INTEGER NOT NULL CHECK(full_page IN (0, 1))
            );
            CREATE TABLE IF NOT EXISTS scoped_balance_samples (
                account_scope TEXT NOT NULL,
                hour_start REAL NOT NULL,
                sample_kind INTEGER NOT NULL CHECK(sample_kind IN (0, 1)),
                captured_at REAL NOT NULL,
                lifetime_micro_usd INTEGER NOT NULL CHECK(typeof(lifetime_micro_usd) = 'integer'),
                available_micro_usd INTEGER NOT NULL CHECK(typeof(available_micro_usd) = 'integer'),
                withdrawable_micro_usd INTEGER NOT NULL CHECK(typeof(withdrawable_micro_usd) = 'integer'),
                lifetime_count INTEGER NOT NULL CHECK(typeof(lifetime_count) = 'integer' AND lifetime_count >= 0),
                PRIMARY KEY(account_scope, hour_start, sample_kind)
            );
            """
        guard sqlite3_exec(database, statements, nil, nil, nil) == SQLITE_OK else { throw SQL.error(database) }
    }

    static func observe(_ response: AccountEarningsResponse, capturedAt: Date,
                        previousCapture: Double?, database: OpaquePointer) throws {
        let captured = capturedAt.timeIntervalSince1970
        guard captured >= (previousCapture ?? -.infinity) else { return }
        let scope = try SQL.scope(response.accountID)
        var count = Int64(response.earnings.count)
        var full = response.count == count && response.earnings.allSatisfy {
            $0.createdAt.timeIntervalSince1970 <= captured
        }
        let prior = try observation(scope: scope, database: database)
        let alreadyCaptured = prior?.balance.capturedAt.timeIntervalSince1970 == captured
        if alreadyCaptured, let prior {
            guard prior.balance.lifetimeMicroUSD == response.totalMicroUSD,
                  prior.balance.availableMicroUSD == response.availableBalanceMicroUSD,
                  prior.balance.withdrawableMicroUSD == response.withdrawableBalanceMicroUSD,
                  prior.balance.lifetimeCount == response.count else {
                throw EarningsDatabaseError.sqlite(message: "conflicting account observations at the same capture time")
            }
            // Different page limits at the same snapshot can add consistent
            // evidence. Keep the strongest page, without fabricating coverage
            // from the union of separately truncated pages.
            count = max(count, prior.pageCreditCount)
            full = full || prior.isFullReportedPage
            if count == prior.pageCreditCount, full == prior.isFullReportedPage { return }
        }
        let current = try SQL.prepare(database, """
            INSERT INTO scoped_credit_observations VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_scope) DO UPDATE SET captured_at = excluded.captured_at,
                lifetime_micro_usd = excluded.lifetime_micro_usd, available_micro_usd = excluded.available_micro_usd,
                withdrawable_micro_usd = excluded.withdrawable_micro_usd, lifetime_count = excluded.lifetime_count,
                page_count = excluded.page_count, full_page = excluded.full_page
            """)
        defer { sqlite3_finalize(current) }
        try SQL.bind(scope, to: current, at: 1, database: database)
        sqlite3_bind_double(current, 2, captured)
        sqlite3_bind_int64(current, 3, response.totalMicroUSD)
        sqlite3_bind_int64(current, 4, response.availableBalanceMicroUSD)
        sqlite3_bind_int64(current, 5, response.withdrawableBalanceMicroUSD)
        sqlite3_bind_int64(current, 6, response.count)
        sqlite3_bind_int64(current, 7, count)
        sqlite3_bind_int(current, 8, full ? 1 : 0)
        guard sqlite3_step(current) == SQLITE_DONE else { throw SQL.error(database) }
        guard !alreadyCaptured else { return }
        let sample = try SQL.prepare(database, """
            INSERT INTO scoped_balance_samples VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_scope, hour_start, sample_kind) DO UPDATE SET
                captured_at = excluded.captured_at, lifetime_micro_usd = excluded.lifetime_micro_usd,
                available_micro_usd = excluded.available_micro_usd, withdrawable_micro_usd = excluded.withdrawable_micro_usd,
                lifetime_count = excluded.lifetime_count
            WHERE excluded.sample_kind = 1
            """)
        defer { sqlite3_finalize(sample) }
        for kind: Int32 in [0, 1] {
            sqlite3_reset(sample)
            sqlite3_clear_bindings(sample)
            try SQL.bind(scope, to: sample, at: 1, database: database)
            sqlite3_bind_double(sample, 2, floor(captured / 3_600) * 3_600)
            sqlite3_bind_int(sample, 3, kind)
            sqlite3_bind_double(sample, 4, captured)
            sqlite3_bind_int64(sample, 5, response.totalMicroUSD)
            sqlite3_bind_int64(sample, 6, response.availableBalanceMicroUSD)
            sqlite3_bind_int64(sample, 7, response.withdrawableBalanceMicroUSD)
            sqlite3_bind_int64(sample, 8, response.count)
            guard sqlite3_step(sample) == SQLITE_DONE else { throw SQL.error(database) }
        }
    }

    static func report(accountID: String, providerID: String?, model: String?, range: DateInterval,
                       unit: ActivityCalendarUnit, calendar: Calendar, database: OpaquePointer) throws -> AccountCreditReport {
        try Task.checkCancellation()
        let scope = try SQL.scope(accountID)
        guard providerID.map({ !$0.contains("\0") }) ?? true,
              model.map({ !$0.isEmpty && !$0.contains("\0") }) ?? true else {
            throw ActivityCalendarError.invalidInterval
        }
        let intervals = try ActivityCalendar.intervals(in: range, unit: unit, calendar: calendar)
        let observation = try observation(scope: scope, database: database)
        let reconciliation = try reconcile(scope: scope, observation: observation, database: database)
        let completeThrough = reconciliation == .matched ? observation?.balance.capturedAt : nil
        var predicates = ["account_scope = ?", "created_at >= ?", "created_at < ?"]
        if providerID != nil { predicates.append("provider_id = ?") }
        if model != nil { predicates.append("model = ?") }
        let rows = try SQL.prepare(database, """
            SELECT created_at, model, amount_micro_usd, prompt_tokens, completion_tokens
            FROM account_credit_records WHERE \(predicates.joined(separator: " AND "))
            ORDER BY created_at, earning_id
            """)
        defer { sqlite3_finalize(rows) }
        try SQL.bind(scope, to: rows, at: 1, database: database)
        sqlite3_bind_double(rows, 2, range.start.timeIntervalSince1970)
        sqlite3_bind_double(rows, 3, range.end.timeIntervalSince1970)
        var binding: Int32 = 4
        if let providerID { try SQL.bind(providerID, to: rows, at: binding, database: database); binding += 1 }
        if let model { try SQL.bind(model, to: rows, at: binding, database: database) }
        var totals = Accumulator()
        var bucketTotals = Array(repeating: Accumulator(), count: intervals.count)
        var models = Set<String>()
        var contributions: [Int: [String: Int64]] = [:]
        var intervalIndex = 0
        var count = 0
        var step = sqlite3_step(rows)
        while step == SQLITE_ROW {
            count += 1
            // A large request fails explicitly; never return truncated money.
            guard count <= 250_000 else {
                throw EarningsDatabaseError.sqlite(message: "scoped credit range exceeds the 250,000-record read limit")
            }
            if count % 256 == 0 { try Task.checkCancellation() }
            let created = Date(timeIntervalSince1970: sqlite3_column_double(rows, 0))
            while intervalIndex < intervals.count, created >= intervals[intervalIndex].end { intervalIndex += 1 }
            guard intervalIndex < intervals.count, let name = sqlite3_column_text(rows, 1) else { throw SQL.error(database) }
            let model = String(cString: name)
            let amount = sqlite3_column_int64(rows, 2)
            let prompt = sqlite3_column_int64(rows, 3), completion = sqlite3_column_int64(rows, 4)
            try totals.add(model: model, amount: amount, prompt: prompt, completion: completion)
            try bucketTotals[intervalIndex].add(model: model, amount: amount, prompt: prompt, completion: completion)
            if model != "base_reward" {
                models.insert(model)
                guard models.count <= 128 else { throw ActivityCalendarError.tooManyBuckets }
                contributions[intervalIndex, default: [:]][model] = try add(contributions[intervalIndex]?[model] ?? 0, amount)
            }
            step = sqlite3_step(rows)
        }
        guard step == SQLITE_DONE else { throw SQL.error(database) }
        try Task.checkCancellation()
        let buckets = intervals.enumerated().map { index, interval in
            let value = bucketTotals[index]
            let known = value.hasRecords || completeThrough.map { interval.end <= $0 } == true
            return AccountCreditBucket(interval: interval, totals: known ? value.value : nil,
                                       coverage: known ? .recorded : .unavailable)
        }
        let modelActivity = intervals.enumerated().flatMap { index, interval in
            (contributions[index] ?? [:]).sorted { $0.key < $1.key }.map { entry in
                ModelActivityBucket(interval: interval, model: entry.key, workMicroUSD: entry.value)
            }
        }
        let known = totals.hasRecords || (!intervals.isEmpty && completeThrough.map { range.end <= $0 } == true)
        return AccountCreditReport(accountScope: scope, providerID: providerID, model: model, range: range,
            observation: observation, reconciliation: reconciliation,
            lifetimeBalanceChange: try balanceChange(scope: scope, range: range, database: database),
            totals: known ? totals.value : nil,
            buckets: buckets, models: models.sorted(), modelActivity: modelActivity)
    }

    static func observation(scope: String, database: OpaquePointer) throws -> AccountCreditObservation? {
        let statement = try SQL.prepare(database, """
            SELECT captured_at, lifetime_micro_usd, available_micro_usd, withdrawable_micro_usd,
                   lifetime_count, page_count, full_page FROM scoped_credit_observations WHERE account_scope = ?
            """)
        defer { sqlite3_finalize(statement) }
        try SQL.bind(scope, to: statement, at: 1, database: database)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else { throw SQL.error(database) }
        return AccountCreditObservation(balance: AccountBalanceSample(
            capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
            lifetimeMicroUSD: sqlite3_column_int64(statement, 1), availableMicroUSD: sqlite3_column_int64(statement, 2),
            withdrawableMicroUSD: sqlite3_column_int64(statement, 3), lifetimeCount: sqlite3_column_int64(statement, 4)),
            pageCreditCount: sqlite3_column_int64(statement, 5), isFullReportedPage: sqlite3_column_int(statement, 6) == 1)
    }

    private static func balanceChange(scope: String, range: DateInterval, database: OpaquePointer) throws -> AccountLifetimeBalanceChange? {
        // Credit-time buckets are half-open. Captured balance observations at
        // the requested end are included, so a current snapshot can anchor it.
        func endpoint(_ ascending: Bool) throws -> AccountBalanceSample? {
            let statement = try SQL.prepare(database, """
                SELECT captured_at, lifetime_micro_usd, available_micro_usd, withdrawable_micro_usd, lifetime_count
                FROM scoped_balance_samples WHERE account_scope = ? AND hour_start >= ? AND hour_start <= ?
                    AND captured_at >= ? AND captured_at <= ?
                ORDER BY captured_at \(ascending ? "ASC" : "DESC") LIMIT 1
                """)
            defer { sqlite3_finalize(statement) }
            try SQL.bind(scope, to: statement, at: 1, database: database)
            sqlite3_bind_double(statement, 2, floor(range.start.timeIntervalSince1970 / 3_600) * 3_600)
            sqlite3_bind_double(statement, 3, floor(range.end.timeIntervalSince1970 / 3_600) * 3_600)
            sqlite3_bind_double(statement, 4, range.start.timeIntervalSince1970)
            sqlite3_bind_double(statement, 5, range.end.timeIntervalSince1970)
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return nil }
            guard step == SQLITE_ROW else { throw SQL.error(database) }
            return AccountBalanceSample(capturedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 0)),
                lifetimeMicroUSD: sqlite3_column_int64(statement, 1), availableMicroUSD: sqlite3_column_int64(statement, 2),
                withdrawableMicroUSD: sqlite3_column_int64(statement, 3), lifetimeCount: sqlite3_column_int64(statement, 4))
        }
        guard let first = try endpoint(true), let latest = try endpoint(false), latest.capturedAt > first.capturedAt else { return nil }
        let (delta, overflow) = latest.lifetimeMicroUSD.subtractingReportingOverflow(first.lifetimeMicroUSD)
        guard !overflow else { throw EarningsDatabaseError.sqlite(message: "scoped balance change out of range") }
        return AccountLifetimeBalanceChange(first: first, latest: latest, lifetimeDeltaMicroUSD: delta,
            lifetimeCountDelta: latest.lifetimeCount - first.lifetimeCount)
    }

    private static func reconcile(scope: String, observation: AccountCreditObservation?, database: OpaquePointer) throws -> AccountCreditReconciliation {
        guard let observation else { return .unavailable }
        // Both scans have explicit row budgets. A small filtered chart must
        // not trigger an unbounded lifetime scan before its range is applied.
        let size = try SQL.prepare(database, """
            SELECT COUNT(*) FROM (SELECT 1 FROM account_credit_records WHERE account_scope = ? LIMIT 250001)
            """)
        defer { sqlite3_finalize(size) }
        try SQL.bind(scope, to: size, at: 1, database: database)
        guard sqlite3_step(size) == SQLITE_ROW else { throw SQL.error(database) }
        let count = sqlite3_column_int64(size, 0)
        guard count <= 250_000 else { return .readLimitExceeded }
        let statement = try SQL.prepare(database, """
            SELECT COALESCE(SUM(amount_micro_usd), 0)
            FROM (SELECT amount_micro_usd FROM account_credit_records WHERE account_scope = ? LIMIT 250000)
            """)
        defer { sqlite3_finalize(statement) }
        try SQL.bind(scope, to: statement, at: 1, database: database)
        guard sqlite3_step(statement) == SQLITE_ROW else { throw SQL.error(database) }
        let amount = sqlite3_column_int64(statement, 0)
        guard observation.isFullReportedPage else { return .incomplete(observedCount: count, observedMicroUSD: amount) }
        return count == observation.balance.lifetimeCount && amount == observation.balance.lifetimeMicroUSD
            ? .matched : .mismatch(observedCount: count, observedMicroUSD: amount)
    }

    private struct Accumulator {
        var work: Int64 = 0, rewards: Int64 = 0, workCount: Int64 = 0, rewardCount: Int64 = 0
        var prompt: Int64 = 0, completion: Int64 = 0
        var hasRecords: Bool { workCount > 0 || rewardCount > 0 }
        var value: AccountCreditTotals { AccountCreditTotals(workMicroUSD: work, rewardMicroUSD: rewards,
            workCreditCount: workCount, rewardCreditCount: rewardCount, promptTokens: prompt, completionTokens: completion) }
        mutating func add(model: String, amount: Int64, prompt: Int64, completion: Int64) throws {
            if model == "base_reward" { rewards = try ScopedCreditReadPersistence.add(rewards, amount); rewardCount = try ScopedCreditReadPersistence.add(rewardCount, 1) }
            else {
                work = try ScopedCreditReadPersistence.add(work, amount); workCount = try ScopedCreditReadPersistence.add(workCount, 1)
                self.prompt = try ScopedCreditReadPersistence.add(self.prompt, prompt)
                self.completion = try ScopedCreditReadPersistence.add(self.completion, completion)
            }
        }
    }
    private static func add(_ left: Int64, _ right: Int64) throws -> Int64 {
        let (result, overflow) = left.addingReportingOverflow(right)
        guard !overflow else { throw EarningsDatabaseError.sqlite(message: "scoped credit total out of range") }
        return result
    }
}
