import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Performance history query efficiency")
struct PerformanceHistoryEfficiencyTests {
    @Test("legacy indexes migrate without losing tied observations")
    func migrationPreservesOrder() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let first = PerformanceSample(observedAt: now, model: "qwen")
        let second = PerformanceSample(observedAt: now, model: "qwen")
        do {
            let db = try PerformanceHistoryDatabase(url: url, now: { now })
            try db.record(first)
            try db.record(second)
        }
        try withSQLite(url) { pointer in
            try execute(pointer, """
                DROP INDEX performance_history_time_order;
                DROP INDEX performance_history_model_time_order;
                CREATE INDEX performance_history_observed_at ON performance_history(observed_at,id);
                CREATE INDEX performance_history_model_observed_at ON performance_history(model,observed_at,id);
                """)
        }
        let migrated = try PerformanceHistoryDatabase(url: url, now: { now })
        let range = DateInterval(start: now.addingTimeInterval(-1), end: now)
        #expect(try migrated.samples(in: range) == [first, second])
        #expect(try migrated.samples(in: range, model: "qwen") == [first, second])
        #expect(try migrated.recent() == [second, first])
        try withSQLite(url) { pointer in
            for sql in [
                "SELECT id,observed_at,model,sample FROM performance_history WHERE observed_at>=0 AND observed_at<=2000000000 ORDER BY observed_at,rowid",
                "SELECT id,observed_at,model,sample FROM performance_history WHERE model='qwen' AND observed_at>=0 AND observed_at<=2000000000 ORDER BY observed_at,rowid",
                "SELECT rowid FROM performance_history ORDER BY observed_at DESC,rowid DESC LIMIT -1 OFFSET 100000"
            ] {
                let plan = try queryPlan(pointer, sql)
                #expect(!plan.contains(where: { $0.contains("TEMP B-TREE") }))
                #expect(plan.contains(where: { $0.contains("INDEX performance_history_") }))
            }
        }
    }

    @Test("cap preserves newest insertion order across replay and out-of-order samples")
    func tiedRetention() throws {
        let url = temporaryURL()
        defer { removeFiles(url) }
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let db = try PerformanceHistoryDatabase(url: url, historyLimit: 3, now: { now })
        let samples = (0..<4).map { _ in PerformanceSample(observedAt: now, model: "qwen") }
        for sample in samples { try db.record(sample) }
        #expect(try db.retainedRecordCount() == 3)
        #expect(try db.recent() == Array(samples.suffix(3).reversed()))
        try db.record(samples[2])
        try db.record(PerformanceSample(observedAt: now.addingTimeInterval(-10), model: "gemma"))
        #expect(try db.recent() == Array(samples.suffix(3).reversed()))
        #expect(try db.retainedRecordCount() == 3)
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("bloomy-history-efficiency-\(UUID().uuidString).sqlite3")
    }

    private func removeFiles(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
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

    private func queryPlan(_ pointer: OpaquePointer, _ sql: String) throws -> [String] {
        var raw: OpaquePointer?
        #expect(sqlite3_prepare_v2(pointer, "EXPLAIN QUERY PLAN " + sql, -1, &raw, nil) == SQLITE_OK)
        let statement = try #require(raw)
        defer { sqlite3_finalize(statement) }
        var result: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let value = sqlite3_column_text(statement, 3) {
                result.append(String(cString: value))
            }
        }
        return result
    }
}
