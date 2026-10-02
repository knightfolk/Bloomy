import Foundation
import SQLite3

public enum EnergyHistoryDatabaseError: Error, Equatable, Sendable {
    case unavailable, corruptRecord, conflictingInterval
}

/// Incremental local journal. Legacy JSON remains untouched as the migration
/// backup; migration rows and its marker commit together. Sample continuity is
/// deliberately never persisted, so a relaunch cannot bridge downtime.
public final class EnergyHistoryDatabase: @unchecked Sendable {
    private let lock = NSLock()
    private let connection: EnergySQLiteConnection
    private let url: URL
    private let maximumIntervals: Int
    private var rowCount = 0

    public static func databaseURL(forLegacyFile file: URL) -> URL {
        file.deletingPathExtension().appendingPathExtension("sqlite3")
    }

    public init(url: URL, legacyFile: URL? = nil,
                maximumIntervals: Int = EnergyHistory.maximumIntervals) throws {
        self.url = url
        self.maximumIntervals = min(max(1, maximumIntervals), EnergyHistory.maximumIntervals)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer,
                             SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw EnergyHistoryDatabaseError.unavailable
        }
        connection = EnergySQLiteConnection(pointer)
        sqlite3_busy_timeout(pointer, 2_000)
        guard (0...1).contains(try schemaVersion()) else { throw EnergyHistoryDatabaseError.corruptRecord }
        try makePrivateFiles()
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("""
            CREATE TABLE IF NOT EXISTS energy_intervals (
                start_at REAL PRIMARY KEY NOT NULL,
                end_at REAL NOT NULL,
                payload BLOB NOT NULL
            )
            """)
        try execute("CREATE TABLE IF NOT EXISTS energy_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL)")
        try migrateLegacyIfNeeded(legacyFile)
        rowCount = try countRows()
        _ = try readHistory(limit: EnergyHistory.maximumIntervals)
        try transaction { try prune(extra: rowCount - self.maximumIntervals) }
        rowCount = min(rowCount, self.maximumIntervals)
        try execute("PRAGMA user_version=1")
        try makePrivateFiles()
    }

    public func history() throws -> EnergyHistory {
        lock.lock()
        defer { lock.unlock() }
        return try readHistory(limit: maximumIntervals)
    }

    private func readHistory(limit: Int) throws -> EnergyHistory {
        let statement = try prepare("SELECT start_at, end_at, payload FROM energy_intervals ORDER BY start_at ASC")
        defer { sqlite3_finalize(statement) }
        var rows: [EnergyInterval] = []
        rows.reserveCapacity(min(rowCount, limit))
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_DONE: return try EnergyHistory(restoring: rows)
            case SQLITE_ROW:
                let interval = try decode(statement)
                guard rows.count < limit else { throw EnergyHistoryDatabaseError.corruptRecord }
                rows.append(interval)
            default: throw EnergyHistoryDatabaseError.unavailable
            }
        }
    }

    /// Replay is harmless; changing an existing interval or overlapping the
    /// durable sequence is rejected. A failed transaction never changes rows.
    @discardableResult
    public func append(_ interval: EnergyInterval) throws -> Bool {
        _ = try EnergyHistory(restoring: [interval])
        lock.lock()
        defer { lock.unlock() }
        var inserted = false
        var committedCount = rowCount
        try transaction {
            if let existing = try intervalStarting(at: interval.start) {
                guard existing == interval else { throw EnergyHistoryDatabaseError.conflictingInterval }
                return
            }
            let latest = try prepare("SELECT end_at FROM energy_intervals ORDER BY start_at DESC LIMIT 1")
            defer { sqlite3_finalize(latest) }
            switch sqlite3_step(latest) {
            case SQLITE_ROW:
                guard interval.start.timeIntervalSince1970 >= sqlite3_column_double(latest, 0) else {
                    throw EnergyHistoryDatabaseError.conflictingInterval
                }
            case SQLITE_DONE: break
            default: throw EnergyHistoryDatabaseError.unavailable
            }
            let count = try countRows()
            try insert(interval)
            try prune(extra: count + 1 - maximumIntervals)
            try makePrivateFiles()
            inserted = true
            committedCount = min(count + 1, maximumIntervals)
        }
        if inserted { rowCount = committedCount }
        return inserted
    }

    private func migrateLegacyIfNeeded(_ legacyFile: URL?) throws {
        let marker = try prepare("SELECT value FROM energy_metadata WHERE key = 'legacy_json_imported'")
        defer { sqlite3_finalize(marker) }
        switch sqlite3_step(marker) {
        case SQLITE_ROW:
            guard sqlite3_column_text(marker, 0).map({ String(cString: $0) }) == "1" else {
                throw EnergyHistoryDatabaseError.corruptRecord
            }
            return
        case SQLITE_DONE: break
        default: throw EnergyHistoryDatabaseError.unavailable
        }
        // Validate the entire source before beginning any imported writes.
        let legacy = try legacyFile.map { try EnergyHistoryFile.read(from: $0) } ?? EnergyHistory()
        guard try countRows() == 0 else { throw EnergyHistoryDatabaseError.corruptRecord }
        try transaction {
            for interval in legacy.intervals.suffix(maximumIntervals) { try insert(interval) }
            try execute("INSERT INTO energy_metadata (key, value) VALUES ('legacy_json_imported', '1')")
            try makePrivateFiles()
        }
    }

    private func insert(_ interval: EnergyInterval) throws {
        let statement = try prepare("INSERT INTO energy_intervals (start_at, end_at, payload) VALUES (?, ?, ?)")
        defer { sqlite3_finalize(statement) }
        let payload = try JSONEncoder().encode(interval)
        guard payload.count <= EnergyHistoryFile.maximumBytes else { throw EnergyHistoryDatabaseError.corruptRecord }
        try checked(sqlite3_bind_double(statement, 1, interval.start.timeIntervalSince1970))
        try checked(sqlite3_bind_double(statement, 2, interval.end.timeIntervalSince1970))
        try payload.withUnsafeBytes {
            try checked(sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), energySQLiteTransient))
        }
        guard sqlite3_step(statement) == SQLITE_DONE else { throw EnergyHistoryDatabaseError.unavailable }
    }

    private func intervalStarting(at date: Date) throws -> EnergyInterval? {
        let statement = try prepare("SELECT start_at, end_at, payload FROM energy_intervals WHERE start_at = ?")
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_bind_double(statement, 1, date.timeIntervalSince1970))
        switch sqlite3_step(statement) {
        case SQLITE_ROW: return try decode(statement)
        case SQLITE_DONE: return nil
        default: throw EnergyHistoryDatabaseError.unavailable
        }
    }

    private func decode(_ statement: OpaquePointer) throws -> EnergyInterval {
        let bytes = Int(sqlite3_column_bytes(statement, 2))
        guard bytes > 0, bytes <= EnergyHistoryFile.maximumBytes,
              let pointer = sqlite3_column_blob(statement, 2) else { throw EnergyHistoryDatabaseError.corruptRecord }
        do {
            let interval = try JSONDecoder().decode(EnergyInterval.self, from: Data(bytes: pointer, count: bytes))
            guard interval.start.timeIntervalSince1970 == sqlite3_column_double(statement, 0),
                  interval.end.timeIntervalSince1970 == sqlite3_column_double(statement, 1) else {
                throw EnergyHistoryDatabaseError.corruptRecord
            }
            _ = try EnergyHistory(restoring: [interval])
            return interval
        } catch { throw EnergyHistoryDatabaseError.corruptRecord }
    }

    private func countRows() throws -> Int {
        let statement = try prepare("SELECT COUNT(*) FROM energy_intervals")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw EnergyHistoryDatabaseError.unavailable }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func schemaVersion() throws -> Int32 {
        let statement = try prepare("PRAGMA user_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw EnergyHistoryDatabaseError.unavailable }
        return sqlite3_column_int(statement, 0)
    }

    private func prune(extra: Int) throws {
        guard extra > 0 else { return }
        let statement = try prepare("DELETE FROM energy_intervals WHERE start_at IN (SELECT start_at FROM energy_intervals ORDER BY start_at ASC LIMIT ?)")
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_bind_int64(statement, 1, Int64(extra)))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw EnergyHistoryDatabaseError.unavailable }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try work(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw EnergyHistoryDatabaseError.unavailable }
        return statement
    }
    private func checked(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw EnergyHistoryDatabaseError.unavailable }
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection.pointer, sql, nil, nil, nil) == SQLITE_OK else {
            throw EnergyHistoryDatabaseError.unavailable
        }
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

private final class EnergySQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(_ pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}
private let energySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
