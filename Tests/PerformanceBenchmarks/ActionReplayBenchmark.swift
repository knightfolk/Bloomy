// Synthetic disk-backed recording comparison. Frozen/Previous classes are
// generated from pinned Git revisions by run-action-replay.py.
import DarkbloomTelemetry
import Foundation

private let replayNow = Date(timeIntervalSince1970: 2_000_000_000)

private protocol ReplayJournal: AnyObject {
    func record(_ event: ActionHistoryEvent) throws
    func recent(limit: Int) throws -> [ActionHistoryEvent]
    func retainedRecordCount() throws -> Int
}

extension ActionHistoryDatabase: ReplayJournal {}
extension FrozenActionHistoryDatabase: ReplayJournal {}
extension PreviousActionHistoryDatabase: ReplayJournal {}

private func event(_ index: Int, occurredAt: Date? = nil, updatedAt: Date? = nil,
                   amount: Int64 = 17) -> ActionHistoryEvent {
    let occurred = occurredAt ?? replayNow.addingTimeInterval(-Double(index + 1))
    return ActionHistoryEvent(
        id: ActionHistoryEvent.deterministicID(namespace: "synthetic-replay", key: String(index)),
        occurredAt: occurred, updatedAt: updatedAt ?? occurred,
        action: .job, trigger: .provider, outcome: .succeeded, model: "synthetic-model",
        job: .init(earningID: Int64(index + 1), promptTokens: 100,
                   completionTokens: 40, amountMicroUSD: amount))
}

private func milliseconds(_ work: () throws -> Void) rethrows -> Double {
    let start = ContinuousClock.now
    try work()
    let duration = start.duration(to: .now).components
    return Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15
}

@main
struct ActionReplayBenchmark {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw NSError(domain: "ActionReplayBenchmark", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Pass one new task-owned database directory."])
        }
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: root.path) else {
            throw NSError(domain: "ActionReplayBenchmark", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Preserve existing evidence; use a fresh directory."])
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let baselineURL = root.appendingPathComponent("seed.sqlite3")
        let seed = (0..<5_000).map { event($0) }
        do {
            let baseline = try ActionHistoryDatabase(url: baselineURL, now: { replayNow })
            for row in seed { try baseline.record(row) }
            let retained = try baseline.retainedRecordCount()
            precondition(retained == seed.count)
        } // Close/checkpoint the seed before making independent file copies.

        let makers: [(String, (URL) throws -> any ReplayJournal)] = [
            ("release142", { try FrozenActionHistoryDatabase(url: $0, now: { replayNow }) }),
            ("previousCheckpoint", { try PreviousActionHistoryDatabase(url: $0, now: { replayNow }) }),
            ("current", { try ActionHistoryDatabase(url: $0, now: { replayNow }) })
        ]
        var results: [[String: Any]] = []
        for scenario in ["identicalEarnings", "correctedEarnings", "newRowsAtCapacity", "expiredEarnings"] {
            var journals: [String: any ReplayJournal] = [:]
            var times: [String: [Double]] = [:]
            for (name, make) in makers {
                let url = root.appendingPathComponent("\(scenario)-\(name).sqlite3")
                try FileManager.default.copyItem(at: baselineURL, to: url)
                journals[name] = try make(url)
                times[name] = []
            }
            let count = scenario == "identicalEarnings" ? 1_000 : 200
            for repetition in 0..<3 {
                let input: [ActionHistoryEvent] = (0..<count).map { index in
                    switch scenario {
                    case "correctedEarnings":
                        event(index, updatedAt: replayNow.addingTimeInterval(Double(repetition + 1)),
                              amount: Int64(18 + repetition))
                    case "newRowsAtCapacity":
                        event(5_000 + repetition * count + index,
                              occurredAt: replayNow.addingTimeInterval(Double(repetition * count + index)))
                    case "expiredEarnings":
                        event(10_000 + index, occurredAt: replayNow.addingTimeInterval(-31 * 86_400 - Double(index)))
                    default:
                        event(index, updatedAt: replayNow.addingTimeInterval(Double(repetition + 1)))
                    }
                }
                // Rotate serial execution order; no competing benchmark threads.
                let names = makers.map { $0.0 }
                for offset in names.indices {
                    let name = names[(offset + repetition) % names.count]
                    let journal = journals[name]!
                    let elapsed = try milliseconds {
                        for row in input { try journal.record(row) }
                    }
                    times[name, default: []].append(elapsed)
                }
                let expected = try journals["release142"]!.recent(limit: 5_000)
                precondition(expected.count == 5_000)
                for name in ["previousCheckpoint", "current"] {
                    let actual = try journals[name]!.recent(limit: 5_000)
                    precondition(actual == expected, "Every retained field and event order must match")
                }
            }
            let medians = times.mapValues { $0.sorted()[1] }
            results.append([
                "scenario": scenario, "initialRows": seed.count, "recordsPerRepetition": count,
                "repetitions": 3, "recordBatchMilliseconds": times,
                "medianBatchMilliseconds": medians,
                "release142OverCurrent": medians["release142"]! / medians["current"]!,
                "previousCheckpointOverCurrent": medians["previousCheckpoint"]! / medians["current"]!,
                "exactRetainedEventsAndOrder": true
            ])
        }
        let output: [String: Any] = [
            "measurements": results,
            "limits": "Optimized standalone public-API recording with synthetic disk-backed WAL databases. Includes record validation, identity checks, corrections, transactions and retention; excludes account parsing, SwiftUI, provider work, whole-app CPU/energy and cold startup."
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
    }
}
