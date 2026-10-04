// Finite opt-in fixture seeder. Always writes a new explicitly supplied file.
import DarkbloomTelemetry
import Foundation
import SQLite3

guard CommandLine.arguments.count == 2 else {
    fatalError("Pass one new synthetic SQLite output path")
}
func seed() throws {
    let output = URL(fileURLWithPath: CommandLine.arguments[1])
    precondition(!FileManager.default.fileExists(atPath: output.path), "Preserve existing evidence")
    let count = PerformanceHistoryDatabase.maximumHistoryLimit
    let endingAt = Date()
    let models = ["qwen3.8-27b", "gemma-4-26b-qat-4bit", "gpt-oss-20b", "ternary-bonsai-2-27b"]
    let database = try PerformanceHistoryDatabase(url: output, now: { endingAt })
    let clock = ContinuousClock()
    let started = clock.now
    var requests: Int64 = 0
    var tokens: Int64 = 0
    for index in 0..<count {
        let date = endingAt.addingTimeInterval(Double(index - count + 1) * 25)
        let visit = index / 60
        let model = models[visit % models.count]
        let idleVisit = visit.isMultiple(of: 10)
        // Keep boundary counters flat so a new model's work cannot leak backwards.
        let active = !idleVisit && index % 60 != 0 && !index.isMultiple(of: 4)
        if active { requests += 1; tokens += 300 }
        let gap = index % 12_000
        let quality: PerformanceSampleQuality = (10..<13).contains(gap) ? .unavailable
            : (13..<16).contains(gap) ? .stale : .current
        let current = quality == .current
        let sample = PerformanceSample(
            id: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", UInt64(index + 1)))!,
            observedAt: date, sourceCapturedAt: current ? date : date.addingTimeInterval(-60),
            quality: quality, providerSession: "4242:1800", model: model,
            residentModels: [model], advertisedModels: models,
            inferenceActive: current ? active : nil, activeRequests: current ? (active ? 1 : 0) : nil,
            tokensPerSecond: current && active ? 40 + Double(index % 20) : nil,
            tokensGenerated: current ? tokens : nil, requestsServed: current ? requests : nil,
            gpuUtilizationPercent: current ? (active ? 75 : 12) : nil,
            gpuMemoryGB: current ? 24 : nil, powerWatts: current ? (active ? 95 : 35) : nil,
            autopilotPhase: visit.isMultiple(of: 20) ? "waiting_inventory" : "shadow")
        try database.record(sample)
        if (index + 1).isMultiple(of: 10_000) {
            FileHandle.standardError.write(Data("Seeded \(index + 1)/\(count) synthetic records\n".utf8))
        }
    }
    let retainedCount = try database.retainedRecordCount()
    precondition(retainedCount == count)
    let period = DateInterval(start: endingAt.addingTimeInterval(-30 * 86_400), end: endingAt)
    var reads: [[String: Any]] = []
    for label in ["cold", "repeat"] {
        let began = clock.now
        let rows = try database.samples(in: period)
        precondition(rows.count == count && rows.first!.observedAt < rows.last!.observedAt)
        let duration = began.duration(to: clock.now).components
        reads.append(["read": label, "rows": rows.count,
            "milliseconds": Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15])
    }
    let duration = started.duration(to: clock.now).components
    let result: [String: Any] = ["synthetic": true, "rows": count, "spacingSeconds": 25,
        "visitSamples": 60, "firstObservedUnix": period.end.timeIntervalSince1970 - Double(count - 1) * 25,
        "lastObservedUnix": endingAt.timeIntervalSince1970,
        "totalSeconds": Double(duration.seconds) + Double(duration.attoseconds) / 1e18,
        "readTimings": reads]
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))

}
try seed()
// The database object is now closed. Make this a self-contained immutable
// fixture for copying, rather than relying on WAL sidecars at bundle time.
var finalized: OpaquePointer?
guard sqlite3_open_v2(CommandLine.arguments[1], &finalized, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
      let finalized else { fatalError("Cannot finalize the owned fixture") }
let finalizedResult = sqlite3_exec(finalized, "PRAGMA journal_mode=DELETE", nil, nil, nil)
precondition(sqlite3_close(finalized) == SQLITE_OK && finalizedResult == SQLITE_OK)
