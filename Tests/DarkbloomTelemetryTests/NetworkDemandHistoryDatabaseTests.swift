import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Private network demand persistence")
struct NetworkDemandHistoryDatabaseTests {
    // An exact bucket boundary keeps the cases below independent of rounding.
    private let fixedNow = Date(timeIntervalSince1970: 2_000_000_100)

    @Test("whole observations survive reopen, replay and same-time conflicts")
    func reopenReplayAndConflict() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let original = snapshot(at: fixedNow.addingTimeInterval(-30.000003), models: [model("b"), model("a", active: 3)])
        do {
            let db = try database(url)
            #expect(try db.record(original))
            #expect(try !db.record(original))
            // Model order is not part of the observation's identity.
            #expect(try !db.record(snapshot(at: original.capturedAt, models: Array(original.models.reversed()))))
        }
        let reopened = try database(url)
        #expect(try report(reopened).observations == [NetworkDemandHistoryObservation(snapshot: original)])
        #expect(throws: NetworkDemandHistoryDatabaseError.conflictingTimestamp) {
            try reopened.record(snapshot(at: original.capturedAt, models: [model("a", active: 4)]))
        }
        #expect(try report(reopened).observations == [NetworkDemandHistoryObservation(snapshot: original)])
    }

    @Test("later snapshots replace all models and older snapshots cannot overwrite")
    func replacementAndOutOfOrder() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let first = snapshot(at: fixedNow.addingTimeInterval(-280), models: [model("old"), model("removed")])
        let newer = snapshot(at: fixedNow.addingTimeInterval(-20), models: [model("new", active: 8)])
        #expect(try db.record(first))
        #expect(try db.record(newer))
        #expect(try !db.record(first))
        #expect(try report(db).observations == [NetworkDemandHistoryObservation(snapshot: newer)])
    }

    @Test("missing, draining and zero-provider samples preserve gaps")
    func gaps() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let snapshots = [
            snapshot(at: fixedNow.addingTimeInterval(-900), models: [model("busy", active: 8, warm: 0)]),
            snapshot(at: fixedNow.addingTimeInterval(-600), models: []),
            snapshot(at: fixedNow.addingTimeInterval(-300), models: [], draining: true),
            snapshot(at: fixedNow, models: [model("idle", active: 0, warm: 2)])
        ]
        for sample in snapshots.reversed() { try db.record(sample) }
        let observations = try report(db).observations
        #expect(observations == snapshots.map(NetworkDemandHistoryObservation.init(snapshot:)))
        #expect(observations[0].models[0].pressure == nil)
        #expect(observations[1].models.isEmpty)
        #expect(observations[2].isDraining)
        #expect(observations[3].models[0].pressure == 0)
    }

    @Test("both retention bounds apply on write, read and open")
    func retention() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let clock = DemandHistoryTestClock(fixedNow)
        do {
            let db = try NetworkDemandHistoryDatabase(url: url, maximumBuckets: 2, retentionHours: 1, now: { clock.read() })
            #expect(try !db.record(snapshot(at: fixedNow.addingTimeInterval(-3_601))))
            for offset in [-900.0, -600, -300] { try db.record(snapshot(at: fixedNow.addingTimeInterval(offset))) }
            #expect(try report(db).observations.map(\.capturedAt) == [-600.0, -300].map { fixedNow.addingTimeInterval($0) })
            clock.set(fixedNow.addingTimeInterval(3_601))
            #expect(try report(db).observations.isEmpty)
            clock.set(fixedNow)
            try db.record(snapshot(at: fixedNow))
        }
        clock.set(fixedNow.addingTimeInterval(72 * 3_600 + 1))
        let reopened = try NetworkDemandHistoryDatabase(url: url, now: { clock.read() })
        #expect(try report(reopened).observations.isEmpty)
    }

    @Test("requested caps are clamped to one through 864 buckets and 72 hours")
    func clampedCaps() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try NetworkDemandHistoryDatabase(url: url, maximumBuckets: .max, retentionHours: .max,
                                                 now: { Date(timeIntervalSince1970: 2_000_000_100) })
        // The 72-hour endpoints span 865 distinct buckets; the absolute cap is 864.
        for index in 0...864 { try db.record(snapshot(at: fixedNow.addingTimeInterval(Double(-index * 300)))) }
        let observations = try report(db).observations
        #expect(observations.count == 864)
        #expect(observations.first?.capturedAt == fixedNow.addingTimeInterval(-863 * 300))
        #expect(try !db.record(snapshot(at: fixedNow.addingTimeInterval(-72 * 3_600 - 1))))

        let smallURL = temporaryURL()
        defer { removeFiles(smallURL) }
        let small = try NetworkDemandHistoryDatabase(url: smallURL, maximumBuckets: .min, retentionHours: .min,
                                                    now: { Date(timeIntervalSince1970: 2_000_000_100) })
        #expect(try !small.record(snapshot(at: fixedNow.addingTimeInterval(-3_601))))
        try small.record(snapshot(at: fixedNow.addingTimeInterval(-300)))
        try small.record(snapshot(at: fixedNow))
        #expect(try report(small).observations.count == 1)
    }

    @Test("invalid input is rejected before storing even dropped source fields")
    func validation() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let original = snapshot(at: fixedNow)
        try db.record(original)
        let invalid = [
            snapshot(at: Date(timeIntervalSince1970: .infinity)),
            snapshot(at: Date(timeIntervalSince1970: .nan)),
            snapshot(at: Date(timeIntervalSince1970: -1)),
            snapshot(at: fixedNow.addingTimeInterval(6)),
            snapshot(at: fixedNow, models: [model(" ")]),
            snapshot(at: fixedNow, models: [model(String(repeating: "x", count: 513))]),
            snapshot(at: fixedNow, models: [model("a", active: -1)]),
            snapshot(at: fixedNow, models: [model("a", queued: -1)]),
            snapshot(at: fixedNow, models: [model("a", warm: -1)]),
            snapshot(at: fixedNow, models: [model("a", aggregateTPS: .nan)]),
            snapshot(at: fixedNow, models: [model("a", aggregateTPS: .infinity)]),
            snapshot(at: fixedNow, models: [model("a", aggregateTPS: -1)]),
            snapshot(at: fixedNow, models: [model("a"), model("a")]),
            snapshot(at: fixedNow, models: (0...128).map { model("m\($0)") }),
            snapshot(at: fixedNow, draining: true)
        ]
        for sample in invalid {
            #expect(throws: NetworkDemandHistoryDatabaseError.invalidSnapshot) { try db.record(sample) }
        }
        #expect(try report(db).observations == [NetworkDemandHistoryObservation(snapshot: original)])
    }

    @Test("encoded JSON size has an independent bound")
    func payloadCap() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        // These model IDs fit the input byte cap, but JSON escaping expands them.
        let models = (0..<128).map { model("\($0)" + String(repeating: "\u{0001}", count: 500)) }
        #expect(throws: NetworkDemandHistoryDatabaseError.invalidSnapshot) {
            try db.record(snapshot(at: fixedNow, models: models))
        }
        #expect(try report(db).observations.isEmpty)
    }

    @Test("range membership uses capture time and preserves the requested range")
    func ranges() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let sample = snapshot(at: fixedNow.addingTimeInterval(-10))
        try db.record(sample)
        let exact = DateInterval(start: sample.capturedAt, duration: 0)
        let result = try db.report(in: exact)
        #expect(result.range == exact)
        #expect(result.readAt == fixedNow)
        #expect(result.observations.count == 1)
        #expect(try db.report(in: DateInterval(start: fixedNow.addingTimeInterval(-299), duration: 1)).observations.isEmpty)
        for invalid in [
            DateInterval(start: fixedNow, duration: 72 * 3_600 + 1),
            DateInterval(start: Date(timeIntervalSince1970: -1), duration: 1),
            DateInterval(start: Date(timeIntervalSince1970: .infinity), duration: 1)
        ] {
            #expect(throws: NetworkDemandHistoryDatabaseError.invalidInterval) { try db.report(in: invalid) }
        }
    }

    @Test("failed pruning rolls back the entire new bucket")
    func rollback() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url, limit: 1)
        let first = snapshot(at: fixedNow.addingTimeInterval(-300), models: [model("a"), model("b")])
        try db.record(first)
        try rawSQL(url, "CREATE TRIGGER block_prune BEFORE DELETE ON network_demand_history BEGIN SELECT RAISE(ABORT, 'blocked'); END")
        #expect(throws: NetworkDemandHistoryDatabaseError.unavailable) { try db.record(snapshot(at: fixedNow)) }
        try rawSQL(url, "DROP TRIGGER block_prune")
        #expect(try report(db).observations == [NetworkDemandHistoryObservation(snapshot: first)])
    }

    @Test("failed replacement leaves all original models intact")
    func replacementRollback() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let first = snapshot(at: fixedNow.addingTimeInterval(-20), models: [model("a"), model("b")])
        try db.record(first)
        try rawSQL(url, "CREATE TRIGGER block_update BEFORE UPDATE ON network_demand_history BEGIN SELECT RAISE(ABORT, 'blocked'); END")
        #expect(throws: NetworkDemandHistoryDatabaseError.unavailable) { try db.record(snapshot(at: fixedNow.addingTimeInterval(-1))) }
        try rawSQL(url, "DROP TRIGGER block_update")
        #expect(try report(db).observations == [NetworkDemandHistoryObservation(snapshot: first)])
    }

    @Test("malformed files and any corrupt selected row fail the entire read")
    func corruption() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        try Data("not sqlite".utf8).write(to: url)
        #expect(throws: NetworkDemandHistoryDatabaseError.unavailable) { try database(url) }
        try FileManager.default.removeItem(at: url)
        let db = try database(url)
        try db.record(snapshot(at: fixedNow.addingTimeInterval(-300)))
        try db.record(snapshot(at: fixedNow))
        try rawSQL(url, "UPDATE network_demand_history SET observation = X'00' WHERE captured_at = 2000000100")
        #expect(throws: NetworkDemandHistoryDatabaseError.corruptRecord) { try report(db) }
    }

    @Test("every indexed field is checked against its payload")
    func indexedIntegrity() throws {
        for field in ["bucket_start", "captured_at"] {
            let url = temporaryURL()
            defer { removeFiles(url) }
            let db = try database(url)
            try db.record(snapshot(at: fixedNow.addingTimeInterval(-20)))
            try rawSQL(url, "UPDATE network_demand_history SET \(field) = \(field) + 1")
            #expect(throws: NetworkDemandHistoryDatabaseError.corruptRecord) { try report(db) }
        }
    }

    @Test("unknown persisted fields and oversized stored payloads are corrupt")
    func payloadIntegrity() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try db.record(snapshot(at: fixedNow))
        try rawSQL(url, "UPDATE network_demand_history SET observation = CAST(json_set(CAST(observation AS TEXT), '$.secret', 'private') AS BLOB)")
        #expect(throws: NetworkDemandHistoryDatabaseError.corruptRecord) { try report(db) }
        try rawSQL(url, "UPDATE network_demand_history SET observation = zeroblob(100001)")
        #expect(throws: NetworkDemandHistoryDatabaseError.corruptRecord) { try report(db) }
    }

    @Test("database and sidecars are private and only whitelisted fields persist")
    func privacy() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try db.record(snapshot(at: fixedNow, models: [model("public-model", active: 7, queued: 2, warm: 4, aggregateTPS: 123)]))
        for suffix in ["", "-wal", "-shm"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let data = try rawPayload(url)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == Set(["capturedAt", "models", "isDraining"]))
        let models = try #require(object["models"] as? [[String: Any]])
        #expect(Set(try #require(models.first).keys) == Set(["modelID", "activeRequests", "queuedRequests", "loadedProviders"]))
        #expect(!String(decoding: data, as: UTF8.self).contains("aggregate"))
    }

    @Test("independent connections serialize concurrent replacements and reads")
    func concurrency() async throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let first = try database(url)
        let second = try database(url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                let date = fixedNow.addingTimeInterval(Double(-index * 300))
                let early = snapshot(at: date.addingTimeInterval(-280), models: [model("early")])
                let latest = snapshot(at: date.addingTimeInterval(-20), models: [model("latest"), model("complete")])
                group.addTask { try first.record(early) }
                group.addTask { try second.record(latest) }
                group.addTask {
                    let rows = try self.report(first).observations
                    #expect(rows.allSatisfy { $0.models.map(\.modelID) == ["early"] || $0.models.map(\.modelID) == ["complete", "latest"] })
                }
            }
            try await group.waitForAll()
        }
        let rows = try report(first).observations
        #expect(rows.count == 40)
        #expect(rows.allSatisfy { $0.models.map(\.modelID) == ["complete", "latest"] })
    }

    @Test("cancellation and invalid clocks cannot mutate or publish history")
    func cancellationAndClock() async throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try db.record(snapshot(at: fixedNow)) }
            #expect(throws: CancellationError.self) { try report(db) }
        }
        await task.value
        #expect(try report(db).observations.isEmpty)
        let other = temporaryURL()
        defer { removeFiles(other) }
        #expect(throws: NetworkDemandHistoryDatabaseError.unavailable) {
            try NetworkDemandHistoryDatabase(url: other, now: { Date(timeIntervalSince1970: .nan) })
        }
    }

    private func snapshot(at date: Date, models: [NetworkModelCapacity]? = nil, draining: Bool = false) -> NetworkCapacitySnapshot {
        .init(models: models ?? [model("a")], capturedAt: date, isDraining: draining)
    }

    private func model(_ id: String, active: Int = 1, queued: Int = 0, warm: Int = 2, aggregateTPS: Double = 12) -> NetworkModelCapacity {
        .init(id: id, ready: true, canAccept: true, routableProviders: 3, warmProviders: warm,
              runningProviders: 2, coldProviders: 1, activeRequests: active, queuedRequests: queued,
              queueLimit: 20, aggregateTokensPerSecond: aggregateTPS, estimatedTimeToFirstTokenMS: 50,
              tokenBudgetRemaining: 100, tokenBudgetTotal: 200)
    }

    private func database(_ url: URL, limit: Int = 864) throws -> NetworkDemandHistoryDatabase {
        try NetworkDemandHistoryDatabase(url: url, maximumBuckets: limit,
                                         now: { Date(timeIntervalSince1970: 2_000_000_100) })
    }

    private func report(_ db: NetworkDemandHistoryDatabase) throws -> NetworkDemandHistoryReport {
        try db.report(in: DateInterval(start: fixedNow.addingTimeInterval(-72 * 3_600), end: fixedNow))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("darkbloom-demand-\(UUID().uuidString).sqlite3")
    }

    private func removeFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private func rawSQL(_ url: URL, _ sql: String) throws {
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let pointer = try #require(raw)
        defer { sqlite3_close(pointer) }
        sqlite3_busy_timeout(pointer, 2_000)
        #expect(sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK)
    }

    private func rawPayload(_ url: URL) throws -> Data {
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let pointer = try #require(raw)
        defer { sqlite3_close(pointer) }
        var statement: OpaquePointer?
        #expect(sqlite3_prepare_v2(pointer, "SELECT observation FROM network_demand_history", -1, &statement, nil) == SQLITE_OK)
        let selected = try #require(statement)
        defer { sqlite3_finalize(selected) }
        #expect(sqlite3_step(selected) == SQLITE_ROW)
        return Data(bytes: try #require(sqlite3_column_blob(selected, 0)), count: Int(sqlite3_column_bytes(selected, 0)))
    }
}

private final class DemandHistoryTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return value }
    func set(_ value: Date) { lock.lock(); defer { lock.unlock() }; self.value = value }
}
