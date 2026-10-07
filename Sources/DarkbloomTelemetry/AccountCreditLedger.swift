import CryptoKit
import Foundation
import SQLite3

/// An observed account credit. Created time is the source's credit timestamp,
/// not proof of the serving interval. Observation times are local capture times.
/// Neither account identity nor provider credentials are exposed in this value.
public struct AccountCreditRecord: Equatable, Sendable {
    public let earningID: Int64
    /// Empty means the source did not identify a provider; it must remain unattributed.
    public let providerID: String
    public let model: String
    public let amountMicroUSD: Int64
    public let promptTokens: Int64
    public let completionTokens: Int64
    public let createdAt: Date
    public let firstObservedAt: Date
    public let changedAt: Date
}

/// Synchronous connection operations; invoked exclusively by EarningsDatabase.
/// The caller owns the transaction and the SQLite connection's actor isolation.
enum CreditLedgerPersistence {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func createSchema(_ database: OpaquePointer) throws {
        try execute(database, """
            CREATE TABLE IF NOT EXISTS account_credit_records (
                account_scope TEXT NOT NULL,
                earning_id INTEGER NOT NULL,
                provider_id TEXT NOT NULL,
                model TEXT NOT NULL,
                amount_micro_usd INTEGER NOT NULL CHECK(typeof(amount_micro_usd) = 'integer'),
                prompt_tokens INTEGER NOT NULL CHECK(typeof(prompt_tokens) = 'integer' AND prompt_tokens >= 0),
                completion_tokens INTEGER NOT NULL CHECK(typeof(completion_tokens) = 'integer' AND completion_tokens >= 0),
                created_at REAL NOT NULL,
                first_observed_at REAL NOT NULL,
                changed_at REAL NOT NULL,
                PRIMARY KEY(account_scope, earning_id)
            );
            CREATE INDEX IF NOT EXISTS credit_scope_time
                ON account_credit_records(account_scope, created_at DESC, earning_id DESC);
            CREATE INDEX IF NOT EXISTS credit_scope_provider_time
                ON account_credit_records(account_scope, provider_id, created_at DESC, earning_id DESC);
            CREATE TABLE IF NOT EXISTS credit_observation_state (
                account_scope TEXT PRIMARY KEY,
                captured_at REAL NOT NULL
            );
            """)
        // SQLite otherwise promotes overflowing integer additions to REAL.
        // Triggers protect old schemas as well as the legacy reward migration.
        for (table, columns) in [
            ("earnings_hourly", ["amount_micro_usd", "jobs", "prompt_tokens", "completion_tokens"]),
            ("rewards_hourly", ["amount_micro_usd", "events"])
        ] {
            let invalid = columns.map { "typeof(NEW.\($0)) != 'integer'" }.joined(separator: " OR ")
            for event in ["INSERT", "UPDATE"] {
                try execute(database, """
                    CREATE TRIGGER IF NOT EXISTS \(table)_integer_\(event.lowercased())
                    BEFORE \(event) ON \(table) WHEN \(invalid)
                    BEGIN SELECT RAISE(ABORT, 'earnings integer total out of range'); END;
                    """)
            }
        }
    }

    /// Deduplicate the page before either store consumes it. Credentials do not
    /// participate in financial equality, and never enter SQL or error strings.
    static func normalized(_ response: AccountEarningsResponse, capturedAt: Date) throws -> AccountEarningsResponse {
        _ = try scope(response.accountID)
        guard capturedAt.timeIntervalSince1970.isFinite, response.count >= 0,
              response.historyLimit >= 0, response.recentCount >= 0 else { throw invalidInput() }
        var unique: [Int64: AccountEarning] = [:]
        for row in response.earnings {
            guard !row.providerID.contains("\0"), validIdentifier(row.model),
                  row.createdAt.timeIntervalSince1970.isFinite,
                  (floor(row.createdAt.timeIntervalSince1970 / 3_600) * 3_600).isFinite,
                  row.promptTokens >= 0, row.completionTokens >= 0 else { throw invalidInput() }
            if let prior = unique[row.id], !sameCredit(prior, row) {
                throw EarningsDatabaseError.sqlite(message: "conflicting duplicate credit records")
            }
            unique[row.id] = row
        }
        return AccountEarningsResponse(accountID: response.accountID,
            earnings: unique.values.sorted { $0.id < $1.id }, count: response.count,
            historyLimit: response.historyLimit, recentCount: response.recentCount,
            totalMicroUSD: response.totalMicroUSD, availableBalanceMicroUSD: response.availableBalanceMicroUSD,
            withdrawableBalanceMicroUSD: response.withdrawableBalanceMicroUSD)
    }

