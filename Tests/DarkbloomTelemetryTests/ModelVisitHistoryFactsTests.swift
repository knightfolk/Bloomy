import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Model visit observation facts parity")
struct ModelVisitHistoryFactsTests {
    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("duplicate resident labels keep sole residence and MRU attribution")
    func duplicateResidents() {
        let rows = [
            sample(0, model: nil, residents: []),
            sample(30, model: "old", residents: ["a", "a"]),
            sample(60, model: "a", residents: ["a", "a", "a"], active: true),
            sample(90, model: "old", residents: ["b", "b"]),
            sample(120, model: nil, residents: [])
        ]
        checkAllWindows(rows)
        let history = ModelVisitHistory(samples: rows)
        #expect(history.visits.map(\.model) == ["a", "b"])
        #expect(history.visits[0].workEvidence == .observedWork)
        #expect(history.visits[1].outcome == .noObservedWork)
    }

    @Test("concurrent residency keeps only a resident MRU and remains uncertain")
    func concurrentAndMismatch() {
        let rows = [
            sample(0), sample(30, residents: ["a", "b", "a"], active: true),
            sample(60, model: "b", residents: ["a", "b", "b"], requests: 1),
            sample(90, model: "old", residents: ["a", "b"]),
            sample(120, model: nil, residents: ["a", "b"]),
            sample(150, model: "old", residents: ["b", "b"], active: true),
            sample(180, model: "b"), sample(210, model: nil, residents: [])
        ]
        checkAllWindows(rows)
        #expect(ModelVisitHistory(samples: rows).visits.map(\.model) == ["a", "b", "b"])
    }

    @Test("invalid intervening rows and incomplete empty slots remain boundaries")
    func invalidAndEmptyRows() {
        let interruptions = [
            sample(30, rate: .infinity), sample(30, rate: .nan),
            sample(30, activeRequests: -1), sample(30, tokens: -1),
            sample(30, model: "/private/model"), sample(30, residents: ["bad label"]),
            sample(30, residents: Array(repeating: "a", count: 257)),
            sample(30, advertised: ["invalid label"]), sample(30, gpu: 101),
            sample(30, session: "invalid"), sample(30, session: nil),
            sample(30, quality: .stale), sample(30, quality: .unavailable),
            sample(30, missingCapture: true), sample(30, capture: 31),
            sample(30, capture: -61), sample(-2_000_000_001),
            sample(30, model: nil, residents: [], active: nil),
            sample(30, model: nil, residents: [], requests: nil),
            sample(30, model: nil, residents: [], tokens: nil),
            sample(30, model: "a", residents: [])
        ]
        for row in interruptions {
            checkAllWindows([sample(0), row, sample(60), sample(90), sample(120, model: nil, residents: [])])
        }
        checkAllWindows([sample(0, model: nil, residents: []), sample(30),
            sample(60), sample(90, model: nil, residents: []), sample(120)])
    }

    @Test("tied times captures restarts gaps resets and missing counters keep exact boundaries")
    func chronologyAndCounters() {
        let interruptions = [
            sample(0), sample(30, capture: 0), sample(-1), sample(30, capture: -1),
            sample(91), sample(91, capture: 1), sample(30, session: "124:2"),
            sample(30, requests: 1, tokens: 20), sample(30, requests: 2, tokens: 1),
            sample(30, requests: nil), sample(30, tokens: nil),
            sample(30, requests: nil, tokens: nil)
        ]
        for row in interruptions {
            checkAllWindows([sample(0, requests: 2, tokens: 20), row,
                sample(120, requests: 3, tokens: 30), sample(150, model: "b", requests: 3, tokens: 30)])
        }
    }

    @Test("clipped direct and counter work retain full observation counts and floating point sums")
    func clippingAndAccumulation() {
        let rows = [sample(0, model: "b"), sample(0.125), sample(0.25, active: true),
            sample(0.625), sample(1.125, requests: 1, tokens: 10),
            sample(1.375, model: "b", requests: 1, tokens: 10), sample(2.75, model: "c", requests: 1, tokens: 10)]
        for interval in [DateInterval(start: base.addingTimeInterval(0.3), end: base.addingTimeInterval(1.0)),
                         DateInterval(start: base.addingTimeInterval(0.625), end: base.addingTimeInterval(1.125)),
                         DateInterval(start: base.addingTimeInterval(1.375), duration: 0),
                         DateInterval(start: base.addingTimeInterval(-1), end: base.addingTimeInterval(0))] {
            check(rows, period: interval, maximumVisits: 500)
        }
        checkAllWindows(rows)
    }

