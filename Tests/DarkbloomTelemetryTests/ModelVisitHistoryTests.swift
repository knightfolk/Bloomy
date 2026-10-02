import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Observed model visits")
struct ModelVisitHistoryTests {
    private let base = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("fresh empty slots bound unused visits across normal unload and reload")
    func confirmedEmptySlotBoundaries() throws {
        let rows = [sample(0, residents: [], modelMissing: true), sample(30, "b"),
            sample(60, "b"), sample(90, residents: [], modelMissing: true), sample(120, "c")]
        let visit = try #require(ModelVisitHistory(samples: rows).completedNoObservedWorkVisits.first)
        #expect(visit.model == "b")
        #expect(visit.durationSeconds == 60)
        #expect(visit.startReason == .residencyChanged)
        #expect(visit.endReason == .residencyChanged)
    }

    @Test("stale or incomplete empty slots cannot bound unused visits")
    func uncertainEmptySlots() {
        for empty in [sample(0, residents: [], quality: .stale, modelMissing: true),
                      sample(0, residents: [], tokens: nil, modelMissing: true)] {
            let rows = [empty, sample(30, "b"), sample(60, "b"), sample(90, residents: [], modelMissing: true)]
            #expect(ModelVisitHistory(samples: rows).completedNoObservedWorkVisits.isEmpty)
        }
    }

    @Test("missing either counter cannot prove absence of work")
    func partialCounterCoverage() {
        for missingRequests in [true, false] {
            let rows = [(0.0, "a"), (30, "b"), (60, "b"), (90, "c")].map { time, model in
                sample(time, model, requests: missingRequests ? nil : 0, tokens: missingRequests ? 0 : nil)
            }
            #expect(ModelVisitHistory(samples: rows).completedNoObservedWorkVisits.isEmpty)
        }
    }

    @Test("a bounded idle selection is retained after switching away")
    func idleVisit() throws {
        let history = ModelVisitHistory(samples: [sample(0, "b"), sample(30), sample(60), sample(90, "b")])
        let visit = try #require(history.completedNoObservedWorkVisits.first)
        #expect(visit.model == "a")
        #expect(visit.observedStart == base.addingTimeInterval(30))
        #expect(visit.observedEnd == base.addingTimeInterval(90))
        #expect(visit.durationSeconds == 60)
        #expect(visit.coveredSeconds == 60)
        #expect(visit.observedIdleSeconds == 30)
        #expect(visit.outcome == .noObservedWork)
        #expect(visit.startReason == .modelChanged)
        #expect(visit.endReason == .modelChanged)
        #expect(history.summary.completedNoObservedWorkCount == 1)
    }

    @Test("one fresh active observation or positive rate proves work")
    func directWork() {
        for activity in [sample(60, active: true), sample(60, rate: 12)] {
            let history = ModelVisitHistory(samples: [sample(0, "b"), sample(30), activity, sample(90, "b")])
            #expect(history.visits[1].outcome == .worked)
            #expect(history.visits[1].workEvidence == .observedWork)
        }
    }

    @Test("a quick completed request between inactive polls still proves work")
    func completedBetweenPolls() {
        let history = ModelVisitHistory(samples: [
            sample(0, "b"), sample(30), sample(60, requests: 1, tokens: 10),
            sample(90, "b", requests: 1, tokens: 10)
        ])
        #expect(history.visits[1].outcome == .worked)
        #expect(history.visits[1].observedIdleSeconds == 0)
    }

    @Test("counter changes across a switch cannot identify either model")
    func switchCounterAmbiguity() {
        let history = ModelVisitHistory(samples: [
            sample(0, "b"), sample(30), sample(60), sample(90, "b", requests: 1),
            sample(120, "b", requests: 1), sample(150, "c", requests: 1)
        ])
        #expect(history.visits[1].outcome == .unknown)
        #expect(history.visits[2].outcome == .unknown)
        #expect(history.completedNoObservedWorkVisits.isEmpty)
    }

    @Test("returning to a model creates a distinct visit")
    func separateReturns() {
        let history = ModelVisitHistory(samples: [sample(0), sample(30, "b"), sample(60), sample(90)])
        #expect(history.visits.map(\.model) == ["a", "b", "a"])
        #expect(Set(history.visits.map(\.id)).count == 3)
        #expect(history.visits[0].isStartTruncated)
        #expect(history.visits[2].isOpen)
        #expect(history.visits[2].outcome == .stillLoaded)
    }

    @Test("gaps restarts resets and missing captures break coverage")
    func interruptedVisits() {
        let cases: [(PerformanceSample, ModelVisitBoundary)] = [
            (sample(160), .longGap),
            (sample(60, session: "123:2"), .providerRestart),
            (sample(60, requests: 0, tokens: 0), .counterReset),
            (sample(60, quality: .stale), .staleOrMissing),
            (sample(60, capture: nil), .staleOrMissing),
            (sample(60, residents: [], modelMissing: true), .staleOrMissing)
        ]
        for (interruption, boundary) in cases {
            let history = ModelVisitHistory(samples: [sample(0, requests: 3, tokens: 30), sample(30, requests: 3, tokens: 30), interruption])
            #expect(history.visits[0].endReason == boundary)
            #expect(history.visits[0].coveredSeconds == 30)
            #expect(history.visits[0].observedEnd == base.addingTimeInterval(30))
            #expect(history.visits[0].outcome == .unknown)
            #expect(history.visits[0].isEndTruncated)
        }
    }

