import Foundation

/// A fresh throughput and serving-state observation supplied by the monitor.
/// The baseline is expected to be a same-model recorded average captured
/// before this inference session began.
public struct ServingSlowdownInput: Equatable, Sendable {
    public let modelID: String?
    public let providerIdentity: String?
    public let currentTokensPerSecond: Double?
    public let baselineTokensPerSecond: Double?
    public let baselineSampleCount: Int
    public let capturedAt: Date
    public let isActiveInference: Bool
    public let highHostGPU: Bool

    public init(
        modelID: String?,
        providerIdentity: String?,
        currentTokensPerSecond: Double?,
        baselineTokensPerSecond: Double?,
        baselineSampleCount: Int,
        capturedAt: Date,
        isActiveInference: Bool,
        highHostGPU: Bool
    ) {
        self.modelID = modelID
        self.providerIdentity = providerIdentity
        self.currentTokensPerSecond = currentTokensPerSecond
        self.baselineTokensPerSecond = baselineTokensPerSecond
        self.baselineSampleCount = baselineSampleCount
        self.capturedAt = capturedAt
        self.isActiveInference = isActiveInference
        self.highHostGPU = highHostGPU
    }
}

/// A sustained, same-model slowdown observed while whole-Mac GPU use is high.
/// Returning a report is a warning signal only; it does not control inference.
public struct ServingSlowdownReport: Equatable, Sendable {
    public let modelID: String
    public let providerIdentity: String
    public let currentTokensPerSecond: Double
    public let baselineTokensPerSecond: Double
    public let baselineSampleCount: Int
    public let ratio: Double
    public let slowdownSince: Date
    public let capturedAt: Date

    public init(
        modelID: String,
        providerIdentity: String,
        currentTokensPerSecond: Double,
        baselineTokensPerSecond: Double,
        baselineSampleCount: Int,
        ratio: Double,
        slowdownSince: Date,
        capturedAt: Date
    ) {
        self.modelID = modelID
        self.providerIdentity = providerIdentity
        self.currentTokensPerSecond = currentTokensPerSecond
        self.baselineTokensPerSecond = baselineTokensPerSecond
        self.baselineSampleCount = baselineSampleCount
        self.ratio = ratio
        self.slowdownSince = slowdownSince
        self.capturedAt = capturedAt
    }
}

/// Detects a sustained drop in a model's token rate while high whole-Mac GPU
/// use provides corroborating evidence of host contention.
///
/// The policy freezes its first valid same-model baseline for an active
/// session. Repeated snapshots do not advance time, and gaps, identity changes,
/// idle inference, or a caller clock rollback restart the session and its
/// cold-start grace. This policy only emits a report; it has no control path.
public struct ServingSlowdownPolicy: Sendable {
    public static let minimumBaselineSamples = 10
    public static let maximumObservationAge: TimeInterval = 10

    public let thresholdRatio: Double
    public let sustainedSeconds: TimeInterval
    public let coldStartGraceSeconds: TimeInterval

    private struct SessionIdentity: Equatable {
        let modelID: String
        let providerIdentity: String
    }

    private var identity: SessionIdentity?
    private var sessionStartedAt: Date?
    private var trustedBaselineTokensPerSecond: Double?
    private var trustedBaselineSampleCount: Int?
    private var slowdownSince: Date?
    private var lastCapturedAt: Date?
    private var lastObservedAt: Date?
    private var lastCurrentTokensPerSecond: Double?

    public init(
        thresholdRatio: Double = 0.6,
        sustainedSeconds: TimeInterval = 30,
        coldStartGraceSeconds: TimeInterval = 30
    ) {
        self.thresholdRatio = thresholdRatio
        self.sustainedSeconds = sustainedSeconds
        self.coldStartGraceSeconds = coldStartGraceSeconds
    }

    public mutating func reset() {
        identity = nil
        sessionStartedAt = nil
        trustedBaselineTokensPerSecond = nil
        trustedBaselineSampleCount = nil
        slowdownSince = nil
        lastCapturedAt = nil
        lastObservedAt = nil
        lastCurrentTokensPerSecond = nil
    }

