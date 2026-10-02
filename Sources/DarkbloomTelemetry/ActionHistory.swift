import CryptoKit
import Foundation

public enum ActionHistoryAction: String, Codable, CaseIterable, Sendable {
    case nudge, swap, modelSelection, saveSettings, downloadModel, deleteModel
    case startProvider, stopProvider, restartProvider, hosting, cooling
    case idleSettings, betaSettings, nudgeSettings, nudgeKey, profitSettings
    case providerUpdates, job, baseReward, watcher
    case autopilotEnrollment, autopilotPause, autopilotResume, autopilotDisable
}

public enum ActionHistoryTrigger: String, Codable, CaseIterable, Sendable {
    case manual, automatic, swap, provider, system
}

public enum ActionHistoryOutcome: String, Codable, CaseIterable, Sendable {
    case started, succeeded, failed, skipped, cancelled, unconfirmed, interrupted
}

/// A controlled explanation code. Provider responses, error descriptions,
/// prompts, credentials, and account identifiers must never enter this journal.
public enum ActionHistoryReason: String, Codable, CaseIterable, Sendable {
    case none, keyMissing, keyRejected, modelUnavailable, requestFailed
    case notConfirmed, providerNotReady, providerBusy, earningsUnavailable
    case workRecorded, cooldown, dailyLimit, disabled, completed, interrupted
    case confirmationRequired
}

public struct ActionHistoryJob: Codable, Equatable, Sendable {
    public let earningID: Int64
    public let promptTokens: Int64
    public let completionTokens: Int64
    public let amountMicroUSD: Int64

    public init(earningID: Int64, promptTokens: Int64, completionTokens: Int64, amountMicroUSD: Int64) {
        self.earningID = earningID
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.amountMicroUSD = amountMicroUSD
    }
}

public struct ActionHistoryEvent: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let occurredAt: Date
    public let updatedAt: Date
    public let action: ActionHistoryAction
    public let trigger: ActionHistoryTrigger
    public let outcome: ActionHistoryOutcome
    public let model: String?
    public let reason: ActionHistoryReason?
    public let correlationID: UUID?
    public let job: ActionHistoryJob?

    public init(
        id: UUID = UUID(),
        occurredAt: Date = Date(),
        updatedAt: Date? = nil,
        action: ActionHistoryAction,
        trigger: ActionHistoryTrigger,
        outcome: ActionHistoryOutcome,
        model: String? = nil,
        reason: ActionHistoryReason? = nil,
        correlationID: UUID? = nil,
        job: ActionHistoryJob? = nil
    ) {
        self.id = id
        self.occurredAt = occurredAt
        self.updatedAt = updatedAt ?? occurredAt
        self.action = action
        self.trigger = trigger
        self.outcome = outcome
        self.model = model
        self.reason = reason
        self.correlationID = correlationID
        self.job = job
    }

    /// Derive the same UUID when an observed action is replayed after restart.
    /// Only the UUID is stored; `key` is never persisted. Use a stable source
    /// identity such as an earning ID, not a credential or request body.
    public static func deterministicID(namespace: String, key: String) -> UUID {
        let digest = SHA256.hash(data: Data((namespace + "\u{0}" + key).utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}
