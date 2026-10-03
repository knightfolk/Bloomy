// Opt-in synthetic component benchmark; never touches provider/history files.
#if !BLOOMY_VISIT_FACTS_SAME_MODULE
import DarkbloomTelemetry
#endif
import Foundation
import Darwin

let visitFactsCount = Int(ProcessInfo.processInfo.environment["BLOOMY_VISIT_FACTS_ROWS"] ?? "100000")!
precondition((1...100_000).contains(visitFactsCount))
let visitFactsEnd = Date(timeIntervalSince1970: 2_000_000_000)
let visitFactsPeriod = DateInterval(start: visitFactsEnd.addingTimeInterval(-30 * 86_400), end: visitFactsEnd)

func visitFactsID(_ index: Int) -> UUID {
    UUID(uuidString: String(format: "00000000-0000-4000-8000-%012llx", UInt64(index + 1)))!
}

func visitFactsInputs(_ kind: String) -> [PerformanceSample] {
    (0..<visitFactsCount).map { index in
        let mixed = kind == "mixed"
        let gapOffset = kind == "longGaps" ? Double(index / 10_000) * 200 : 0
        let totalGapOffset = kind == "longGaps" ? Double((visitFactsCount - 1) / 10_000) * 200 : 0
        let step = mixed ? 24.0 : 10.0
        let date = visitFactsEnd.addingTimeInterval(-Double(visitFactsCount - index) * step - totalGapOffset + gapOffset)
        let model = kind == "switches" ? "model-\((index / 8) % 4)"
            : mixed && !(index / 60).isMultiple(of: 2) ? "gemma" : "qwen"
        let quality: PerformanceSampleQuality = mixed && index.isMultiple(of: 151) ? .unavailable
            : mixed && index.isMultiple(of: 73) ? .stale : .current
        let active = kind == "active" || (mixed && index.isMultiple(of: 3))
        return PerformanceSample(id: visitFactsID(index), observedAt: date,
            sourceCapturedAt: date, quality: quality, providerSession: "1:100",
            model: model, residentModels: [model], advertisedModels: ["qwen", "gemma"],
            inferenceActive: quality == .current ? active : nil,
            tokensPerSecond: quality == .current ? (mixed || active ? 40 : 0) : nil,
            tokensGenerated: kind == "idle" ? 0 : Int64(index * 100),
            requestsServed: kind == "idle" ? 0 : Int64(index / 3))
    }
}

func visitFactsElapsed<T>(_ action: () -> T) -> (T, Double) {
    let started = ContinuousClock.now
    let result = action()
    let duration = started.duration(to: .now).components
    return (result, Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15)
}

var visitFactsResults: [[String: Any]] = []
for kind in ["mixed", "idle", "active", "switches", "longGaps"] {
    let inputs = visitFactsInputs(kind)
    let expected = ModelVisitHistoryFactsReference(samples: inputs, period: visitFactsPeriod, maximumVisits: 100_000)
    let initial = ModelVisitHistory(samples: inputs, period: visitFactsPeriod, maximumVisits: 100_000)
    precondition(initial.visits == expected.visits)
    precondition(initial.summary == expected.summary)
    var referenceTimes: [Double] = []
    var candidateTimes: [Double] = []
    for repetition in 0..<3 {
        func reference() {
            let (result, time) = visitFactsElapsed {
                ModelVisitHistoryFactsReference(samples: inputs, period: visitFactsPeriod, maximumVisits: 100_000)
            }
            precondition(result.visits == expected.visits && result.summary == expected.summary)
            referenceTimes.append(time)
        }
        func candidate() {
            let (result, time) = visitFactsElapsed {
                ModelVisitHistory(samples: inputs, period: visitFactsPeriod, maximumVisits: 100_000)
            }
            precondition(result.visits == expected.visits && result.summary == expected.summary)
            candidateTimes.append(time)
        }
        if repetition.isMultiple(of: 2) { reference(); candidate() }
        else { candidate(); reference() }
    }
    let before = referenceTimes.sorted()[1]
    let after = candidateTimes.sorted()[1]
    visitFactsResults.append(["fixture": kind, "rows": inputs.count,
        "visits": expected.visits.count, "referenceMilliseconds": referenceTimes,
        "candidateMilliseconds": candidateTimes, "referenceMedianMilliseconds": before,
        "candidateMedianMilliseconds": after, "ratio": before / after,
        "exactVisitsAndSummaryMatch": true])
}
let visitFactsJSON = try JSONSerialization.data(withJSONObject: visitFactsResults, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: visitFactsJSON, as: UTF8.self))
