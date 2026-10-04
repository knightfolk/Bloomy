import CryptoKit
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
    private let decoder = JSONDecoder()
    private var decodedRows = PerformanceHistoryDecodedCache.Generation.empty
    private var decodedDiagnostics = PerformanceHistoryDecodedCache.Diagnostics.empty
    private var snapshotSourceID = UUID()
    private var insertionSequence: UInt64 = 0
    private var insertions: [(sequence: UInt64, rowID: Int64)] = []
    private static let insertionJournalLimit = 512

    var decodedCacheDiagnostics: PerformanceHistoryDecodedCache.Diagnostics {
        lock.lock()
        defer { lock.unlock() }
        return decodedDiagnostics
    }

    /// Release derived read data when its consumer becomes inactive. Stored
    /// measurements, retention and provider state are unaffected.
    @discardableResult
    public func clearDecodedReadCache() -> Int {
        lock.lock()
        defer { lock.unlock() }
        let released = decodedRows.entries.count
        decodedRows = .empty
        decodedDiagnostics = .empty
        return released
    }

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
            CREATE INDEX IF NOT EXISTS performance_history_time_order
            ON performance_history (observed_at)
            """)
        try Self.execute(pointer, """
            CREATE INDEX IF NOT EXISTS performance_history_model_time_order
            ON performance_history (model, observed_at)
            """)
        // SQLite appends rowid to these indexes, matching chronological
        // insertion order without sorting tied timestamps. Create replacements
        // before removing the older indexes; measurements remain untouched.
        try Self.execute(pointer, "DROP INDEX IF EXISTS performance_history_observed_at")
        try Self.execute(pointer, "DROP INDEX IF EXISTS performance_history_model_observed_at")
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
        var insertedRowID: Int64?
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
            } else {
                insertedRowID = sqlite3_last_insert_rowid(connection.pointer)
            }
            try prune(at: time)
            try makePrivateFiles()
        }
        // Publish only committed inserts. Retention may recycle a rowid (and
        // even an expired UUID), so these rows must be decoded on the next read.
        if let insertedRowID {
            if insertionSequence == .max {
                snapshotSourceID = UUID()
                insertionSequence = 0
                insertions.removeAll(keepingCapacity: true)
            }
            insertionSequence += 1
            insertions.append((insertionSequence, insertedRowID))
            if insertions.count > Self.insertionJournalLimit { insertions.removeFirst() }
        }
    }

    /// Reuses validated payloads while always querying current indexed
    /// membership and order. Outside commits, foreign tokens and expired local
    /// insertion history force a full read. No second decoded cache is created.
    public func readSnapshot(
        in interval: DateInterval, model: String? = nil,
        reusing previous: PerformanceHistoryReadSnapshot? = nil
    ) throws -> PerformanceHistoryReadSnapshot {
        try Task.checkCancellation()
        guard PerformanceSample.validTimestamp(interval.start), PerformanceSample.validTimestamp(interval.end),
              interval.duration.isFinite, interval.duration >= 0 else { throw PerformanceHistoryDatabaseError.invalidInterval }
        if let model, !PerformanceSample(model: model).isValid { throw PerformanceHistoryDatabaseError.invalidSample }
        lock.lock()
        defer { lock.unlock() }
        try prune()
        let before = try dataVersion()
        // Unmanaged triggers can change earlier payloads during our own insert
        // or prune without advancing data_version. The normal schema has none;
        // an extended schema remains supported through fully validated reads.
        let hasTriggers = try hasUnmanagedTriggers()
        let eligible = previous.flatMap { snapshot -> PerformanceHistoryReadSnapshot? in
            guard !hasTriggers, snapshot.sourceID == snapshotSourceID, snapshot.dataVersion == before,
                  snapshot.insertionSequence <= insertionSequence,
                  insertionSequence - snapshot.insertionSequence <= UInt64(insertions.count) else { return nil }
            return snapshot
        }
        let result = try snapshotRows(in: interval, model: model, previous: eligible)
        let after = try dataVersion()
        if eligible != nil, before != after {
            // Metadata and payload SELECTs were pinned to one WAL snapshot,
            // but an outside commit may invalidate reused payloads. Discard the
            // attempt and read every payload in a new consistent transaction.
            let freshBefore = try dataVersion()
            let fresh = try snapshotRows(in: interval, model: model, previous: nil)
            let freshAfter = try dataVersion()
            try Task.checkCancellation()
            return makeSnapshot(fresh, version: !hasTriggers && freshBefore == freshAfter ? freshAfter : nil)
        }
        try Task.checkCancellation()
        return makeSnapshot(result, version: !hasTriggers && before == after ? after : nil)
    }

    private func makeSnapshot(
        _ result: (samples: [PerformanceSample], rowIDs: [Int64], reused: Int), version: Int64?
    ) -> PerformanceHistoryReadSnapshot {
        .init(samples: result.samples, reusedSampleCount: result.reused, rowIDs: result.rowIDs,
              sourceID: snapshotSourceID, dataVersion: version, insertionSequence: insertionSequence)
    }

    private func dataVersion() throws -> Int64 {
        let statement = try prepare("PRAGMA data_version")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_INTEGER else {
            throw PerformanceHistoryDatabaseError.unavailable
        }
        return sqlite3_column_int64(statement, 0)
    }

    private func hasUnmanagedTriggers() throws -> Bool {
        let statement = try prepare("SELECT 1 FROM sqlite_schema WHERE type = 'trigger' LIMIT 1")
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW || step == SQLITE_DONE else { throw PerformanceHistoryDatabaseError.unavailable }
        // Finalize before BEGIN so this probe never holds an implicit read
        // transaction across the external-write fence.
        return step == SQLITE_ROW
    }

    private func snapshotRows(
        in interval: DateInterval, model: String?, previous: PerformanceHistoryReadSnapshot?
    ) throws -> (samples: [PerformanceSample], rowIDs: [Int64], reused: Int) {
        // BEGIN pins membership and per-row payload reads together. The lock
        // prevents same-connection writes until COMMIT and the version fence.
        try Self.execute(connection.pointer, "BEGIN")
        do {
            let statement = try prepare("""
                SELECT id, observed_at, model, \(previous == nil ? "sample, rowid" : "rowid")
                FROM performance_history WHERE observed_at >= ? AND observed_at <= ?
                \(model == nil ? "" : "AND model = ?") ORDER BY observed_at DESC, rowid DESC
                """)
            defer { sqlite3_finalize(statement) }
            try checked(sqlite3_bind_double(statement, 1, interval.start.timeIntervalSince1970))
            try checked(sqlite3_bind_double(statement, 2, interval.end.timeIntervalSince1970))
            if let model { try bind(model, statement, 3) }
            let lookup = previous == nil ? nil : try prepare(
                "SELECT id, observed_at, model, sample FROM performance_history WHERE rowid = ?")
            defer { if let lookup { sqlite3_finalize(lookup) } }
            var indices: [Int64: Int] = [:]
            if let previous {
                indices.reserveCapacity(previous.rowIDs.count)
                for (index, rowID) in previous.rowIDs.enumerated() { indices[rowID] = index }
            }
            let previousSequence = previous?.insertionSequence ?? insertionSequence
            let dirty = Set(insertions.lazy.filter { $0.sequence > previousSequence }.map(\.rowID))
            var samples: [PerformanceSample] = []
            var rowIDs: [Int64] = []
            if let previous { samples.reserveCapacity(previous.samples.count); rowIDs.reserveCapacity(previous.rowIDs.count) }
            var reused = 0
            while true {
                if samples.count.isMultiple(of: 64) { try Task.checkCancellation() }
                let step = sqlite3_step(statement)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { throw PerformanceHistoryDatabaseError.unavailable }
                let rowColumn: Int32 = previous == nil ? 4 : 3
                guard sqlite3_column_type(statement, rowColumn) == SQLITE_INTEGER else {
                    throw PerformanceHistoryDatabaseError.corruptRecord
                }
                let rowID = sqlite3_column_int64(statement, rowColumn)
                let sample: PerformanceSample
                if let previous, let index = indices[rowID], !dirty.contains(rowID),
                   try metadataMatches(statement, sample: previous.samples[index]) {
                    sample = previous.samples[index]
                    reused += 1
                } else if let lookup {
                    try checked(sqlite3_reset(lookup))
                    try checked(sqlite3_bind_int64(lookup, 1, rowID))
                    guard sqlite3_step(lookup) == SQLITE_ROW else { throw PerformanceHistoryDatabaseError.corruptRecord }
                    sample = try decode(lookup)
                } else {
                    sample = try decode(statement)
                }
                samples.append(sample)
                rowIDs.append(rowID)
            }
            try Task.checkCancellation()
            samples.reverse()
            rowIDs.reverse()
            try Task.checkCancellation()
            try Self.execute(connection.pointer, "COMMIT")
            return (samples, rowIDs, reused)
        } catch {
            try? Self.execute(connection.pointer, "ROLLBACK")
            throw error
        }
    }

    private func metadataMatches(_ statement: OpaquePointer, sample: PerformanceSample) throws -> Bool {
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              sqlite3_column_type(statement, 1) == SQLITE_FLOAT || sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
              sqlite3_column_type(statement, 2) == SQLITE_NULL || sqlite3_column_type(statement, 2) == SQLITE_TEXT,
              let idText = text(statement, 0), let id = UUID(uuidString: idText) else {
            throw PerformanceHistoryDatabaseError.corruptRecord
        }
        let model: String?
        if sqlite3_column_type(statement, 2) == SQLITE_TEXT {
            guard let value = text(statement, 2) else { throw PerformanceHistoryDatabaseError.corruptRecord }
            model = value
        } else { model = nil }
        return id == sample.id && sqlite3_column_double(statement, 1) == sample.observedAt.timeIntervalSince1970
            && model == sample.model
    }

    /// Chronological order, including unavailable/stale rows so callers can
    /// show gaps. Model filters refer only to the serving model on the sample.
    public func samples(in interval: DateInterval, model: String? = nil) throws -> [PerformanceSample] {
        try Task.checkCancellation()
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
            ORDER BY observed_at DESC, rowid DESC
            """)
        defer { sqlite3_finalize(statement) }
        try checked(sqlite3_bind_double(statement, 1, interval.start.timeIntervalSince1970))
        try checked(sqlite3_bind_double(statement, 2, interval.end.timeIntervalSince1970))
        if let model { try bind(model, statement, 3) }
        return try rows(statement, chronological: true)
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
        return try rows(statement, chronological: false)
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

    private func rows(_ statement: OpaquePointer, chronological: Bool) throws -> [PerformanceSample] {
        let previous = decodedRows
        let staged = PerformanceHistoryDecodedCache.Builder()
        var result: [PerformanceSample] = []
        var hits = 0
        var misses = 0
        var hashedRows = 0
        while true {
            // Bound obsolete decoding work when a view's read task is cancelled.
            if result.count.isMultiple(of: 64) { try Task.checkCancellation() }
            switch sqlite3_step(statement) {
            case SQLITE_DONE:
                // A late cancellation must not publish a partially obsolete read.
                try Task.checkCancellation()
                if chronological { result.reverse() }
                try Task.checkCancellation()
                let generation = staged.finish()
                decodedRows = generation
                decodedDiagnostics = .init(
                    rows: generation.entries.count, accountedBytes: generation.accountedBytes,
                    hits: hits, misses: misses, hashedRows: hashedRows,
                    peakAccountedBytes: previous.accountedBytes + staged.peakAccountedBytes
                )
                return result
            case SQLITE_ROW:
                let (sample, reused, hashed) = try decodedRow(statement, previous: previous, staged: staged)
                result.append(sample)
                if reused { hits += 1 } else { misses += 1 }
                if hashed { hashedRows += 1 }
            default: throw PerformanceHistoryDatabaseError.unavailable
            }
        }
    }

    private func decode(_ statement: OpaquePointer) throws -> PerformanceSample {
        try decodedRow(statement, previous: decodedRows, staged: nil).0
    }

    private func decodedRow(
        _ statement: OpaquePointer, previous: PerformanceHistoryDecodedCache.Generation,
        staged: PerformanceHistoryDecodedCache.Builder?
    ) throws -> (PerformanceSample, Bool, Bool) {
        guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              sqlite3_column_type(statement, 1) == SQLITE_FLOAT || sqlite3_column_type(statement, 1) == SQLITE_INTEGER,
              sqlite3_column_type(statement, 2) == SQLITE_NULL || sqlite3_column_type(statement, 2) == SQLITE_TEXT,
              sqlite3_column_type(statement, 3) == SQLITE_BLOB,
              let idText = text(statement, 0), let id = UUID(uuidString: idText),
              let bytes = sqlite3_column_blob(statement, 3) else { throw PerformanceHistoryDatabaseError.corruptRecord }
        let size = Int(sqlite3_column_bytes(statement, 3))
        guard size > 0, size <= Self.maximumPayloadBytes else { throw PerformanceHistoryDatabaseError.corruptRecord }
        // SQLite owns these bytes until the next step/finalize. Neither the
        // generation nor its entries retain the payload or this temporary view.
        let payload = Data(bytesNoCopy: UnsafeMutableRawPointer(mutating: bytes), count: size, deallocator: .none)
        let cached = previous.entries[id]
        // Verify every possible reuse. A miss beyond this read's bounded cache
        // still gets decoded and validated, without an unnecessary hash.
        var digest = cached.map { _ in SHA256.hash(data: payload) }
        let sample: PerformanceSample
        let reused: Bool
        if let cached, cached.digest == digest {
            sample = cached.sample
            reused = true
        } else {
            guard let decoded = try? decoder.decode(PerformanceSample.self, from: payload), decoded.isValid else {
                throw PerformanceHistoryDatabaseError.corruptRecord
            }
            sample = decoded
            reused = false
        }
        let indexedModel: String?
        if sqlite3_column_type(statement, 2) == SQLITE_TEXT {
            guard let model = text(statement, 2) else { throw PerformanceHistoryDatabaseError.corruptRecord }
            indexedModel = model
        } else {
            indexedModel = nil
        }
        // Hash equality never substitutes for checking the current indexed
        // columns. Another SQLite writer can alter them independently of BLOBs.
        guard sample.id == id,
              sample.observedAt.timeIntervalSince1970 == sqlite3_column_double(statement, 1),
              sample.model == indexedModel else { throw PerformanceHistoryDatabaseError.corruptRecord }
        if let staged {
            if reused, let cached {
                staged.insert(cached)
            } else if let cost = staged.admissionCost(of: sample) {
                if digest == nil { digest = SHA256.hash(data: payload) }
                if let digest { staged.insert(.init(digest: digest, sample: sample, accountedBytes: cost)) }
            }
        }
        return (sample, reused, digest != nil)
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
        // COUNT(*) uses SQLite's compact b-tree count. Below the cap there is
        // no reason to walk every retained index entry with OFFSET on each tick.
        let count = try prepare("SELECT COUNT(*) FROM performance_history")
        defer { sqlite3_finalize(count) }
        guard sqlite3_step(count) == SQLITE_ROW else { throw PerformanceHistoryDatabaseError.unavailable }
        guard sqlite3_column_int64(count, 0) > Int64(historyLimit) else { return }
        // Only actual overflow needs a chronological index walk.
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
