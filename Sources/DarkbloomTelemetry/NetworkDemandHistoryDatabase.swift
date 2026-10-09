import Foundation
import SQLite3

public enum NetworkDemandHistoryDatabaseError: Error, Equatable, LocalizedError, Sendable {
    case unavailable, invalidSnapshot, conflictingTimestamp, corruptRecord, invalidInterval

    public var errorDescription: String? {
        switch self {
        case .unavailable: "Local network demand history is unavailable."
        case .invalidSnapshot: "Network demand history rejected invalid observation data."
        case .conflictingTimestamp: "Network demand history found conflicting observations at the same time."
        case .corruptRecord: "Local network demand history contains an unreadable entry."
        case .invalidInterval: "Network demand history rejected an invalid time range."
        }
    }
}

/// Private, bounded network observations. A bucket replacement stores the
/// complete observation atomically, including missing models and draining gaps.
public final class NetworkDemandHistoryDatabase: @unchecked Sendable {
    public static let maximumHistoryBuckets = 864
    public static let maximumRetentionHours = 72
    private static let maximumPayloadBytes = 100_000
    private let lock = NSLock()
    private let connection: NetworkDemandHistorySQLiteConnection
    private let url: URL
    private let maximumBuckets: Int
    private let retentionHours: Int
    private let now: @Sendable () -> Date

