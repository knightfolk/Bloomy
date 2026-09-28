import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import Foundation
import SQLite3

public enum DurableOperationError: Error, Equatable, Sendable {
    case duplicateRequestConflict
    case journalFull
    case corruptRecord
    case invalidTransition
}

public enum OperationClaim: Equatable, Sendable {
    case execute(OperationStatus)
    case existing(OperationStatus)

    public var status: OperationStatus {
        switch self {
        case .execute(let status), .existing(let status): status
        }
    }
}

public enum VerifiedOperationFinding: Sendable {
    case succeeded
    case failed(SafeErrorResponse)
}

/// A synchronous SQLite commit is the dispatch intent. Callers must execute a
/// mutation only after `claim` returns `.execute`. A restarted journal marks
/// unresolved intents uncertain and never redispatches them automatically.
public actor PersistentOperationJournal {
    public static let maximumLimit = 10_000
    private let database: HelperDatabase
    private let limit: Int

    public init(url: URL, limit: Int = 1_000, recoveredAt: Date = .now) throws {
        database = try HelperDatabase(url: url)
        self.limit = min(max(limit, 1), Self.maximumLimit)
        try database.execute("""
            CREATE TABLE IF NOT EXISTS helper_operations (
                device_id TEXT NOT NULL,
                request_id TEXT NOT NULL,
                command_id TEXT NOT NULL,
                operation_id TEXT NOT NULL UNIQUE,
                state TEXT NOT NULL,
                updated_at REAL NOT NULL,
                status_json BLOB NOT NULL,
                PRIMARY KEY (device_id, request_id)
            )
            """)
        try Self.recover(database, at: recoveredAt)
    }

    public func claim(_ command: AuthorizedCommand, at now: Date = .now) throws -> OperationClaim {
        try database.execute("BEGIN IMMEDIATE")
        do {
            if let existing = try find(deviceID: command.deviceID, requestID: command.proposal.requestID) {
                guard existing.commandID == command.commandID else { throw DurableOperationError.duplicateRequestConflict }
                try database.execute("COMMIT")
                return .existing(existing)
            }
            try makeRoom(at: now)
            let status = OperationStatus(
                operationID: UUID(), requestID: command.proposal.requestID,
                commandID: command.commandID, state: .accepted,
                progress: nil, error: nil, updatedAt: now
            )
            let statement = try database.prepare("""
                INSERT INTO helper_operations
                    (device_id, request_id, command_id, operation_id, state, updated_at, status_json)
                VALUES (?, ?, ?, ?, ?, ?, ?)
                """)
            defer { sqlite3_finalize(statement) }
            bindText(command.deviceID.uuidString, to: statement, at: 1)
            bindText(command.proposal.requestID.uuidString, to: statement, at: 2)
            bindText(command.commandID.uuidString, to: statement, at: 3)
            bindText(status.operationID.uuidString, to: statement, at: 4)
            bindText(status.state.rawValue, to: statement, at: 5)
            sqlite3_bind_double(statement, 6, now.timeIntervalSince1970)
            bindData(try JSONEncoder().encode(status), to: statement, at: 7)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw HelperDatabaseError.sqlite }
            try database.execute("COMMIT")
            return .execute(status)
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    public func finish(
        operationID: UUID,
        state: OperationState,
        error: SafeErrorResponse? = nil,
        at now: Date = .now
    ) throws -> OperationStatus {
        guard [.succeeded, .failed, .outcomeUncertain].contains(state),
              let previous = try find(operationID: operationID),
              previous.state == .accepted else { throw DurableOperationError.invalidTransition }
        let status = OperationStatus(
            operationID: operationID, requestID: previous.requestID,
            commandID: previous.commandID, state: state,
            progress: state == .succeeded ? 1 : nil, error: error, updatedAt: now
        )
        let statement = try database.prepare("UPDATE helper_operations SET state = ?, updated_at = ?, status_json = ? WHERE operation_id = ?")
        defer { sqlite3_finalize(statement) }
        bindText(state.rawValue, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        bindData(try JSONEncoder().encode(status), to: statement, at: 3)
        bindText(operationID.uuidString, to: statement, at: 4)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HelperDatabaseError.sqlite }
        return status
    }

    public func status(operationID: UUID, deviceID: UUID) throws -> OperationStatus? {
        let statement = try database.prepare(
            "SELECT status_json FROM helper_operations WHERE operation_id = ? AND device_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bindText(operationID.uuidString, to: statement, at: 1)
        bindText(deviceID.uuidString, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try Self.decode(statement)
    }

    /// A trusted local observer may resolve an uncertain outcome after
    /// inspecting real provider/app state. This method never redispatches.
    public func reconcile(
        operationID: UUID,
        deviceID: UUID,
        finding: VerifiedOperationFinding,
        at now: Date = .now
    ) throws -> OperationStatus {
        guard let previous = try status(operationID: operationID, deviceID: deviceID),
              previous.state == .outcomeUncertain else {
            throw DurableOperationError.invalidTransition
        }
        let state: OperationState
        let error: SafeErrorResponse?
        switch finding {
        case .succeeded: state = .succeeded; error = nil
        case .failed(let safeError): state = .failed; error = safeError
        }
        let resolved = OperationStatus(
            operationID: operationID, requestID: previous.requestID,
            commandID: previous.commandID, state: state,
            progress: state == .succeeded ? 1 : nil,
            error: error, updatedAt: now
        )
        let statement = try database.prepare("""
            UPDATE helper_operations SET state = ?, updated_at = ?, status_json = ?
            WHERE operation_id = ? AND device_id = ? AND state = 'outcomeUncertain'
            """)
        defer { sqlite3_finalize(statement) }
        bindText(state.rawValue, to: statement, at: 1)
        sqlite3_bind_double(statement, 2, now.timeIntervalSince1970)
        bindData(try JSONEncoder().encode(resolved), to: statement, at: 3)
        bindText(operationID.uuidString, to: statement, at: 4)
        bindText(deviceID.uuidString, to: statement, at: 5)
        guard sqlite3_step(statement) == SQLITE_DONE, sqlite3_changes(database.pointer) == 1 else {
            throw DurableOperationError.invalidTransition
        }
        return resolved
    }

    public func count() throws -> Int {
        let statement = try database.prepare("SELECT COUNT(*) FROM helper_operations")
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw HelperDatabaseError.sqlite }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func find(deviceID: UUID, requestID: UUID) throws -> OperationStatus? {
        let statement = try database.prepare(
            "SELECT status_json FROM helper_operations WHERE device_id = ? AND request_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        bindText(deviceID.uuidString, to: statement, at: 1)
        bindText(requestID.uuidString, to: statement, at: 2)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try Self.decode(statement)
    }

    private func find(operationID: UUID) throws -> OperationStatus? {
        let statement = try database.prepare("SELECT status_json FROM helper_operations WHERE operation_id = ?")
        defer { sqlite3_finalize(statement) }
        bindText(operationID.uuidString, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_ROW else { return nil }
        return try Self.decode(statement)
    }

    private func makeRoom(at now: Date) throws {
        guard try count() >= limit else { return }
        let statement = try database.prepare("""
            DELETE FROM helper_operations WHERE rowid = (
                SELECT rowid FROM helper_operations
                WHERE state IN ('succeeded', 'failed', 'outcomeUncertain')
                  AND updated_at < ?
                ORDER BY rowid ASC LIMIT 1
            )
            """)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now.addingTimeInterval(-3_600).timeIntervalSince1970)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw HelperDatabaseError.sqlite }
        guard try count() < limit else { throw DurableOperationError.journalFull }
    }

    private static func recover(_ database: HelperDatabase, at now: Date) throws {
        try database.execute("BEGIN IMMEDIATE")
        do {
            let select = try database.prepare("SELECT operation_id, status_json FROM helper_operations")
            var updates: [(String, Data)] = []
            while true {
                let step = sqlite3_step(select)
                if step == SQLITE_DONE { break }
                guard step == SQLITE_ROW else { sqlite3_finalize(select); throw HelperDatabaseError.sqlite }
                guard let id = sqlite3_column_text(select, 0),
                      let data = readData(select, at: 1),
                      let status = try? JSONDecoder().decode(OperationStatus.self, from: data)
                else { sqlite3_finalize(select); throw DurableOperationError.corruptRecord }
                if [.accepted, .mutating, .reconciling, .draining].contains(status.state) {
                    let recovered = OperationStatus(
                        operationID: status.operationID, requestID: status.requestID,
                        commandID: status.commandID, state: .outcomeUncertain,
                        progress: nil,
                        error: SafeErrorResponse(code: .internalFailure, reason: .outcomeUncertain),
                        updatedAt: now
                    )
                    updates.append((String(cString: id), try JSONEncoder().encode(recovered)))
                }
            }
            sqlite3_finalize(select)
            for (id, data) in updates {
                let update = try database.prepare("UPDATE helper_operations SET state = ?, updated_at = ?, status_json = ? WHERE operation_id = ?")
                bindText(OperationState.outcomeUncertain.rawValue, to: update, at: 1)
                sqlite3_bind_double(update, 2, now.timeIntervalSince1970)
                bindData(data, to: update, at: 3)
                bindText(id, to: update, at: 4)
                let result = sqlite3_step(update)
                sqlite3_finalize(update)
                guard result == SQLITE_DONE else { throw HelperDatabaseError.sqlite }
            }
            try database.execute("COMMIT")
        } catch {
            try? database.execute("ROLLBACK")
            throw error
        }
    }

    private static func decode(_ statement: OpaquePointer) throws -> OperationStatus {
        guard let data = readData(statement, at: 0),
              let status = try? JSONDecoder().decode(OperationStatus.self, from: data)
        else { throw DurableOperationError.corruptRecord }
        return status
    }
}

public enum OperationExecutionResult: Sendable {
    case succeeded
    case failed(SafeErrorResponse)
    case outcomeUncertain
}

/// The closure is invoked once, after the intent commit. A thrown error is
/// uncertain because the mutation may have happened before the throw.
public actor DurableOperationExecutor: HostOperationDispatching {
    private let journal: PersistentOperationJournal
    private let audit: PersistentAuditLog?
    private let perform: @Sendable (AuthorizedCommand) async throws -> OperationExecutionResult

    public init(
        journal: PersistentOperationJournal,
        audit: PersistentAuditLog? = nil,
        perform: @escaping @Sendable (AuthorizedCommand) async throws -> OperationExecutionResult
    ) {
        self.journal = journal
        self.audit = audit
        self.perform = perform
    }

    public func dispatch(_ command: AuthorizedCommand) async throws -> OperationStatus {
        let claim = try await journal.claim(command)
        guard case let .execute(accepted) = claim else { return claim.status }
        if let audit {
            do {
                try await audit.append(.init(
                    at: .now, event: .dispatchIntent,
                    action: Self.auditAction(command.proposal.action),
                    deviceID: command.deviceID,
                    requestID: command.proposal.requestID,
                    commandID: command.commandID
                ))
            } catch {
                return try await journal.finish(
                    operationID: accepted.operationID, state: .failed,
                    error: .init(code: .internalFailure, reason: .internalFailure)
                )
            }
        }
        do {
            let result = try await perform(command)
            switch result {
            case .succeeded:
                let status = try await journal.finish(operationID: accepted.operationID, state: .succeeded)
                try? await audit?.append(.init(at: .now, event: .succeeded,
                                               action: Self.auditAction(command.proposal.action),
                                               deviceID: command.deviceID,
                                               requestID: command.proposal.requestID,
                                               commandID: command.commandID))
                return status
            case .failed(let error):
                let status = try await journal.finish(operationID: accepted.operationID, state: .failed, error: error)
                try? await audit?.append(.init(at: .now, event: .failed,
                                               action: Self.auditAction(command.proposal.action),
                                               deviceID: command.deviceID,
                                               requestID: command.proposal.requestID,
                                               commandID: command.commandID))
                return status
            case .outcomeUncertain:
                let status = try await journal.finish(operationID: accepted.operationID, state: .outcomeUncertain)
                try? await audit?.append(.init(at: .now, event: .outcomeUncertain,
                                               action: Self.auditAction(command.proposal.action),
                                               deviceID: command.deviceID,
                                               requestID: command.proposal.requestID,
                                               commandID: command.commandID))
                return status
            }
        } catch {
            return try await journal.finish(operationID: accepted.operationID, state: .outcomeUncertain)
        }
    }

    public func operation(_ operationID: UUID, deviceID: UUID) async -> OperationStatus? {
        try? await journal.status(operationID: operationID, deviceID: deviceID)
    }

    private static func auditAction(_ action: ControlAction) -> HelperAuditAction {
        switch action {
        case .providerLifecycle(.start): .providerStart
        case .providerLifecycle(.stop): .providerStop
        case .providerLifecycle(.restart): .providerRestart
        case .applySavedModelsLive: .providerLiveSwitch
        case .applySettings: .settingsPatch
        case .saveSettings: .settingsSave
        case .appLifecycle(.open): .appOpen
        case .appLifecycle(.quit): .appQuit
        case .appLifecycle(.relaunch): .appRelaunch
        }
    }
}
