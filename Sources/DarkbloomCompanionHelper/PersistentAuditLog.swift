import DarkbloomCompanionHost
import Foundation
import SQLite3

public enum HelperAuditEvent: String, Codable, Sendable {
    case paired, prepared, authorized, dispatchIntent, succeeded, failed, outcomeUncertain, revoked
}

public enum HelperAuditAction: String, Codable, Sendable {
    case providerStart, providerStop, providerRestart, providerLiveSwitch
    case settingsPatch, settingsSave, appOpen, appQuit, appRelaunch
}

/// Fixed codes and identifiers only. No log lines, paths, account identity,
/// command payloads, or provider error prose can enter this record.
public struct HelperAuditRecord: Codable, Equatable, Sendable {
    public let at: Date
    public let event: HelperAuditEvent
    public let action: HelperAuditAction?
    public let deviceID: UUID?
    public let requestID: UUID?
    public let commandID: UUID?

    public init(
        at: Date, event: HelperAuditEvent, action: HelperAuditAction? = nil,
        deviceID: UUID? = nil, requestID: UUID? = nil, commandID: UUID? = nil
    ) {
        self.at = at
        self.event = event
        self.action = action
        self.deviceID = deviceID
        self.requestID = requestID
        self.commandID = commandID
    }
}

public actor PersistentAuditLog: CompanionAuditRecording {
    private let database: HelperDatabase
    private let limit: Int

    public init(url: URL, limit: Int = 1_000) throws {
        database = try HelperDatabase(url: url)
        self.limit = min(max(limit, 1), 10_000)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS helper_audit (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                record_json BLOB NOT NULL
            )
            """)
    }

    public func append(_ record: HelperAuditRecord) throws {
        let data = try JSONEncoder().encode(record)
        guard data.count <= 4_096 else { throw HelperDatabaseError.sqlite }
        try database.execute("BEGIN IMMEDIATE")
        do {
            let statement = try database.prepare("INSERT INTO helper_audit (record_json) VALUES (?)")
            bindData(data, to: statement, at: 1)
            let result = sqlite3_step(statement)
            sqlite3_finalize(statement)
            guard result == SQLITE_DONE else { throw HelperDatabaseError.sqlite }
            let prune = try database.prepare("""
                DELETE FROM helper_audit WHERE id NOT IN (
                    SELECT id FROM helper_audit ORDER BY id DESC LIMIT ?
                )
                """)
            sqlite3_bind_int(prune, 1, Int32(limit))
            let pruned = sqlite3_step(prune)
            sqlite3_finalize(prune)
            guard pruned == SQLITE_DONE else { throw HelperDatabaseError.sqlite }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    public func append(_ entry: CompanionAuditEntry) throws {
        let event: HelperAuditEvent = switch entry.event {
        case .paired: .paired
        case .prepared: .prepared
        case .authorized: .authorized
        case .dispatched: .dispatchIntent
        case .succeeded: .succeeded
        case .failed: .failed
        case .revoked: .revoked
        }
        let action: HelperAuditAction?
        switch entry.actionType {
        case nil: action = nil
        case "provider.start": action = .providerStart
        case "provider.stop": action = .providerStop
        case "provider.restart": action = .providerRestart
        case "provider.applyLive": action = .providerLiveSwitch
        case "settings.patch": action = .settingsPatch
        case "settings.save": action = .settingsSave
        case "app.open": action = .appOpen
        case "app.quit": action = .appQuit
        case "app.relaunch": action = .appRelaunch
        default: throw HelperDatabaseError.sqlite
        }
        try append(.init(
            at: entry.at, event: event, action: action,
            deviceID: entry.deviceID, requestID: entry.requestID,
            commandID: entry.commandID
        ))
    }

    public func recent(limit requested: Int = 100) throws -> [HelperAuditRecord] {
        guard requested > 0 else { return [] }
        let statement = try database.prepare("""
            SELECT record_json FROM (
                SELECT id, record_json FROM helper_audit ORDER BY id DESC LIMIT ?
            ) ORDER BY id ASC
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(min(requested, limit)))
        var values: [HelperAuditRecord] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW,
                  let data = readData(statement, at: 0, maximumBytes: 4_096),
                  let value = try? JSONDecoder().decode(HelperAuditRecord.self, from: data)
            else { throw HelperDatabaseError.sqlite }
            values.append(value)
        }
        return values
    }
}
