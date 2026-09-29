import Foundation

/// User-adjustable timing bounds. Hold and return cooldown are enforced by
/// the caller that owns switching state; confirmation and load allowance are
/// used by this pure evidence policy.
public struct ProfitSwitchTiming: Codable, Equatable, Sendable {
    public let confirmationMinutes: Int
    public let minimumHoldMinutes: Int
    public let returnCooldownMinutes: Int
    public let loadAllowanceMinutes: Int

    public init(
        confirmationMinutes: Int = 10,
        minimumHoldMinutes: Int = 60,
        returnCooldownMinutes: Int = 180,
        loadAllowanceMinutes: Int = 5
    ) {
        self.confirmationMinutes = min(60, max(5, confirmationMinutes))
        self.minimumHoldMinutes = min(240, max(30, minimumHoldMinutes))
        self.returnCooldownMinutes = max(
            self.minimumHoldMinutes,
            min(1_440, max(60, returnCooldownMinutes))
        )
        self.loadAllowanceMinutes = min(30, max(1, loadAllowanceMinutes))
    }

    private enum CodingKeys: String, CodingKey {
        case confirmationMinutes, minimumHoldMinutes, returnCooldownMinutes, loadAllowanceMinutes
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            confirmationMinutes: try values.decodeIfPresent(Int.self, forKey: .confirmationMinutes) ?? 10,
            minimumHoldMinutes: try values.decodeIfPresent(Int.self, forKey: .minimumHoldMinutes) ?? 60,
            returnCooldownMinutes: try values.decodeIfPresent(Int.self, forKey: .returnCooldownMinutes) ?? 180,
            loadAllowanceMinutes: try values.decodeIfPresent(Int.self, forKey: .loadAllowanceMinutes) ?? 5
        )
    }
}

/// One observed model's demand and estimated hourly economics. The estimates
/// are inputs to a heuristic, not a promise of future earnings.
public struct ProfitSwitchCandidate: Equatable, Sendable {
    public let modelID: String
    public let requests: Int
    public let pressure: Double
    public let grossUSDPerActiveHour: Double
    public let netUSDPerActiveHour: Double
    public let loadSeconds: Double

    public init(
        modelID: String,
        requests: Int,
        pressure: Double,
        grossUSDPerActiveHour: Double,
        netUSDPerActiveHour: Double,
        loadSeconds: Double
    ) {
        self.modelID = modelID
        self.requests = requests
        self.pressure = pressure
        self.grossUSDPerActiveHour = grossUSDPerActiveHour
        self.netUSDPerActiveHour = netUSDPerActiveHour
        self.loadSeconds = loadSeconds
    }
}

public struct ProfitSwitchInput: Equatable, Sendable {
    public let currentModelID: String
    public let candidates: [ProfitSwitchCandidate]
    public let capturedAt: Date

    public init(currentModelID: String, candidates: [ProfitSwitchCandidate], capturedAt: Date) {
        self.currentModelID = currentModelID
        self.candidates = candidates
        self.capturedAt = capturedAt
    }
}

/// A conservative one-hour estimate. The caller decides whether a switch is
/// actually safe or allowed and owns cooldowns, dwell, and control operations.
public struct ProfitSwitchProposal: Equatable, Sendable {
    public let modelID: String
    public let currentModelID: String
    public let estimatedGainUSD: Double
    public let estimatedGainPercent: Double?
    public let loadSeconds: Double

    public init(
        modelID: String,
        currentModelID: String,
        estimatedGainUSD: Double,
        estimatedGainPercent: Double?,
        loadSeconds: Double
    ) {
        self.modelID = modelID
        self.currentModelID = currentModelID
        self.estimatedGainUSD = estimatedGainUSD
        self.estimatedGainPercent = estimatedGainPercent
        self.loadSeconds = loadSeconds
    }
}

/// Requires a profitable winner in at least three distinct, recent samples
/// spanning ten minutes. A gap over 150 seconds starts a new window.
public struct ProfitSwitchPolicy: Sendable {
    private let timing: ProfitSwitchTiming
    private var winnerID: String?
    private var currentModelID: String?
    private var firstCapture: Date?
    private var lastCapture: Date?
    private var lastObservedAt: Date?
    private var sampleCount = 0

    public init(timing: ProfitSwitchTiming = .init()) {
        self.timing = timing
    }

    /// Checks a single fresh snapshot without changing temporal confirmation.
    /// This can revalidate economics after control state is refreshed.
    public static func evaluate(
        _ input: ProfitSwitchInput,
        at now: Date,
        timing: ProfitSwitchTiming = .init()
    ) -> ProfitSwitchProposal? {
        guard now.timeIntervalSince1970.isFinite,
              input.capturedAt.timeIntervalSince1970.isFinite,
              (0...120).contains(now.timeIntervalSince(input.capturedAt))
        else { return nil }
        return winner(in: input, timing: timing)
    }

