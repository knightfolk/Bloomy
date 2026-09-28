import CryptoKit
import Foundation

/// Versioned, allowlisted evidence for an observe-only model decision. Account
/// identity, raw work rows, provider credentials, and executable state are not
/// represented here. A caller classifies work as same-account before assembly.
public struct RecommendationInput: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public let version: Int
    public let evaluatedAt: Date
    public let currentModelID: String?
    public let inventoryCapturedAt: Date?
    public let capacityIsDraining: Bool
    public let candidates: [RecommendationCandidateInput]

    public init(
        evaluatedAt: Date,
        currentModelID: String?,
        inventoryCapturedAt: Date?,
        capacityIsDraining: Bool,
        candidates: [RecommendationCandidateInput],
        version: Int = currentVersion
    ) {
        self.version = version
        self.evaluatedAt = evaluatedAt
        self.currentModelID = currentModelID
        self.inventoryCapturedAt = inventoryCapturedAt
        self.capacityIsDraining = capacityIsDraining
        self.candidates = candidates
    }

    var canonicalized: Self {
        Self(
            evaluatedAt: evaluatedAt,
            currentModelID: currentModelID,
            inventoryCapturedAt: inventoryCapturedAt,
            capacityIsDraining: capacityIsDraining,
            candidates: candidates.sorted { $0.modelID < $1.modelID },
            version: version
        )
    }
}

public struct RecommendationCandidateInput: Codable, Equatable, Sendable {
    public let modelID: String
    public let enabled: Bool
    public let downloaded: Bool
    public let capacity: RecommendationCapacityEvidence?
    public let readiness: RecommendationReadinessEvidence?
    public let tokenRates: [RecommendationTokenRateEvidence]
    public let observedWork: [RecommendationWorkEvidence]

    public init(
        modelID: String,
        enabled: Bool,
        downloaded: Bool,
        capacity: RecommendationCapacityEvidence?,
        readiness: RecommendationReadinessEvidence?,
        tokenRates: [RecommendationTokenRateEvidence] = [],
        observedWork: [RecommendationWorkEvidence] = []
    ) {
        self.modelID = modelID
        self.enabled = enabled
        self.downloaded = downloaded
        self.capacity = capacity
        self.readiness = readiness
        self.tokenRates = tokenRates
        self.observedWork = observedWork
    }
}

public struct RecommendationCapacityEvidence: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let ready: Bool
    public let activeRequests: Int
    public let queuedRequests: Int
    public let warmProviders: Int

    public init(capturedAt: Date, ready: Bool, activeRequests: Int, queuedRequests: Int, warmProviders: Int) {
        self.capturedAt = capturedAt
        self.ready = ready
        self.activeRequests = activeRequests
        self.queuedRequests = queuedRequests
        self.warmProviders = warmProviders
    }

    fileprivate var isValid: Bool {
        activeRequests >= 0 && queuedRequests >= 0 && warmProviders >= 0
            && activeRequests <= 1_000_000 && queuedRequests <= 1_000_000
            && warmProviders <= 1_000_000
    }

    fileprivate var demandBand: RecommendationDemandBand {
        let band = NetworkModelCapacity.demandBand(
            activeRequests: activeRequests,
            queuedRequests: queuedRequests,
            warmProviders: warmProviders
        )
        return RecommendationDemandBand(rawValue: band.rawValue) ?? .low
    }

    fileprivate var demandPerWarmProvider: Double? {
        guard warmProviders > 0 else { return nil }
        return Double(activeRequests + queuedRequests) / Double(warmProviders)
    }
}

public struct RecommendationReadinessEvidence: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let compatible: Bool
    public let locallyReady: Bool
    public let memoryFits: Bool

    public init(capturedAt: Date, compatible: Bool, locallyReady: Bool, memoryFits: Bool) {
        self.capturedAt = capturedAt
        self.compatible = compatible
        self.locallyReady = locallyReady
        self.memoryFits = memoryFits
    }
}