    @Test("deterministic mixed histories match full visits and summaries for clipping and suffix limits")
    func randomizedParity() {
        for seed in 1...24 {
            var random = Generator(state: UInt64(seed))
            var seconds = 0.0
            var requests: Int64 = 0
            var tokens: Int64 = 0
            var session = "123:1"
            var rows: [PerformanceSample] = []
            for index in 0..<256 {
                seconds += [0, 0.125, 0.25, 1, 30, 90, 91][random.pick(7)]
                if index % 29 == 0 { session = session == "123:1" ? "124:2" : "123:1" }
                requests += Int64(random.pick(3))
                tokens += Int64(random.pick(11))
                if index % 31 == 0 { requests = 0; tokens = 0 }
                let model = ["a", "a", "b", "old", nil][random.pick(5)]
                let residents = [["a"], ["a", "a"], ["b", "b", "b"], ["a", "b", "a"], [], ["b"]][random.pick(6)]
                let special = index % 11 == 0 ? random.pick(11) : -1
                rows.append(sample(seconds, model: model, residents: residents,
                    active: [false, false, true, nil][random.pick(4)],
                    activeRequests: special == 0 ? -1 : [0, 0, 1, nil][random.pick(4)],
                    rate: special == 1 ? .infinity : [0, 0, 0.5, nil][random.pick(4)],
                    requests: special == 2 ? nil : requests, tokens: special == 3 ? nil : tokens,
                    session: special == 4 ? nil : session,
                    quality: special == 5 ? .stale : .current,
                    capture: special == 7 ? seconds + 1 : special == 8 ? seconds - 91 : special == 9 ? seconds - 30 : seconds,
                    missingCapture: special == 6, advertised: special == 10 ? ["invalid label"] : ["a", "b"]))
            }
            checkAllWindows(rows)
        }
    }

    private func checkAllWindows(_ rows: [PerformanceSample]) {
        let end = rows.last?.observedAt.timeIntervalSince(base) ?? 0
        let periods: [DateInterval?] = [nil,
            DateInterval(start: base.addingTimeInterval(-1), duration: max(0, end + 2)),
            DateInterval(start: base.addingTimeInterval(max(0, end / 3)), duration: max(0, end / 3)),
            DateInterval(start: base.addingTimeInterval(end), duration: 0)]
        for period in periods {
            for maximum in [-1, 0, 1, 3, 500, 5_000] {
                check(rows, period: period, maximumVisits: maximum)
            }
        }
    }

    private func check(_ rows: [PerformanceSample], period: DateInterval?, maximumVisits: Int) {
        let expected = ModelVisitHistoryFactsReference(samples: rows, period: period, maximumVisits: maximumVisits)
        let actual = ModelVisitHistory(samples: rows, period: period, maximumVisits: maximumVisits)
        #expect(actual.visits == expected.visits)
        #expect(actual.summary == expected.summary)
        #expect(actual.completedNoObservedWorkVisits == expected.completedNoObservedWorkVisits)
    }

    private func sample(_ seconds: Double, model: String? = "a", residents: [String]? = nil,
                        active: Bool? = false, activeRequests: Int? = 0, rate: Double? = 0,
                        requests: Int64? = 0, tokens: Int64? = 0, session: String? = "123:1",
                        quality: PerformanceSampleQuality = .current, capture: Double? = nil,
                        missingCapture: Bool = false, advertised: [String] = [], gpu: Double? = nil) -> PerformanceSample {
        PerformanceSample(observedAt: base.addingTimeInterval(seconds),
            sourceCapturedAt: missingCapture ? nil : capture.map { base.addingTimeInterval($0) } ?? base.addingTimeInterval(seconds),
            quality: quality, providerSession: session, model: model,
            residentModels: residents ?? model.map { [$0] } ?? [], advertisedModels: advertised,
            inferenceActive: active, activeRequests: activeRequests, tokensPerSecond: rate,
            tokensGenerated: tokens, requestsServed: requests, gpuUtilizationPercent: gpu)
    }

    private struct Generator {
        var state: UInt64
        mutating func pick(_ count: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int((state >> 32) % UInt64(count))
        }
    }
}