    @Test("last-used names without residency do not create loaded visits")
    func residencyRequired() {
        #expect(ModelVisitHistory(samples: [sample(0, residents: []), sample(30, residents: [])]).visits.isEmpty)
        #expect(ModelVisitHistory(samples: [sample(0, residents: ["b"]), sample(30, residents: ["b"])]).visits.map(\.model) == ["b"])
    }

    @Test("provider activity and counters with concurrent residents stay unattributed")
    func concurrentResidents() {
        let history = ModelVisitHistory(samples: [
            sample(0, "b"), sample(30, residents: ["a", "c"], active: true),
            sample(60, residents: ["a", "c"], rate: 20, requests: 1), sample(90, "b", requests: 1)
        ])
        #expect(history.visits[1].outcome == .unknown)
        #expect(history.visits[1].workEvidence == .unknown)
        #expect(history.completedNoObservedWorkVisits.isEmpty)
    }

    @Test("first observation and period clipping cannot claim a complete idle visit")
    func truncation() {
        let samples = [sample(0, "b"), sample(30), sample(60), sample(90, "b"), sample(120, "c")]
        #expect(ModelVisitHistory(samples: Array(samples[1...])).visits[0].outcome == .unknown)
        let period = DateInterval(start: base.addingTimeInterval(45), end: base.addingTimeInterval(105))
        let history = ModelVisitHistory(samples: samples, period: period)
        #expect(history.visits.map(\.model) == ["a", "b"])
        #expect(history.visits[0].observedStart == period.start)
        #expect(history.visits[0].durationSeconds == 45)
        #expect(history.visits[0].isStartTruncated)
        #expect(history.visits[0].outcome == .unknown)
        #expect(history.visits[1].isEndTruncated)
        #expect(history.visits[1].outcome == .unknown)
        #expect(history.completedNoObservedWorkVisits.isEmpty)
    }

    @Test("an open visit keeps positive evidence separately from still loaded")
    func openVisit() {
        let history = ModelVisitHistory(samples: [sample(0), sample(30, active: true)])
        #expect(history.visits[0].outcome == .stillLoaded)
        #expect(history.visits[0].workEvidence == .observedWork)
        #expect(history.visits[0].observedEnd == base.addingTimeInterval(30))
        #expect(history.completedNoObservedWorkVisits.isEmpty)
        #expect(history.summary.stillLoadedCount == 1)
    }

    @Test("missing counters cannot exclude work between polls")
    func missingCounters() {
        let history = ModelVisitHistory(samples: [
            sample(0, "b", requests: nil, tokens: nil), sample(30, requests: nil, tokens: nil),
            sample(60, requests: nil, tokens: nil), sample(90, "b", requests: nil, tokens: nil)
        ])
        #expect(history.visits[1].outcome == .unknown)
        #expect(history.visits[1].observedIdleSeconds == 0)
    }

    @Test("output bound keeps latest visits without merging histories")
    func outputBound() {
        let samples = [sample(0), sample(30, "b"), sample(60), sample(90, "b")]
        #expect(ModelVisitHistory(samples: samples, maximumVisits: 2).visits.map(\.model) == ["a", "b"])
        #expect(ModelVisitHistory(samples: samples, maximumVisits: 0).visits.isEmpty)
    }

    @Test("work outside the requested period does not become work inside it")
    func periodEvidence() {
        let samples = [
            sample(0, "b"), sample(30, active: true), sample(60), sample(90, "b")
        ]
        let period = DateInterval(start: base.addingTimeInterval(45), end: base.addingTimeInterval(90))
        let history = ModelVisitHistory(samples: samples, period: period)
        #expect(history.visits[0].workEvidence == .unknown)
        #expect(history.visits[0].outcome == .unknown)
        #expect(history.visits[0].coveredSeconds == 45)
        #expect(history.summary.workedCount == 0)
    }

    @Test("partial counter intervals cannot attribute work to a clipped period")
    func partialCounterInterval() {
        let samples = [sample(0, "b"), sample(30), sample(60, requests: 1), sample(90, "b", requests: 1)]
        let period = DateInterval(start: base.addingTimeInterval(45), end: base.addingTimeInterval(90))
        #expect(ModelVisitHistory(samples: samples, period: period).visits[0].workEvidence == .unknown)
    }

