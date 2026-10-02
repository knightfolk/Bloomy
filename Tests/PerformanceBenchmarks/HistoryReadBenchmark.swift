// Opt-in, synthetic benchmark. See docs/METRICS_REFRESH_OPTIMIZATION_20261002.md.
import DarkbloomTelemetry
import Foundation
import SQLite3
import Darwin

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
let end = Date(timeIntervalSince1970: 2_000_000_000)
let range = DateInterval(start: end.addingTimeInterval(-30 * 86_400), end: end)
let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

func elapsed<T>(_ operation: () throws -> T) rethrows -> (T, Double) {
    let start = ContinuousClock.now
    let result = try operation()
    let duration = start.duration(to: .now).components
    return (result, Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
}

func seed(_ url: URL, count: Int) throws {
    var raw: OpaquePointer?
    precondition(sqlite3_open(url.path, &raw) == SQLITE_OK)
    let connection = raw!
    defer { sqlite3_close(connection) }
    precondition(sqlite3_exec(connection, "BEGIN IMMEDIATE", nil, nil, nil) == SQLITE_OK)
    var prepared: OpaquePointer?
    precondition(sqlite3_prepare_v2(connection,
        "INSERT INTO performance_history(id,observed_at,model,sample) VALUES(?,?,?,?)",
        -1, &prepared, nil) == SQLITE_OK)
    let statement = prepared!
    defer { sqlite3_finalize(statement) }
    let encoder = JSONEncoder()
    for index in 0..<count {
        let date = end.addingTimeInterval(-Double(count - index) * 24)
        let model = (index / 60).isMultiple(of: 2) ? "qwen" : "gemma"
        let quality: PerformanceSampleQuality = index.isMultiple(of: 151) ? .unavailable
            : index.isMultiple(of: 73) ? .stale : .current
        let sample = PerformanceSample(observedAt: date, sourceCapturedAt: date,
            quality: quality, providerSession: "1:100", model: model,
            residentModels: [model], advertisedModels: ["qwen", "gemma"],
            inferenceActive: quality == .current ? index.isMultiple(of: 3) : nil,
            tokensPerSecond: quality == .current ? 40 : nil,
            tokensGenerated: Int64(index * 100), requestsServed: Int64(index / 3))
        let payload = try encoder.encode(sample)
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        precondition(sqlite3_bind_text(statement, 1, sample.id.uuidString, -1, transient) == SQLITE_OK)
        precondition(sqlite3_bind_double(statement, 2, date.timeIntervalSince1970) == SQLITE_OK)
        precondition(sqlite3_bind_text(statement, 3, model, -1, transient) == SQLITE_OK)
        payload.withUnsafeBytes { bytes in
            precondition(sqlite3_bind_blob(statement, 4, bytes.baseAddress, Int32(bytes.count), transient) == SQLITE_OK)
            precondition(sqlite3_step(statement) == SQLITE_DONE)
        }
    }
    precondition(sqlite3_exec(connection, "COMMIT", nil, nil, nil) == SQLITE_OK)
}

var results: [[String: Any]] = []
for count in [10_000, 100_000] {
    let url = outputDirectory.appendingPathComponent("history-\(count).sqlite3")
    precondition(!FileManager.default.fileExists(atPath: url.path), "Choose a fresh output directory")
    let database = try PerformanceHistoryDatabase(url: url, now: { end })
    try seed(url, count: count)
    let (baseline, cold) = try elapsed { try database.samples(in: range) }
    precondition(baseline.count == count)
    var reads: [Double] = []
    for _ in 0..<3 {
        let (samples, milliseconds) = try elapsed { try database.samples(in: range) }
        precondition(samples == baseline)
        reads.append(milliseconds)
    }
    let (_, summaryTime) = elapsed { PerformanceSummary(samples: baseline) }
    let (_, visitTime) = elapsed { ModelVisitHistory(samples: baseline, period: range) }
    for index in 0..<15 {
        try database.record(PerformanceSample(observedAt: end.addingTimeInterval(-15 + Double(index)),
            quality: .unavailable, model: "qwen"))
    }
    let (updated, updatedTime) = try elapsed { try database.samples(in: range) }
    precondition(updated.count == min(count + 15, PerformanceHistoryDatabase.maximumHistoryLimit))
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    results.append(["rows": count, "coldReadMilliseconds": cold,
        "repeatReadMilliseconds": reads, "repeatMedianMilliseconds": reads.sorted()[1],
        "summaryMilliseconds": summaryTime, "visitsMilliseconds": visitTime,
        "readAfter15InsertsMilliseconds": updatedTime, "updatedRows": updated.count,
        "peakRSSBytes": usage.ru_maxrss])
}
let json = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