public struct RecommendationTokenRateEvidence: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let tokensPerSecond: Double
    public let sampleCount: Int

    public init(capturedAt: Date, tokensPerSecond: Double, sampleCount: Int) {
        self.capturedAt = capturedAt
        self.tokensPerSecond = tokensPerSecond
        self.sampleCount = sampleCount
    }
}

public enum RecommendationWorkScope: String, Codable, Equatable, Sendable {
    case sameAccount
    case crossAccount
    case unknown
}

/// This is observed account-scoped work, never a local earnings forecast.
public struct RecommendationWorkEvidence: Codable, Equatable, Sendable {
    public let capturedAt: Date
    public let period: DateInterval
    public let microUSD: Int64
    public let jobs: Int64
    public let recordedHours: Int
    public let unknownHours: Int
    public let uncertainBoundaryHours: Int
    public let scope: RecommendationWorkScope

    public init(
        capturedAt: Date,
        period: DateInterval,
        microUSD: Int64,
        jobs: Int64,
        recordedHours: Int,
        unknownHours: Int,
        uncertainBoundaryHours: Int,
        scope: RecommendationWorkScope
    ) {
        self.capturedAt = capturedAt
        self.period = period
        self.microUSD = microUSD
        self.jobs = jobs
        self.recordedHours = recordedHours
        self.unknownHours = unknownHours
        self.uncertainBoundaryHours = uncertainBoundaryHours
        self.scope = scope
    }
}

public enum RecommendationDemandBand: String, Codable, Equatable, Sendable {
    case low, moderate, high, urgent

    fileprivate var rank: Int {
        switch self {
        case .low: 0
        case .moderate: 1
        case .high: 2
        case .urgent: 3
        }
    }
}

public enum RecommendationOutcome: Codable, Equatable, Sendable {
    case insufficientEvidence
    case stay
    /// A read-only suggestion. It carries no dispatch authority.
    case consider(modelID: String)
}

public enum RecommendationConfidence: String, Codable, Equatable, Sendable {
    case insufficient
    case limited
    case corroborated
}

public enum RecommendationBlocker: String, Codable, CaseIterable, Equatable, Sendable {
    case unsupportedVersion, invalidInput, missingCurrentModel, missingCurrentCapacity
    case staleCapacity, staleInventory, draining, duplicateCandidate, networkUnavailable
    case notEnabled, notDownloaded, missingReadiness, staleReadiness
    case incompatible, notLocallyReady, memoryInsufficient, noDemand
}

public enum RecommendationFactorKind: String, Codable, Equatable, Sendable {
    case networkDemand, networkReadiness, networkPressure, inventory, compatibility, readiness, memory, measuredThroughput, observedWork
}

public enum RecommendationProvenance: String, Codable, Equatable, Sendable {
    case networkAggregate, localInventory, localReadiness, localMeasuredRate, accountObservedWork
}

public enum RecommendationFreshness: String, Codable, Equatable, Sendable {
    case fresh, stale, missing, invalid, duplicate, partial, crossAccount
}

public struct RecommendationCoverage: Codable, Equatable, Sendable {
    public let recordedHours: Int
    public let unknownHours: Int
    public let uncertainBoundaryHours: Int
    public let sampleCount: Int?
}

public struct RecommendationFactor: Codable, Equatable, Sendable {
    public let kind: RecommendationFactorKind
    public let provenance: RecommendationProvenance
    public let sourceCapturedAt: Date?
    public let ageSeconds: TimeInterval?
    public let freshness: RecommendationFreshness
    /// Counts, rates, observed micro-USD per job, or boolean 0/1 by kind.
    public let numericValue: Double?
    public let coverage: RecommendationCoverage?

    fileprivate init(
        kind: RecommendationFactorKind,
        provenance: RecommendationProvenance,
        capturedAt: Date?,
        at now: Date,
        freshness: RecommendationFreshness,
        numericValue: Double? = nil,
        coverage: RecommendationCoverage? = nil
    ) {
        self.kind = kind
        self.provenance = provenance
        sourceCapturedAt = capturedAt
        let age = capturedAt.map { now.timeIntervalSince($0) }
        ageSeconds = age.flatMap { $0.isFinite ? Swift.max(0, $0) : nil }
        self.freshness = freshness
        self.numericValue = numericValue
        self.coverage = coverage
    }
}

