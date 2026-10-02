import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Private performance persistence")
struct PerformanceHistoryDatabaseTests {
    private let fixedNow = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("inventory waiting remains a valid private measurement through reopen")
    func waitingInventory() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let sample = PerformanceSample(
            observedAt: fixedNow, sourceCapturedAt: fixedNow.addingTimeInterval(-1), quality: .current,
            providerSession: "123:100", model: "gemma", inferenceActive: true,
            tokensPerSecond: 12, tokensGenerated: 40, requestsServed: 2,
            autopilotPhase: "waiting_inventory"
        )
        #expect(sample.isValid)
        do { try database(url).record(sample) }
        #expect(try database(url).recent() == [sample])
    }

    @Test("all structured metrics survive reopen and exact replay")
    func reopenAndReplay() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let time = fixedNow.addingTimeInterval(-30.000003)
        let sample = PerformanceSample(
            observedAt: time, sourceCapturedAt: time.addingTimeInterval(-1.000002), quality: .current,
            providerSession: "123:1999999900.000001", model: "qwen/qwen3", residentModels: ["qwen/qwen3", "other"],
            advertisedModels: ["qwen/qwen3"], inferenceActive: true, activeRequests: 2,
            tokensPerSecond: 31.5, tokensGenerated: 100, requestsServed: 10,
            gpuUtilizationPercent: 55, gpuMemoryGB: 12, powerWatts: 35, autopilotPhase: "active"
        )
        do {
            let db = try database(url)
            try db.record(sample)
        }
        let reopened = try database(url)
        #expect(try reopened.recent() == [sample])
        try reopened.record(sample)
        #expect(try reopened.retainedRecordCount() == 1)
        #expect(throws: PerformanceHistoryDatabaseError.conflictingID) {
            try reopened.record(PerformanceSample(id: sample.id, observedAt: time, quality: .stale))
        }
        #expect(try reopened.recent() == [sample])
    }

    @Test("intervals are chronological and only serving model matches a filter")
    func orderingAndServingAttribution() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let first = PerformanceSample(observedAt: fixedNow.addingTimeInterval(-60), model: "a", residentModels: ["b"])
        let second = PerformanceSample(observedAt: fixedNow.addingTimeInterval(-30), model: "b", residentModels: ["a"])
        try db.record(second)
        try db.record(first)
        let range = DateInterval(start: fixedNow.addingTimeInterval(-90), end: fixedNow)
        #expect(try db.samples(in: range) == [first, second])
        #expect(try db.samples(in: range, model: "a") == [first])
        #expect(try db.recent(limit: 1) == [second])
        #expect(try db.recent(limit: 0).isEmpty)
    }

    @Test("both retention bounds apply to writes and reopening")
    func retention() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        do {
            let db = try database(url, limit: 3)
            try db.record(PerformanceSample(observedAt: fixedNow.addingTimeInterval(-31 * 86_400)))
            for offset in (-5 ... -1) { try db.record(PerformanceSample(observedAt: fixedNow.addingTimeInterval(Double(offset)))) }
            #expect(try db.retainedRecordCount() == 3)
            #expect(try db.recent(limit: 20).map(\.observedAt) == [-1.0, -2, -3].map { fixedNow.addingTimeInterval($0) })
        }
        let later = try PerformanceHistoryDatabase(url: url, now: { Date(timeIntervalSince1970: 2_000_000_000 + 31 * 86_400) })
        #expect(try later.recent().isEmpty)
    }

    @Test("invalid fields and numeric values are rejected without losing prior samples")
    func validation() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let original = PerformanceSample(observedAt: fixedNow)
        try db.record(original)
        let invalid: [PerformanceSample] = [
            PerformanceSample(observedAt: Date(timeIntervalSince1970: .infinity)),
            PerformanceSample(observedAt: fixedNow, sourceCapturedAt: Date(timeIntervalSince1970: .nan)),
            PerformanceSample(observedAt: fixedNow, sourceCapturedAt: fixedNow.addingTimeInterval(1)),
            PerformanceSample(observedAt: fixedNow, model: "model\nAuthorization: Bearer secret"),
            PerformanceSample(observedAt: fixedNow, model: String(repeating: "x", count: 161)),
            PerformanceSample(observedAt: fixedNow, advertisedModels: Array(repeating: "a", count: 257)),
            PerformanceSample(observedAt: fixedNow, providerSession: "account-secret"),
            PerformanceSample(observedAt: fixedNow, autopilotPhase: "error with private text"),
            PerformanceSample(observedAt: fixedNow, autopilotPhase: "private-secret"),
            PerformanceSample(observedAt: fixedNow, activeRequests: -1),
            PerformanceSample(observedAt: fixedNow, tokensPerSecond: .nan),
            PerformanceSample(observedAt: fixedNow, tokensGenerated: -1),
            PerformanceSample(observedAt: fixedNow, requestsServed: -1),
            PerformanceSample(observedAt: fixedNow, gpuUtilizationPercent: 101),
            PerformanceSample(observedAt: fixedNow, gpuMemoryGB: -1),
            PerformanceSample(observedAt: fixedNow, powerWatts: .infinity),
            PerformanceSample(observedAt: fixedNow.addingTimeInterval(86_401))
        ]
        for sample in invalid {
            #expect(throws: PerformanceHistoryDatabaseError.invalidSample) { try db.record(sample) }
        }
        #expect(try db.recent() == [original])
    }

    @Test("corrupt files and rows fail explicitly rather than truncate a result")
    func corruption() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        try Data("invalid sqlite".utf8).write(to: url)
        #expect(throws: PerformanceHistoryDatabaseError.unavailable) { try database(url) }
        try FileManager.default.removeItem(at: url)
        let db = try database(url)
        try db.record(PerformanceSample(observedAt: fixedNow))
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let pointer = try #require(raw)
        defer { sqlite3_close(pointer) }
        #expect(sqlite3_exec(pointer, "INSERT INTO performance_history VALUES ('bad-id', 2000000000, NULL, X'00')", nil, nil, nil) == SQLITE_OK)
        #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) { try db.recent() }
        #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) {
            try db.samples(in: DateInterval(start: fixedNow.addingTimeInterval(-60), end: fixedNow))
        }
    }

    @Test("failed pruning rolls back the inserted sample and keeps earlier history")
    func transactionRollback() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url, limit: 1)
        let first = PerformanceSample(observedAt: fixedNow.addingTimeInterval(-30))
        try db.record(first)
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let pointer = try #require(raw)
        defer { sqlite3_close(pointer) }
        #expect(sqlite3_exec(pointer, "CREATE TRIGGER block_prune BEFORE DELETE ON performance_history BEGIN SELECT RAISE(ABORT, 'blocked'); END", nil, nil, nil) == SQLITE_OK)
        #expect(throws: PerformanceHistoryDatabaseError.unavailable) {
            try db.record(PerformanceSample(observedAt: fixedNow))
        }
        #expect(sqlite3_exec(pointer, "DROP TRIGGER block_prune", nil, nil, nil) == SQLITE_OK)
        #expect(try db.recent() == [first])
    }

    @Test("tampered indexed fields are reported as corrupted measurements")
    func indexedFieldIntegrity() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try db.record(PerformanceSample(observedAt: fixedNow, model: "a"))
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let pointer = try #require(raw)
        defer { sqlite3_close(pointer) }
        #expect(sqlite3_exec(pointer, "UPDATE performance_history SET model = 'b'", nil, nil, nil) == SQLITE_OK)
        #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) { try db.recent() }
    }

    @Test("permissions remain private and JSON contains only the measurement whitelist")
    func privacy() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try db.record(PerformanceSample(observedAt: fixedNow))
        for suffix in ["", "-wal", "-shm"] {
            let path = url.path + suffix
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
        let data = try JSONEncoder().encode(try #require(db.recent().first))
        let fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(fields.keys) == Set(["id", "observedAt", "quality", "residentModels", "advertisedModels"]))
    }

    @Test("concurrent writers retain every sample")
    func concurrentWrites() async throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<40 {
                let sample = PerformanceSample(observedAt: fixedNow.addingTimeInterval(Double(-index)))
                group.addTask { try db.record(sample) }
            }
            try await group.waitForAll()
        }
        #expect(try db.retainedRecordCount() == 40)
    }

    private func database(_ url: URL, limit: Int = 100_000) throws -> PerformanceHistoryDatabase {
        try PerformanceHistoryDatabase(url: url, historyLimit: limit, now: { Date(timeIntervalSince1970: 2_000_000_000) })
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("darkbloom-performance-\(UUID().uuidString).sqlite3")
    }

    private func removeFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
}
