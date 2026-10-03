import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Performance summary coverage")
struct PerformanceHistoryTests {
    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("time-weighted rates and counter deltas use fresh adjacent samples")
    func weightedSummary() {
        let summary = PerformanceSummary(samples: [
            sample(0, rate: 10, gpu: 20, requests: 10, tokens: 100),
            sample(30, rate: 20, gpu: 40, requests: 12, tokens: 140),
            sample(90, rate: 40, gpu: 80, requests: 15, tokens: 230)
        ])
        #expect(summary.sampleCount == 3)
        #expect(summary.coveredSeconds == 90)
        #expect(summary.activeSeconds == 90)
        #expect(summary.activeCoveredSeconds == 90)
        #expect(summary.averageTokenRate == 25)
        #expect(summary.averageGPUUtilizationPercent == 50)
        #expect(summary.completedRequests == 5)
        #expect(summary.generatedTokens == 130)
    }

    @Test("gaps stale unavailable and duplicate captures cannot invent coverage")
    func invalidIntervals() {
        let fresh = sample(0)
        let interruptions = [
            sample(30, quality: .stale), sample(30, quality: .unavailable),
            sample(100), sample(30, captureOffset: 0), sample(-30),
            sample(30, session: "123:2"), sample(30, session: nil),
            sample(30, captureOffset: -100)
        ]
        for interruption in interruptions {
            let summary = PerformanceSummary(samples: [fresh, interruption])
            #expect(summary.coveredSeconds == 0)
            #expect(summary.activeSeconds == 0)
            #expect(summary.averageTokenRate == nil)
            #expect(summary.completedRequests == nil)
        }
        let resumed = PerformanceSummary(samples: [sample(0), sample(30, quality: .unavailable), sample(60), sample(90)])
        #expect(resumed.coveredSeconds == 30)
    }

    @Test("counter reset skips its interval but later fresh deltas may resume")
    func counterReset() {
        let summary = PerformanceSummary(samples: [
            sample(0, requests: 20, tokens: 200),
            sample(30, requests: 1, tokens: 10),
            sample(60, requests: 4, tokens: 40)
        ])
        #expect(summary.coveredSeconds == 30)
        #expect(summary.completedRequests == 3)
        #expect(summary.generatedTokens == 30)
    }

    @Test("model summary retains intervening model boundaries")
    func modelAttribution() {
        let samples = [
            sample(0, model: "a", requests: 0, tokens: 0),
            sample(30, model: "b", requests: 2, tokens: 20),
            sample(60, model: "a", requests: 4, tokens: 40),
            sample(90, model: "a", requests: 5, tokens: 50)
        ]
        let all = PerformanceSummary(samples: samples)
        #expect(all.coveredSeconds == 90)
        #expect(all.completedRequests == 5)
        let modelA = PerformanceSummary(samples: samples, model: "a")
        #expect(modelA.sampleCount == 3)
        #expect(modelA.coveredSeconds == 30)
        #expect(modelA.completedRequests == nil)
        #expect(modelA.generatedTokens == nil)
    }

    @Test("unknown differs from a measured zero and idle speed is excluded")
    func unavailableCountersAndIdle() {
        let summary = PerformanceSummary(samples: [sample(0, active: false), sample(30, active: false)])
        #expect(summary.coveredSeconds == 30)
        #expect(summary.activeSeconds == 0)
        #expect(summary.activeCoveredSeconds == 30)
        #expect(summary.averageTokenRate == nil)
        #expect(summary.completedRequests == nil)
        #expect(summary.generatedTokens == nil)
        let zero = PerformanceSummary(samples: [sample(0, requests: 5, tokens: 10), sample(30, requests: 5, tokens: 10)])
        #expect(zero.completedRequests == 0)
        #expect(zero.generatedTokens == 0)
    }

    @Test("activity coverage preserves unknown rather than treating it as idle")
    func unknownActivity() {
        let unknown = PerformanceSample(observedAt: base.addingTimeInterval(30), sourceCapturedAt: base.addingTimeInterval(30), quality: .current, providerSession: "123:1", model: "a")
        let summary = PerformanceSummary(samples: [sample(0), unknown, sample(60), sample(90, active: false)])
        #expect(summary.coveredSeconds == 90)
        #expect(summary.activeCoveredSeconds == 30)
        #expect(summary.activeSeconds == 0)
        let fallback = PerformanceSample(observedAt: base.addingTimeInterval(30), sourceCapturedAt: base.addingTimeInterval(30), quality: .current, providerSession: "123:1", model: "a", activeRequests: 1)
        #expect(PerformanceSummary(samples: [sample(0), fallback]).activeCoveredSeconds == 30)
        #expect(PerformanceSummary(samples: [sample(0), fallback]).activeSeconds == 30)
    }

    @Test("counter totals cannot overflow into a fabricated value")
    func overflowIsUnknown() {
        let summary = PerformanceSummary(samples: [
            sample(0, requests: 0, tokens: 0),
            sample(30, requests: .max, tokens: .max),
            sample(60, requests: 0, tokens: 0),
            sample(90, requests: 1, tokens: 1),
            sample(120, requests: 2, tokens: 2)
        ])
        #expect(summary.completedRequests == nil)
        #expect(summary.generatedTokens == nil)
    }

    @Test("missing captures and invalid numeric data fail closed")
    func missingAndInvalid() {
        let missing = PerformanceSample(observedAt: base, quality: .current, providerSession: "123:1", model: "a")
        #expect(PerformanceSummary(samples: [missing, sample(30)]).coveredSeconds == 0)
        #expect(PerformanceSummary(samples: [sample(0), sample(30, rate: .infinity)]).coveredSeconds == 0)
        #expect(PerformanceSummary(samples: []).sampleCount == 0)
    }

    @Test("idle GPU coverage excludes work, unknown counts and capture gaps")
    func idleGPUCoverage() {
        let idle = PerformanceSummary(samples: [sample(0, active: false, gpu: 40, requests: 10),
            sample(30, active: false, gpu: 80, requests: 10)])
        #expect(idle.averageIdleGPUUtilizationPercent == 60)
        #expect(idle.idleGPUCoveredSeconds == 30)
        for next in [sample(30, active: true, requests: 10),
                     sample(30, active: false, requests: 11),
                     sample(30, active: false), sample(120, active: false, requests: 10)] {
            let summary = PerformanceSummary(samples: [sample(0, active: false, requests: 10), next])
            #expect(summary.averageIdleGPUUtilizationPercent == nil)
            #expect(summary.idleGPUCoveredSeconds == 0)
        }
    }

    private func sample(
        _ seconds: Double, quality: PerformanceSampleQuality = .current,
        captureOffset: Double? = nil, session: String? = "123:1", model: String? = "a",
        active: Bool = true, rate: Double = 10, gpu: Double = 20,
        requests: Int64? = nil, tokens: Int64? = nil
    ) -> PerformanceSample {
        PerformanceSample(
            observedAt: base.addingTimeInterval(seconds),
            sourceCapturedAt: base.addingTimeInterval(captureOffset ?? seconds),
            quality: quality, providerSession: session, model: model,
            inferenceActive: active, tokensPerSecond: rate,
            tokensGenerated: tokens, requestsServed: requests, gpuUtilizationPercent: gpu
        )
    }
}
