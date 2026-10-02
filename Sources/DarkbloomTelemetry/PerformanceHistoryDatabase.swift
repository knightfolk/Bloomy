import Foundation
import SQLite3

public enum PerformanceHistoryDatabaseError: Error, Equatable, LocalizedError, Sendable {
    case unavailable, invalidSample, conflictingID, corruptRecord, invalidInterval

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Local performance history is unavailable."
        case .invalidSample: "Performance history rejected invalid measurement data."
        case .conflictingID: "Performance history found a conflicting sample identifier."
        case .corruptRecord: "Local performance history contains an unreadable entry."
        case .invalidInterval: "Performance history rejected an invalid time range."
        }
    }
}

/// A local SQLite journal with explicit storage errors and a fixed retention
/// ceiling. Synchronous calls are serialized across threads with one lock.
public final class PerformanceHistoryDatabase: @unchecked Sendable {
    public static let maximumHistoryLimit = 100_000
    public static let maximumRetentionDays = 30
    private static let maximumPayloadBytes = 100_000
    private let lock = NSLock()
    private let connection: PerformanceHistorySQLiteConnection
    private let url: URL
    private let historyLimit: Int
    private let retentionDays: Int
    private let now: @Sendable () -> Date

    public init(
        url: URL, historyLimit: Int = maximumHistoryLimit,
        retentionDays: Int = maximumRetentionDays,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        self.url = url
        self.historyLimit = min(max(historyLimit, 1), Self.maximumHistoryLimit)
        self.retentionDays = min(max(retentionDays, 1), Self.maximumRetentionDays)
        self.now = now
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer,
                             SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw PerformanceHistoryDatabaseError.unavailable
        }
        connection = PerformanceHistorySQLiteConnection(pointer: pointer)
        sqlite3_busy_timeout(pointer, 2_000)
        try makePrivateFiles()
        try Self.execute(pointer, "PRAGMA journal_mode=WAL")
        try Self.execute(pointer, "PRAGMA synchronous=NORMAL")
        try Self.execute(pointer, "PRAGMA secure_delete=ON")
        try Self.execute(pointer, """
            CREATE TABLE IF NOT EXISTS performance_history (
                id TEXT PRIMARY KEY NOT NULL,
                observed_at REAL NOT NULL,
                model TEXT,
                sample BLOB NOT NULL
            )
            """)
        try Self.execute(pointer, """
            CREATE INDEX IF NOT EXISTS performance_history_observed_at
            ON performance_history (observed_at, id)
            """)
        try Self.execute(pointer, """
            CREATE INDEX IF NOT EXISTS performance_history_model_observed_at
            ON performance_history (model, observed_at, id)
            """)
        try makePrivateFiles()
        try prune()
    }

    public convenience init(
        path: String, retentionDays: Int = maximumRetentionDays,
        maximumRows: Int = maximumHistoryLimit
    ) throws {
        try self.init(url: URL(fileURLWithPath: path), historyLimit: maximumRows, retentionDays: retentionDays)
    }

    /// IDs are immutable. Replaying an identical sample is harmless; changing
    /// any measurement under an existing ID is an explicit conflict.
    public func record(_ sample: PerformanceSample) throws {
        guard sample.isValid else { throw PerformanceHistoryDatabaseError.invalidSample }
        let payload = try Self.encode(sample)
        guard payload.count <= Self.maximumPayloadBytes else { throw PerformanceHistoryDatabaseError.invalidSample }
        lock.lock()
        defer { lock.unlock() }
        let time = now()
        guard PerformanceSample.validTimestamp(time), sample.observedAt <= time.addingTimeInterval(86_400) else {
            throw PerformanceHistoryDatabaseError.invalidSample
        }
        try transaction {
            let statement = try prepare("INSERT OR IGNORE INTO performance_history (id, observed_at, model, sample) VALUES (?, ?, ?, ?)")
            defer { sqlite3_finalize(statement) }
            try bind(sample.id.uuidString, statement, 1)
            try checked(sqlite3_bind_double(statement, 2, sample.observedAt.timeIntervalSince1970))
            try bind(sample.model, statement, 3)
            try payload.withUnsafeBytes {
                try checked(sqlite3_bind_blob(statement, 4, $0.baseAddress, Int32($0.count), performanceHistorySQLiteTransient))
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw PerformanceHistoryDatabaseError.unavailable }
            if sqlite3_changes(connection.pointer) == 0 {
                let existing = try prepare("SELECT id, observed_at, model, sample FROM performance_history WHERE id = ?")
                defer { sqlite3_finalize(existing) }
                try bind(sample.id.uuidString, existing, 1)
                guard sqlite3_step(existing) == SQLITE_ROW else { throw PerformanceHistoryDatabaseError.unavailable }
                guard try Self.encode(decode(existing)) == payload else { throw PerformanceHistoryDatabaseError.conflictingID }
            }
            try prune(at: time)
            try makePrivateFiles()
        }
    }

    /// Chronological order, including unavailable/stale rows so callers can
    /// show gaps. Model filters refer only to the serving model on the sample.
    public func samples(in interval: DateInterval, model: String? = nil) throws -> [PerformanceSample] {
        guard PerformanceSample.validTimestamp(interval.start), PerformanceSample.validTimestamp(interval.end),
              interval.duration.isFinite, interval.duration >= 0 else { throw PerformanceHistoryDatabaseError.invalidInterval }
        if let model, !PerformanceSample(model: model).isValid { throw PerformanceHistoryDatabaseError.invalidSample }
        lock.lock()
        defer { lock.unlock() }
        try prune()
        let statement = try prepare("""
            SELECT id, observed_at, model, sample FROM performance_history
            WHERE observed_at >= ? AND observed_at <= ?
            \(model == nil ? "" : "AND model = ?")
            ORDER BY observed_at ASC, rowid ASC
            """)
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_bind_double(statement, 1, interval.start.timeIntervalSince1970))
        try checked(sqlite3_bind_double(statement, 2, interval.end.timeIntervalSince1970))
        if let model { try bind(model, statement, 3) }
        return try rows(statement)
    }

    /// Newest measurements first.
    public func recent(limit: Int = 100) throws -> [PerformanceSample] {
        lock.lock()
        defer { lock.unlock() }
        try prune()
        let count = min(max(limit, 0), historyLimit)
        guard count > 0 else { return [] }
        let statement = try prepare("SELECT id, observed_at, model, sample FROM performance_history ORDER BY observed_at DESC, rowid DESC LIMIT ?")
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_bind_int64(statement, 1, Int64(count)))
        return try rows(statement)
    }

    public func retainedRecordCount() throws -> Int {
        lock.lock()
        defer { lock.unlock() }
        try prune()
        let statement = try prepare("SELECT COUNT(*) FROM performance_history")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw PerformanceHistoryDatabaseError.unavailable }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func rows(_ statement: OpaquePointer) throws -> [PerformanceSample] {
        var result: [PerformanceSample] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return result
            case SQLITE_ROW: result.append(try decode(statement))
            default: throw PerformanceHistoryDatabaseError.unavailable
            }
        }
    }

    private func decode(_ statement: OpaquePointer) throws -> PerformanceSample {
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              sqlite3_column_type(statement, 1) == SQLITE_FLOAT || sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
              sqlite3_column_type(statement, 2) == SQLITE_NULL || sqlite3_column_type(statement, 2) == SQLITE_TEXT,
              sqlite3_column_type(statement, 3) == SQLITE_BLOB,
              let idText = text(statement, 0), let id = UUID(uuidString: idText),
              let bytes = sqlite3_column_blob(statement, 3) else { throw PerformanceHistoryDatabaseError.corruptRecord }
        let size = Int(sqlite3_column_bytes(statement, 3))
        guard size > 0, size <= Self.maximumPayloadBytes else { throw PerformanceHistoryDatabaseError.corruptRecord }
        let payload = Data(bytes: bytes, count: size)
        guard let sample = try? JSONDecoder().decode(PerformanceSample.self, from: payload), sample.isValid,
              sample.id == id, sample.observedAt.timeIntervalSince1970 == sqlite3_column_double(statement, 1),
              sample.model == text(statement, 2) else { throw PerformanceHistoryDatabaseError.corruptRecord }
        return sample
    }

    private func prune() throws {
        try transaction { try prune(at: now()); try makePrivateFiles() }
    }

    private func prune(at time: Date) throws {
        guard PerformanceSample.validTimestamp(time) else { throw PerformanceHistoryDatabaseError.unavailable }
        let statement = try prepare("""
            DELETE FROM performance_history WHERE observed_at < ?
            """)
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_bind_double(statement, 1, time.addingTimeInterval(-Double(retentionDays) * 86_400).timeIntervalSince1970))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw PerformanceHistoryDatabaseError.unavailable }
        // Select only overflow rows, instead of rebuilding a 100k-ID membership
        // set and scanning every payload on each periodic write.
        let overflow = try prepare("""
            DELETE FROM performance_history WHERE rowid IN (
                SELECT rowid FROM performance_history
                ORDER BY observed_at DESC, rowid DESC LIMIT -1 OFFSET ?
            )
            """)
        defer { sqlite3_finalize(overflow) }
        try checked(sqlite3_bind_int64(overflow, 1, Int64(historyLimit)))
        guard sqlite3_step(overflow) == SQLITE_DONE else { throw PerformanceHistoryDatabaseError.unavailable }
    }

    private func transaction(_ operation: () throws -> Void) throws {
        try Self.execute(connection.pointer, "BEGIN IMMEDIATE")
        do {
            try operation()
            try Self.execute(connection.pointer, "COMMIT")
        } catch {
            try? Self.execute(connection.pointer, "ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let result = sqlite3_prepare_v2(connection.pointer, sql, -1, &statement, nil)
        guard result == SQLITE_OK, let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw PerformanceHistoryDatabaseError.unavailable
        }
        return statement
    }

    private func checked(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw PerformanceHistoryDatabaseError.unavailable }
    }

    private func bind(_ value: String?, _ statement: OpaquePointer, _ index: Int32) throws {
        if let value {
            try checked(sqlite3_bind_text(statement, index, value, -1, performanceHistorySQLiteTransient))
        } else { try checked(sqlite3_bind_null(statement, index)) }
    }

    private func text(_ statement: OpaquePointer, _ index: Int32) -> String? {
        guard let bytes = sqlite3_column_text(statement, index) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, index))
        return String(bytes: UnsafeBufferPointer(start: bytes, count: count), encoding: .utf8)
    }

    private static func encode(_ sample: PerformanceSample) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(sample)
    }

    private static func execute(_ pointer: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK else { throw PerformanceHistoryDatabaseError.unavailable }
    }

    private func makePrivateFiles() throws {
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
            }
        }
    }
}

private final class PerformanceHistorySQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

private let performanceHistorySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