public struct RecommendationCandidateAssessment: Codable, Equatable, Sendable {
    public let modelID: String
    public let eligible: Bool
    public let demandBand: RecommendationDemandBand?
    public let blockers: [RecommendationBlocker]
    public let factors: [RecommendationFactor]

    fileprivate var observedWorkPerJob: Double? {
        factors.first { $0.kind == .observedWork && $0.freshness == .fresh }?.numericValue
    }
    fileprivate var measuredRate: Double? {
        factors.first { $0.kind == .measuredThroughput && $0.freshness == .fresh }?.numericValue
    }
    fileprivate var demandCount: Double {
        factors.first { $0.kind == .networkDemand }?.numericValue ?? 0
    }
    fileprivate var networkPressure: Double {
        factors.first { $0.kind == .networkPressure }?.numericValue ?? 0
    }
}

public struct RecommendationDecision: Codable, Equatable, Sendable {
    public let id: String
    public let version: Int
    public let evaluatedAt: Date
    public let outcome: RecommendationOutcome
    public let confidence: RecommendationConfidence
    public let blockers: [RecommendationBlocker]
    public let assessments: [RecommendationCandidateAssessment]
}

public enum RecommendationEvaluator {
    public static func evaluate(_ source: RecommendationInput) -> RecommendationDecision {
        let input = source.canonicalized
        let now = input.evaluatedAt
        let assessments = input.candidates.map { assess($0, inventoryAt: input.inventoryCapturedAt, now: now) }
        var blockers: [RecommendationBlocker] = []
        if input.version != RecommendationInput.currentVersion { blockers.append(.unsupportedVersion) }
        if !validDate(now) || input.candidates.count > 128
            || input.candidates.contains(where: { !validModelID($0.modelID) }) {
            blockers.append(.invalidInput)
        }
        if Set(input.candidates.map(\.modelID)).count != input.candidates.count {
            blockers.append(.duplicateCandidate)
        }
        if input.capacityIsDraining { blockers.append(.draining) }
        if freshness(input.inventoryCapturedAt, at: now, maximumAge: 120) != .fresh {
            blockers.append(.staleInventory)
        }
        guard let currentModelID = input.currentModelID, validModelID(currentModelID) else {
            blockers.append(.missingCurrentModel)
            return decision(input, .insufficientEvidence, .insufficient, blockers, assessments)
        }
        guard let currentIndex = input.candidates.firstIndex(where: { $0.modelID == currentModelID }),
              let currentCapacity = input.candidates[currentIndex].capacity else {
            blockers.append(.missingCurrentCapacity)
            return decision(input, .insufficientEvidence, .insufficient, blockers, assessments)
        }
        if !currentCapacity.isValid || freshness(currentCapacity.capturedAt, at: now, maximumAge: 120) != .fresh {
            blockers.append(.staleCapacity)
        }
        guard blockers.isEmpty else {
            return decision(input, .insufficientEvidence, .insufficient, blockers, assessments)
        }

        let currentBand = currentCapacity.demandBand
        let alternatives = zip(input.candidates, assessments).filter { candidate, assessment in
            candidate.modelID != currentModelID && assessment.eligible
                && (assessment.demandBand?.rank ?? -1) > currentBand.rank
                && (assessment.demandBand?.rank ?? -1) >= RecommendationDemandBand.high.rank
        }
        guard let best = alternatives.sorted(by: { left, right in
            let lhs = left.1
            let rhs = right.1
            if lhs.demandBand != rhs.demandBand { return (lhs.demandBand?.rank ?? -1) > (rhs.demandBand?.rank ?? -1) }
            if lhs.demandCount != rhs.demandCount { return lhs.demandCount > rhs.demandCount }
            if lhs.networkPressure != rhs.networkPressure { return lhs.networkPressure > rhs.networkPressure }
            let lhsWork = lhs.observedWorkPerJob ?? -1
            let rhsWork = rhs.observedWorkPerJob ?? -1
            if lhsWork != rhsWork { return lhsWork > rhsWork }
            let lhsRate = lhs.measuredRate ?? -1
            let rhsRate = rhs.measuredRate ?? -1
            if lhsRate != rhsRate { return lhsRate > rhsRate }
            return lhs.modelID < rhs.modelID
        }).first else {
            return decision(input, .stay, .limited, [], assessments)
        }
        let confidence: RecommendationConfidence = best.1.observedWorkPerJob != nil && best.1.measuredRate != nil
            ? .corroborated : .limited
        return decision(input, .consider(modelID: best.0.modelID), confidence, [], assessments)
    }

