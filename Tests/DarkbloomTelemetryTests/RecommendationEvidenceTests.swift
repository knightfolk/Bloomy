import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Recommendation evidence")
struct RecommendationEvidenceTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    @Test("fresh demand with local eligibility produces an explainable observe-only consideration")
    func considersHigherDemandWithFactors() {
        let input = input()
        let decision = RecommendationEvaluator.evaluate(input)

        #expect(decision.outcome == .consider(modelID: "better"))
        #expect(decision.confidence == .limited)
        #expect(decision.assessments.map(\.modelID) == ["better", "current"])
        let better = decision.assessments[0]
        #expect(better.eligible)
        #expect(better.demandBand == .urgent)
        #expect(better.factors.contains {
            $0.kind == .networkDemand && $0.provenance == .networkAggregate
                && $0.sourceCapturedAt == now.addingTimeInterval(-10)
                && $0.freshness == .fresh
        })
        #expect(better.factors.contains {
            $0.kind == .memory && $0.provenance == .localReadiness
                && $0.freshness == .fresh
        })
    }

    @Test("stale and duplicate base evidence never produces a consideration")
    func baseEvidenceFailsClosed() {
        let stale = input(capacityAge: 121)
        let staleDecision = RecommendationEvaluator.evaluate(stale)
        #expect(staleDecision.outcome == .insufficientEvidence)
        #expect(staleDecision.blockers.contains(.staleCapacity))

        let duplicate = input(duplicateCandidate: true)
        let duplicateDecision = RecommendationEvaluator.evaluate(duplicate)
        #expect(duplicateDecision.outcome == .insufficientEvidence)
        #expect(duplicateDecision.blockers.contains(.duplicateCandidate))
    }

    @Test("incompatible or memory-blocked alternatives produce stay")
    func eligibilityGatesStay() {
        for readiness in [
            RecommendationReadinessEvidence(capturedAt: now, compatible: false, locallyReady: true, memoryFits: true),
            RecommendationReadinessEvidence(capturedAt: now, compatible: true, locallyReady: true, memoryFits: false),
        ] {
            let decision = RecommendationEvaluator.evaluate(input(betterReadiness: readiness))
            #expect(decision.outcome == .stay)
            #expect(decision.assessments[0].eligible == false)
        }
    }

    @Test("invalid capacity and coverage are explicit and never strengthen a decision")
    func invalidEvidenceCannotStrengthen() {
        let baseline = input()
        let malformed = RecommendationCandidateInput(
            modelID: "better", enabled: true, downloaded: true,
            capacity: .init(capturedAt: now, ready: true, activeRequests: -1, queuedRequests: 2, warmProviders: 1),
            readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true),
            tokenRates: [.init(capturedAt: now, tokensPerSecond: 20, sampleCount: 3)],
            observedWork: [work(unknownHours: -1)]
        )
        let invalid = RecommendationInput(
            evaluatedAt: now, currentModelID: baseline.currentModelID,
            inventoryCapturedAt: baseline.inventoryCapturedAt,
            capacityIsDraining: false,
            candidates: [baseline.candidates[0], malformed]
        )
        let decision = RecommendationEvaluator.evaluate(invalid)
        #expect(decision.outcome == .stay)
        #expect(decision.assessments[0].factors.contains {
            $0.kind == .networkDemand && $0.freshness == .invalid
        })
        #expect(decision.assessments[0].factors.contains {
            $0.kind == .observedWork && $0.freshness == .invalid
        })
    }

    @Test("network readiness is a separate eligibility gate")
    func unreadyNetworkCandidateStays() {
        let baseline = input()
        let unavailable = RecommendationCandidateInput(
            modelID: "better", enabled: true, downloaded: true,
            capacity: .init(capturedAt: now, ready: false, activeRequests: 1, queuedRequests: 2, warmProviders: 1),
            readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true)
        )
        let decision = RecommendationEvaluator.evaluate(RecommendationInput(
            evaluatedAt: now, currentModelID: "current", inventoryCapturedAt: now,
            capacityIsDraining: false, candidates: [baseline.candidates[0], unavailable]
        ))
        #expect(decision.outcome == .stay)
        #expect(decision.assessments[0].blockers.contains(.networkUnavailable))
    }

    @Test("equal demand retains the existing pressure-per-warm-provider tie-break")
    func pressureBreaksEqualDemandTie() {
        let baseline = input()
        let wide = RecommendationCandidateInput(
            modelID: "a-wide", enabled: true, downloaded: true,
            capacity: .init(capturedAt: now, ready: true, activeRequests: 1, queuedRequests: 1, warmProviders: 10),
            readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true)
        )
        let pressured = RecommendationCandidateInput(
            modelID: "z-pressured", enabled: true, downloaded: true,
            capacity: .init(capturedAt: now, ready: true, activeRequests: 1, queuedRequests: 1, warmProviders: 1),
            readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true)
        )
        let decision = RecommendationEvaluator.evaluate(RecommendationInput(
            evaluatedAt: now, currentModelID: "current", inventoryCapturedAt: now,
            capacityIsDraining: false,
            candidates: [baseline.candidates[0], wide, pressured]
        ))
        #expect(decision.outcome == .consider(modelID: "z-pressured"))
        let pressureIsVisible = decision.assessments.last?.factors.contains(where: {
            $0.kind == .networkPressure && $0.numericValue == 2
        }) ?? false
        #expect(pressureIsVisible)
    }

    @Test("partial, stale, duplicate, and cross-account work cannot raise confidence")
    func weakWorkDoesNotStrengthenDecision() {
        let valid = RecommendationEvaluator.evaluate(input(work: [work()]))
        #expect(valid.confidence == .corroborated)

        let invalidWork: [[RecommendationWorkEvidence]] = [
            [work(unknownHours: 1)],
            [work(capturedAt: now.addingTimeInterval(-601))],
            [work(), work()],
            [work(scope: .crossAccount)],
        ]
        for observations in invalidWork {
            let decision = RecommendationEvaluator.evaluate(input(work: observations))
            #expect(decision.outcome == .consider(modelID: "better"))
            #expect(decision.confidence == .limited)
            #expect(decision.assessments[0].factors.contains {
                $0.kind == .observedWork && $0.freshness != .fresh
            })
        }
    }

    @Test("same evidence replays to the same decision independent of candidate order")
    func deterministicReplay() {
        let first = input(work: [work()])
        let reversed = RecommendationInput(
            evaluatedAt: first.evaluatedAt,
            currentModelID: first.currentModelID,
            inventoryCapturedAt: first.inventoryCapturedAt,
            capacityIsDraining: first.capacityIsDraining,
            candidates: Array(first.candidates.reversed())
        )
        #expect(RecommendationEvaluator.evaluate(first) == RecommendationEvaluator.evaluate(reversed))
    }

    private func input(
        capacityAge: TimeInterval = 10,
        duplicateCandidate: Bool = false,
        betterReadiness: RecommendationReadinessEvidence? = nil,
        work: [RecommendationWorkEvidence] = []
    ) -> RecommendationInput {
        let captured = now.addingTimeInterval(-capacityAge)
        let current = RecommendationCandidateInput(
            modelID: "current", enabled: true, downloaded: true,
            capacity: .init(capturedAt: captured, ready: true, activeRequests: 0, queuedRequests: 0, warmProviders: 1),
            readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true)
        )
        let better = RecommendationCandidateInput(
            modelID: "better", enabled: true, downloaded: true,
            capacity: .init(capturedAt: captured, ready: true, activeRequests: 1, queuedRequests: 2, warmProviders: 1),
            readiness: betterReadiness ?? .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true),
            tokenRates: [.init(capturedAt: now, tokensPerSecond: 20, sampleCount: 3)],
            observedWork: work
        )
        return RecommendationInput(
            evaluatedAt: now, currentModelID: "current", inventoryCapturedAt: now,
            capacityIsDraining: false,
            candidates: duplicateCandidate ? [current, better, better] : [current, better]
        )
    }

    private func work(
        capturedAt: Date? = nil,
        unknownHours: Int = 0,
        scope: RecommendationWorkScope = .sameAccount
    ) -> RecommendationWorkEvidence {
        RecommendationWorkEvidence(
            capturedAt: capturedAt ?? now,
            period: DateInterval(start: now.addingTimeInterval(-3_600), end: now),
            microUSD: 200, jobs: 2, recordedHours: 1,
            unknownHours: unknownHours, uncertainBoundaryHours: 0, scope: scope
        )
    }
}
