import CryptoKit
import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Bounded verified performance decoding")
struct PerformanceHistoryDecodedCacheTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("warm reads reuse decoding but see an externally replaced middle payload")
    func externalMiddleReplacement() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let values = (0..<5).map { PerformanceSample(observedAt: now.addingTimeInterval(Double($0 - 5)), model: "a") }
        for sample in values { try db.record(sample) }
        #expect(try db.samples(in: interval) == values)
        #expect(try db.samples(in: interval) == values)
        #expect(db.decodedCacheDiagnostics.hits == 5)
        #expect(db.decodedCacheDiagnostics.misses == 0)
        let replacement = PerformanceSample(id: values[2].id, observedAt: values[2].observedAt, model: "a", tokensPerSecond: 73)
        try replacePayload(url, sample: replacement)
        var expected = values
        expected[2] = replacement
        #expect(try db.samples(in: interval) == expected)
        #expect(db.decodedCacheDiagnostics.hits == 4)
        #expect(db.decodedCacheDiagnostics.misses == 1)
    }

    @Test("warm payload reuse still rejects corrupt blobs and indexed fields")
    func warmCorruption() throws {
        for mutation in ["sample = X'00'", "model = 'b'", "observed_at = observed_at - 0.5", "id = '00000000-0000-0000-0000-000000000000'"] {
            let url = temporaryURL()
            defer { removeFiles(url) }
            let db = try database(url)
            let first = PerformanceSample(observedAt: now.addingTimeInterval(-3), model: "a")
            let middle = PerformanceSample(observedAt: now.addingTimeInterval(-2), model: "a")
            let last = PerformanceSample(observedAt: now.addingTimeInterval(-1), model: "a")
            for value in [first, middle, last] { try db.record(value) }
            _ = try db.samples(in: interval)
            let before = db.decodedCacheDiagnostics
            try withSQLite(url) { try execute($0, "UPDATE performance_history SET \(mutation) WHERE id = '\(middle.id.uuidString)'") }
            #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) { try db.samples(in: interval) }
            #expect(db.decodedCacheDiagnostics == before)
        }
    }

    @Test("a nil serving model cannot hide malformed indexed text")
    func malformedOptionalIndexedText() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try db.record(PerformanceSample(observedAt: now))
        _ = try db.recent()
        try withSQLite(url) { try execute($0, "UPDATE performance_history SET model = CAST(X'FF' AS TEXT)") }
        #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) { try db.recent() }
    }

    @Test("query order and serving filters remain authoritative after cache warming")
    func tiedOutOfOrderAndFilters() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let first = PerformanceSample(observedAt: now.addingTimeInterval(-2), model: "a", residentModels: ["b"])
        let second = PerformanceSample(observedAt: first.observedAt, model: "b", residentModels: ["a"])
        let older = PerformanceSample(observedAt: now.addingTimeInterval(-3), model: "a")
        let newest = PerformanceSample(observedAt: now.addingTimeInterval(-1), model: "b")
        for value in [first, second, older, newest] { try db.record(value) }
        #expect(try db.samples(in: interval) == [older, first, second, newest])
        #expect(try db.recent() == [newest, second, first, older])
        #expect(db.decodedCacheDiagnostics.hits == 4)
        #expect(try db.samples(in: interval, model: "a") == [older, first])
        #expect(try db.samples(in: interval, model: "b") == [second, newest])
        #expect(try db.samples(in: DateInterval(start: first.observedAt, end: first.observedAt)) == [first, second])
    }

    @Test("appends replay conflicts and pruning preserve committed cache semantics")
    func appendsAndPruning() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url, limit: 3)
        let values = (0..<4).map { PerformanceSample(observedAt: now.addingTimeInterval(Double($0 - 4))) }
        for value in values.prefix(3) { try db.record(value) }
        _ = try db.samples(in: interval)
        let before = db.decodedCacheDiagnostics
        try db.record(values[1])
        #expect(db.decodedCacheDiagnostics == before)
        #expect(throws: PerformanceHistoryDatabaseError.conflictingID) {
            try db.record(PerformanceSample(id: values[1].id, observedAt: values[1].observedAt, tokensPerSecond: 1))
        }
        #expect(db.decodedCacheDiagnostics == before)
        try db.record(values[3])
        #expect(try db.samples(in: interval) == Array(values.suffix(3)))
        #expect(db.decodedCacheDiagnostics.hits == 2)
        #expect(db.decodedCacheDiagnostics.misses == 1)
        #expect(db.decodedCacheDiagnostics.rows == 3)
        try db.record(PerformanceSample(observedAt: now.addingTimeInterval(-31 * 86_400)))
        #expect(try db.recent() == Array(values.suffix(3).reversed()))
    }

    @Test("failed write and partial failed scan do not publish a generation")
    func failedWriteAndRead() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url, limit: 3)
        let values = (0..<3).map { PerformanceSample(observedAt: now.addingTimeInterval(Double($0 - 3))) }
        for value in values { try db.record(value) }
        _ = try db.samples(in: interval)
        let before = db.decodedCacheDiagnostics
        try withSQLite(url) { try execute($0, "CREATE TRIGGER block_prune BEFORE DELETE ON performance_history BEGIN SELECT RAISE(ABORT, 'blocked'); END") }
        #expect(throws: PerformanceHistoryDatabaseError.unavailable) { try db.record(PerformanceSample(observedAt: now)) }
        #expect(db.decodedCacheDiagnostics == before)
        try withSQLite(url) {
            try execute($0, "DROP TRIGGER block_prune; UPDATE performance_history SET sample = X'00' WHERE id = '\(values[0].id.uuidString)'")
        }
        #expect(throws: PerformanceHistoryDatabaseError.corruptRecord) { try db.samples(in: interval) }
        #expect(db.decodedCacheDiagnostics == before)
        try replacePayload(url, sample: values[0])
        #expect(try db.samples(in: interval) == values)
        #expect(db.decodedCacheDiagnostics.hits == 3)
    }

    @Test("cancellation leaves a warmed generation unchanged")
    func cancelledRead() async throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let value = PerformanceSample(observedAt: now)
        try db.record(value)
        _ = try db.recent()
        let before = db.decodedCacheDiagnostics
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try db.samples(in: interval)
        }
        do {
            _ = try await task.value
            Issue.record("cancelled history read unexpectedly succeeded")
        } catch is CancellationError { }
        #expect(db.decodedCacheDiagnostics == before)
    }

    @Test("cancelling an active long scan preserves the prior generation")
    func cancelledActiveRead() async throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let clock = SignallingClock(now)
        let db = try PerformanceHistoryDatabase(url: url, now: { clock.value() })
        try insertMany(url, count: 12_000)
        _ = try db.recent(limit: 1)
        let before = db.decodedCacheDiagnostics
        clock.arm()
        let range = DateInterval(start: now.addingTimeInterval(-20_000), end: now)
        let task = Task.detached { try db.samples(in: range) }
        let started = await Task.detached { clock.waitForStart() }.value
        #expect(started)
        // The SQLite scan is already running; this fixture takes substantially
        // longer than this delay even under an optimized build.
        try await Task.sleep(for: .milliseconds(5))
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("active cancelled history scan unexpectedly succeeded")
        } catch is CancellationError { }
        #expect(db.decodedCacheDiagnostics == before)
        #expect(try db.recent(limit: 1).count == 1)
        #expect(db.decodedCacheDiagnostics.hits == 1)
    }

    @Test("age pruning removes warmed rows in the same database instance")
    func warmedAgePruning() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let clock = SignallingClock(now)
        let db = try PerformanceHistoryDatabase(url: url, now: { clock.value() })
        try db.record(PerformanceSample(observedAt: now))
        _ = try db.recent()
        clock.advance(by: 31 * 86_400)
        #expect(try db.recent().isEmpty)
        #expect(db.decodedCacheDiagnostics.rows == 0)
        #expect(db.decodedCacheDiagnostics.hits == 0)
        #expect(db.decodedCacheDiagnostics.misses == 0)
    }

    @Test("releasing derived cache preserves history and makes the next read cold")
    func clearingCache() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        let value = PerformanceSample(observedAt: now)
        try db.record(value)
        _ = try db.recent()
        _ = try db.recent()
        #expect(db.decodedCacheDiagnostics.hits == 1)
        #expect(db.clearDecodedReadCache() == 1)
        #expect(db.decodedCacheDiagnostics.rows == 0)
        #expect(db.decodedCacheDiagnostics.accountedBytes == 0)
        #expect(try db.retainedRecordCount() == 1)
        #expect(try db.recent() == [value])
        #expect(db.decodedCacheDiagnostics.hits == 0)
        #expect(db.decodedCacheDiagnostics.misses == 1)
        #expect(db.decodedCacheDiagnostics.peakAccountedBytes <= 16 * 1_024 * 1_024)
        _ = try db.recent()
        #expect(db.decodedCacheDiagnostics.peakAccountedBytes <= 32 * 1_024 * 1_024)
    }

    @Test("staged generations bound rows and bytes and retain the newest fitting rows")
    func boundedGeneration() {
        let values = (0..<8).map { PerformanceSample(observedAt: now.addingTimeInterval(Double($0 - 8))) }
        let rowBound = PerformanceHistoryDecodedCache.Builder(maximumRows: 3, maximumBytes: 16_384)
        for value in values.reversed() { rowBound.insert(entry(value)) }
        let retained = rowBound.finish()
        #expect(retained.entries.count == 3)
        #expect(Set(retained.entries.keys) == Set(values.suffix(3).map(\.id)))
        #expect(retained.accountedBytes <= 16_384)
        #expect(rowBound.admissionCost(of: values[0]) == nil)
        let builder = PerformanceHistoryDecodedCache.Builder(maximumRows: 100, maximumBytes: 2_048)
        for value in values.reversed() { builder.insert(entry(value)) }
        let generation = builder.finish()
        #expect(generation.entries.count > 0)
        #expect(generation.entries.count < 8)
        #expect(generation.accountedBytes <= 2_048)
        #expect(generation.entries[values.last!.id] != nil)
        let large = PerformanceSample(observedAt: now, residentModels: Array(repeating: String(repeating: "x", count: 160), count: 256))
        #expect(large.isValid)
        builder.insert(entry(large))
        #expect(builder.finish().entries[large.id] == nil)
        #expect(builder.finish().accountedBytes <= 2_048)
    }

    @Test("an oversized recent row does not displace fitting newer or older rows")
    func mixedAdmission() {
        let builder = PerformanceHistoryDecodedCache.Builder(maximumRows: 3, maximumBytes: 4_096)
        let newest = PerformanceSample(observedAt: now)
        let large = PerformanceSample(observedAt: now.addingTimeInterval(-1), residentModels: Array(repeating: String(repeating: "x", count: 160), count: 256))
        let older = PerformanceSample(observedAt: now.addingTimeInterval(-2))
        #expect(builder.admissionCost(of: newest) != nil)
        builder.insert(entry(newest))
        #expect(builder.admissionCost(of: large) == nil)
        builder.insert(entry(large))
        #expect(builder.admissionCost(of: older) != nil)
        builder.insert(entry(older))
        let generation = builder.finish()
        #expect(Set(generation.entries.keys) == [newest.id, older.id])
        #expect(generation.accountedBytes <= 4_096)
    }

    @Test("unretained misses still decode external edits without hashing the full scan")
    func unretainedMisses() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let db = try database(url)
        try insertMany(url, count: 33_000)
        let range = DateInterval(start: now.addingTimeInterval(-40_000), end: now)
        let first = try db.samples(in: range)
        #expect(first.count == 33_000)
        #expect(db.decodedCacheDiagnostics.hashedRows == db.decodedCacheDiagnostics.rows)
        #expect(db.decodedCacheDiagnostics.hashedRows < first.count)
        let prior = first[100]
        let replacement = PerformanceSample(id: prior.id, observedAt: prior.observedAt, tokensPerSecond: 77)
        try replacePayload(url, sample: replacement)
        let second = try db.samples(in: range)
        #expect(second[100] == replacement)
        #expect(second.first == first.first)
        #expect(second.last == first.last)
        #expect(db.decodedCacheDiagnostics.hashedRows == db.decodedCacheDiagnostics.rows)
        #expect(db.decodedCacheDiagnostics.hashedRows < second.count)
    }

    @Test("large scans cannot exceed either generation budget")
    func fullGenerationBudget() {
        let builder = PerformanceHistoryDecodedCache.Builder()
        var newestID = UUID()
        for offset in 0..<33_000 {
            let value = PerformanceSample(observedAt: now.addingTimeInterval(Double(-offset)))
            if offset == 0 { newestID = value.id }
            builder.insert(entry(value))
        }
        let generation = builder.finish()
        #expect(generation.entries.count > 0)
        #expect(generation.entries.count <= 32_768)
        #expect(generation.entries[newestID] != nil)
        #expect(generation.accountedBytes <= 16 * 1_024 * 1_024)
        #expect(builder.peakAccountedBytes <= 16 * 1_024 * 1_024)
        let disabled = PerformanceHistoryDecodedCache.Builder(maximumRows: 0, maximumBytes: 0)
        disabled.insert(entry(PerformanceSample(observedAt: now)))
        #expect(disabled.finish().entries.isEmpty)
        #expect(disabled.finish().accountedBytes == 0)
    }

    private var interval: DateInterval { DateInterval(start: now.addingTimeInterval(-100), end: now) }
    private func database(_ url: URL, limit: Int = 100_000) throws -> PerformanceHistoryDatabase {
        try PerformanceHistoryDatabase(url: url, historyLimit: limit, now: { Date(timeIntervalSince1970: 2_000_000_000) })
    }
    private func entry(_ value: PerformanceSample) -> PerformanceHistoryDecodedCache.Entry {
        PerformanceHistoryDecodedCache.Entry(digest: SHA256.hash(data: Data(value.id.uuidString.utf8)), sample: value)
    }
    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("bloomy-history-decoded-\(UUID().uuidString).sqlite3")
    }
    private func removeFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }
    private func withSQLite(_ url: URL, _ body: (OpaquePointer) throws -> Void) throws {
        var raw: OpaquePointer?
        #expect(sqlite3_open(url.path, &raw) == SQLITE_OK)
        let pointer = try #require(raw)
        defer { sqlite3_close(pointer) }
        try body(pointer)
    }
    private func execute(_ pointer: OpaquePointer, _ sql: String) throws {
        #expect(sqlite3_exec(pointer, sql, nil, nil, nil) == SQLITE_OK)
    }
    private func insertMany(_ url: URL, count: Int) throws {
        try withSQLite(url) { pointer in
            try execute(pointer, "BEGIN")
            var raw: OpaquePointer?
            #expect(sqlite3_prepare_v2(pointer, "INSERT INTO performance_history VALUES (?, ?, NULL, ?)", -1, &raw, nil) == SQLITE_OK)
            let statement = try #require(raw)
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            for offset in 0..<count {
                let sample = PerformanceSample(observedAt: now.addingTimeInterval(Double(-offset)))
                let payload = try encoder.encode(sample)
                #expect(sqlite3_bind_text(statement, 1, sample.id.uuidString, -1, transient) == SQLITE_OK)
                #expect(sqlite3_bind_double(statement, 2, sample.observedAt.timeIntervalSince1970) == SQLITE_OK)
                payload.withUnsafeBytes {
                    #expect(sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32($0.count), transient) == SQLITE_OK)
                }
                #expect(sqlite3_step(statement) == SQLITE_DONE)
                #expect(sqlite3_reset(statement) == SQLITE_OK)
            }
            try execute(pointer, "COMMIT")
        }
    }

    private func replacePayload(_ url: URL, sample: PerformanceSample) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let payload = try encoder.encode(sample)
        try withSQLite(url) { pointer in
            var raw: OpaquePointer?
            #expect(sqlite3_prepare_v2(pointer, "UPDATE performance_history SET sample = ? WHERE id = ?", -1, &raw, nil) == SQLITE_OK)
            let statement = try #require(raw)
            defer { sqlite3_finalize(statement) }
            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            payload.withUnsafeBytes {
                #expect(sqlite3_bind_blob(statement, 1, $0.baseAddress, Int32($0.count), transient) == SQLITE_OK)
            }
            #expect(sqlite3_bind_text(statement, 2, sample.id.uuidString, -1, transient) == SQLITE_OK)
            #expect(sqlite3_step(statement) == SQLITE_DONE)
        }
    }
}

private final class SignallingClock: @unchecked Sendable {
    let started = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var date: Date
    private var armed = false
    init(_ date: Date) { self.date = date }
    func value() -> Date {
        lock.lock()
        let signal = armed
        armed = false
        let result = date
        lock.unlock()
        if signal { started.signal() }
        return result
    }
    func waitForStart() -> Bool {
        started.wait(timeout: .now() + 5) == .success
    }
    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }
    func advance(by seconds: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(seconds)
        lock.unlock()
    }
}
