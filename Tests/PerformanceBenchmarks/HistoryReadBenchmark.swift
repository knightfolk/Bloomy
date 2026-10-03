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

func residentBytes() -> UInt64 {
    var information = mach_task_basic_info()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &information) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
        }
    }
    precondition(result == KERN_SUCCESS)
    return information.resident_size
}

func identifier(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", UInt64(index + 1)))!
}

// This mode intentionally releases returned arrays between reads. Compare two
// isolated executables linked to the baseline/candidate libraries; allocator
// reuse and SQLite pages are still included, so RSS is not a precise cache size.
@inline(never)
func readAndDiscard(_ database: PerformanceHistoryDatabase, count: Int) throws {
    let samples = try database.samples(in: range)
    precondition(samples.count == count)
    precondition(samples.first?.id == identifier(0))
    precondition(samples.last?.id == identifier(count - 1))
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
        let sample = PerformanceSample(id: identifier(index), observedAt: date, sourceCapturedAt: date,
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

func rawPayloadScan(_ url: URL, count: Int) {
    var raw: OpaquePointer?
    precondition(sqlite3_open_v2(url.path, &raw, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
    let connection = raw!
    defer { sqlite3_close(connection) }
    var prepared: OpaquePointer?
    precondition(sqlite3_prepare_v2(connection,
        "SELECT sample FROM performance_history ORDER BY observed_at,rowid", -1, &prepared, nil) == SQLITE_OK)
    let statement = prepared!
    defer { sqlite3_finalize(statement) }
    var rows = 0
    var bytes = 0
    while sqlite3_step(statement) == SQLITE_ROW {
        let size = Int(sqlite3_column_bytes(statement, 0))
        let payload = Data(bytes: sqlite3_column_blob(statement, 0)!, count: size)
        precondition(payload.first == UInt8(ascii: "{"))
        bytes += payload.count
        rows += 1
    }
    precondition(rows == count && bytes > 0)
}

if ProcessInfo.processInfo.environment["BLOOMY_HISTORY_MEMORY_ONLY"] == "1" {
    let count = Int(ProcessInfo.processInfo.environment["BLOOMY_HISTORY_MEMORY_ROWS"] ?? "100000")!
    precondition((1...100_000).contains(count))
    let url = outputDirectory.appendingPathComponent("memory-history.sqlite3")
    precondition(!FileManager.default.fileExists(atPath: url.path))
    let database = try PerformanceHistoryDatabase(url: url, now: { end })
    try seed(url, count: count)
    let before = residentBytes()
    var readings: [UInt64] = []
    var times: [Double] = []
    for _ in 0..<4 {
        let (_, time) = try elapsed { try readAndDiscard(database, count: count) }
        times.append(time)
        readings.append(residentBytes())
    }
    let data = try JSONSerialization.data(withJSONObject: ["rows": count,
        "residentBeforeReadBytes": before, "residentAfterDiscardedReadsBytes": readings,
        "readMilliseconds": times], options: [.prettyPrinted, .sortedKeys])
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

var results: [[String: Any]] = []
for count in [10_000, 100_000] {
    let url = outputDirectory.appendingPathComponent("history-\(count).sqlite3")
    precondition(!FileManager.default.fileExists(atPath: url.path), "Choose a fresh output directory")
    let database = try PerformanceHistoryDatabase(url: url, now: { end })
    try seed(url, count: count)
    let (_, rawScan) = elapsed { rawPayloadScan(url, count: count) }
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
    var appended: [PerformanceSample] = []
    for index in 0..<15 {
        let sample = PerformanceSample(id: identifier(count + index),
            observedAt: end.addingTimeInterval(-15 + Double(index)),
            quality: .unavailable, model: "qwen")
        try database.record(sample)
        appended.append(sample)
    }
    let (updated, updatedTime) = try elapsed { try database.samples(in: range) }
    precondition(updated.count == min(count + 15, PerformanceHistoryDatabase.maximumHistoryLimit))
    let evicted = max(count + 15 - PerformanceHistoryDatabase.maximumHistoryLimit, 0)
    precondition(updated == Array(baseline.dropFirst(evicted)) + appended)
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    results.append(["rows": count, "coldReadMilliseconds": cold,
        "rawPayloadScanMilliseconds": rawScan,
        "repeatReadMilliseconds": reads, "repeatMedianMilliseconds": reads.sorted()[1],
        "summaryMilliseconds": summaryTime, "visitsMilliseconds": visitTime,
        "readAfter15InsertsMilliseconds": updatedTime, "updatedRows": updated.count,
        "peakRSSBytes": usage.ru_maxrss])
}
let json = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: json, as: UTF8.self))
