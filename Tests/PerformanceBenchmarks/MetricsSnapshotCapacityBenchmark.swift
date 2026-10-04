// Opt-in synthetic Release capacity/timing probe. Pass a closed seed and fresh output directory.
import Foundation
import SQLite3
import DarkbloomTelemetry
let source = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2], isDirectory: true)
precondition(!FileManager.default.fileExists(atPath: output.path), "Preserve previous evidence")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
let path = output.appendingPathComponent("history.sqlite")
try FileManager.default.copyItem(at: source, to: path)
var conn: OpaquePointer?; precondition(sqlite3_open(path.path, &conn) == SQLITE_OK)
var stmt: OpaquePointer?; precondition(sqlite3_prepare_v2(conn, "SELECT MAX(observed_at) FROM performance_history", -1, &stmt, nil) == SQLITE_OK)
precondition(sqlite3_step(stmt) == SQLITE_ROW)
let end = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0))
sqlite3_finalize(stmt); sqlite3_close(conn)
let db = try PerformanceHistoryDatabase(url: path, now: { end.addingTimeInterval(1) })
var prior: PerformanceHistoryReadSnapshot?
var broad: [PerformanceSample] = []
var narrow: [PerformanceSample] = []
var timings: [[String: Any]] = []
for (name, seconds, reuse) in [("cold24h", 86400.0, false), ("expand30d", 2592000.0, true), ("repeat30d", 2592000.0, true), ("cold30d", 2592000.0, false), ("shrink24h", 86400.0, true)] {
 let started = ContinuousClock.now
 let next = try db.readSnapshot(in: .init(start: end.addingTimeInterval(-seconds), end: end), reusing: reuse ? prior : nil)
 let duration = started.duration(to: .now).components
 FileHandle.standardOutput.write(Data("\(name): count=\(next.samples.count), capacity=\(next.samples.capacity), stride=\(MemoryLayout<PerformanceSample>.stride), reused=\(next.reusedSampleCount), ms=\(Double(duration.seconds)*1000+Double(duration.attoseconds)/1e15)\n".utf8))
 if next.samples.count == 100_000 {
  if broad.isEmpty { broad = next.samples } else { precondition(next.samples == broad) }
 } else {
  if narrow.isEmpty { narrow = next.samples } else { precondition(next.samples == narrow) }
 }

 timings.append(["phase": name, "rows": next.samples.count, "capacity": next.samples.capacity,
  "reused": next.reusedSampleCount, "milliseconds": Double(duration.seconds)*1000+Double(duration.attoseconds)/1e15])
 prior = next
}

let ordinary = try db.samples(in: .init(start: end.addingTimeInterval(-2592000), end: end))
precondition(broad == ordinary)
let ordinaryNarrow = try db.samples(in: .init(start: end.addingTimeInterval(-86400), end: end))
precondition(narrow == ordinaryNarrow)
let result: [String: Any] = ["synthetic": true, "allFieldsAndOrderEqual": true,
 "sampleStride": MemoryLayout<PerformanceSample>.stride, "reads": timings]
try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
 .write(to: output.appendingPathComponent("result.json"), options: .atomic)
