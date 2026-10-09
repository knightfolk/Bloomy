// Inert, optimized component comparison. Never reads the real provider log.
import DarkbloomTelemetry
import Foundation

@main
enum LegacyTailReadBenchmark {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        precondition(!FileManager.default.fileExists(atPath: root.path), "Preserve existing evidence")
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".darkbloom"), withIntermediateDirectories: true)
        let policy = DarkbloomSourcePolicy(homeDirectory: root, environmentPath: "")
        let repeats = 5, reads = 30
        var results: [[String: Any]] = []
        for mode in ["ordinary", "sensitive", "quiet", "changing"] {
            let padding = String(repeating: "2026-10-09T10:00:00+0000 INFO Inference: idle telemetry observation\n", count: 2200)
            let selected = (0..<100).map { index in
                let body = mode == "sensitive" ? "Authorization: Bearer fixture-secret-\(index)" : "Loading delayed for synthetic-model-\(index)"
                return "2026-10-09T10:00:\(String(format: "%02d", index % 60))+0000 WARNING Inference: \(body)\n"
            }.joined()
            let original = Data((padding + (mode == "quiet" ? "" : selected)).utf8)
            try original.write(to: policy.legacyLog)
            func referenceRead() throws -> [LogEvent] {
                let data = try BoundedFileTail.read(url: policy.legacyLog, maxBytes: DarkbloomSourcePolicy.legacyLogByteLimit)
                #if LEGACY_FROZEN_REFERENCE
                return FrozenLegacyLogParser.parse(String(decoding: data, as: UTF8.self), limit: 100)
                #else
                return LegacyLogParser.parse(String(decoding: data, as: UTF8.self), limit: 100)
                #endif
            }
            var reference = EventBuffer(capacity: 100)
            reference.insert(try referenceRead())
            var oldTimes: [Double] = [], newTimes: [Double] = []
            var oldCold: [Double] = [], newCold: [Double] = []
            for iteration in 0..<repeats {
                for old in iteration.isMultiple(of: 2) ? [true, false] : [false, true] {
                    try original.write(to: policy.legacyLog)
                    let source = LocalTelemetrySource(policy: policy, runner: CappedProcessRunner())
                    var buffer = EventBuffer(capacity: 100)
                    var expected = reference
                    let cold = ContinuousClock.now
                    if old { buffer.insert(try referenceRead()) }
                    else { buffer.insert(try await source.readLegacyEvents(limit: 100)) }
                    let coldMS = milliseconds(cold.duration(to: .now))
                    precondition(buffer.events == reference.events, "Cold fields/order/privacy differ")
                    var elapsedMS = 0.0
                    for index in 0..<reads {
                        if mode == "changing" {
                            let appended = "2026-10-09T10:01:\(String(format: "%02d", index))+0000 WARNING Model: Loading revision \(index)\n"
                            try (original + Data(appended.utf8)).write(to: policy.legacyLog)
                            expected.insert(try referenceRead())
                        }
                        // The fixture's writes/reference calculations are not
                        // Bloomy acquisition work; time only read plus merge.
                        let start = ContinuousClock.now
                        if old { buffer.insert(try referenceRead()) }
                        else { buffer.insert(try await source.readLegacyEvents(limit: 100)) }
                        elapsedMS += milliseconds(start.duration(to: .now))
                        precondition(buffer.events == expected.events, "Repeated fields/order/privacy differ")
                    }
                    let ms = elapsedMS / Double(reads)
                    if old { oldTimes.append(ms); oldCold.append(coldMS) }
                    else { newTimes.append(ms); newCold.append(coldMS) }
                }
            }
            results.append(["mode": mode, "events": reference.events.count, "readsPerRepeat": reads,
                "referenceMillisecondsPerRead": oldTimes, "sourceMillisecondsPerRead": newTimes,
                "referenceMedianMillisecondsPerRead": oldTimes.sorted()[repeats / 2],
                "sourceMedianMillisecondsPerRead": newTimes.sorted()[repeats / 2],
                "referenceColdMilliseconds": oldCold, "sourceColdMilliseconds": newCold,
                "parity": true])
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: root.appendingPathComponent("result.json"))
        print(String(decoding: data, as: UTF8.self))
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let value = duration.components
        return Double(value.seconds) * 1_000 + Double(value.attoseconds) / 1e15
    }
}
