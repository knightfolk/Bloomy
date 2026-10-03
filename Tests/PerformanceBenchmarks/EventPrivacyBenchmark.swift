// Release-only, inert repeated log-tail comparison; never reads real logs.
import DarkbloomTelemetry
import Foundation

@main
enum EventPrivacyBenchmark {
    static func main() throws {
        let repeats = 5
        let reads = 20
        var results: [[String: Any]] = []
        for mode in ["ordinary", "warning-tail", "sensitive"] {
            let events = (0..<100).map { index in
                let message: String
                switch mode {
                case "warning-tail": message = "\u{1b}[31mLoad delayed \(index)\u{1b}[0m; file /Users/fixture-user/models; see https://example.invalid/private"
                case "sensitive": message = "Authorization: Bearer fixture-\(index)"
                default: message = "Loaded model \(index); prompt_tokens=10 completion_tokens=20"
                }
                return LogEvent(timestamp: Date(timeIntervalSince1970: Double(index)), severity: .warning,
                    category: "Inference", message: message, source: .legacy,
                    processID: 42, processImage: "/Users/fixture-user/bin/provider")
            }
            var expected = EventBufferPrivacyReference(capacity: 100)
            expected.insert(events)
            var initial = EventBuffer(capacity: 100)
            initial.insert(events)
            precondition(initial.events == expected.events, "Redaction/retention parity failed")
            var oldTimes: [Double] = [], newTimes: [Double] = []
            for iteration in 0..<repeats {
                // Alternate order to reduce a consistent warm-up advantage.
                for old in iteration.isMultiple(of: 2) ? [true, false] : [false, true] {
                    let start = ContinuousClock.now
                    if old {
                        var buffer = EventBufferPrivacyReference(capacity: 100)
                        for _ in 0..<reads { buffer.insert(events) }
                        precondition(buffer.events == expected.events)
                    } else {
                        var buffer = EventBuffer(capacity: 100)
                        for _ in 0..<reads { buffer.insert(events) }
                        precondition(buffer.events == expected.events)
                    }
                    let elapsed = start.duration(to: .now).components
                    let milliseconds = Double(elapsed.seconds) * 1_000 + Double(elapsed.attoseconds) / 1e15
                    if old { oldTimes.append(milliseconds / Double(reads)) }
                    else { newTimes.append(milliseconds / Double(reads)) }
                }
            }
            results.append(["mode": mode, "eventsPerRead": events.count, "readsPerRepeat": reads,
                            "oldMillisecondsPerRead": oldTimes, "newMillisecondsPerRead": newTimes,
                            "oldMedianMillisecondsPerRead": oldTimes.sorted()[repeats / 2],
                            "newMedianMillisecondsPerRead": newTimes.sorted()[repeats / 2], "parity": true])
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