    static func ingest(_ response: AccountEarningsResponse, capturedAt: Date, database: OpaquePointer) throws {
        let accountScope = try scope(response.accountID)
        let observation = try prepare(database, "SELECT captured_at FROM credit_observation_state WHERE account_scope = ?")
        defer { sqlite3_finalize(observation) }
        try bind(accountScope, to: observation, at: 1, database: database)
        let result = sqlite3_step(observation)
        guard result == SQLITE_ROW || result == SQLITE_DONE else { throw error(database) }
        let previousCapture: Double? = result == SQLITE_ROW ? sqlite3_column_double(observation, 0) : nil
        let captured = capturedAt.timeIntervalSince1970
        let lookup = try prepare(database, """
            SELECT earning_id, provider_id, model, amount_micro_usd, prompt_tokens, completion_tokens,
                   created_at, first_observed_at, changed_at
            FROM account_credit_records WHERE account_scope = ? AND earning_id = ?
            """)
        defer { sqlite3_finalize(lookup) }
        let write = try prepare(database, """
            INSERT INTO account_credit_records
                (account_scope, earning_id, provider_id, model, amount_micro_usd, prompt_tokens,
                 completion_tokens, created_at, first_observed_at, changed_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(account_scope, earning_id) DO UPDATE SET
                provider_id = excluded.provider_id, model = excluded.model,
                amount_micro_usd = excluded.amount_micro_usd, prompt_tokens = excluded.prompt_tokens,
                completion_tokens = excluded.completion_tokens, created_at = excluded.created_at,
                changed_at = excluded.changed_at
            """)
        defer { sqlite3_finalize(write) }
        for row in response.earnings {
            sqlite3_reset(lookup)
            sqlite3_clear_bindings(lookup)
            try bind(accountScope, to: lookup, at: 1, database: database)
            sqlite3_bind_int64(lookup, 2, row.id)
            let step = sqlite3_step(lookup)
            guard step == SQLITE_ROW || step == SQLITE_DONE else { throw error(database) }
            if step == SQLITE_ROW {
                let existing = try record(lookup)
                if matches(existing, row) { continue }
                let boundary = max(previousCapture ?? existing.changedAt.timeIntervalSince1970,
                                   existing.changedAt.timeIntervalSince1970)
                if captured < boundary { continue }
                if captured == boundary {
                    throw EarningsDatabaseError.sqlite(message: "conflicting credit observations at the same capture time")
                }
            }
            sqlite3_reset(write)
            sqlite3_clear_bindings(write)
            try bind(accountScope, to: write, at: 1, database: database)
            sqlite3_bind_int64(write, 2, row.id)
            try bind(row.providerID, to: write, at: 3, database: database)
            try bind(row.model, to: write, at: 4, database: database)
            sqlite3_bind_int64(write, 5, row.amountMicroUSD)
            sqlite3_bind_int64(write, 6, Int64(row.promptTokens))
            sqlite3_bind_int64(write, 7, Int64(row.completionTokens))
            sqlite3_bind_double(write, 8, row.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(write, 9, captured)
            sqlite3_bind_double(write, 10, captured)
            guard sqlite3_step(write) == SQLITE_DONE else { throw error(database) }
        }
        if captured > (previousCapture ?? -.infinity) {
            let state = try prepare(database, """
                INSERT INTO credit_observation_state(account_scope, captured_at) VALUES (?, ?)
                ON CONFLICT(account_scope) DO UPDATE SET captured_at = excluded.captured_at
                """)
            defer { sqlite3_finalize(state) }
            try bind(accountScope, to: state, at: 1, database: database)
            sqlite3_bind_double(state, 2, captured)
            guard sqlite3_step(state) == SQLITE_DONE else { throw error(database) }
        }
    }

    static func records(accountID: String, providerID: String?, from: Date?, to: Date?, limit: Int,
                        database: OpaquePointer) throws -> [AccountCreditRecord] {
        let accountScope = try scope(accountID)
        guard (1...5_000).contains(limit), providerID.map({ !$0.contains("\0") }) ?? true,
              from.map({ $0.timeIntervalSince1970.isFinite }) ?? true,
              to.map({ $0.timeIntervalSince1970.isFinite }) ?? true else { throw invalidInput() }
        if let from, let to, from >= to { throw invalidInput() }
        var predicates = ["account_scope = ?"]
        if providerID != nil { predicates.append("provider_id = ?") }
        if from != nil { predicates.append("created_at >= ?") }
        if to != nil { predicates.append("created_at < ?") }
        let statement = try prepare(database, """
            SELECT earning_id, provider_id, model, amount_micro_usd, prompt_tokens, completion_tokens,
                   created_at, first_observed_at, changed_at
            FROM account_credit_records WHERE \(predicates.joined(separator: " AND "))
            ORDER BY created_at DESC, earning_id DESC LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }
        try bind(accountScope, to: statement, at: 1, database: database)
        var index: Int32 = 2
        if let providerID { try bind(providerID, to: statement, at: index, database: database); index += 1 }
        if let from { sqlite3_bind_double(statement, index, from.timeIntervalSince1970); index += 1 }
        if let to { sqlite3_bind_double(statement, index, to.timeIntervalSince1970); index += 1 }
        sqlite3_bind_int64(statement, index, Int64(limit))
        var rows: [AccountCreditRecord] = []
        var step = sqlite3_step(statement)
        while step == SQLITE_ROW {
            rows.append(try record(statement))
            step = sqlite3_step(statement)
        }
        guard step == SQLITE_DONE else { throw error(database) }
        return rows
    }

    private static func scope(_ accountID: String) throws -> String {
        guard validIdentifier(accountID) else { throw invalidInput() }
        return SHA256.hash(data: Data(("Bloomy.account-credit-scope.v1\0" + accountID).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
    private static func validIdentifier(_ value: String) -> Bool { !value.isEmpty && !value.contains("\0") }
    private static func sameCredit(_ a: AccountEarning, _ b: AccountEarning) -> Bool {
        a.providerID == b.providerID && a.model == b.model && a.amountMicroUSD == b.amountMicroUSD &&
        a.promptTokens == b.promptTokens && a.completionTokens == b.completionTokens && a.createdAt.timeIntervalSince1970 == b.createdAt.timeIntervalSince1970
    }
    // Compare Unix-epoch values, the timestamp representation SQLite retains.
    private static func matches(_ a: AccountCreditRecord, _ b: AccountEarning) -> Bool {
        a.providerID == b.providerID && a.model == b.model && a.amountMicroUSD == b.amountMicroUSD &&
        a.promptTokens == Int64(b.promptTokens) && a.completionTokens == Int64(b.completionTokens) && a.createdAt.timeIntervalSince1970 == b.createdAt.timeIntervalSince1970
    }
    private static func record(_ statement: OpaquePointer) throws -> AccountCreditRecord {
        guard let provider = sqlite3_column_text(statement, 1), let model = sqlite3_column_text(statement, 2) else {
            throw EarningsDatabaseError.sqlite(message: "invalid stored credit record")
        }
        return AccountCreditRecord(earningID: sqlite3_column_int64(statement, 0),
            providerID: String(cString: provider), model: String(cString: model),
            amountMicroUSD: sqlite3_column_int64(statement, 3), promptTokens: sqlite3_column_int64(statement, 4),
            completionTokens: sqlite3_column_int64(statement, 5), createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
            firstObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 7)),
            changedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 8)))
    }
    private static func prepare(_ database: OpaquePointer, _ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw error(database) }
        return statement
    }
    private static func bind(_ value: String, to statement: OpaquePointer, at index: Int32, database: OpaquePointer) throws {
        guard sqlite3_bind_text(statement, index, value, -1, transient) == SQLITE_OK else { throw error(database) }
    }
    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw error(database) }
    }
    private static func error(_ database: OpaquePointer) -> EarningsDatabaseError {
        // Codes are useful diagnostics; SQLite's text can include caller data in future schemas.
        .sqlite(message: "credit storage operation failed (SQLite \(sqlite3_extended_errcode(database)))")
    }
    private static func invalidInput() -> EarningsDatabaseError { .sqlite(message: "invalid credit input or query bounds") }
}
