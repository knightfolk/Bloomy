import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Action history persistence")
struct ActionHistoryDatabaseTests {
    private let fixedNow = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("actions and typed job data survive reopening")
    func survivesRestart() throws {
        let url = temporaryDatabaseURL()
        let occurred = fixedNow.addingTimeInterval(-60)
        let id = ActionHistoryEvent.deterministicID(namespace: "earning", key: "812")
        let event = ActionHistoryEvent(
            id: id,
            occurredAt: occurred,
            action: .job,
            trigger: .provider,
            outcome: .succeeded,
            model: "qwen/qwen3-coder",
            correlationID: UUID(),
            job: ActionHistoryJob(
                earningID: 812, promptTokens: 120, completionTokens: 40, amountMicroUSD: 17
            )
        )
        do {
            let database = try makeDatabase(url: url)
            try database.record(event)
        }
        let reopened = try makeDatabase(url: url)
        #expect(try reopened.recent() == [event])
        #expect(ActionHistoryEvent.deterministicID(namespace: "earning", key: "812") == id)
        #expect(ActionHistoryEvent.deterministicID(namespace: "earning", key: "813") != id)
    }

    @Test("fractional account timestamp replays after a SQLite round trip")
    func fractionalTimestampReplay() throws {
        let url = temporaryDatabaseURL()
        let occurred = fixedNow.addingTimeInterval(-60).addingTimeInterval(0.000002)
        let captured = fixedNow.addingTimeInterval(-5).addingTimeInterval(0.000003)
        let event = ActionHistoryEvent(
            id: ActionHistoryEvent.deterministicID(namespace: "account", key: "fractional-812"),
            occurredAt: occurred, updatedAt: captured,
            action: .job, trigger: .provider, outcome: .succeeded,
            model: "qwen3-coder",
            job: ActionHistoryJob(earningID: 812, promptTokens: 120,
                                  completionTokens: 40, amountMicroUSD: 17)
        )
        do {
            let database = try makeDatabase(url: url)
            try database.record(event)
        }
        let reopened = try makeDatabase(url: url)
        let persisted = try #require(reopened.recent().first)
        // The Date reference-epoch value loses a fraction of a microsecond
        // when stored as SQLite's Unix-epoch REAL, despite representing the
        // same persisted timestamp.
        #expect(persisted.occurredAt != event.occurredAt)
        #expect(persisted.occurredAt.timeIntervalSince1970 == event.occurredAt.timeIntervalSince1970)
        try reopened.record(event)
        #expect(try reopened.retainedRecordCount() == 1)
    }

