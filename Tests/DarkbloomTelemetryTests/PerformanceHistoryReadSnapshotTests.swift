import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

struct PerformanceHistoryReadSnapshotTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private var interval: DateInterval { .init(start: now.addingTimeInterval(-30 * 86_400), end: now.addingTimeInterval(60)) }

    @Test("snapshot repeats preserve every field, unknown gaps and insertion order at tied timestamps")
    func completeRepeat() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let samples = [
            sample(0, id: UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!),
            sample(0, id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, model: nil, quality: .unavailable),
            sample(0, model: "gemma", quality: .stale), sample(30, model: "gemma")
        ]
        for row in samples { try db.record(row) }
        let first = try db.readSnapshot(in: interval)
        #expect(first.samples == samples)
        #expect(first.reusedSampleCount == 0)
        let next = try db.readSnapshot(in: interval, reusing: first)
        #expect(next.samples == samples)
        #expect(next.reusedSampleCount == samples.count)
        #expect(PerformanceSummary(samples: next.samples) == PerformanceSummary(samples: samples))
    }

    @Test("changing periods and serving-model filters query current membership and retain all-model gaps")
    func movingScopes() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        for index in 0..<30 { try db.record(sample(index * 30, model: index % 3 == 0 ? nil : (index % 2 == 0 ? "qwen" : "gemma"))) }
        var previous = try db.readSnapshot(in: interval)
        for (start, end, model) in [(100, 600, nil), (300, 800, "gemma"), (0, 900, nil), (0, 900, "qwen"), (500, 510, nil)] as [(Int, Int, String?)] {
            let range = DateInterval(start: now.addingTimeInterval(Double(start - 1_000)), end: now.addingTimeInterval(Double(end - 1_000)))
            let next = try db.readSnapshot(in: range, model: model, reusing: previous)
            #expect(next.samples == (try db.samples(in: range, model: model)))
            previous = next
        }
    }

    @Test("new out-of-order and tied rows decode while unchanged local rows reuse")
    func localInsertion() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let first = sample(200), last = sample(400)
        try db.record(first); try db.record(last)
        let prior = try db.readSnapshot(in: interval)
        let older = sample(100, quality: .stale), tie = sample(200, model: nil), middle = sample(300)
        try db.record(older); try db.record(tie); try db.record(middle)
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.samples == [older, first, tie, middle, last])
        #expect(next.reusedSampleCount == 2)
        #expect(next.samples == (try db.samples(in: interval)))
    }

    @Test("replays and conflicts do not publish inserts or replace completed snapshots")
    func replayConflict() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let original = sample(0)
        try db.record(original)
        let prior = try db.readSnapshot(in: interval)
        try db.record(original)
        #expect(throws: PerformanceHistoryDatabaseError.conflictingID) { try db.record(sample(0, id: original.id, rate: 99)) }
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.samples == [original])
        #expect(next.reusedSampleCount == 1)
    }

    @Test("overflow retention removes old membership while preserving remaining payloads")
    func retainedMembership() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url, limit: 3)
        let rows = (0..<5).map { sample($0 * 30) }
        for row in rows.prefix(3) { try db.record(row) }
        let prior = try db.readSnapshot(in: interval)
        for row in rows.suffix(2) { try db.record(row) }
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.samples == Array(rows.suffix(3)))
        #expect(next.reusedSampleCount == 1)
    }

    @Test("locally recycled rowid and UUID with identical indexed fields still decode the replacement payload")
    func localRowIDReuse() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let clock = SnapshotTestClock(now)
        let db = try PerformanceHistoryDatabase(url: url, now: { clock.read() })
        let original = sample(0)
        try db.record(original)
        let prior = try db.readSnapshot(in: interval)
        clock.set(now.addingTimeInterval(31 * 86_400))
        #expect(try db.retainedRecordCount() == 0)
        clock.set(now)
        let replacement = sample(0, id: original.id, rate: 81)
        try db.record(replacement)
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.rowIDs == prior.rowIDs)
        #expect(next.samples == [replacement])
        #expect(next.reusedSampleCount == 0)
    }

    @Test("snapshots from another database instance or expired insertion history force full validation")
    func ownershipAndJournalOverflow() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        try db.record(sample(0))
        let prior = try db.readSnapshot(in: interval)
        let reopened = try database(url)
        let foreign = try reopened.readSnapshot(in: interval, reusing: prior)
        #expect(foreign.samples == prior.samples)
        #expect(foreign.reusedSampleCount == 0)
        for index in 1...513 { try db.record(sample(index)) }
        let expired = try db.readSnapshot(in: interval, reusing: prior)
        #expect(expired.samples == (try db.samples(in: interval)))
        #expect(expired.reusedSampleCount == 0)
        #expect(try db.readSnapshot(in: interval, reusing: expired).reusedSampleCount == 514)
    }

    @Test("external BLOB corrections invalidate reuse even when indexed fields and rowids stay unchanged")
    func outsideCorrection() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let original = sample(0)
        try db.record(original)
        let prior = try db.readSnapshot(in: interval)
        let replacement = sample(0, id: original.id, rate: 75)
        try withRaw(url) { try updatePayload($0, sample: replacement) }
        let corrected = try db.readSnapshot(in: interval, reusing: prior)
        #expect(corrected.samples == [replacement])
        #expect(corrected.reusedSampleCount == 0)
        #expect(prior.samples == [original])
    }

    @Test("outside deletion and recycled insertion cannot reuse stale samples")
    func outsideRowIDReuse() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let original = sample(0)
        try db.record(original)
        let prior = try db.readSnapshot(in: interval)
        let replacement = sample(0, id: original.id, rate: 70)
        let payload = try JSONEncoder().encode(replacement).map { String(format: "%02x", $0) }.joined()
        try withRaw(url) { pointer in
            try execute(pointer, "BEGIN IMMEDIATE; DELETE FROM performance_history; INSERT INTO performance_history VALUES ('\(replacement.id)', \(replacement.observedAt.timeIntervalSince1970), 'qwen', X'\(payload)'); COMMIT")
        }
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.rowIDs == prior.rowIDs)
        #expect(next.samples == [replacement])
        #expect(next.reusedSampleCount == 0)
    }

    @Test("outside payload or indexed-column corruption fails explicitly with prior results intact")
    func corruption() throws {
        for sql in ["UPDATE performance_history SET sample = X'00'", "UPDATE performance_history SET model = 'wrong'", "UPDATE performance_history SET observed_at = observed_at + 1", "UPDATE performance_history SET id = 'invalid'"] {
            let url = temporaryURL(); defer { removeFiles(url) }
            let db = try database(url)
            let original = sample(0)
            try db.record(original)
            let prior = try db.readSnapshot(in: interval)
            try withRaw(url) { try execute($0, sql) }
            #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) { try db.readSnapshot(in: interval, reusing: prior) }
            #expect(prior.samples == [original])
        }
    }

    @Test("failed write transactions never publish partially inserted rows")
    func rollback() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url, limit: 1)
        let original = sample(0)
        try db.record(original)
        let prior = try db.readSnapshot(in: interval)
        try withRaw(url) { try execute($0, "CREATE TRIGGER block_delete BEFORE DELETE ON performance_history BEGIN SELECT RAISE(ABORT, 'blocked'); END") }
        #expect(throws: PerformanceHistoryDatabaseError.unavailable) { try db.record(sample(1)) }
        try withRaw(url) { try execute($0, "DROP TRIGGER block_delete") }
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.samples == [original])
        #expect(try db.readSnapshot(in: interval, reusing: next).reusedSampleCount == 1)
    }

    @Test("cancelled reads leave the completed reuse token valid and release the transaction")
    func cancellation() async throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        try db.record(sample(0))
        let prior = try db.readSnapshot(in: interval)
        let range = interval
        let cancelled = Task.detached {
            withUnsafeCurrentTask { $0?.cancel() }
            return try db.readSnapshot(in: range, reusing: prior)
        }
        do { _ = try await cancelled.value; Issue.record("Cancelled read unexpectedly completed") }
        catch { #expect(error is CancellationError) }
        #expect(try db.readSnapshot(in: interval, reusing: prior).reusedSampleCount == 1)
        try db.record(sample(1))
        #expect(try db.retainedRecordCount() == 2)
    }

    @Test("unmanaged triggers that mutate old payloads during local writes disable reuse")
    func triggeredCorrections() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let original = sample(0)
        try db.record(original)
        let corrected = sample(0, id: original.id, rate: 79)
        let payload = try JSONEncoder().encode(corrected).map { String(format: "%02x", $0) }.joined()
        try withRaw(url) { try execute($0, "CREATE TRIGGER correct_previous AFTER INSERT ON performance_history BEGIN UPDATE performance_history SET sample = X'\(payload)' WHERE id = '\(original.id)'; END") }
        let prior = try db.readSnapshot(in: interval)
        #expect(prior.dataVersion == nil)
        try db.record(sample(1))
        let next = try db.readSnapshot(in: interval, reusing: prior)
        #expect(next.samples.first == corrected)
        #expect(next.reusedSampleCount == 0)
        #expect(next.samples == (try db.samples(in: interval)))
    }

    @Test("deterministic mixed histories match ordinary reads and summaries over changing scopes")
    func mixedHistoryParity() throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url, limit: 350)
        var previous: PerformanceHistoryReadSnapshot?
        for batch in 0..<20 {
            for index in 0..<25 {
                let n = batch * 25 + index
                try db.record(sample((n * 137) % 1_000, model: n % 4 == 0 ? nil : (n % 3 == 0 ? "gemma" : "qwen"), quality: PerformanceSampleQuality.allCases[n % 3], rate: Double(n % 100)))
            }
            let start = (batch * 71) % 500
            let range = DateInterval(start: now.addingTimeInterval(Double(start - 1_000)), end: now)
            let model: String? = batch % 3 == 0 ? "gemma" : nil
            let next = try db.readSnapshot(in: range, model: model, reusing: previous)
            let ordinary = try db.samples(in: range, model: model)
            #expect(next.samples == ordinary)
            #expect(PerformanceSummary(samples: next.samples) == PerformanceSummary(samples: ordinary))
            previous = next
        }
    }

    @Test("atomic external corrections remain internally consistent across concurrent reads")
    func concurrentOutsideWrites() async throws {
        let url = temporaryURL(); defer { removeFiles(url) }
        let db = try database(url)
        let rows = (0..<128).map { sample($0) }
        for row in rows { try db.record(row) }
        let range = interval
        // Each commit changes all rows as one transaction. A result mixing the
        // two phases would expose an unpinned lookup or an unfenced reused row.
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try withRaw(url) { pointer in
                    for phase in 0..<30 {
                        try execute(pointer, "BEGIN IMMEDIATE")
                        for row in rows {
                            let corrected = PerformanceSample(id: row.id, observedAt: row.observedAt, model: row.model, tokensPerSecond: phase.isMultiple(of: 2) ? 40 : 80)
                            try updatePayload(pointer, sample: corrected)
                        }
                        try execute(pointer, "COMMIT")
                    }
                }
            }
            group.addTask {
                var previous: PerformanceHistoryReadSnapshot?
                for _ in 0..<60 {
                    let next = try db.readSnapshot(in: range, reusing: previous)
                    #expect(next.samples.count == rows.count)
                    #expect(Set(next.samples.compactMap(\.tokensPerSecond)).count == 1)
                    previous = next
                }
            }
            try await group.waitForAll()
        }
    }

    private func sample(_ offset: Int, id: UUID = UUID(), model: String? = "qwen", quality: PerformanceSampleQuality = .current, rate: Double = 40) -> PerformanceSample {
        let date = now.addingTimeInterval(Double(offset - 1_000))
        return PerformanceSample(id: id, observedAt: date, sourceCapturedAt: date.addingTimeInterval(-1), quality: quality,
            providerSession: "123:1999990000", model: model, residentModels: ["qwen", "gemma"], advertisedModels: ["qwen", "gemma", "bonsai"],
            inferenceActive: true, activeRequests: 2, tokensPerSecond: rate, tokensGenerated: Int64(offset * 100), requestsServed: Int64(offset),
            gpuUtilizationPercent: 55, gpuMemoryGB: 12, powerWatts: 35, autopilotPhase: "shadow")
    }
    private func database(_ url: URL, limit: Int = 100_000) throws -> PerformanceHistoryDatabase {
        try PerformanceHistoryDatabase(url: url, historyLimit: limit, now: { Date(timeIntervalSince1970: 2_000_000_000) })
    }
    private func temporaryURL() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("snapshot-test-\(UUID()).sqlite") }
    private func removeFiles(_ url: URL) { for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) } }
}

private final class SnapshotTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date
    init(_ date: Date) { self.date = date }
    func read() -> Date { lock.lock(); defer { lock.unlock() }; return date }
    func set(_ date: Date) { lock.lock(); defer { lock.unlock() }; self.date = date }
}

private func withRaw(_ url: URL, _ body: (OpaquePointer) throws -> Void) throws {
    var raw: OpaquePointer?
    guard sqlite3_open(url.path, &raw) == SQLITE_OK, let pointer = raw else {
        if let raw { sqlite3_close(raw) }
        throw PerformanceHistoryDatabaseError.unavailable
    }
    defer { sqlite3_close(pointer) }
    sqlite3_busy_timeout(pointer, 2_000)
    try body(pointer)
}

private func execute(_ pointer: OpaquePointer, _ sql: String) throws {
    guard sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK else { throw PerformanceHistoryDatabaseError.unavailable }
}

private func updatePayload(_ pointer: OpaquePointer, sample: PerformanceSample) throws {
    let payload = try JSONEncoder().encode(sample).map { String(format: "%02x", $0) }.joined()
    try execute(pointer, "UPDATE performance_history SET sample = X'\(payload)' WHERE id = '\(sample.id)'")
}