    public init(
        url: URL, maximumBuckets: Int = maximumHistoryBuckets,
        retentionHours: Int = maximumRetentionHours,
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws {
        try Task.checkCancellation()
        self.url = url
        self.maximumBuckets = min(max(maximumBuckets, 1), Self.maximumHistoryBuckets)
        self.retentionHours = min(max(retentionHours, 1), Self.maximumRetentionHours)
        self.now = now
        guard url.isFileURL else { throw NetworkDemandHistoryDatabaseError.unavailable }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch { throw NetworkDemandHistoryDatabaseError.unavailable }
        var pointer: OpaquePointer?
        guard sqlite3_open_v2(url.path, &pointer,
                             SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw NetworkDemandHistoryDatabaseError.unavailable
        }
        connection = NetworkDemandHistorySQLiteConnection(pointer: pointer)
        sqlite3_busy_timeout(pointer, 2_000)
        try makePrivateFiles()
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=NORMAL")
        try execute("PRAGMA secure_delete=ON")
        try execute("""
            CREATE TABLE IF NOT EXISTS network_demand_history (
                bucket_start REAL PRIMARY KEY NOT NULL,
                captured_at REAL NOT NULL,
                observation BLOB NOT NULL
            )
            """)
        try execute("""
            CREATE INDEX IF NOT EXISTS network_demand_history_capture_order
            ON network_demand_history (captured_at)
            """)
        try transaction { try prune(at: validatedNow()); try makePrivateFiles() }
    }

    /// Identical timestamps are immutable; a newer observation replaces the
    /// complete occupied bucket. Expired and older observations are ignored.
    @discardableResult
    public func record(_ snapshot: NetworkCapacitySnapshot) throws -> Bool {
        try Task.checkCancellation()
        guard Self.validInput(snapshot) else { throw NetworkDemandHistoryDatabaseError.invalidSnapshot }
        let observation = NetworkDemandHistoryObservation(snapshot: snapshot)
        guard observation.isValid else { throw NetworkDemandHistoryDatabaseError.invalidSnapshot }
        let payload = try Self.encode(observation)
        guard payload.count <= Self.maximumPayloadBytes else { throw NetworkDemandHistoryDatabaseError.invalidSnapshot }
        try Task.checkCancellation()
        lock.lock()
        defer { lock.unlock() }
        let time = try validatedNow()
        guard observation.capturedAt <= time.addingTimeInterval(NetworkCapacitySnapshot.maximumFutureSkew) else {
            throw NetworkDemandHistoryDatabaseError.invalidSnapshot
        }
        return try transaction {
            try prune(at: time)
            guard observation.capturedAt >= cutoff(at: time) else {
                try makePrivateFiles()
                return false
            }
            let existing = try prepare("SELECT bucket_start, captured_at, observation FROM network_demand_history WHERE bucket_start = ?")
            defer { sqlite3_finalize(existing) }
            try checked(sqlite3_bind_double(existing, 1, observation.bucketStart.timeIntervalSince1970))
            let step = sqlite3_step(existing)
            guard step == SQLITE_ROW || step == SQLITE_DONE else { throw NetworkDemandHistoryDatabaseError.unavailable }
            if step == SQLITE_ROW {
                let previous = try decode(existing)
                if previous.capturedAt == observation.capturedAt {
                    guard previous == observation else { throw NetworkDemandHistoryDatabaseError.conflictingTimestamp }
                    try makePrivateFiles()
                    return false
                }
                if previous.capturedAt > observation.capturedAt {
                    try makePrivateFiles()
                    return false
                }
            }
            try Task.checkCancellation()
            let insert = try prepare("""
                INSERT INTO network_demand_history (bucket_start, captured_at, observation) VALUES (?, ?, ?)
                ON CONFLICT(bucket_start) DO UPDATE SET captured_at = excluded.captured_at, observation = excluded.observation
                """)
            defer { sqlite3_finalize(insert) }
            try checked(sqlite3_bind_double(insert, 1, observation.bucketStart.timeIntervalSince1970))
            try checked(sqlite3_bind_double(insert, 2, observation.capturedAt.timeIntervalSince1970))
            try payload.withUnsafeBytes {
                try checked(sqlite3_bind_blob(insert, 3, $0.baseAddress, Int32($0.count), networkDemandHistorySQLiteTransient))
            }
            guard sqlite3_step(insert) == SQLITE_DONE else { throw NetworkDemandHistoryDatabaseError.unavailable }
            try prune(at: time)
            try makePrivateFiles()
            return true
        }
    }

    /// Reads indexed membership and payloads in one pinned SQLite transaction.
    /// The caller's range is preserved exactly; invalid ranges are rejected.
    public func report(in range: DateInterval) throws -> NetworkDemandHistoryReport {
        try Task.checkCancellation()
        guard Self.validTimestamp(range.start), Self.validTimestamp(range.end),
              range.duration.isFinite, range.duration >= 0,
              range.duration <= Double(Self.maximumRetentionHours) * 3_600 else {
            throw NetworkDemandHistoryDatabaseError.invalidInterval
        }
        lock.lock()
        defer { lock.unlock() }
        let time = try validatedNow()
        return try transaction {
            try prune(at: time)
            try makePrivateFiles()
            let statement = try prepare("""
                SELECT bucket_start, captured_at, observation FROM network_demand_history
                WHERE captured_at >= ? AND captured_at <= ? ORDER BY captured_at ASC
                """)
            defer { sqlite3_finalize(statement) }
            try checked(sqlite3_bind_double(statement, 1, range.start.timeIntervalSince1970))
            try checked(sqlite3_bind_double(statement, 2, range.end.timeIntervalSince1970))
            var observations: [NetworkDemandHistoryObservation] = []
            while true {
                try Task.checkCancellation()
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw NetworkDemandHistoryDatabaseError.unavailable }
                guard observations.count < Self.maximumHistoryBuckets else { throw NetworkDemandHistoryDatabaseError.corruptRecord }
                observations.append(try decode(statement))
            }
            return .init(range: range, readAt: time, observations: observations)
        }
    }

    private static func validInput(_ snapshot: NetworkCapacitySnapshot) -> Bool {
        guard validTimestamp(snapshot.capturedAt), snapshot.models.count <= 128,
              !snapshot.isDraining || snapshot.models.isEmpty else { return false }
        return snapshot.models.allSatisfy {
            !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.id.utf8.count <= 512
                && $0.routableProviders >= 0 && $0.warmProviders >= 0 && $0.runningProviders >= 0 && $0.coldProviders >= 0
                && $0.activeRequests >= 0 && $0.queuedRequests >= 0 && $0.queueLimit >= 0
                && $0.aggregateTokensPerSecond.isFinite && $0.aggregateTokensPerSecond >= 0
                && $0.estimatedTimeToFirstTokenMS >= 0 && $0.tokenBudgetRemaining >= 0
                && $0.tokenBudgetTotal >= 0 && $0.tokenBudgetRemaining <= $0.tokenBudgetTotal
        }
    }

