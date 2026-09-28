import Foundation
import SQLite3

public enum RecommendationJournalError: Error, Equatable, Sendable {
    case sqlite
    case recordTooLarge
    case corruptRecord
}

public struct RecommendationJournalEntry: Equatable, Sendable {
    public let input: RecommendationInput
    public let storedDecision: RecommendationDecision
}

public struct RecommendationReplayEntry: Equatable, Sendable {
    public let input: RecommendationInput
    public let storedDecision: RecommendationDecision
    public let replayedDecision: RecommendationDecision
    public var matches: Bool { storedDecision == replayedDecision }
}

/// Private, bounded evidence history. Recording never calls a provider or
/// dispatches a model mutation. Replaying uses the same pure evaluator.
public actor RecommendationJournal {
    public static let maximumLimit = 10_000
    public static let maximumRecordBytes = 256 * 1_024

    private let connection: RecommendationSQLiteConnection
    private let limit: Int

    public init(url: URL, limit: Int = 1_000) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            url.path, &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil
        ) == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw RecommendationJournalError.sqlite
        }
        connection = RecommendationSQLiteConnection(pointer: database)
        self.limit = min(max(limit, 1), Self.maximumLimit)
        sqlite3_busy_timeout(database, 2_000)
        do {
            try Self.execute(database, "PRAGMA journal_mode=WAL")
            try Self.execute(database, "PRAGMA synchronous=NORMAL")
            try Self.execute(database, """
                CREATE TABLE IF NOT EXISTS recommendation_journal (
                    id TEXT PRIMARY KEY,
                    evaluated_at REAL NOT NULL,
                    input_json BLOB NOT NULL,
                    decision_json BLOB NOT NULL
                )
                """)
            try Self.execute(database, """
                CREATE INDEX IF NOT EXISTS recommendation_journal_time
                ON recommendation_journal (evaluated_at)
                """)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path
            )
        } catch {
            throw error
        }
    }

    @discardableResult
    public func record(_ source: RecommendationInput) throws -> RecommendationDecision {
        let input = source.canonicalized
        let decision = RecommendationEvaluator.evaluate(input)
        guard let inputData = try? RecommendationCoding.encoder.encode(input),
              let decisionData = try? RecommendationCoding.encoder.encode(decision),
              inputData.count <= Self.maximumRecordBytes,
              decisionData.count <= Self.maximumRecordBytes else {
            throw RecommendationJournalError.recordTooLarge
        }

        let database = connection.pointer
        try Self.execute(database, "BEGIN IMMEDIATE")
        do {
            let statement = try prepare("""
                INSERT OR IGNORE INTO recommendation_journal
                    (id, evaluated_at, input_json, decision_json)
                VALUES (?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_text(statement, 1, decision.id, -1, recommendationSQLiteTransient)
            sqlite3_bind_double(statement, 2, decision.evaluatedAt.timeIntervalSince1970)
            inputData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 3, bytes.baseAddress, Int32(bytes.count), recommendationSQLiteTransient)
            }
            decisionData.withUnsafeBytes { bytes in
                sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), recommendationSQLiteTransient)
            }
            guard sqlite3_step(statement) == SQLITE_DONE else { throw RecommendationJournalError.sqlite }
            try prune()
            try Self.execute(database, "COMMIT")
        } catch {
            try? Self.execute(database, "ROLLBACK")
            throw error
        }
        return decision
    }

    public func recent(limit requestedLimit: Int = 100) throws -> [RecommendationJournalEntry] {
        let count = min(max(requestedLimit, 0), limit)
        guard count > 0 else { return [] }
        let statement = try prepare("""
            SELECT input_json, decision_json FROM (
                SELECT rowid, input_json, decision_json
                FROM recommendation_journal ORDER BY rowid DESC LIMIT ?
            ) ORDER BY rowid ASC
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(count))
        var entries: [RecommendationJournalEntry] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW,
                  let inputData = blob(statement, column: 0),
                  let decisionData = blob(statement, column: 1),
                  inputData.count <= Self.maximumRecordBytes,
                  decisionData.count <= Self.maximumRecordBytes,
                  let input = try? RecommendationCoding.decoder.decode(RecommendationInput.self, from: inputData),
                  let decision = try? RecommendationCoding.decoder.decode(RecommendationDecision.self, from: decisionData)
            else { throw RecommendationJournalError.corruptRecord }
            entries.append(.init(input: input, storedDecision: decision))
        }
        return entries
    }

    public func replay(limit: Int = 100) throws -> [RecommendationReplayEntry] {
        try recent(limit: limit).map { entry in
            RecommendationReplayEntry(
                input: entry.input,
                storedDecision: entry.storedDecision,
                replayedDecision: RecommendationEvaluator.evaluate(entry.input)
            )
        }
    }

    private func prune() throws {
        let statement = try prepare("""
            DELETE FROM recommendation_journal WHERE rowid NOT IN (
                SELECT rowid FROM recommendation_journal ORDER BY rowid DESC LIMIT ?
            )
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int64(statement, 1, Int64(limit))
        guard sqlite3_step(statement) == SQLITE_DONE else { throw RecommendationJournalError.sqlite }

        let age = try prepare("""
            DELETE FROM recommendation_journal
            WHERE evaluated_at < (SELECT MAX(evaluated_at) - 2592000 FROM recommendation_journal)
            """)
        defer { sqlite3_finalize(age) }
        guard sqlite3_step(age) == SQLITE_DONE else { throw RecommendationJournalError.sqlite }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else { throw RecommendationJournalError.sqlite }
        return statement
    }

    private func blob(_ statement: OpaquePointer, column: Int32) -> Data? {
        guard let pointer = sqlite3_column_blob(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard (1...Self.maximumRecordBytes).contains(count) else { return nil }
        return Data(bytes: pointer, count: count)
    }

    private static func execute(_ database: OpaquePointer, _ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw RecommendationJournalError.sqlite
        }
    }
}

private final class RecommendationSQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer
    init(pointer: OpaquePointer) { self.pointer = pointer }
    deinit { sqlite3_close(pointer) }
}

private let recommendationSQLiteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
