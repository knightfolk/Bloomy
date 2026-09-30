import Foundation
import SQLite3

public enum ActionHistoryDatabaseError: Error, Equatable, LocalizedError, Sendable {
    case unavailable
    case invalidEvent
    case missingEvent
    case invalidTransition
    case conflictingID
    case corruptRecord

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Local action history is unavailable."
        case .invalidEvent: "Action history rejected invalid event data."
        case .missingEvent: "The action history entry no longer exists."
        case .invalidTransition: "Action history rejected an out-of-order outcome."
        case .conflictingID: "Action history found a conflicting event identifier."
        case .corruptRecord: "Local action history contains an unreadable entry."
        }
    }
}

/// A private, bounded SQLite journal for user actions and observed account
/// earnings. The lock serializes synchronous calls across threads. Callers
/// receive storage failures rather than silently losing an action.
public final class ActionHistoryDatabase: @unchecked Sendable {
    public static let maximumHistoryLimit = 5_000
    public static let maximumRetentionDays = 30

    private let lock = NSLock()
    private let connection: ActionHistorySQLiteConnection
    private let historyLimit: Int
    private let retentionDays: Int
    private let now: @Sendable () -> Date

    public init(
        url: URL,
        historyLimit: Int = maximumHistoryLimit,
        retentionDays: Int = maximumRetentionDays,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw ActionHistoryDatabaseError.unavailable
        }
        connection = ActionHistorySQLiteConnection(pointer: database)
        self.historyLimit = min(max(historyLimit, 1), Self.maximumHistoryLimit)
        self.retentionDays = min(max(retentionDays, 1), Self.maximumRetentionDays)
        self.now = now
        sqlite3_busy_timeout(database, 2_000)

