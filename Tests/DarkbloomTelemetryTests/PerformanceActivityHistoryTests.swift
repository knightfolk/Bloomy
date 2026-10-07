import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Provider activity timeline")
struct PerformanceActivityHistoryTests {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    var period: DateInterval { DateInterval(start: base, duration: 300) }

    @Test("active endpoints and work between idle readings stay different")
    func workKinds() {
        let samples = [sample(0, active: true), sample(30, active: true),
            sample(60, active: false, requests: 1), sample(90, active: false, requests: 2)]
        let history = PerformanceActivityHistory(samples: samples, period: period)
        #expect(history.segments.map(\.evidence) == [.active, .betweenReadings])
        #expect(history.segments.last?.start == base.addingTimeInterval(30))
        #expect(history.segments.last?.end == base.addingTimeInterval(90))
    }

    @Test("idle requires known unchanged counters and no contradictory direct work")
    func idleEvidence() {
        let first = sample(0, active: false)
        #expect(PerformanceActivityHistory(samples: [first, sample(30, active: false)], period: period).segments.first?.evidence == .idle)
        for second in [sample(30, active: nil), sample(30, active: true),
            sample(30, active: false, requests: nil), sample(30, active: false, tokens: nil),
            sample(30, active: false, rate: 1), sample(30, active: false, activeRequests: 1)] {
            #expect(PerformanceActivityHistory(samples: [first, second], period: period).segments.first?.evidence == .uncertain)
        }
    }

    @Test("stale gaps sessions resets and repeated captures are not bridged")
    func interruptions() {
        for interruption in [sample(30, quality: .stale), sample(30, quality: .unavailable),
            sample(120), sample(30, session: "123:2"), sample(30, capture: 0),
            sample(30, requests: 0, tokens: 0)] {
            let rows = [sample(0, requests: 5, tokens: 5), interruption]
            #expect(PerformanceActivityHistory(samples: rows, period: period).segments.isEmpty)
            #expect(PerformanceSummary(samples: rows).coveredSeconds == 0)
        }
        let history = PerformanceActivityHistory(samples: [sample(0), sample(30),
            sample(60, quality: .stale), sample(90), sample(120)], period: period)
        #expect(history.segments.count == 2)
        #expect(history.segments[0].end == base.addingTimeInterval(30))
        #expect(history.segments[1].start == base.addingTimeInterval(90))
    }

    @Test("adjacent identical readings merge without model attribution")
    func coalescing() {
        let rows = [sample(0, model: "qwen"), sample(30, model: "gemma"), sample(60, model: nil)]
        let history = PerformanceActivityHistory(samples: rows, period: period)
        #expect(history.segments.count == 1)
        #expect(history.segments[0].end.timeIntervalSince(history.segments[0].start) == PerformanceSummary(samples: rows).coveredSeconds)
    }

    @Test("range clipping happens after adjacency and keeps boundary evidence")
    func clipping() {
        let rows = [sample(0), sample(30), sample(60)]
        let range = DateInterval(start: base.addingTimeInterval(15), duration: 30)
        let history = PerformanceActivityHistory(samples: rows, period: range)
        #expect(history.segments.count == 1)
        #expect(history.segments[0].start == range.start)
        #expect(history.segments[0].end == range.end)
        let counterRows = [sample(0, active: false), sample(30, active: false, requests: 1)]
        #expect(PerformanceActivityHistory(samples: counterRows, period: range).segments.first?.evidence == .uncertain)
        #expect(PerformanceActivityHistory(samples: rows, period: DateInterval(start: base, duration: 0)).segments.isEmpty)
    }

    @Test("retention is explicit and preserves recent gaps")
    func retention() {
        let rows = (0..<8).map { sample(Double($0 * 30), active: $0 % 2 == 0) }
        let all = PerformanceActivityHistory(samples: rows, period: period)
        // Alternating endpoints all classify uncertain and coalesce.
        #expect(all.segments.count == 1)
        let interrupted = [sample(0), sample(30), sample(60, quality: .stale),
            sample(90), sample(120), sample(150, quality: .stale), sample(180), sample(210)]
        let limited = PerformanceActivityHistory(samples: interrupted, period: period, maximumSegments: 2)
        #expect(limited.totalSegmentCount == 3)
        #expect(limited.segments.count == 2)
        #expect(limited.segments.first?.start == base.addingTimeInterval(90))
        #expect(PerformanceActivityHistory(samples: interrupted, period: period, maximumSegments: 0).segments.isEmpty)
    }

    @Test("selected model and no resident do not filter provider activity")
    func snapshotScope() {
        let rows = [sample(0, model: "qwen"), sample(30, model: "gemma"), sample(60, model: nil)]
        let all = PerformanceMetricsSnapshot(samples: rows, range: period, model: nil)
        let selected = PerformanceMetricsSnapshot(samples: rows, range: period, model: "missing")
        #expect(selected.visits.isEmpty)
        #expect(!selected.activity.segments.isEmpty)
        #expect(selected.activity == all.activity)
    }

    private func sample(_ seconds: Double, active: Bool? = true, requests: Int64? = 0,
                        tokens: Int64? = 0, rate: Double = 0, activeRequests: Int? = nil,
                        quality: PerformanceSampleQuality = .current, session: String = "123:1",
                        capture: Double? = nil, model: String? = "qwen") -> PerformanceSample {
        PerformanceSample(observedAt: base.addingTimeInterval(seconds),
            sourceCapturedAt: base.addingTimeInterval(capture ?? seconds), quality: quality,
            providerSession: session, model: model, inferenceActive: active,
            activeRequests: activeRequests, tokensPerSecond: rate, tokensGenerated: tokens, requestsServed: requests)
    }
}
