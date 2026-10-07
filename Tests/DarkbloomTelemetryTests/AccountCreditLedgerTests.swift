import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Account credit ledger")
struct AccountCreditLedgerTests {
    private let date = Date(timeIntervalSince1970: 2_000_000)

    @Test func lateIDsCorrectionsAndPartialPagesArePreserved() async throws {
        let database = try EarningsDatabase(url: temporaryURL())
        try await database.ingest(page([credit(101, amount: 100), credit(103, amount: 300)]), capturedAt: date)
        let corrected = credit(101, amount: -25, provider: "other-provider", model: "base_reward",
                               at: date.addingTimeInterval(-3_600), tokens: 0)
        try await database.ingest(page([corrected, credit(102, amount: 0)]), capturedAt: date.addingTimeInterval(60))
        try await database.ingest(page([]), capturedAt: date.addingTimeInterval(120))
        let records = try await database.accountCreditRecords(accountID: "account-A")
        #expect(records.map(\.earningID) == [103, 102, 101])
        let row = try #require(records.first { $0.earningID == 101 })
        #expect(row.amountMicroUSD == -25 && row.providerID == "other-provider")
        #expect(row.model == "base_reward" && row.promptTokens == 0 && row.completionTokens == 0)
        #expect(row.createdAt == date.addingTimeInterval(-3_600))
        #expect(row.firstObservedAt == date && row.changedAt == date.addingTimeInterval(60))
        #expect(try await database.accountCreditRecords(accountID: "account-A", providerID: "other-provider").count == 1)
    }