        // Make the main file private before WAL mode can create sidecars. On
        // reopen, tighten any sidecars left by an older run as well.
        try Self.makePrivate(url)
        try Self.makePrivateIfPresent(URL(fileURLWithPath: url.path + "-wal"))
        try Self.makePrivateIfPresent(URL(fileURLWithPath: url.path + "-shm"))
        try Self.execute(database, "PRAGMA journal_mode=WAL")
        try Self.execute(database, "PRAGMA synchronous=NORMAL")
        try Self.execute(database, "PRAGMA secure_delete=ON")
        try Self.execute(database, """
            CREATE TABLE IF NOT EXISTS action_history (
                id TEXT PRIMARY KEY,
                occurred_at REAL NOT NULL,
                updated_at REAL NOT NULL,
                action TEXT NOT NULL,
                trigger TEXT NOT NULL,
                outcome TEXT NOT NULL,
                model TEXT,
                reason TEXT,
                correlation_id TEXT,
                earning_id INTEGER,
                prompt_tokens INTEGER,
                completion_tokens INTEGER,
                amount_micro_usd INTEGER
            )
            """)
        try Self.execute(database, """
            CREATE INDEX IF NOT EXISTS action_history_occurred_at
            ON action_history (occurred_at DESC, id)
            """)
        try Self.makePrivate(url)
        try Self.makePrivateIfPresent(URL(fileURLWithPath: url.path + "-wal"))
        try Self.makePrivateIfPresent(URL(fileURLWithPath: url.path + "-shm"))
    }

    public func record(_ event: ActionHistoryEvent) throws {
        guard Self.isValid(event, now: now()) else {
            throw ActionHistoryDatabaseError.invalidEvent
        }
        lock.lock()
        defer { lock.unlock() }
        let database = connection.pointer
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let statement = try prepare("""
                INSERT OR IGNORE INTO action_history
                    (id, occurred_at, updated_at, action, trigger, outcome,
                     model, reason, correlation_id, earning_id, prompt_tokens,
                     completion_tokens, amount_micro_usd)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }
            bind(event.id.uuidString, to: statement, at: 1)
            sqlite3_bind_double(statement, 2, event.occurredAt.timeIntervalSince1970)
            sqlite3_bind_double(statement, 3, event.updatedAt.timeIntervalSince1970)
            bind(event.action.rawValue, to: statement, at: 4)
            bind(event.trigger.rawValue, to: statement, at: 5)
            bind(event.outcome.rawValue, to: statement, at: 6)
            bind(event.model, to: statement, at: 7)
            bind(event.reason?.rawValue, to: statement, at: 8)
            bind(event.correlationID?.uuidString, to: statement, at: 9)
            bind(event.job?.earningID, to: statement, at: 10)
            bind(event.job?.promptTokens, to: statement, at: 11)
            bind(event.job?.completionTokens, to: statement, at: 12)
            bind(event.job?.amountMicroUSD, to: statement, at: 13)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw ActionHistoryDatabaseError.unavailable
            }
            if sqlite3_changes(database) == 0 {
                guard let existing = try fetch(id: event.id), Self.sameIdentity(existing, event) else {
                    throw ActionHistoryDatabaseError.conflictingID
                }
                if existing.job != event.job {
                    if event.updatedAt > existing.updatedAt {
                        try correctJob(event)
                    } else if event.updatedAt == existing.updatedAt {
                        throw ActionHistoryDatabaseError.conflictingID
                    }
                }
            }
            try prune(at: now())
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
    }

    /// Completes a started entry. An unconfirmed outcome may later become a
    /// confirmed success or failure. A replay of the same final result is safe.
    public func updateOutcome(
        id: UUID,
        outcome: ActionHistoryOutcome,
        reason: ActionHistoryReason? = nil,
        updatedAt: Date = Date()
    ) throws {
        guard outcome != .started, Self.isValidTimestamp(updatedAt.timeIntervalSince1970),
              updatedAt.timeIntervalSince1970 <= now().timeIntervalSince1970 + 86_400 else {
            throw ActionHistoryDatabaseError.invalidEvent
        }
        lock.lock()
        defer { lock.unlock() }
        guard let existing = try fetch(id: id) else {
            throw ActionHistoryDatabaseError.missingEvent
        }
        if existing.outcome == outcome && existing.reason == reason { return }
        guard existing.outcome == .started || existing.outcome == .unconfirmed,
              updatedAt >= existing.updatedAt else {
            throw ActionHistoryDatabaseError.invalidTransition
        }
        let statement = try prepare("""
            UPDATE action_history SET outcome = ?, reason = ?, updated_at = ? WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        bind(outcome.rawValue, to: statement, at: 1)
        bind(reason?.rawValue, to: statement, at: 2)
        sqlite3_bind_double(statement, 3, updatedAt.timeIntervalSince1970)
        bind(id.uuidString, to: statement, at: 4)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ActionHistoryDatabaseError.unavailable
        }
    }

    /// Newest entries first. Reading also applies age retention after a long
    /// app shutdown, so expired history does not reappear at the next launch.
    public func recent(limit: Int = 100) throws -> [ActionHistoryEvent] {
        lock.lock()
        defer { lock.unlock() }
        try prune(at: now())
        let count = min(max(limit, 0), historyLimit)
        guard count > 0 else { return [] }
        let statement = try prepare("""
            SELECT id, occurred_at, updated_at, action, trigger, outcome,
                   model, reason, correlation_id, earning_id, prompt_tokens,
                   completion_tokens, amount_micro_usd
            FROM action_history ORDER BY occurred_at DESC, rowid DESC LIMIT ?
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(count))
        var result: [ActionHistoryEvent] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { return result }
            guard step == SQLITE_ROW else { throw ActionHistoryDatabaseError.unavailable }
            result.append(try decode(statement))
        }
    }

    public func retainedRecordCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        try prune(at: now())
        let statement = try prepare("SELECT COUNT(*) FROM action_history")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw ActionHistoryDatabaseError.unavailable }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func fetch(id: UUID) throws -> ActionHistoryEvent? {
        let statement = try prepare("""
            SELECT id, occurred_at, updated_at, action, trigger, outcome,
                   model, reason, correlation_id, earning_id, prompt_tokens,
                   completion_tokens, amount_micro_usd
            FROM action_history WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        bind(id.uuidString, to: statement, at: 1)
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return try decode(statement)
        case SQLITE_DONE: return nil
        default: throw ActionHistoryDatabaseError.unavailable
        }
    }

    private func decode(_ statement: OpaquePointer) throws -> ActionHistoryEvent {
        guard let idText = text(statement, at: 0), let id = UUID(uuidString: idText),
              sqlite3_column_type(statement, 1) != SQLITE_NULL,
              sqlite3_column_type(statement, 2) != SQLITE_NULL,
              let actionText = text(statement, at: 3),
              let action = ActionHistoryAction(rawValue: actionText),
              let triggerText = text(statement, at: 4),
              let trigger = ActionHistoryTrigger(rawValue: triggerText),
              let outcomeText = text(statement, at: 5),
              let outcome = ActionHistoryOutcome(rawValue: outcomeText) else {
            throw ActionHistoryDatabaseError.corruptRecord
        }
        let model = text(statement, at: 6)
        let reasonText = text(statement, at: 7)
        let reason = reasonText.flatMap(ActionHistoryReason.init(rawValue:))
        let correlationText = text(statement, at: 8)
        let correlationID = correlationText.flatMap(UUID.init(uuidString:))
        if (reasonText != nil && reason == nil) || (correlationText != nil && correlationID == nil) {
            throw ActionHistoryDatabaseError.corruptRecord
        }
        let hasJobColumn = (9...12).map { sqlite3_column_type(statement, Int32($0)) != SQLITE_NULL }
        guard hasJobColumn.allSatisfy({ $0 }) || hasJobColumn.allSatisfy({ !$0 }) else {
            throw ActionHistoryDatabaseError.corruptRecord
        }
        let job = hasJobColumn[0] ? ActionHistoryJob(
            earningID: sqlite3_column_int64(statement, 9),
            promptTokens: sqlite3_column_int64(statement, 10),
            completionTokens: sqlite3_column_int64(statement, 11),
            amountMicroUSD: sqlite3_column_int64(statement, 12)
        ) : nil
        let event = ActionHistoryEvent(
            id: id,
            occurredAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
            updatedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 2)),
            action: action,
            trigger: trigger,
            outcome: outcome,
            model: model,
            reason: reason,
            correlationID: correlationID,
            job: job
        )
        guard Self.isValid(event, now: nil) else { throw ActionHistoryDatabaseError.corruptRecord }
        return event
    }

    private func prune(at time: Date) throws {
        guard Self.isValidTimestamp(time.timeIntervalSince1970) else {
            throw ActionHistoryDatabaseError.unavailable
        }
        let statement = try prepare("""
            DELETE FROM action_history WHERE occurred_at < ?
               OR id NOT IN (
                   SELECT id FROM action_history
                   ORDER BY occurred_at DESC, rowid DESC LIMIT ?
               )
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, time.addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970)
        sqlite3_bind_int64(statement, 2, Int64(historyLimit))
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ActionHistoryDatabaseError.unavailable
        }
    }

    private func correctJob(_ event: ActionHistoryEvent) throws {
        guard (event.action == .job || event.action == .baseReward), let job = event.job else {
            throw ActionHistoryDatabaseError.conflictingID
        }
        let statement = try prepare("""
            UPDATE action_history
            SET earning_id = ?, prompt_tokens = ?, completion_tokens = ?,
                amount_micro_usd = ?, updated_at = ?
            WHERE id = ?
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, job.earningID)
        sqlite3_bind_int64(statement, 2, job.promptTokens)
        sqlite3_bind_int64(statement, 3, job.completionTokens)
        sqlite3_bind_int64(statement, 4, job.amountMicroUSD)
        sqlite3_bind_double(statement, 5, event.updatedAt.timeIntervalSince1970)
        bind(event.id.uuidString, to: statement, at: 6)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw ActionHistoryDatabaseError.unavailable
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw ActionHistoryDatabaseError.unavailable }
        return statement
    }

    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, actionHistorySQLiteTransient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func bind(_ value: Int64?, to statement: OpaquePointer, at index: Int32) {
        if let value {
            sqlite3_bind_int64(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    private func text(_ statement: OpaquePointer, at index: Int32) -> String? {
        guard let value = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: value)
    }

    private static func sameIdentity(_ first: ActionHistoryEvent, _ second: ActionHistoryEvent) -> Bool {
        // SQLite persists Unix-epoch REAL. Converting that Double back to
        // Date can shift its reference-epoch representation by a fraction of
        // a microsecond, even when the stored timestamp is unchanged.
        first.id == second.id
            && first.occurredAt.timeIntervalSince1970 == second.occurredAt.timeIntervalSince1970
            && first.action == second.action && first.trigger == second.trigger
            && first.model == second.model && first.correlationID == second.correlationID
            && first.job?.earningID == second.job?.earningID
    }

    private static func isValid(_ event: ActionHistoryEvent, now: Date?) -> Bool {
        let occurred = event.occurredAt.timeIntervalSince1970
        let updated = event.updatedAt.timeIntervalSince1970
        guard isValidTimestamp(occurred), isValidTimestamp(updated), updated >= occurred else { return false }
        if let now, occurred > now.timeIntervalSince1970 + 86_400 { return false }
        if let model = event.model {
            guard !model.isEmpty, model.utf8.count <= 160,
                  model.unicodeScalars.allSatisfy({
                      CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/+-")
                          .contains($0)
                  }) else { return false }
        }
        if let job = event.job {
            guard event.action == .job || event.action == .baseReward,
                  job.earningID > 0, job.promptTokens >= 0,
                  job.completionTokens >= 0, job.amountMicroUSD >= 0 else { return false }
        } else if event.action == .job || event.action == .baseReward {
            return false
        }
        return true
    }

    private static func isValidTimestamp(_ value: TimeInterval) -> Bool {
        value.isFinite && (0...253_402_300_799).contains(value)
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw ActionHistoryDatabaseError.unavailable
        }
    }

    private static func makePrivate(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func makePrivateIfPresent(_ url: URL) throws {
        if FileManager.default.fileExists(atPath: url.path) {
            try makePrivate(url)
        }
    }
}

private final class ActionHistorySQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

private let actionHistorySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
