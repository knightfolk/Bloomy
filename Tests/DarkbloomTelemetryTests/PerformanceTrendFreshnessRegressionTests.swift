import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Performance trend freshness regressions")
struct PerformanceTrendFreshnessRegressionTests {
    @Test("a fresh record rejected by the graph cannot label old points current")
    func excludedNewest() {
        let now = Date()
        let old = PerformanceSample(observedAt: now.addingTimeInterval(-30), sourceCapturedAt: now.addingTimeInterval(-30),
            quality: .current, providerSession: "1:100", model: "qwen", inferenceActive: true, gpuUtilizationPercent: 40)
        let invalid = PerformanceSample(observedAt: now, quality: .current,
            providerSession: "1:100", model: "qwen", inferenceActive: true, gpuUtilizationPercent: 60)
        let trend = PerformanceTrend(metric: .gpu, samples: [old, invalid])
        #expect(trend.points.map(\.id) == [old.id])
        #expect(trend.status(at: now, storageError: nil) == "Current measurement unavailable")
    }

    @Test("missing provider coverage does not claim hardware is missing")
    func sourceCoverage() {
        let now = Date()
        let sample = PerformanceSample(observedAt: now, quality: .unavailable, gpuUtilizationPercent: 40)
        let trend = PerformanceTrend(metric: .gpu, samples: [sample])
        #expect(trend.points.isEmpty)
        #expect(trend.status(at: now, storageError: nil) == "Waiting for provider observation")
    }
}