    @Test func accountsAreIsolatedAndRepeatsDoNotRewriteRawRows() async throws {
        let url = temporaryURL()
        let database = try EarningsDatabase(url: url)
        try await database.ingest(page([credit(1, amount: 10)]), capturedAt: date)
        try await database.ingest(page([credit(1, amount: 20)], account: "account-B"), capturedAt: date.addingTimeInterval(10))
        // A credential rotation is not a correction to the financial record.
        try await database.ingest(page([credit(1, amount: 10, key: "rotated-secret")]), capturedAt: date.addingTimeInterval(20))
        #expect(try await database.accountCreditRecords(accountID: "account-A").map(\.amountMicroUSD) == [10])
        #expect(try await database.accountCreditRecords(accountID: "account-B").map(\.amountMicroUSD) == [20])
        #expect(try await database.accountCreditRecords(accountID: "account-A").first?.changedAt == date)
        #expect(try await database.accountCreditRecords(accountID: "unknown").isEmpty == true)
        // All SQLite artifacts must be private while the writer is open.
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: path)
        }
        // Reopening an older database also repairs existing permissive sidecars.
        let reopened = try EarningsDatabase(url: url)
        #expect(try await reopened.accountCreditRecords(accountID: "account-A").count == 1)
        for suffix in ["", "-wal", "-shm"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        var bytes = try Data(contentsOf: url)
        let wal = URL(fileURLWithPath: url.path + "-wal")
        if FileManager.default.fileExists(atPath: wal.path) { bytes.append(try Data(contentsOf: wal)) }
        for secret in ["account-A", "account-B", "secret-canary", "rotated-secret"] {
            #expect(bytes.range(of: Data(secret.utf8)) == nil)
        }
        // Keep both actor-owned connections alive throughout sidecar inspection.
        #expect(try await database.accountCreditRecords(accountID: "account-B").count == 1)
        #expect(try await reopened.accountCreditRecords(accountID: "account-A").count == 1)
    }

    @Test func olderObservationsCannotUndoNewerCorrections() async throws {
        let database = try EarningsDatabase(url: temporaryURL())
        try await database.ingest(page([credit(1, amount: 10)]), capturedAt: date)
        // A newer unchanged page establishes an observation boundary without rewriting the row.
        try await database.ingest(page([credit(1, amount: 10)]), capturedAt: date.addingTimeInterval(30))
        try await database.ingest(page([credit(1, amount: 50), credit(0, amount: 5)]), capturedAt: date.addingTimeInterval(10))
        #expect(try await database.accountCreditRecords(accountID: "account-A").map(\.amountMicroUSD) == [10, 5])
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(1, amount: 99)]), capturedAt: date.addingTimeInterval(30))
        }
        #expect(try await database.accountCreditRecords(accountID: "account-A").first?.amountMicroUSD == 10)
    }

    @Test func duplicatesCollapseAndContradictionsRollBack() async throws {
        let database = try EarningsDatabase(url: temporaryURL())
        let row = credit(1, amount: 10)
        try await database.ingest(page([row, row]), capturedAt: date)
        #expect(try await database.earningsByModel(since: date.addingTimeInterval(-3_600)).first?.jobs == 1)
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(2, amount: 20), credit(2, amount: 21)]), capturedAt: date.addingTimeInterval(60))
        }
        #expect(try await database.accountCreditRecords(accountID: "account-A").count == 1)
        #expect(try await database.lastIngestedEarningID() == 1)
    }

    @Test func checkedSwiftAndSQLiteSumsRollBackAllStores() async throws {
        for model in ["qwen", "base_reward"] {
            let database = try EarningsDatabase(url: temporaryURL())
            await #expect(throws: EarningsDatabaseError.self) {
                try await database.ingest(page([credit(1, amount: .max, model: model), credit(2, amount: 1, model: model)]), capturedAt: date)
            }
            #expect(try await database.accountCreditRecords(accountID: "account-A").isEmpty)
            #expect(try await database.accountSampleCount() == 0)
            #expect(try await database.lastIngestedEarningID() == nil)
            try await database.ingest(page([credit(1, amount: .max, model: model)]), capturedAt: date)
            await #expect(throws: EarningsDatabaseError.self) {
                try await database.ingest(page([credit(2, amount: 1, model: model)]), capturedAt: date.addingTimeInterval(60))
            }
            #expect(try await database.accountCreditRecords(accountID: "account-A").count == 1)
            #expect(try await database.lastIngestedEarningID() == 1)
        }
    }

    @Test func boundedQueriesAndReopenPreserveExactRecords() async throws {
        let url = temporaryURL()
        do {
            let database = try EarningsDatabase(url: url)
            try await database.ingest(page([credit(1, amount: 10), credit(2, amount: 20)]), capturedAt: date)
        }
        let reopened = try EarningsDatabase(url: url)
        #expect(try await reopened.accountCreditRecords(accountID: "account-A", limit: 1).map(\.earningID) == [2])
        #expect(try await reopened.accountCreditRecords(accountID: "account-A", from: date, to: date.addingTimeInterval(1)).count == 2)
        #expect(try await reopened.accountCreditRecords(accountID: "account-A", to: date).isEmpty)
        for limit in [0, 5_001] {
            await #expect(throws: EarningsDatabaseError.self) { try await reopened.accountCreditRecords(accountID: "account-A", limit: limit) }
        }
        await #expect(throws: EarningsDatabaseError.self) {
            try await reopened.ingest(page([credit(3, amount: 1, tokens: -1)]), capturedAt: date)
        }
        #expect(try await reopened.accountCreditRecords(accountID: "account-A").count == 2)
    }

    @Test func fractionalTimestampReplayIsUnchangedAfterReopen() async throws {
        let url = temporaryURL()
        let occurred = Date(timeIntervalSince1970: 1_760_000_000).addingTimeInterval(0.000002)
        let captured = occurred.addingTimeInterval(5).addingTimeInterval(0.000003)
        let row = credit(1, amount: 10, at: occurred)
        do {
            let database = try EarningsDatabase(url: url)
            try await database.ingest(page([row]), capturedAt: captured)
            try await database.ingest(page([row]), capturedAt: captured)
            try await database.ingest(page([row]), capturedAt: captured.addingTimeInterval(1))
        }
        let reopened = try EarningsDatabase(url: url)
        try await reopened.ingest(page([row]), capturedAt: captured.addingTimeInterval(2))
        let records = try await reopened.accountCreditRecords(accountID: "account-A")
        let persisted = try #require(records.first)
        #expect(records.count == 1)
        #expect(persisted.createdAt != occurred) // Exercise the Date round-trip difference.
        #expect(persisted.createdAt.timeIntervalSince1970 == occurred.timeIntervalSince1970)
        #expect(persisted.changedAt.timeIntervalSince1970 == captured.timeIntervalSince1970)
        #expect(persisted.firstObservedAt.timeIntervalSince1970 == captured.timeIntervalSince1970)
    }

    @Test func equalTimeConflictRollsBackAnEarlierLateInsertion() async throws {
        let database = try EarningsDatabase(url: temporaryURL())
        try await database.ingest(page([credit(10, amount: 10)]), capturedAt: date)
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(1, amount: 1), credit(10, amount: 99)]), capturedAt: date)
        }
        #expect(try await database.accountCreditRecords(accountID: "account-A").map(\.earningID) == [10])
        #expect(try await database.accountSampleCount() == 1)
        #expect(try await database.lastIngestedEarningID() == 10)
        try await database.ingest(page([credit(10, amount: 0)]), capturedAt: date.addingTimeInterval(1))
        #expect(try await database.accountCreditRecords(accountID: "account-A").first?.amountMicroUSD == 0)
    }

    @Test func negativeAndTokenOverflowAreTransactional() async throws {
        for model in ["qwen", "base_reward"] {
            let database = try EarningsDatabase(url: temporaryURL())
            await #expect(throws: EarningsDatabaseError.self) {
                try await database.ingest(page([credit(1, amount: .min, model: model), credit(2, amount: -1, model: model)]), capturedAt: date)
            }
            #expect(try await database.accountCreditRecords(accountID: "account-A").isEmpty)
            try await database.ingest(page([credit(1, amount: .min, model: model)]), capturedAt: date)
            await #expect(throws: EarningsDatabaseError.self) {
                try await database.ingest(page([credit(2, amount: -1, model: model)]), capturedAt: date.addingTimeInterval(1))
            }
            #expect(try await database.accountCreditRecords(accountID: "account-A").count == 1)
        }
        let database = try EarningsDatabase(url: temporaryURL())
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(1, amount: 1, tokens: .max), credit(2, amount: 1, tokens: 1)]), capturedAt: date)
        }
        #expect(try await database.accountCreditRecords(accountID: "account-A").isEmpty)
        try await database.ingest(page([credit(1, amount: 1, tokens: .max)]), capturedAt: date)
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(2, amount: 1, tokens: 1)]), capturedAt: date.addingTimeInterval(1))
        }
        #expect(try await database.lastIngestedEarningID() == 1)
    }

    @Test func legacyMigrationIsPreservedAndReopenIsIdempotent() async throws {
        let url = temporaryURL()
        try legacyDatabase(url, reward: 10, legacy: 20)
        do {
            let database = try EarningsDatabase(url: url)
            #expect(try await database.rewardEarnings(since: .distantPast).microUSD == 30)
            try await database.ingest(page([credit(1, amount: 5)]), capturedAt: date)
            #expect(try await database.accountCreditRecords(accountID: "account-A").count == 1)
            // Legacy model totals cannot be assigned to this account or reconstructed from this page.
            #expect(try await database.earningsByModel(since: .distantPast).first?.microUSD == 100)
        }
        let reopened = try EarningsDatabase(url: url)
        #expect(try await reopened.rewardEarnings(since: .distantPast).microUSD == 30)
        #expect(try await reopened.rewardEarnings(since: .distantPast).events == 2)
        #expect(try await reopened.accountCreditRecords(accountID: "account-A").count == 1)
    }

    @Test func overflowingMigrationLeavesBothOriginalRowsIntact() throws {
        for (existing, addition) in [(Int64.max, Int64(1)), (Int64.min, Int64(-1))] {
            let url = temporaryURL()
            try legacyDatabase(url, reward: existing, legacy: addition)
            #expect(throws: EarningsDatabaseError.self) { try EarningsDatabase(url: url) }
            #expect(try scalar(url, "SELECT amount_micro_usd FROM rewards_hourly") == existing)
            #expect(try scalar(url, "SELECT amount_micro_usd FROM earnings_hourly WHERE model = 'base_reward'") == addition)
            #expect(try scalar(url, "SELECT COUNT(*) FROM sqlite_master WHERE name = 'account_credit_records'") == 0)
        }
    }

    @Test func invalidBoundsAndUnknownProviderDoNotLoseCredits() async throws {
        let database = try EarningsDatabase(url: temporaryURL())
        try await database.ingest(page([credit(1, amount: 0, provider: "")]), capturedAt: date)
        #expect(try await database.accountCreditRecords(accountID: "account-A", providerID: "").count == 1)
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.accountCreditRecords(accountID: "account-A", from: date, to: date)
        }
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.accountCreditRecords(accountID: "account-A", from: Date(timeIntervalSince1970: .nan))
        }
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(2, amount: 5)]), capturedAt: Date(timeIntervalSince1970: .infinity))
        }
        await #expect(throws: EarningsDatabaseError.self) {
            try await database.ingest(page([credit(2, amount: 5)], account: "account\0invalid"), capturedAt: date)
        }
        #expect(try await database.accountCreditRecords(accountID: "account-A").count == 1)
    }

    @Test func aggregateReadThrowsInsteadOfReturningPartialResults() async throws {
        let database = try EarningsDatabase(url: temporaryURL())
        try await database.ingest(page([credit(1, amount: .max)]), capturedAt: date)
        try await database.ingest(page([credit(2, amount: .max, at: date.addingTimeInterval(3_600))]), capturedAt: date.addingTimeInterval(3_600))
        await #expect(throws: EarningsDatabaseError.self) { try await database.earningsByModel(since: date.addingTimeInterval(-3_600)) }
        #expect(try await database.accountCreditRecords(accountID: "account-A").count == 2)
    }

    private func legacyDatabase(_ url: URL, reward: Int64, legacy: Int64) throws {
        try withSQLite(url) { database in
            let sql = """
                CREATE TABLE earnings_hourly(hour_start REAL, model TEXT, amount_micro_usd INTEGER,
                    jobs INTEGER, prompt_tokens INTEGER, completion_tokens INTEGER, PRIMARY KEY(hour_start, model));
                CREATE TABLE rewards_hourly(hour_start REAL PRIMARY KEY, amount_micro_usd INTEGER, events INTEGER);
                INSERT INTO rewards_hourly VALUES (1998000, \(reward), 1);
                INSERT INTO earnings_hourly VALUES (1998000, 'base_reward', \(legacy), 1, 0, 0);
                INSERT INTO earnings_hourly VALUES (1998000, 'qwen', 100, 1, 10, 10);
                """
            guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw EarningsDatabaseError.sqlite(message: "fixture creation failed") }
        }
    }
    private func scalar(_ url: URL, _ sql: String) throws -> Int64 {
        try withSQLite(url) { database in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw EarningsDatabaseError.sqlite(message: "fixture query failed") }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw EarningsDatabaseError.sqlite(message: "fixture query failed") }
            return sqlite3_column_int64(statement, 0)
        }
    }
    private func withSQLite<T>(_ url: URL, _ operation: (OpaquePointer) throws -> T) throws -> T {
        var pointer: OpaquePointer?
        guard sqlite3_open(url.path, &pointer) == SQLITE_OK, let pointer else { throw EarningsDatabaseError.sqlite(message: "fixture open failed") }
        defer { sqlite3_close(pointer) }
        return try operation(pointer)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bloomy-ledger-test-\(UUID()).sqlite3")
    }
    private func page(_ rows: [AccountEarning], account: String = "account-A") -> AccountEarningsResponse {
        AccountEarningsResponse(accountID: account, earnings: rows, count: 100, historyLimit: 100, recentCount: rows.count)
    }
    private func credit(_ id: Int64, amount: Int64, provider: String = "provider-A", model: String = "qwen",
                        at: Date? = nil, tokens: Int = 10, key: String = "secret-canary") -> AccountEarning {
        AccountEarning(id: id, providerID: provider, providerKey: key, model: model, amountMicroUSD: amount,
                       promptTokens: tokens, completionTokens: tokens, createdAt: at ?? date)
    }
}
