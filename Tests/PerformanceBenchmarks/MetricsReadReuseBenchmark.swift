// Synthetic, opt-in component comparison. Compile baseline without and
// candidate with -D METRICS_READ_REUSE, against their frozen Release libraries.
import DarkbloomTelemetry
import Foundation
import SQLite3

let seed = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
precondition(!FileManager.default.fileExists(atPath: output.path), "Preserve existing evidence")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let url = output.appendingPathComponent("history.sqlite")
try FileManager.default.copyItem(at: seed, to: url)
var pointer: OpaquePointer?
precondition(sqlite3_open_v2(url.path, &pointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK)
var statement: OpaquePointer?
precondition(sqlite3_prepare_v2(pointer, "SELECT MAX(observed_at),COUNT(*) FROM performance_history", -1, &statement, nil) == SQLITE_OK)
precondition(sqlite3_step(statement) == SQLITE_ROW)
let end = Date(timeIntervalSince1970: sqlite3_column_double(statement, 0))
precondition(sqlite3_column_int(statement, 1) == 100_000)
sqlite3_finalize(statement); sqlite3_close(pointer)
let database = try PerformanceHistoryDatabase(url: url, now: { end.addingTimeInterval(60) })
let range = DateInterval(start: end.addingTimeInterval(-30 * 86_400), end: end.addingTimeInterval(60))
#if METRICS_READ_REUSE
var previous: PerformanceHistoryReadSnapshot?
#endif
var reads: [[String: Any]] = []
func read(_ label: String) throws -> [PerformanceSample] {
    let start = ContinuousClock.now
    let samples: [PerformanceSample]
    var reused = 0
    #if METRICS_READ_REUSE
    let next = try database.readSnapshot(in: range, reusing: previous)
    previous = next; samples = next.samples; reused = next.reusedSampleCount
    #else
    samples = try database.samples(in: range)
    #endif
    let duration = start.duration(to: .now).components
    reads.append(["label": label, "rows": samples.count, "reused": reused,
        "milliseconds": Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15])
    return samples
}
let first = try read("initial")
precondition(first.count == 100_000)
for index in 0..<3 {
    let repeated = try read("repeat-\(index)")
    precondition(repeated == first)
}
var appended: [PerformanceSample] = []
for index in 0..<15 {
    let sample = PerformanceSample(observedAt: end.addingTimeInterval(Double(index + 1)),
        quality: index.isMultiple(of: 3) ? .unavailable : .current,
        providerSession: "4242:1800", model: index.isMultiple(of: 2) ? "qwen" : "gemma",
        residentModels: [index.isMultiple(of: 2) ? "qwen" : "gemma"], inferenceActive: false)
    try database.record(sample); appended.append(sample)
}
let updated = try read("after-15-inserts")
precondition(updated == Array(first.dropFirst(15)) + appended)
let result: [String: Any] = ["synthetic": true, "allFieldsAndOrderEqual": true, "reads": reads]
let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
try data.write(to: output.appendingPathComponent("result.json"), options: .atomic)
print(String(decoding: data, as: UTF8.self))
