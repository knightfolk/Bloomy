import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Inactivity nudge policy")
struct InactivityNudgePolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    @Test("returns the first observed idle instant without consuming the attempt")
    func sustainedIdle() {
        var policy = InactivityNudgePolicy()
        #expect(policy.observe(state(at: 2_000_000), at: start, threshold: 30) == nil)
        #expect(policy.observe(state(at: 2_000_010), at: start.addingTimeInterval(10), threshold: 30) == nil)
        #expect(policy.observe(state(at: 2_000_020), at: start.addingTimeInterval(20), threshold: 30) == nil)
        #expect(policy.observe(state(at: 2_000_030), at: start.addingTimeInterval(30), threshold: 30) == start)
        #expect(policy.observe(state(at: 2_000_040), at: start.addingTimeInterval(40), threshold: 30) == start)
        policy.reset()
        #expect(policy.observe(state(at: 2_000_050), at: start.addingTimeInterval(50), threshold: 30) == nil)
    }

    @Test("app sleep and backward clock movement restart the idle window")
    func observationContinuity() {
        var policy = InactivityNudgePolicy()
        #expect(policy.observe(state(at: 2_000_000), at: start, threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_016), at: start.addingTimeInterval(16), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_026), at: start.addingTimeInterval(26), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_036), at: start.addingTimeInterval(36), threshold: 20)
            == start.addingTimeInterval(16))
        #expect(policy.observe(state(at: 2_000_035), at: start.addingTimeInterval(35), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_045), at: start.addingTimeInterval(45), threshold: 20) == nil)
    }

    @Test("regressed daemon write time cannot bridge an idle window")
    func writeTimeRegression() {
        var policy = InactivityNudgePolicy()
        #expect(policy.observe(state(at: 2_000_004), at: start.addingTimeInterval(4), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_003), at: start.addingTimeInterval(8), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_018), at: start.addingTimeInterval(18), threshold: 10)
            == start.addingTimeInterval(8))
    }

    @Test("stale, future, absent, and invalid timestamps erase prior idle evidence")
    func timestampIntegrity() {
        var policy = InactivityNudgePolicy()
        #expect(policy.observe(state(at: 2_000_000), at: start, threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_000), at: start.addingTimeInterval(11), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_020), at: start.addingTimeInterval(20), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_031), at: start.addingTimeInterval(30), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_025), at: start.addingTimeInterval(35), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_046), at: start.addingTimeInterval(45), threshold: 20) == nil)
        #expect(policy.observe(nil, at: start.addingTimeInterval(55), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_060), at: start.addingTimeInterval(59), threshold: 20) == nil)
        #expect(policy.observe(state(at: .nan), at: start.addingTimeInterval(60), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_070), at: Date(timeIntervalSince1970: .infinity), threshold: 20) == nil)
        #expect(policy.observe(state(at: 2_000_070), at: start.addingTimeInterval(70), threshold: .nan) == nil)
        #expect(policy.observe(state(at: 2_000_070), at: start.addingTimeInterval(70), threshold: -1) == nil)
    }

    @Test("activity and changed process, model, or counters start a new window")
    func stateChanges() {
        var policy = InactivityNudgePolicy()
        let baseline = state(at: 2_000_000)
        #expect(policy.observe(baseline, at: start, threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_010, stats: .init(tokensGenerated: 1, requestsServed: 0, usageGaps: 0)),
                               at: start.addingTimeInterval(10), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_020, stats: .init(tokensGenerated: 1, requestsServed: 0, usageGaps: 0)),
                               at: start.addingTimeInterval(20), threshold: 10) == start.addingTimeInterval(10))
        #expect(policy.observe(state(at: 2_000_030, stats: .init(tokensGenerated: 1, requestsServed: 0, usageGaps: 1)),
                               at: start.addingTimeInterval(30), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_040, stats: .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 1)),
                               at: start.addingTimeInterval(40), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_050, stats: .init(tokensGenerated: 0, requestsServed: 1, usageGaps: 1)),
                               at: start.addingTimeInterval(50), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_060, process: 2, stats: .init(tokensGenerated: 0, requestsServed: 1, usageGaps: 1)),
                               at: start.addingTimeInterval(60), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_070, model: "model-b", advertised: ["model-b"], warm: ["model-b"],
                                     process: 2, stats: .init(tokensGenerated: 0, requestsServed: 1, usageGaps: 1)),
                               at: start.addingTimeInterval(70), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_080, inferenceActive: true),
                               at: start.addingTimeInterval(80), threshold: 10) == nil)
        #expect(policy.observe(state(at: 2_000_090), at: start.addingTimeInterval(90), threshold: 10) == nil)
    }

    @Test("unknown lifecycle, pending startup, switches, and multiple routes cannot prove idle")
    func failClosedOnAmbiguousServing() {
        let now = start
        let candidates: [DaemonState] = [
            state(at: 2_000_000, lifecycle: nil),
            state(at: 2_000_000, lifecycle: .init(outcome: .unknown)),
            state(at: 2_000_000, lifecycle: .init(outcome: .busy, remainingRequests: 0)),
            state(at: 2_000_000, lifecycle: .init(outcome: .serving)),
            state(at: 2_000_000, lifecycle: .init(outcome: .serving, remainingRequests: 1)),
            state(at: 2_000_000, trustStatus: nil),
            state(at: 2_000_000, trustStatus: "offline"),
            state(at: 2_000_000, inferenceActive: true),
            state(at: 2_000_000, pending: nil),
            state(at: 2_000_000, pending: ["model-b"]),
            state(at: 2_000_000, modelSwitch: .init(outcome: .switching, models: ["model-a"], remainingRequests: 0)),
            state(at: 2_000_000, modelSwitch: .init(outcome: .serving, models: ["model-a"])),
            state(at: 2_000_000, modelSwitch: .init(outcome: .serving, models: ["model-a"], remainingRequests: 1)),
            state(at: 2_000_000, advertised: nil),
            state(at: 2_000_000, advertised: ["model-a", "model-b"]),
            state(at: 2_000_000, warm: ["model-a", "model-b"]),
            state(at: 2_000_000, advertised: ["model-b"]),
            state(at: 2_000_000, hasLoadFailure: true),
            state(at: 2_000_000, availability: .init(phase: .unknown)),
            state(at: 2_000_000, stats: .init(tokensGenerated: 0, requestsServed: -1, usageGaps: 0)),
            state(at: 2_000_000, stats: .init(tokensGenerated: -1, requestsServed: 0, usageGaps: 0)),
            state(at: 2_000_000, stats: .init(tokensGenerated: 0, requestsServed: 0, usageGaps: -1)),
        ]
        for candidate in candidates {
            var policy = InactivityNudgePolicy()
            #expect(policy.observe(candidate, at: now, threshold: 0) == nil)
        }
        var policy = InactivityNudgePolicy()
        #expect(policy.observe(state(at: 2_000_000, modelSwitch: .init(outcome: .serving,
            models: ["model-a"], remainingRequests: 0)), at: now, threshold: 0) == now)
    }

    @Test("complete lifetime or an older row proves the reward-only window")
    func rewardCoverage() {
        let now = start
        let since = now.addingTimeInterval(-60)
        let reward = earning(id: 2, model: "base_reward", amount: 100, at: now)
        #expect(NudgeEarningsEvidence.evaluate(response([reward]), since: since, now: now) == .baseRewardsOnly)
        let boundary = earning(id: 3, model: "base_reward", amount: 1, at: since)
        #expect(NudgeEarningsEvidence.evaluate(response([reward, boundary], count: 50), since: since, now: now)
            == .insufficientHistory)
        let older = earning(id: 1, model: "base_reward", amount: 1, at: since.addingTimeInterval(-1))
        #expect(NudgeEarningsEvidence.evaluate(response([reward, older], count: 50), since: since, now: now)
            == .baseRewardsOnly)
        #expect(NudgeEarningsEvidence.evaluate(response([reward], count: 50), since: since, now: now)
            == .insufficientHistory)
        #expect(NudgeEarningsEvidence.evaluate(response([reward], count: 50, historyLimit: 1),
            since: since, now: now) == .insufficientHistory)
    }

    @Test("zero-priced account work defeats reward-only evidence")
    func workEvidence() {
        let now = start
        let since = now.addingTimeInterval(-60)
        let rows = [
            earning(id: 1, model: "base_reward", amount: 100, at: now),
            earning(id: 2, model: "unrelated-provider-model", amount: 0, at: now),
        ]
        #expect(NudgeEarningsEvidence.evaluate(response(rows, count: 50), since: since, now: now)
            == .workRecorded)
        #expect(NudgeEarningsEvidence.evaluate(response([earning(id: 3, model: "base_reward", amount: 0, at: now)]),
            since: since, now: now) == .insufficientHistory)
        #expect(NudgeEarningsEvidence.evaluate(response([]), since: since, now: now) == .insufficientHistory)
    }

    @Test("malformed metadata, duplicate rows, and bad values are unavailable")
    func malformedEarnings() {
        let now = start
        let since = now.addingTimeInterval(-60)
        let reward = earning(id: 1, model: "base_reward", amount: 10, at: now)
        let malformed: [AccountEarningsResponse] = [
            response([reward], count: -1),
            response([reward], count: 0),
            response([reward], recentCount: 0),
            response([reward], historyLimit: 0),
            response([reward, reward]),
            response([earning(id: 1, model: "base_reward", amount: -1, at: now)]),
            response([earning(id: 1, model: "base_reward", amount: 1, promptTokens: -1, at: now)]),
            response([earning(id: 1, model: "base_reward", amount: 1, completionTokens: -1, at: now)]),
            response([earning(id: 1, model: "base_reward", amount: 1, at: now.addingTimeInterval(1))]),
            response([earning(id: 1, model: "base_reward", amount: 1, at: Date(timeIntervalSince1970: .nan))]),
        ]
        for candidate in malformed {
            #expect(NudgeEarningsEvidence.evaluate(candidate, since: since, now: now) == .unavailable)
        }
        #expect(NudgeEarningsEvidence.evaluate(response([reward]), since: now.addingTimeInterval(1), now: now)
            == .unavailable)
        #expect(NudgeEarningsEvidence.evaluate(response([reward]), since: since,
            now: Date(timeIntervalSince1970: .infinity)) == .unavailable)
    }

    private func state(
        at writtenAt: TimeInterval,
        model: String = "model-a",
        advertised: [String]? = ["model-a"],
        warm: [String] = ["model-a"],
        process: Int32 = 1,
        stats: ProviderStats = .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
        inferenceActive: Bool = false,
        trustStatus: String? = "online",
        lifecycle: ProviderLifecycleState? = .init(outcome: .serving, remainingRequests: 0),
        pending: [String]? = [],
        modelSwitch: ProviderModelSwitchState? = nil,
        hasLoadFailure: Bool = false,
        availability: ProviderAvailabilityState? = nil
    ) -> DaemonState {
        DaemonState(
            schema: 1, version: "test", currentModel: model, warmModels: warm,
            stats: stats,
            trust: trustStatus.map { .init(level: "hardware", status: $0, reason: "test", receivedAt: writtenAt) },
            capacity: nil, slots: [], inferenceActive: inferenceActive,
            startedAt: 1_999_000, writtenAt: writtenAt, pid: process,
            processIdentity: .init(pid: process, startTimeMicros: Int64(process)),
            advertisedModels: advertised,
            modelLoadFailures: hasLoadFailure ? [.init(model: model)] : [],
            lifecycle: lifecycle, startupPreloadPendingModels: pending,
            modelSwitch: modelSwitch, availability: availability
        )
    }

    private func earning(
        id: Int64,
        model: String,
        amount: Int64,
        promptTokens: Int = 0,
        completionTokens: Int = 0,
        at date: Date
    ) -> AccountEarning {
        AccountEarning(
            id: id, providerID: "provider", providerKey: "key", model: model,
            amountMicroUSD: amount, promptTokens: promptTokens,
            completionTokens: completionTokens, createdAt: date
        )
    }

    private func response(
        _ rows: [AccountEarning],
        count: Int64? = nil,
        historyLimit: Int = 1_000,
        recentCount: Int? = nil
    ) -> AccountEarningsResponse {
        AccountEarningsResponse(
            accountID: "account", earnings: rows, count: count ?? Int64(rows.count),
            historyLimit: historyLimit, recentCount: recentCount ?? rows.count
        )
    }
}