    public mutating func observe(_ input: ProfitSwitchInput?, at now: Date) -> ProfitSwitchProposal? {
        guard let input,
              let proposal = Self.evaluate(input, at: now, timing: timing)
        else {
            reset()
            return nil
        }

        if let lastObservedAt {
            let observationGap = now.timeIntervalSince(lastObservedAt)
            if !observationGap.isFinite || observationGap < 0 || observationGap > 150 {
                reset()
            }
        }
        if let lastCapture {
            let gap = input.capturedAt.timeIntervalSince(lastCapture)
            if gap < 0 || !gap.isFinite {
                reset()
                return nil
            }
            if gap == 0 {
                // A repeat may retain evidence, but cannot count as a new sample.
                // Changing winner or current model on the same capture is ambiguous.
                if winnerID != proposal.modelID || currentModelID != input.currentModelID {
                    reset()
                } else {
                    lastObservedAt = now
                }
                return nil
            }
            if gap > 150 || winnerID != proposal.modelID || currentModelID != input.currentModelID {
                reset()
            }
        }

        if firstCapture == nil {
            firstCapture = input.capturedAt
            sampleCount = 0
        }
        winnerID = proposal.modelID
        currentModelID = input.currentModelID
        lastCapture = input.capturedAt
        lastObservedAt = now
        sampleCount += 1

        guard let firstCapture,
              sampleCount >= 3,
              input.capturedAt.timeIntervalSince(firstCapture) >= Double(timing.confirmationMinutes * 60)
        else { return nil }
        return proposal
    }

    public mutating func reset() {
        winnerID = nil
        currentModelID = nil
        firstCapture = nil
        lastCapture = nil
        lastObservedAt = nil
        sampleCount = 0
    }

    private static func winner(in input: ProfitSwitchInput, timing: ProfitSwitchTiming) -> ProfitSwitchProposal? {
        guard !input.currentModelID.isEmpty, !input.candidates.isEmpty else { return nil }
        var seen = Set<String>()
        for candidate in input.candidates {
            guard !candidate.modelID.isEmpty,
                  seen.insert(candidate.modelID).inserted,
                  candidate.requests >= 0,
                  candidate.pressure.isFinite, candidate.pressure >= 0,
                  candidate.grossUSDPerActiveHour.isFinite, candidate.grossUSDPerActiveHour >= 0,
                  candidate.netUSDPerActiveHour.isFinite, candidate.netUSDPerActiveHour >= 0,
                  candidate.grossUSDPerActiveHour >= candidate.netUSDPerActiveHour,
                  candidate.loadSeconds.isFinite, (0...1_800).contains(candidate.loadSeconds)
            else { return nil }
        }
        guard let current = input.candidates.first(where: { $0.modelID == input.currentModelID }),
              current.netUSDPerActiveHour > 0
        else { return nil }

        let currentProjection = current.netUSDPerActiveHour * min(1, current.pressure)
        let pressureThreshold = max(current.pressure * 1.25, current.pressure + 0.1)
        guard currentProjection.isFinite, pressureThreshold.isFinite else { return nil }

        var best: ProfitSwitchProposal?
        for candidate in input.candidates where candidate.modelID != input.currentModelID {
            guard candidate.requests > current.requests,
                  candidate.pressure >= pressureThreshold,
                  candidate.grossUSDPerActiveHour > current.grossUSDPerActiveHour,
                  candidate.netUSDPerActiveHour > 0
            else { continue }

            let loadSeconds = max(Double(timing.loadAllowanceMinutes * 60), candidate.loadSeconds)
            let candidateProjection = candidate.netUSDPerActiveHour
                * min(1, candidate.pressure) * ((3_600 - loadSeconds) / 3_600)
            let gain = candidateProjection - currentProjection
            let requiredGain = max(abs(currentProjection) * 0.3, 0.05)
            guard candidateProjection.isFinite, gain.isFinite,
                  requiredGain.isFinite, gain >= requiredGain
            else { continue }

            // With no current projected demand the percentage is undefined.
            // USD remains the authoritative gate.
            let percent = currentProjection > 0 ? (gain / currentProjection) * 100 : nil
            guard percent?.isFinite ?? true else { continue }
            let proposal = ProfitSwitchProposal(
                modelID: candidate.modelID,
                currentModelID: input.currentModelID,
                estimatedGainUSD: gain,
                estimatedGainPercent: percent,
                loadSeconds: loadSeconds
            )
            if best == nil || proposal.estimatedGainUSD > best!.estimatedGainUSD
                || (proposal.estimatedGainUSD == best!.estimatedGainUSD && proposal.modelID < best!.modelID) {
                best = proposal
            }
        }
        return best
    }
}