    /// Returns a report only after a valid low-throughput streak has lasted
    /// through both the session grace period and configured dwell.
    public mutating func observe(_ input: ServingSlowdownInput?, at now: Date) -> ServingSlowdownReport? {
        guard isConfigurationValid,
              let input,
              Self.isFresh(input.capturedAt, at: now),
              input.isActiveInference,
              let modelID = Self.nonEmpty(input.modelID),
              let providerIdentity = Self.nonEmpty(input.providerIdentity) else {
            reset()
            return nil
        }

        let incomingIdentity = SessionIdentity(modelID: modelID, providerIdentity: providerIdentity)
        if identity != incomingIdentity {
            reset()
        }

        if let lastObservedAt {
            let clockDelta = now.timeIntervalSince(lastObservedAt)
            if !clockDelta.isFinite || clockDelta < 0 || clockDelta > Self.maximumObservationAge {
                reset()
            }
        }

        if let lastCapturedAt {
            let sourceDelta = input.capturedAt.timeIntervalSince(lastCapturedAt)
            if sourceDelta == 0 {
                // The capture is still fresh, but this source has not supplied
                // new evidence. A duplicate may repeat the warning; it cannot
                // move its timestamps or change the frozen baseline/streak.
                lastObservedAt = now
                guard Self.isPositiveFinite(input.currentTokensPerSecond) else { return nil }
                return warning(at: input.capturedAt, highHostGPU: input.highHostGPU)
            }
            if !sourceDelta.isFinite || sourceDelta < 0 || sourceDelta > Self.maximumObservationAge {
                reset()
            }
        }

        if identity == nil {
            // Resolve the baseline on the first fresh active observation,
            // even if this provider has not emitted a usable throughput value
            // yet. This keeps the active run from later moving its own norm.
            identity = incomingIdentity
            sessionStartedAt = input.capturedAt
            if let baseline = input.baselineTokensPerSecond,
               baseline.isFinite,
               baseline > 0,
               input.baselineSampleCount >= Self.minimumBaselineSamples {
                trustedBaselineTokensPerSecond = baseline
                trustedBaselineSampleCount = input.baselineSampleCount
            }
        }

        guard identity == incomingIdentity,
              let baseline = trustedBaselineTokensPerSecond,
              trustedBaselineSampleCount != nil else {
            // An invalid or under-sampled baseline at session start stays
            // unavailable until the session resets. A later rolling average
            // could already include this run.
            lastCapturedAt = input.capturedAt
            lastObservedAt = now
            lastCurrentTokensPerSecond = nil
            slowdownSince = nil
            return nil
        }

        guard let current = input.currentTokensPerSecond,
              current.isFinite,
              current > 0 else {
            // A unique sample with unknown or zero throughput breaks the low
            // streak, while the already-frozen session baseline stays intact.
            lastCapturedAt = input.capturedAt
            lastObservedAt = now
            lastCurrentTokensPerSecond = nil
            slowdownSince = nil
            return nil
        }

        lastCapturedAt = input.capturedAt
        lastObservedAt = now
        lastCurrentTokensPerSecond = current

        let ratio = current / baseline
        guard ratio.isFinite, ratio <= thresholdRatio else {
            slowdownSince = nil
            return nil
        }
        if slowdownSince == nil { slowdownSince = input.capturedAt }

        return warning(at: input.capturedAt, highHostGPU: input.highHostGPU)
    }

    private var isConfigurationValid: Bool {
        thresholdRatio.isFinite && (0...1).contains(thresholdRatio) && thresholdRatio > 0
            && sustainedSeconds.isFinite && sustainedSeconds >= 0
            && coldStartGraceSeconds.isFinite && coldStartGraceSeconds >= 0
    }

    private func warning(at capturedAt: Date, highHostGPU: Bool) -> ServingSlowdownReport? {
        guard highHostGPU,
              let identity,
              let sessionStartedAt,
              let baseline = trustedBaselineTokensPerSecond,
              let baselineSampleCount = trustedBaselineSampleCount,
              let current = lastCurrentTokensPerSecond,
              let slowdownSince else { return nil }

        let coldElapsed = capturedAt.timeIntervalSince(sessionStartedAt)
        let slowElapsed = capturedAt.timeIntervalSince(slowdownSince)
        guard coldElapsed.isFinite,
              slowElapsed.isFinite,
              coldElapsed >= coldStartGraceSeconds,
              slowElapsed >= sustainedSeconds else { return nil }

        let ratio = current / baseline
        guard ratio.isFinite, ratio <= thresholdRatio else { return nil }
        return ServingSlowdownReport(
            modelID: identity.modelID,
            providerIdentity: identity.providerIdentity,
            currentTokensPerSecond: current,
            baselineTokensPerSecond: baseline,
            baselineSampleCount: baselineSampleCount,
            ratio: ratio,
            slowdownSince: slowdownSince,
            capturedAt: capturedAt
        )
    }

    private static func isFresh(_ capturedAt: Date, at now: Date) -> Bool {
        let captureSeconds = capturedAt.timeIntervalSince1970
        let nowSeconds = now.timeIntervalSince1970
        let age = now.timeIntervalSince(capturedAt)
        return captureSeconds.isFinite && nowSeconds.isFinite && age.isFinite
            && (0...maximumObservationAge).contains(age)
    }

    private static func isPositiveFinite(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && value > 0
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
}
