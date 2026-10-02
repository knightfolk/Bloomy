import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Model visit accumulation")
struct ModelVisitScalingTests {
    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("a long bounded idle visit preserves all coverage and observations")
    func longIdleVisit() throws {
        let count = 2_048
        let rows = [sample(0, model: nil)]
            + (1...count).map { sample($0) }
            + [sample(count + 1, model: nil)]
        let visit = try #require(ModelVisitHistory(samples: rows).visits.first)
        #expect(visit.model == "a")
        #expect(visit.id == rows[1].id)
        #expect(visit.sampleCount == count)
        #expect(visit.coveredSeconds == Double(count))
        #expect(visit.observedIdleSeconds == Double(count - 1))
        #expect(visit.outcome == .noObservedWork)
        #expect(visit.startReason == .residencyChanged)
        #expect(visit.endReason == .residencyChanged)
        #expect(!visit.isStartTruncated && !visit.isEndTruncated && !visit.isOpen)
    }

    @Test("clipping a long worked visit retains original count and clips coverage")
    func clippedWorkedVisit() throws {
        let count = 2_048
        let rows = (0..<count).map { sample($0, active: true, requests: Int64($0)) }
        let period = DateInterval(start: base.addingTimeInterval(512.5), duration: 1_024)
        let visit = try #require(ModelVisitHistory(samples: rows, period: period).visits.first)
        #expect(visit.sampleCount == count)
        #expect(visit.observedStart == period.start)
        #expect(visit.observedEnd == period.end)
        #expect(visit.coveredSeconds == period.duration)
        #expect(visit.observedIdleSeconds == 0)
        #expect(visit.workEvidence == .observedWork && visit.outcome == .worked)
        #expect(visit.startReason == .periodBoundary && visit.endReason == .periodBoundary)
        #expect(visit.isStartTruncated && visit.isEndTruncated && !visit.isOpen)
    }

    @Test("frequent switches keep attribution and exclude an intervening long gap")
    func frequentSwitchesWithGap() {
        let count = 512
        let rows = (0..<count).map { index in
            sample(index + (index >= count / 2 ? 100 : 0), model: index / 2 % 2 == 0 ? "a" : "b")
        }
        let visits = ModelVisitHistory(samples: rows).visits
        #expect(visits.count == count / 2)
        #expect(visits.map(\.model) == (0..<count / 2).map { $0 % 2 == 0 ? "a" : "b" })
        #expect(visits.allSatisfy { $0.sampleCount == 2 })
        #expect(visits.reduce(0) { $0 + $1.coveredSeconds } == Double(count - 2))
        #expect(visits.reduce(0) { $0 + $1.observedIdleSeconds } == Double(count / 2))
        #expect(visits[count / 4 - 1].endReason == .longGap)
        #expect(visits[count / 4].startReason == .longGap)
        #expect(visits[count / 4 - 1].outcome == .unknown)
        #expect(visits[count / 4].outcome == .unknown)
        #expect(visits.filter { $0.outcome == .noObservedWork }.count == count / 2 - 4)
        #expect(visits.last?.outcome == .stillLoaded)
        #expect(ModelVisitHistory(samples: rows, maximumVisits: 3).visits == Array(visits.suffix(3)))
    }

    // Opt in only: BLOOMY_MODEL_VISIT_BENCHMARK=1 swift test -c release
    // --filter ModelVisitScalingTests/scalingBenchmark. Optional comma-separated
    // BLOOMY_MODEL_VISIT_BENCHMARK_COUNTS selects pilots up to 100,000 samples.
    @Test("opt-in release scaling benchmark", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_MODEL_VISIT_BENCHMARK"] == "1"))
    func scalingBenchmark() throws {
        let counts = (ProcessInfo.processInfo.environment["BLOOMY_MODEL_VISIT_BENCHMARK_COUNTS"] ?? "10000,50000,100000")
            .split(separator: ",").compactMap { Int($0) }.filter { (2...100_000).contains($0) }
        #expect(!counts.isEmpty)
        for count in counts {
            for active in [false, true] {
                let rows = (0..<count).map { sample($0, active: active, requests: active ? Int64($0) : 0) }
                var durations: [Double] = []
                for _ in 0..<3 {
                    let start = ContinuousClock.now
                    let history = ModelVisitHistory(samples: rows)
                    let elapsed = start.duration(to: .now).components
                    durations.append(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)
                    let visit = try #require(history.visits.first)
                    #expect(history.visits.count == 1 && visit.sampleCount == count)
                    #expect(visit.coveredSeconds == Double(count - 1))
                    #expect(visit.observedIdleSeconds == (active ? 0 : Double(count - 1)))
                    #expect(visit.workEvidence == (active ? .observedWork : .unknown))
                    #expect(visit.outcome == .stillLoaded)
                }
                print("ModelVisit benchmark continuous \(active ? "worked" : "idle") count=\(count) medianSeconds=\(durations.sorted()[1])")
            }
            let rows = (0..<count).map { index in
                sample(index + (index >= count / 2 ? 100 : 0), model: index % 2 == 0 ? "a" : "b")
            }
            let start = ContinuousClock.now
            let history = ModelVisitHistory(samples: rows, maximumVisits: count)
            let elapsed = start.duration(to: .now).components
            #expect(history.visits.count == count)
            #expect(history.visits.reduce(0) { $0 + $1.coveredSeconds } == Double(count - 2))
            #expect(history.visits.allSatisfy { $0.sampleCount == 1 })
            print("ModelVisit benchmark switches/gap count=\(count) seconds=\(Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18)")
        }
    }

    private func sample(_ seconds: Int, model: String? = "a", active: Bool = false, requests: Int64 = 0) -> PerformanceSample {
        let date = base.addingTimeInterval(Double(seconds))
        return PerformanceSample(
            observedAt: date, sourceCapturedAt: date, quality: .current,
            providerSession: "123:1", model: model, residentModels: model.map { [$0] } ?? [],
            inferenceActive: active, activeRequests: active ? 1 : 0,
            tokensPerSecond: active ? 10 : 0, tokensGenerated: requests * 10, requestsServed: requests
        )
    }
}
