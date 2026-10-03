import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Serving slowdown policy")
struct ServingSlowdownPolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    private func sample(
        _ offset: TimeInterval,
        modelID: String? = "model-a",
        providerIdentity: String? = "provider-a",
        current: Double? = 50,
        baseline: Double? = 100,
        baselineCount: Int = 12,
        active: Bool = true,
        highGPU: Bool = true
    ) -> ServingSlowdownInput {
        .init(
            modelID: modelID,
            providerIdentity: providerIdentity,
            currentTokensPerSecond: current,
            baselineTokensPerSecond: baseline,
            baselineSampleCount: baselineCount,
            capturedAt: start.addingTimeInterval(offset),
            isActiveInference: active,
            highHostGPU: highGPU
        )
    }

    @Test("same-model slowdown warns only after the cold grace and dwell")
    func warnsOnSustainedSameModelSlowdown() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0), at: start) == nil)
        #expect(policy.observe(sample(3), at: start.addingTimeInterval(3)) == nil)
        let warning = policy.observe(sample(6), at: start.addingTimeInterval(6))

        #expect(warning?.modelID == "model-a")
        #expect(warning?.providerIdentity == "provider-a")
        #expect(warning?.currentTokensPerSecond == 50)
        #expect(warning?.baselineTokensPerSecond == 100)
        #expect(warning?.baselineSampleCount == 12)
        #expect(warning?.ratio == 0.5)
        #expect(warning?.slowdownSince == start)
        #expect(warning?.capturedAt == start.addingTimeInterval(6))
    }

    @Test("the first eligible baseline stays frozen through a slowdown streak")
    func baselineChangesDoNotMoveTheThresholdOrEraseStreak() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0), at: start) == nil)
        #expect(policy.observe(sample(3, baseline: 200, baselineCount: 40), at: start.addingTimeInterval(3)) == nil)
        let warning = policy.observe(sample(6, baseline: 300, baselineCount: 80), at: start.addingTimeInterval(6))

        #expect(warning?.baselineTokensPerSecond == 100)
        #expect(warning?.baselineSampleCount == 12)
        #expect(warning?.ratio == 0.5)
    }

    @Test("baseline freezes at the first active observation even before throughput arrives")
    func sparseThroughputDoesNotDelayBaselineFreeze() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0, current: nil), at: start) == nil)
        #expect(policy.observe(sample(3, current: 50, baseline: 200), at: start.addingTimeInterval(3)) == nil)
        #expect(policy.observe(sample(6, current: 50, baseline: 300), at: start.addingTimeInterval(6)) == nil)
        let warning = policy.observe(sample(9, current: 50, baseline: 400), at: start.addingTimeInterval(9))

        #expect(warning?.baselineTokensPerSecond == 100)
        #expect(warning?.ratio == 0.5)
        #expect(warning?.slowdownSince == start.addingTimeInterval(3))
    }

    @Test("an invalid starting baseline cannot be replaced by a rolling value mid-session")
    func invalidInitialBaselineStaysUnavailableUntilReset() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0, current: nil, baselineCount: 9), at: start) == nil)
        #expect(policy.observe(sample(3, baselineCount: 12), at: start.addingTimeInterval(3)) == nil)
        #expect(policy.observe(sample(6, baselineCount: 20), at: start.addingTimeInterval(6)) == nil)
        #expect(policy.observe(sample(9, baselineCount: 20), at: start.addingTimeInterval(9)) == nil)

        #expect(policy.observe(sample(12, active: false), at: start.addingTimeInterval(12)) == nil)
        #expect(policy.observe(sample(13, baselineCount: 12), at: start.addingTimeInterval(13)) == nil)
        #expect(policy.observe(sample(16, baselineCount: 12), at: start.addingTimeInterval(16)) == nil)
        #expect(policy.observe(sample(19, baselineCount: 12), at: start.addingTimeInterval(19)) != nil)
    }

    @Test("high whole-Mac GPU is required to return the warning")
    func highGPUEligibility() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0, highGPU: false), at: start) == nil)
        #expect(policy.observe(sample(3, highGPU: false), at: start.addingTimeInterval(3)) == nil)
        #expect(policy.observe(sample(6, highGPU: false), at: start.addingTimeInterval(6)) == nil)
        #expect(policy.observe(sample(9, highGPU: true), at: start.addingTimeInterval(9)) != nil)
    }

    @Test("missing, stale, future, zero, and under-sampled baselines cannot warn")
    func rejectsUnavailableOrInvalidMetrics() {
        let invalidSamples: [(ServingSlowdownInput, Date)] = [
            (sample(0, modelID: nil), start),
            (sample(0, providerIdentity: "  "), start),
            (sample(0, current: nil), start),
            (sample(0, current: 0), start),
            (sample(0, current: .nan), start),
            (sample(0, baseline: nil), start),
            (sample(0, baseline: 0), start),
            (sample(0, baseline: .infinity), start),
            (sample(0, baselineCount: 9), start),
            (sample(0, active: false), start),
            (sample(0), start.addingTimeInterval(-11)),
            (sample(2), start.addingTimeInterval(1)),
        ]

        for (invalid, now) in invalidSamples {
            var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 3, coldStartGraceSeconds: 3)
            #expect(policy.observe(invalid, at: now) == nil)
        }
    }

    @Test("a source gap over ten seconds starts a fresh cold session")
    func longGapResetsDwellAndGrace() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0), at: start) == nil)
        #expect(policy.observe(sample(11), at: start.addingTimeInterval(11)) == nil)
        #expect(policy.observe(sample(14), at: start.addingTimeInterval(14)) == nil)
        #expect(policy.observe(sample(17), at: start.addingTimeInterval(17)) != nil)
    }

    @Test("duplicate source timestamps do not advance or erase a valid streak")
    func duplicateSnapshotsPreserveStreakWithoutAdvancingIt() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0), at: start) == nil)
        #expect(policy.observe(sample(0), at: start.addingTimeInterval(1)) == nil)
        #expect(policy.observe(sample(3), at: start.addingTimeInterval(3)) == nil)
        #expect(policy.observe(sample(3), at: start.addingTimeInterval(5)) == nil)
        let warning = policy.observe(sample(6), at: start.addingTimeInterval(6))
        #expect(warning != nil)
        #expect(policy.observe(sample(6), at: start.addingTimeInterval(7)) == warning)
    }

    @Test("caller clock rollback resets the streak and cold grace")
    func callerClockRollbackResetsTheSession() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0), at: start) == nil)
        #expect(policy.observe(sample(3), at: start.addingTimeInterval(5)) == nil)
        #expect(policy.observe(sample(4), at: start.addingTimeInterval(4.5)) == nil)
        #expect(policy.observe(sample(7), at: start.addingTimeInterval(7)) == nil)
        #expect(policy.observe(sample(10), at: start.addingTimeInterval(10)) != nil)
    }

    @Test("idle and model/provider changes begin new sessions with new baselines")
    func sessionAndIdentityChangesReset() {
        var policy = ServingSlowdownPolicy(thresholdRatio: 0.6, sustainedSeconds: 6, coldStartGraceSeconds: 6)

        #expect(policy.observe(sample(0), at: start) == nil)
        #expect(policy.observe(sample(3, active: false), at: start.addingTimeInterval(3)) == nil)
        #expect(policy.observe(sample(4, baseline: 200), at: start.addingTimeInterval(4)) == nil)
        #expect(policy.observe(sample(7, modelID: "model-b", providerIdentity: "provider-b", baseline: 200), at: start.addingTimeInterval(7)) == nil)
        #expect(policy.observe(sample(10, modelID: "model-b", providerIdentity: "provider-b", baseline: 200), at: start.addingTimeInterval(10)) == nil)
        let warning = policy.observe(sample(13, modelID: "model-b", providerIdentity: "provider-b", baseline: 200), at: start.addingTimeInterval(13))

        #expect(warning?.modelID == "model-b")
        #expect(warning?.providerIdentity == "provider-b")
        #expect(warning?.baselineTokensPerSecond == 200)
        #expect(warning?.ratio == 0.25)
    }
}