    private static func assess(
        _ candidate: RecommendationCandidateInput,
        inventoryAt: Date?,
        now: Date
    ) -> RecommendationCandidateAssessment {
        var blockers: [RecommendationBlocker] = []
        var factors: [RecommendationFactor] = []
        let capacityState = candidate.capacity.map { freshness($0.capturedAt, at: now, maximumAge: 120) } ?? .missing
        let validCapacity = candidate.capacity.map { $0.isValid && capacityState == .fresh } ?? false
        if !validCapacity { blockers.append(.staleCapacity) }
        let capacity = validCapacity ? candidate.capacity : nil
        if capacity?.ready == false { blockers.append(.networkUnavailable) }
        let reportedCapacityState: RecommendationFreshness = candidate.capacity?.isValid == false
            ? .invalid : capacityState
        factors.append(.init(
            kind: .networkDemand, provenance: .networkAggregate,
            capturedAt: candidate.capacity?.capturedAt, at: now,
            freshness: reportedCapacityState,
            numericValue: capacity.map { Double($0.activeRequests + $0.queuedRequests) }
        ))
        factors.append(.init(
            kind: .networkReadiness, provenance: .networkAggregate,
            capturedAt: candidate.capacity?.capturedAt, at: now,
            freshness: reportedCapacityState,
            numericValue: capacity.map { $0.ready ? 1 : 0 }
        ))
        factors.append(.init(
            kind: .networkPressure, provenance: .networkAggregate,
            capturedAt: candidate.capacity?.capturedAt, at: now,
            freshness: reportedCapacityState,
            numericValue: capacity?.demandPerWarmProvider
        ))

        let inventoryState = freshness(inventoryAt, at: now, maximumAge: 120)
        if inventoryState != .fresh { blockers.append(.staleInventory) }
        if !candidate.enabled { blockers.append(.notEnabled) }
        if !candidate.downloaded { blockers.append(.notDownloaded) }
        factors.append(.init(
            kind: .inventory, provenance: .localInventory, capturedAt: inventoryAt, at: now,
            freshness: inventoryState, numericValue: candidate.enabled && candidate.downloaded ? 1 : 0
        ))

        let readinessState = candidate.readiness.map { freshness($0.capturedAt, at: now, maximumAge: 120) } ?? .missing
        if candidate.readiness == nil { blockers.append(.missingReadiness) }
        else if readinessState != .fresh { blockers.append(.staleReadiness) }
        if candidate.readiness?.compatible == false { blockers.append(.incompatible) }
        if candidate.readiness?.locallyReady == false { blockers.append(.notLocallyReady) }
        if candidate.readiness?.memoryFits == false { blockers.append(.memoryInsufficient) }
        for (kind, value) in [
            (RecommendationFactorKind.compatibility, candidate.readiness?.compatible),
            (.readiness, candidate.readiness?.locallyReady),
            (.memory, candidate.readiness?.memoryFits),
        ] {
            factors.append(.init(
                kind: kind, provenance: .localReadiness,
                capturedAt: candidate.readiness?.capturedAt, at: now,
                freshness: readinessState, numericValue: value.map { $0 ? 1 : 0 }
            ))
        }

        let rate = candidate.tokenRates
        let rateState: RecommendationFreshness
        if rate.isEmpty { rateState = .missing }
        else if rate.count != 1 { rateState = .duplicate }
        else if !rate[0].tokensPerSecond.isFinite || rate[0].tokensPerSecond <= 0
                    || !(1...1_000_000).contains(rate[0].sampleCount) { rateState = .invalid }
        else { rateState = freshness(rate[0].capturedAt, at: now, maximumAge: 600) }
        factors.append(.init(
            kind: .measuredThroughput, provenance: .localMeasuredRate,
            capturedAt: rate.count == 1 ? rate[0].capturedAt : nil, at: now,
            freshness: rateState,
            numericValue: rateState == .fresh ? rate[0].tokensPerSecond : nil,
            coverage: rate.count == 1 ? .init(recordedHours: 0, unknownHours: 0,
                                               uncertainBoundaryHours: 0, sampleCount: rate[0].sampleCount) : nil
        ))

        let work = candidate.observedWork
        let workState: RecommendationFreshness
        if work.isEmpty { workState = .missing }
        else if work.count != 1 { workState = .duplicate }
        else if work[0].scope != .sameAccount { workState = .crossAccount }
        else if work[0].recordedHours < 0 || work[0].unknownHours < 0
                    || work[0].uncertainBoundaryHours < 0 { workState = .invalid }
        else if work[0].recordedHours == 0 || work[0].unknownHours > 0 || work[0].uncertainBoundaryHours > 0 {
            workState = .partial
        } else if work[0].microUSD < 0 || work[0].jobs <= 0
                    || work[0].period.duration <= 0 || work[0].period.duration > 86_400
                    || work[0].period.end > now || now.timeIntervalSince(work[0].period.end) > 600 {
            workState = .invalid
        } else { workState = freshness(work[0].capturedAt, at: now, maximumAge: 600) }
        factors.append(.init(
            kind: .observedWork, provenance: .accountObservedWork,
            capturedAt: work.count == 1 ? work[0].capturedAt : nil, at: now,
            freshness: workState,
            numericValue: workState == .fresh ? Double(work[0].microUSD) / Double(work[0].jobs) : nil,
            coverage: work.count == 1 ? .init(
                recordedHours: work[0].recordedHours,
                unknownHours: work[0].unknownHours,
                uncertainBoundaryHours: work[0].uncertainBoundaryHours,
                sampleCount: nil
            ) : nil
        ))

        if capacity?.activeRequests == 0 && capacity?.queuedRequests == 0 { blockers.append(.noDemand) }
        return RecommendationCandidateAssessment(
            modelID: candidate.modelID,
            eligible: blockers.isEmpty,
            demandBand: capacity?.demandBand,
            blockers: blockers.sorted { $0.rawValue < $1.rawValue },
            factors: factors
        )
    }

    private static func decision(
        _ input: RecommendationInput,
        _ outcome: RecommendationOutcome,
        _ confidence: RecommendationConfidence,
        _ blockers: [RecommendationBlocker],
        _ assessments: [RecommendationCandidateAssessment]
    ) -> RecommendationDecision {
        let data = (try? RecommendationCoding.encoder.encode(input)) ?? Data()
        let id = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return RecommendationDecision(
            id: id, version: input.version, evaluatedAt: input.evaluatedAt,
            outcome: outcome, confidence: confidence,
            blockers: blockers.sorted { $0.rawValue < $1.rawValue },
            assessments: assessments
        )
    }

    private static func freshness(_ capturedAt: Date?, at now: Date, maximumAge: TimeInterval) -> RecommendationFreshness {
        guard let capturedAt else { return .missing }
        let age = now.timeIntervalSince(capturedAt)
        return age.isFinite && (-5...maximumAge).contains(age) ? .fresh : .stale
    }

    private static func validDate(_ date: Date) -> Bool {
        let value = date.timeIntervalSince1970
        return value.isFinite && (-62_135_596_800...253_402_300_799).contains(value)
    }

    private static func validModelID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 512
            && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
    }
}

enum RecommendationCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN"
        )
        return decoder
    }
}