    @Test("a genuinely different timestamp cannot reuse an action ID")
    func timestampConflict() throws {
        let database = try makeDatabase(url: temporaryDatabaseURL())
        let id = ActionHistoryEvent.deterministicID(namespace: "account", key: "timestamp-conflict")
        let occurred = fixedNow.addingTimeInterval(-60).addingTimeInterval(0.000002)
        let first = ActionHistoryEvent(
            id: id, occurredAt: occurred, action: .job,
            trigger: .provider, outcome: .succeeded,
            model: "qwen3-coder",
            job: ActionHistoryJob(earningID: 813, promptTokens: 10,
                                  completionTokens: 20, amountMicroUSD: 5)
        )
        try database.record(first)
        let conflicting = ActionHistoryEvent(
            id: id, occurredAt: occurred.addingTimeInterval(0.001),
            action: .job, trigger: .provider, outcome: .succeeded,
            model: "qwen3-coder",
            job: first.job
        )
        #expect(throws: ActionHistoryDatabaseError.conflictingID) {
            try database.record(conflicting)
        }
        #expect(try database.retainedRecordCount() == 1)
    }

    @Test("newer account data corrects an earning without making a second row")
    func correctedEarning() throws {
        let database = try makeDatabase(url: temporaryDatabaseURL())
        let id = ActionHistoryEvent.deterministicID(namespace: "account", key: "812")
        func earning(amount: Int64, capturedAt: Date) -> ActionHistoryEvent {
            ActionHistoryEvent(
                id: id, occurredAt: fixedNow.addingTimeInterval(-60), updatedAt: capturedAt,
                action: .job, trigger: .provider, outcome: .succeeded,
                model: "qwen3-coder",
                job: ActionHistoryJob(earningID: 812, promptTokens: 120,
                                      completionTokens: 40, amountMicroUSD: amount)
            )
        }
        let first = earning(amount: 10, capturedAt: fixedNow.addingTimeInterval(-20))
        let corrected = earning(amount: 17, capturedAt: fixedNow.addingTimeInterval(-10))
        try database.record(first)
        try database.record(corrected)
        try database.record(first)
        #expect(try database.recent().count == 1)
        #expect(try database.recent().first?.job?.amountMicroUSD == 17)
        #expect(try database.recent().first?.updatedAt == corrected.updatedAt)
    }

    @Test("one attempt updates to a final outcome without moving its start time")
    func idempotentOutcomeUpdate() throws {
        let database = try makeDatabase(url: temporaryDatabaseURL())
        let event = ActionHistoryEvent(
            id: ActionHistoryEvent.deterministicID(namespace: "nudge", key: "session-1"),
            occurredAt: fixedNow.addingTimeInterval(-30),
            action: .nudge,
            trigger: .automatic,
            outcome: .started,
            model: "qwen3-coder"
        )
        try database.record(event)
        let finished = fixedNow.addingTimeInterval(-5)
        try database.updateOutcome(id: event.id, outcome: .failed, reason: .requestFailed, updatedAt: finished)
        try database.record(event)
        try database.updateOutcome(id: event.id, outcome: .failed, reason: .requestFailed, updatedAt: fixedNow)
        let rows = try database.recent()
        #expect(rows.count == 1)
        #expect(rows[0].occurredAt == event.occurredAt)
        #expect(rows[0].updatedAt == finished)
        #expect(rows[0].outcome == .failed)
        #expect(rows[0].reason == .requestFailed)
        #expect(throws: ActionHistoryDatabaseError.invalidTransition) {
            try database.updateOutcome(id: event.id, outcome: .succeeded, updatedAt: fixedNow)
        }
    }

    @Test("unconfirmed attempts may resolve to a confirmed outcome")
    func lateConfirmation() throws {
        let database = try makeDatabase(url: temporaryDatabaseURL())
        let event = ActionHistoryEvent(
            occurredAt: fixedNow.addingTimeInterval(-30),
            action: .swap, trigger: .manual, outcome: .started
        )
        try database.record(event)
        try database.updateOutcome(id: event.id, outcome: .unconfirmed, reason: .notConfirmed,
                                   updatedAt: fixedNow.addingTimeInterval(-20))
        try database.updateOutcome(id: event.id, outcome: .succeeded, updatedAt: fixedNow)
        #expect(try database.recent().first?.outcome == .succeeded)
    }

    @Test("age and row limits are applied on writes and after reopening")
    func boundedRetention() throws {
        let url = temporaryDatabaseURL()
        let database = try makeDatabase(url: url, historyLimit: 3)
        try database.record(event(at: fixedNow.addingTimeInterval(-31 * 86_400), key: "expired"))
        for index in 0..<5 {
            try database.record(event(at: fixedNow.addingTimeInterval(Double(index - 5)), key: "\(index)"))
        }
        #expect(try database.recent(limit: 10).count == 3)
        #expect(try database.recent(limit: 10).map(\.id) == (2..<5).reversed().map {
            ActionHistoryEvent.deterministicID(namespace: "test", key: "\($0)")
        })

        let later = try ActionHistoryDatabase(
            url: url, historyLimit: 3,
            now: { Date(timeIntervalSince1970: 2_000_000_000 + 31 * 86_400) }
        )
        #expect(try later.recent().isEmpty)
    }

    @Test("reopening applies simultaneous age and count limits with stable timestamp ties",
          arguments: [1, 3, 37], [1, 7, 30])
    func retentionMatchesOrderedReference(limit: Int, days: Int) throws {
        let url = temporaryDatabaseURL()
        let rows = (0..<80).map { index in
            // Repeated timestamps and interleaved ages deliberately disagree
            // with UUID lexical order and insertion order.
            let age = [0, 1, 7, 29][(index * 17) % 4]
            return event(at: fixedNow.addingTimeInterval(-Double(age) * 86_400), key: "tie-\(index)")
        }
        do {
            let original = try makeDatabase(url: url)
            for row in rows { try original.record(row) }
        }
        let reopened = try ActionHistoryDatabase(url: url, historyLimit: limit,
                                                retentionDays: days, now: { Date(timeIntervalSince1970: 2_000_000_001) })
        let cutoff = fixedNow.addingTimeInterval(1 - Double(days) * 86_400)
        let expected = rows.enumerated().sorted {
            $0.element.occurredAt == $1.element.occurredAt
                ? $0.offset > $1.offset
                : $0.element.occurredAt > $1.element.occurredAt
        }.prefix(limit).map(\.element).filter { $0.occurredAt >= cutoff }
        #expect(try reopened.recent(limit: 5_000) == expected)
        #expect(try reopened.retainedRecordCount() == expected.count)
        // A subsequent read must not reorder or remove the remaining rows.
        #expect(try reopened.recent(limit: 5_000) == expected)
    }

    @Test("retention includes the exact age boundary and expires it after time advances")
    func ageBoundaryIsInclusive() throws {
        let url = temporaryDatabaseURL()
        let boundary = event(at: fixedNow.addingTimeInterval(-30 * 86_400), key: "boundary")
        do {
            let database = try makeDatabase(url: url)
            try database.record(event(at: boundary.occurredAt.addingTimeInterval(-1), key: "too-old"))
            try database.record(boundary)
            #expect(try database.recent() == [boundary])
        }
        let later = try ActionHistoryDatabase(url: url, now: { Date(timeIntervalSince1970: 2_000_000_001) })
        #expect(try later.recent(limit: 0).isEmpty)
        #expect(try later.retainedRecordCount() == 0)
    }

    @Test("replaying a retained equal-timestamp entry does not move it ahead of later inserts")
    func tiedReplayDoesNotChangeRetentionOrder() throws {
        let database = try makeDatabase(url: temporaryDatabaseURL(), historyLimit: 3)
        let first = event(at: fixedNow, key: "first")
        let second = event(at: fixedNow, key: "second")
        let third = event(at: fixedNow, key: "third")
        let fourth = event(at: fixedNow, key: "fourth")
        for row in [first, second, third, first, fourth] { try database.record(row) }
        #expect(try database.recent() == [fourth, third, second])
    }

    @Test("bad files and malformed event data fail visibly")
    func errorsAreVisible() throws {
        let corruptURL = temporaryDatabaseURL()
        try Data("not a sqlite database".utf8).write(to: corruptURL)
        #expect(throws: ActionHistoryDatabaseError.unavailable) {
            try ActionHistoryDatabase(url: corruptURL)
        }

        let database = try makeDatabase(url: temporaryDatabaseURL())
        #expect(throws: ActionHistoryDatabaseError.invalidEvent) {
            try database.record(ActionHistoryEvent(
                occurredAt: fixedNow, action: .nudge, trigger: .automatic,
                outcome: .failed, model: "model\nAuthorization: Bearer secret"
            ))
        }
        #expect(throws: ActionHistoryDatabaseError.missingEvent) {
            try database.updateOutcome(id: UUID(), outcome: .failed, updatedAt: fixedNow)
        }
    }

    @Test("a malformed row is reported instead of disappearing from history")
    func corruptRowIsVisible() throws {
        let url = temporaryDatabaseURL()
        let database = try makeDatabase(url: url)
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        guard let raw else { return }
        defer { sqlite3_close(raw) }
        let sql = """
            INSERT INTO action_history
            (id, occurred_at, updated_at, action, trigger, outcome)
            VALUES ('bad-id', 2000000000, 2000000000, 'unknown', 'system', 'succeeded')
            """
        #expect(sqlite3_exec(raw, sql, nil, nil, nil) == SQLITE_OK)
        #expect(throws: ActionHistoryDatabaseError.corruptRecord) {
            try database.recent()
        }
    }

    @Test("journal file is private and stores no arbitrary message fields")
    func privateStructuredData() throws {
        let url = temporaryDatabaseURL()
        let database = try makeDatabase(url: url)
        try database.record(event(at: fixedNow, key: "private"))
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        for suffix in ["-wal", "-shm"] {
            let sidecar = url.path + suffix
            if FileManager.default.fileExists(atPath: sidecar) {
                let sidecarAttributes = try FileManager.default.attributesOfItem(atPath: sidecar)
                #expect((sidecarAttributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
            }
        }
        let json = try JSONEncoder().encode(try database.recent().first!)
        let keys = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(Set(keys.keys) == Set(["id", "occurredAt", "updatedAt", "action", "trigger", "outcome"]))
    }

    private func event(at time: Date, key: String) -> ActionHistoryEvent {
        ActionHistoryEvent(
            id: ActionHistoryEvent.deterministicID(namespace: "test", key: key),
            occurredAt: time, action: .watcher, trigger: .system, outcome: .succeeded
        )
    }

    private func makeDatabase(url: URL, historyLimit: Int = 5_000) throws -> ActionHistoryDatabase {
        try ActionHistoryDatabase(url: url, historyLimit: historyLimit, now: {
            Date(timeIntervalSince1970: 2_000_000_000)
        })
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("darkbloom-action-history-\(UUID().uuidString).sqlite3")
    }
}
