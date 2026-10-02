import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Metrics recording freshness")
struct MetricsRecordingFreshnessTests {
    @Test("recording freshness requires a finite nonnegative age within ninety seconds", arguments: [0.0, 90.0, 90.001, -0.001, Double.infinity, Double.nan])
    func observationAge(age: TimeInterval) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = PerformanceSample(observedAt: now.addingTimeInterval(-age), quality: .current)
        let expected = age.isFinite && (0...90).contains(age)
        #expect(MetricsRecordingFreshness.isCurrent(sample, at: now) == expected)
        #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: now)
            == (expected ? "Recording locally" : "Waiting for fresh measurements"))
    }

    @Test("missing, stale, unavailable and failed recording do not claim current measurements")
    func unavailableRecording() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for quality in [PerformanceSampleQuality.stale, .unavailable] {
            let sample = PerformanceSample(observedAt: now, quality: quality)
            #expect(!MetricsRecordingFreshness.isCurrent(sample, at: now))
            #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: now) == "Waiting for fresh measurements")
        }
        #expect(!MetricsRecordingFreshness.isCurrent(nil, at: now))
        #expect(MetricsRecordingFreshness.status(nil, storageError: nil, at: now) == "Waiting for fresh measurements")
        #expect(MetricsRecordingFreshness.status(PerformanceSample(observedAt: now, quality: .current), storageError: "Synthetic read error", at: now)
            == "Recording needs attention")
    }

    @Test("a clock rollback changes freshness without rewriting the retained read's analysis window")
    @MainActor
    func futureObservationRetainsAnalysis() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let sample = PerformanceSample(observedAt: end, quality: .current)
        let token = PerformanceMetricsReadToken(generation: 1, endingAt: end)
        let original = PerformanceMetricsContent(samples: [sample], recordingStartedAt: nil, now: end, timelineDate: end, readToken: token)
        let rolledBack = PerformanceMetricsContent(samples: [sample], recordingStartedAt: nil,
            now: end.addingTimeInterval(-30), timelineDate: end, readToken: token)
        #expect(original.analysisQuery == rolledBack.analysisQuery)
        #expect(rolledBack.analysisQuery.range.end == end)
        #expect(rolledBack.now == end.addingTimeInterval(-30))
        #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: original.now, timelineDate: original.timelineDate) == "Recording locally")
        #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: rolledBack.now, timelineDate: rolledBack.timelineDate) == "Waiting for fresh measurements")
    }

    @Test("a read arriving between minute ticks is current and later ticks expire it without moving analysis")
    @MainActor
    func betweenTickArrival() {
        let tick = Date(timeIntervalSince1970: 1_800_000_000)
        let captured = tick.addingTimeInterval(30)
        let sample = PerformanceSample(observedAt: captured, quality: .current)
        let token = PerformanceMetricsReadToken(generation: 2, endingAt: captured)
        let arrival = PerformanceMetricsContent(samples: [sample], recordingStartedAt: nil,
            now: captured.addingTimeInterval(0.25), timelineDate: tick, readToken: token)
        #expect(arrival.now > tick)
        #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: arrival.now, timelineDate: arrival.timelineDate) == "Recording locally")
        // Using only the retained tick would incorrectly classify this legitimate arrival as future.
        #expect(!MetricsRecordingFreshness.isCurrent(sample, at: tick))
        let expiryTick = tick.addingTimeInterval(180)
        let expired = PerformanceMetricsContent(samples: [sample], recordingStartedAt: nil,
            now: expiryTick, timelineDate: expiryTick, readToken: token)
        #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: expired.now, timelineDate: expired.timelineDate) == "Waiting for fresh measurements")
        #expect(arrival.analysisQuery == expired.analysisQuery)
        #expect(expired.analysisQuery.range.end == captured)
    }

    @Test("invalid wall or timeline clocks cannot qualify a sample as current", arguments: [Double.nan, Double.infinity, -Double.infinity])
    func invalidRenderClock(seconds: TimeInterval) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let invalid = Date(timeIntervalSinceReferenceDate: seconds)
        let sample = PerformanceSample(observedAt: now, quality: .current)
        #expect(!MetricsRecordingFreshness.isCurrent(sample, at: invalid, timelineDate: now))
        #expect(!MetricsRecordingFreshness.isCurrent(sample, at: now, timelineDate: invalid))
        #expect(MetricsRecordingFreshness.status(sample, storageError: nil, at: now, timelineDate: invalid) == "Waiting for fresh measurements")
    }
}