    private static func validTimestamp(_ date: Date) -> Bool {
        date.timeIntervalSince1970.isFinite && date.timeIntervalSince1970 >= 0
    }

    private func validatedNow() throws -> Date {
        let time = now()
        guard Self.validTimestamp(time) else { throw NetworkDemandHistoryDatabaseError.unavailable }
        return time
    }

    private func decode(_ statement: OpaquePointer) throws -> NetworkDemandHistoryObservation {
        try Task.checkCancellation()
        guard [SQLITE_INTEGER, SQLITE_FLOAT].contains(sqlite3_column_type(statement, 0)),
              [SQLITE_INTEGER, SQLITE_FLOAT].contains(sqlite3_column_type(statement, 1)),
              sqlite3_column_type(statement, 2) == SQLITE_BLOB,
              let bytes = sqlite3_column_blob(statement, 2) else { throw NetworkDemandHistoryDatabaseError.corruptRecord }
        let size = Int(sqlite3_column_bytes(statement, 2))
        guard size > 0, size <= Self.maximumPayloadBytes else { throw NetworkDemandHistoryDatabaseError.corruptRecord }
        let payload = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), count: size, deallocator: .none)
        guard let observation = try? JSONDecoder().decode(NetworkDemandHistoryObservation.self, from: payload),
              observation.isValid,
              observation.capturedAt.timeIntervalSince1970 == sqlite3_column_double(statement, 1),
              observation.bucketStart.timeIntervalSince1970 == sqlite3_column_double(statement, 0),
              // Reject extra JSON fields and noncanonical payloads as well.
              (try? Self.encode(observation)) == payload else { throw NetworkDemandHistoryDatabaseError.corruptRecord }
        try Task.checkCancellation()
        return observation
    }

    private func cutoff(at time: Date) -> Date {
        time.addingTimeInterval(-Double(retentionHours) * 3_600)
    }

    private func prune(at time: Date) throws {
        try Task.checkCancellation()
        let age = try prepare("DELETE FROM network_demand_history WHERE captured_at < ?")
        defer { sqlite3_finalize(age) }
        try checked(sqlite3_bind_double(age, 1, cutoff(at: time).timeIntervalSince1970))
        guard sqlite3_step(age) == SQLITE_DONE else { throw NetworkDemandHistoryDatabaseError.unavailable }
        let overflow = try prepare("""
            DELETE FROM network_demand_history WHERE bucket_start IN (
                SELECT bucket_start FROM network_demand_history ORDER BY captured_at DESC LIMIT -1 OFFSET ?
            )
            """)
        defer { sqlite3_finalize(overflow) }
        try checked(sqlite3_bind_int64(overflow, 1, Int64(maximumBuckets)))
        guard sqlite3_step(overflow) == SQLITE_DONE else { throw NetworkDemandHistoryDatabaseError.unavailable }
    }

    private func transaction<T>(_ operation: () throws -> T) throws -> T {
        try Task.checkCancellation()
        try execute("BEGIN IMMEDIATE")
        do {
            let result = try operation()
            try Task.checkCancellation()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            if let statement { sqlite3_finalize(statement) }
            throw NetworkDemandHistoryDatabaseError.unavailable
        }
        return statement
    }

    private func checked(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw NetworkDemandHistoryDatabaseError.unavailable }
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(connection.pointer, sql, nil, nil, nil) == SQLITE_OK else {
            throw NetworkDemandHistoryDatabaseError.unavailable
        }
    }

    private static func encode(_ observation: NetworkDemandHistoryObservation) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do { return try encoder.encode(observation) }
        catch { throw NetworkDemandHistoryDatabaseError.invalidSnapshot }
    }

    private func makePrivateFiles() throws {
        do {
            for suffix in ["", "-wal", "-shm"] {
                let path = url.path + suffix
                if FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
                }
            }
        } catch { throw NetworkDemandHistoryDatabaseError.unavailable }
    }
}

private final class NetworkDemandHistorySQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

private let networkDemandHistorySQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
