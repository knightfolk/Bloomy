import DarkbloomCompanionHelper
import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import Foundation
import Testing

@Suite("Companion helper durability")
struct HelperDurabilityTests {
    @Test("one runtime owns the lock until it exits")
    func singleOwner() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("runtime.lock")
        var first: RuntimeOwnershipLock? = try RuntimeOwnershipLock(url: url)
        #expect(throws: HelperOwnershipError.alreadyOwned) { try RuntimeOwnershipLock(url: url) }
        first = nil
        withExtendedLifetime(first) {}
        let second = try RuntimeOwnershipLock(url: url)
        withExtendedLifetime(second) {}
    }

    @Test("intent survives reopen as uncertain and duplicate request never executes again")
    func crashRecoveryAndIdempotence() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("operations.sqlite3")
        let command = makeCommand()
        let intent: OperationStatus
        do {
            let journal = try PersistentOperationJournal(url: url)
            let claim = try await journal.claim(command)
            guard case let .execute(status) = claim else { Issue.record("missing first claim"); return }
            intent = status
            #expect(try await journal.claim(command) == .existing(intent))
            #expect(try await journal.count() == 1)
        }
        let reopened = try PersistentOperationJournal(url: url)
        let recovered = try await reopened.status(operationID: intent.operationID, deviceID: command.deviceID)
        #expect(recovered?.state == .outcomeUncertain)
        #expect(try await reopened.claim(command) == .existing(recovered!))
        await #expect(throws: DurableOperationError.duplicateRequestConflict) {
            try await reopened.claim(makeCommand(requestID: command.proposal.requestID, deviceID: command.deviceID))
        }
        await #expect(throws: DurableOperationError.invalidTransition) {
            try await reopened.finish(operationID: intent.operationID, state: .succeeded)
        }
        await #expect(throws: DurableOperationError.invalidTransition) {
            try await reopened.reconcile(
                operationID: intent.operationID, deviceID: UUID(), finding: .succeeded
            )
        }
        let resolved = try await reopened.reconcile(
            operationID: intent.operationID, deviceID: command.deviceID, finding: .succeeded
        )
        #expect(resolved.state == .succeeded)
        #expect(try await reopened.claim(command) == .existing(resolved))
    }

    @Test("executor commits intent before callback and duplicate requests do not call callback")
    func intentBeforeExecution() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try PersistentOperationJournal(url: directory.appendingPathComponent("operations.sqlite3"))
        let audit = try PersistentAuditLog(url: directory.appendingPathComponent("audit.sqlite3"))
        let probe = ExecutionProbe()
        let executor = DurableOperationExecutor(journal: journal, audit: audit) { command in
            let claim = try await journal.claim(command)
            await probe.note(claim)
            await probe.noteAudit(try await audit.recent().contains { $0.event == .dispatchIntent })
            return .succeeded
        }
        let command = makeCommand()
        let first = try await executor.dispatch(command)
        let second = try await executor.dispatch(command)
        #expect(first == second)
        #expect(first.state == .succeeded)
        #expect(await probe.callCount == 1)
        #expect(await probe.sawExistingIntent)
        #expect(await probe.sawAuditIntent)
    }

    @Test("retention evicts completed records but never discards unresolved intent")
    func operationRetention() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try PersistentOperationJournal(
            url: directory.appendingPathComponent("operations.sqlite3"), limit: 1
        )
        let start = Date(timeIntervalSince1970: 1_000_000)
        let first = makeCommand()
        let firstClaim = try await journal.claim(first, at: start)
        await #expect(throws: DurableOperationError.journalFull) {
            try await journal.claim(makeCommand(), at: start.addingTimeInterval(60))
        }
        _ = try await journal.finish(
            operationID: firstClaim.status.operationID, state: .succeeded, at: start
        )
        let second = makeCommand()
        await #expect(throws: DurableOperationError.journalFull) {
            try await journal.claim(second, at: start.addingTimeInterval(60))
        }
        #expect(try await journal.claim(second, at: start.addingTimeInterval(3_601)).status.state == .accepted)
        #expect(try await journal.count() == 1)
        #expect(try await journal.status(operationID: firstClaim.status.operationID, deviceID: first.deviceID) == nil)
    }

    @Test("audit is capped and fixed-code records cannot carry private payload text")
    func auditPrivacyAndRetention() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("audit.sqlite3")
        let journal = try PersistentAuditLog(url: url, limit: 2)
        let device = UUID()
        for event in [HelperAuditEvent.prepared, .dispatchIntent, .succeeded] {
            try await journal.append(.init(at: .now, event: event, action: .providerRestart, deviceID: device))
        }
        let values = try await journal.recent(limit: 10)
        #expect(values.map(\.event) == [.dispatchIntent, .succeeded])
        let reopened = try PersistentAuditLog(url: url, limit: 2)
        #expect(try await reopened.recent(limit: 10) == values)
        let bytes = try Data(contentsOf: url)
        #expect(!String(decoding: bytes, as: UTF8.self).contains("SECRET_CANARY"))
    }

    private func makeCommand(requestID: UUID = UUID(), deviceID: UUID = UUID()) -> AuthorizedCommand {
        AuthorizedCommand(
            commandID: UUID(),
            proposal: .init(requestID: requestID, action: .providerLifecycle(.restart)),
            deviceID: deviceID
        )
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("helper-test-\(UUID().uuidString)")
    }
}

private actor ExecutionProbe {
    private(set) var callCount = 0
    private(set) var sawExistingIntent = false
    private(set) var sawAuditIntent = false
    func note(_ claim: OperationClaim) {
        callCount += 1
        if case .existing = claim { sawExistingIntent = true }
    }
    func noteAudit(_ value: Bool) { sawAuditIntent = value }
}
