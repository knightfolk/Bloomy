import Foundation
import SQLite3

public enum AlertHistoryDatabaseError: Error, LocalizedError, Sendable {
    case sqlite(message: String)
    case invalidTransition

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): "Local alert-history database error — \(message)"
        case .invalidTransition: "Alert transition contains invalid bounded evidence."
        }
    }
}

/// A small private SQLite journal. Both historical rows and active dedupe
/// state survive app restarts; retained rows contain fixed codes and bounded
/// numeric evidence only.
public actor AlertHistoryDatabase: AlertHistoryRecording {
    public static let maximumHistoryLimit = 2_000

    private let connection: AlertHistorySQLiteConnection
    private let historyLimit: Int

    public init(url: URL, historyLimit: Int = 500) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw AlertHistoryDatabaseError.sqlite(message: "could not open database")
        }
        connection = AlertHistorySQLiteConnection(pointer: database)
        self.historyLimit = min(max(historyLimit, 1), Self.maximumHistoryLimit)
        sqlite3_busy_timeout(database, 2_000)

        do {
            try Self.execute(database, sql: "PRAGMA journal_mode=WAL")
            try Self.execute(database, sql: "PRAGMA synchronous=NORMAL")
            try Self.execute(database, sql: """
                CREATE TABLE IF NOT EXISTS alert_history (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    code TEXT NOT NULL,
                    transition TEXT NOT NULL,
                    occurred_at REAL NOT NULL,
                    observed_duration_seconds INTEGER,
                    observation_count INTEGER NOT NULL,
                    UNIQUE (code, transition, occurred_at)
                )
                """)
            try Self.execute(database, sql: """
                CREATE TABLE IF NOT EXISTS active_alerts (
                    code TEXT PRIMARY KEY,
                    raised_at REAL NOT NULL
                )
                """)
            try Self.execute(database, sql: """
                CREATE INDEX IF NOT EXISTS alert_history_occurred_at
                ON alert_history (occurred_at, id)
                """)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw error
        }
    }

    public func record(_ transitions: [AlertTransition]) throws {
        guard !transitions.isEmpty else { return }
        guard transitions.allSatisfy(Self.isValid) else {
            throw AlertHistoryDatabaseError.invalidTransition
        }

        let database = connection.pointer
        try Self.execute(database, sql: "BEGIN IMMEDIATE")
        do {
            for transition in transitions {
                try insert(transition, into: database)
            }
            try prune()
            try Self.execute(database, sql: "COMMIT")
        } catch {
            try? Self.execute(database, sql: "ROLLBACK")
            throw error
        }
    }

    public func recentHistory(limit: Int = 100) throws -> [AlertRecord] {
        let boundedLimit = min(max(limit, 0), historyLimit)
        guard boundedLimit > 0 else { return [] }
        let statement = try prepare("""
            SELECT id, code, transition, occurred_at,
                   observed_duration_seconds, observation_count
            FROM (
                SELECT id, code, transition, occurred_at,
                       observed_duration_seconds, observation_count
                FROM alert_history ORDER BY id DESC LIMIT ?
            ) ORDER BY id ASC
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(boundedLimit))

        var rows: [AlertRecord] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw lastError() }
            guard let codeValue = columnText(statement, 1),
                  let code = OperationalAlertCode(rawValue: codeValue),
                  let kindValue = columnText(statement, 2),
                  let kind = AlertTransitionKind(rawValue: kindValue) else { continue }
            let timestamp = sqlite3_column_double(statement, 3)
            let observationCount = sqlite3_column_int64(statement, 5)
            let duration: Int? = sqlite3_column_type(statement, 4) == SQLITE_NULL
                ? nil : Int(sqlite3_column_int64(statement, 4))
            guard Self.isValidTimestamp(timestamp),
                  (1...1_000_000).contains(observationCount),
                  (duration.map { (0...86_400).contains($0) } ?? true) else { continue }
            rows.append(AlertRecord(
                id: sqlite3_column_int64(statement, 0),
                code: code,
                kind: kind,
                occurredAt: Date(timeIntervalSince1970: timestamp),
                observedDurationSeconds: duration,
                observationCount: Int(observationCount)
            ))
        }
        return rows
    }

    public func activeAlertCodes() throws -> Set<OperationalAlertCode> {
        let statement = try prepare("SELECT code FROM active_alerts ORDER BY code")
        defer { sqlite3_finalize(statement) }
        var result: Set<OperationalAlertCode> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let value = columnText(statement, 0),
                  let code = OperationalAlertCode(rawValue: value) else { continue }
            result.insert(code)
        }
        return result
    }

    public func retainedRecordCount() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM alert_history")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func insert(_ transition: AlertTransition, into database: OpaquePointer) throws {
        let statement = try prepare("""
            INSERT OR IGNORE INTO alert_history
                (code, transition, occurred_at, observed_duration_seconds, observation_count)
            VALUES (?, ?, ?, ?, ?)
            """)
        defer { sqlite3_finalize(statement) }
        bind(transition.code.rawValue, to: statement, at: 1)
        bind(transition.kind.rawValue, to: statement, at: 2)
        sqlite3_bind_double(statement, 3, transition.occurredAt.timeIntervalSince1970)
        if let duration = transition.observedDurationSeconds {
            sqlite3_bind_int64(statement, 4, Int64(duration))
        } else {
            sqlite3_bind_null(statement, 4)
        }
        sqlite3_bind_int64(statement, 5, Int64(transition.observationCount))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        guard sqlite3_changes(database) == 1 else { return }

        switch transition.kind {
        case .raised:
            let active = try prepare("""
                INSERT INTO active_alerts (code, raised_at) VALUES (?, ?)
                ON CONFLICT(code) DO NOTHING
                """)
            defer { sqlite3_finalize(active) }
            bind(transition.code.rawValue, to: active, at: 1)
            sqlite3_bind_double(active, 2, transition.occurredAt.timeIntervalSince1970)
            guard sqlite3_step(active) == SQLITE_DONE else { throw lastError() }
        case .recovered, .suppressed:
            let inactive = try prepare("DELETE FROM active_alerts WHERE code = ?")
            defer { sqlite3_finalize(inactive) }
            bind(transition.code.rawValue, to: inactive, at: 1)
            guard sqlite3_step(inactive) == SQLITE_DONE else { throw lastError() }
        }
    }

    private func prune() throws {
        let statement = try prepare("""
            DELETE FROM alert_history
            WHERE id NOT IN (
                SELECT id FROM alert_history ORDER BY id DESC LIMIT ?
            )
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(historyLimit))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        // VACUUM would make every write expensive. SQLite reuses the bounded
        // free pages in this table, keeping retained history capped in rows.
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw lastError() }
        return statement
    }

    private func bind(_ value: String, to statement: OpaquePointer, at index: Int32) {
        sqlite3_bind_text(statement, index, value, -1, alertHistorySQLiteTransient)
    }

    private func columnText(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private func lastError() -> AlertHistoryDatabaseError {
        .sqlite(message: String(cString: sqlite3_errmsg(connection.pointer)))
    }

    private static func isValid(_ transition: AlertTransition) -> Bool {
        let timestamp = transition.occurredAt.timeIntervalSince1970
        guard isValidTimestamp(timestamp),
              (1...1_000_000).contains(transition.observationCount) else { return false }
        if let duration = transition.observedDurationSeconds {
            return (0...86_400).contains(duration)
        }
        return true
    }

    private static func isValidTimestamp(_ timestamp: TimeInterval) -> Bool {
        timestamp.isFinite && (-62_135_596_800...253_402_300_799).contains(timestamp)
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite failure"
            sqlite3_free(errorMessage)
            throw AlertHistoryDatabaseError.sqlite(message: message)
        }
    }
}

private let alertHistorySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private final class AlertHistorySQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}