    @Test("duplicate captures unknown sessions and invalid data fail closed")
    func invalidObservations() {
        let invalidSamples = [
            PerformanceSample(observedAt: base.addingTimeInterval(30), sourceCapturedAt: base,
                quality: .current, providerSession: "123:1", model: "a", residentModels: ["a"], inferenceActive: false),
            sample(30, session: nil), sample(30, rate: .infinity)
        ]
        for invalid in invalidSamples {
            let history = ModelVisitHistory(samples: [sample(0), invalid])
            #expect(history.visits[0].coveredSeconds == 0)
            #expect(history.visits[0].isEndTruncated)
            #expect(history.visits[0].outcome == .unknown)
        }
    }

    @Test("a resident removal closes the visit without bridging unloaded time")
    func unloaded() {
        let history = ModelVisitHistory(samples: [sample(0), sample(30), sample(60, residents: []), sample(90), sample(120)])
        #expect(history.visits.map(\.model) == ["a", "a"])
        #expect(history.visits[0].endReason == .residencyChanged)
        #expect(history.visits[0].durationSeconds == 30)
        #expect(history.visits[1].coveredSeconds == 30)
        #expect(history.visits[1].isStartTruncated)
    }

    @Test("active request evidence takes precedence over a contradictory inactive flag")
    func activeRequestEvidence() {
        let active = PerformanceSample(observedAt: base.addingTimeInterval(60), sourceCapturedAt: base.addingTimeInterval(60),
            quality: .current, providerSession: "123:1", model: "a", residentModels: ["a"],
            inferenceActive: false, activeRequests: 1, tokensPerSecond: 0, tokensGenerated: 0, requestsServed: 0)
        let visit = ModelVisitHistory(samples: [sample(0, "b"), sample(30), active, sample(90, "b")]).visits[1]
        #expect(visit.workEvidence == .observedWork)
        #expect(visit.observedIdleSeconds == 0)
    }

    @Test("a visit ending at the period start does not create an empty extra row")
    func exactPeriodBoundary() {
        let samples = [sample(0), sample(30, "b"), sample(60), sample(90, "b"), sample(120, "c")]
        let period = DateInterval(start: base.addingTimeInterval(90), end: base.addingTimeInterval(120))
        #expect(ModelVisitHistory(samples: samples, period: period).visits.map(\.model) == ["b"])
    }

    @Test("unused resident visits survive a most-recently-used name that never changes")
    func soleResidenceOverridesLastUsed() throws {
        let history = ModelVisitHistory(samples: [
            sample(0, residents: ["a"]), sample(30, residents: ["b"]),
            sample(60, residents: ["b"]), sample(90, residents: ["c"])
        ])
        #expect(history.visits.map(\.model) == ["a", "b", "c"])
        #expect(history.completedNoObservedWorkVisits.map(\.model) == ["b"])
        #expect(try #require(history.completedNoObservedWorkVisits.first).durationSeconds == 60)
        let missingLastUsed = ModelVisitHistory(samples: [
            sample(0, residents: ["a"], modelMissing: true),
            sample(30, residents: ["b"], modelMissing: true),
            sample(60, residents: ["c"], modelMissing: true)
        ])
        #expect(missingLastUsed.completedNoObservedWorkVisits.map(\.model) == ["b"])
    }

    @Test("active flags and rate for a previous model cannot prove work for a new resident")
    func lastUsedMismatchActivity() throws {
        let history = ModelVisitHistory(samples: [
            sample(0), sample(30, residents: ["b"], active: true, rate: 10),
            sample(60, residents: ["b"]), sample(90, residents: ["c"])
        ])
        #expect(history.visits.map(\.model) == ["a", "b", "c"])
        let visit = try #require(history.visits.first { $0.model == "b" })
        #expect(visit.workEvidence == .unknown)
        #expect(visit.outcome == .unknown)
        #expect(visit.observedIdleSeconds == 0)
    }

    @Test("same sole resident counters can prove quick work while the last-used label is old")
    func residentCounterEvidence() throws {
        let history = ModelVisitHistory(samples: [
            sample(0), sample(30, residents: ["b"]), sample(60, residents: ["b"], requests: 1),
            sample(90, residents: ["c"], requests: 1)
        ])
        let visit = try #require(history.visits.first { $0.model == "b" })
        #expect(visit.outcome == .worked)
    }

    private func sample(
        _ seconds: Double, _ model: String = "a", residents: [String]? = nil,
        active: Bool? = false, rate: Double? = 0, requests: Int64? = 0, tokens: Int64? = 0,
        session: String? = "123:1", quality: PerformanceSampleQuality = .current,
        capture: Bool? = true, modelMissing: Bool = false
    ) -> PerformanceSample {
        PerformanceSample(
            observedAt: base.addingTimeInterval(seconds),
            sourceCapturedAt: capture == true ? base.addingTimeInterval(seconds) : nil,
            quality: quality, providerSession: session, model: modelMissing ? nil : model,
            residentModels: residents ?? [model], inferenceActive: active,
            tokensPerSecond: rate, tokensGenerated: tokens, requestsServed: requests
        )
    }
}
