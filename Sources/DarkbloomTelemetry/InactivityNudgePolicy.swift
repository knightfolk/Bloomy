import Foundation

/// Observes continuous, explicitly idle provider state. The caller owns any
/// notification cooldown; returning a start date does not consume an attempt.
public struct InactivityNudgePolicy: Sendable {
    private struct IdleSignature: Equatable, Sendable {
        let processIdentity: ProcessIdentity
        let model: String
        let stats: ProviderStats
    }

    private var idleStartedAt: Date?
    private var lastObservedAt: Date?
    private var lastWrittenAt: TimeInterval?
    private var signature: IdleSignature?

    public init() {}

    /// Returns the first observed idle instant once the uninterrupted threshold
    /// has elapsed. Long polling gaps, including app sleep, start a new window.
    public mutating func observe(
        _ state: DaemonState?,
        at now: Date,
        threshold: TimeInterval = 900
    ) -> Date? {
        let nowSeconds = now.timeIntervalSince1970
        guard nowSeconds.isFinite,
              threshold.isFinite,
              threshold >= 0,
              let state,
              state.writtenAt.isFinite,
              (0...10).contains(nowSeconds - state.writtenAt),
              !state.inferenceActive,
              state.trust?.status == "online",
              state.lifecycle?.outcome == .serving,
              state.lifecycle?.remainingRequests == 0,
              state.startupPreloadPendingModels?.isEmpty == true,
              state.availability == nil,
              state.modelLoadFailures.isEmpty,
              state.stats.requestsServed >= 0,
              state.stats.tokensGenerated >= 0,
              state.stats.usageGaps >= 0,
              !state.currentModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              state.advertisedModels?.contains(state.currentModel) == true,
              state.warmModels == [state.currentModel]
        else {
            reset()
            return nil
        }

        if let modelSwitch = state.modelSwitch,
           modelSwitch.outcome != .serving || modelSwitch.remainingRequests != 0 {
            reset()
            return nil
        }

        let currentSignature = IdleSignature(
            processIdentity: state.processIdentity,
            model: state.currentModel,
            stats: state.stats
        )
        if let lastObservedAt,
           let lastWrittenAt,
           let signature,
           (now.timeIntervalSince(lastObservedAt) < 0
                || now.timeIntervalSince(lastObservedAt) > 15
                || state.writtenAt < lastWrittenAt
                || signature != currentSignature) {
            reset()
        }

        if idleStartedAt == nil {
            idleStartedAt = now
        }
        lastObservedAt = now
        lastWrittenAt = state.writtenAt
        signature = currentSignature

        guard let idleStartedAt,
              now.timeIntervalSince(idleStartedAt) >= threshold else {
            return nil
        }
        return idleStartedAt
    }

    public mutating func reset() {
        idleStartedAt = nil
        lastObservedAt = nil
        lastWrittenAt = nil
        signature = nil
    }
}

/// Account-wide earnings evidence. A work event on any provider makes a
/// reward-only inactivity claim unsafe, even when its recorded price is zero.
public enum NudgeEarningsEvidence: Equatable, Sendable {
    case baseRewardsOnly
    case workRecorded
    case insufficientHistory
    case unavailable

    public static func evaluate(
        _ response: AccountEarningsResponse,
        since: Date,
        now: Date
    ) -> Self {
        let sinceSeconds = since.timeIntervalSince1970
        let nowSeconds = now.timeIntervalSince1970
        let rows = response.earnings
        guard sinceSeconds.isFinite,
              nowSeconds.isFinite,
              sinceSeconds >= 0,
              sinceSeconds <= nowSeconds,
              response.count >= 0,
              response.historyLimit > 0,
              response.recentCount >= 0,
              response.recentCount == rows.count,
              rows.count <= response.historyLimit,
              response.count >= Int64(rows.count)
        else { return .unavailable }

        var seenIDs = Set<Int64>()
        var oldest: Date?
        var hasWork = false
        var hasPositiveReward = false
        for row in rows {
            let createdSeconds = row.createdAt.timeIntervalSince1970
            guard row.id > 0,
                  seenIDs.insert(row.id).inserted,
                  row.amountMicroUSD >= 0,
                  row.promptTokens >= 0,
                  row.completionTokens >= 0,
                  createdSeconds.isFinite,
                  createdSeconds >= 0,
                  createdSeconds <= nowSeconds
            else { return .unavailable }

            if let currentOldest = oldest {
                if row.createdAt < currentOldest { oldest = row.createdAt }
            } else {
                oldest = row.createdAt
            }
            guard row.createdAt >= since else { continue }
            if row.model == "base_reward" {
                hasPositiveReward = hasPositiveReward || row.amountMicroUSD > 0
            } else {
                hasWork = true
            }
        }

        if hasWork { return .workRecorded }
        let completeLifetime = response.count == Int64(rows.count)
        guard completeLifetime || (oldest.map { $0 < since } ?? false) else {
            return .insufficientHistory
        }
        return hasPositiveReward ? .baseRewardsOnly : .insufficientHistory
    }
}
