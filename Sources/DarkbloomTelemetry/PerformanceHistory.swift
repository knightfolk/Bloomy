import Foundation

public enum PerformanceSampleQuality: String, Codable, CaseIterable, Sendable {
    case current, stale, unavailable
}

/// A whitelist of local performance measurements. Never add provider log text,
/// prompts, errors, credentials, account IDs, or request bodies to this record.
public struct PerformanceSample: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let observedAt: Date
    public let sourceCapturedAt: Date?
    public let quality: PerformanceSampleQuality
    public let providerSession: String?
    public let model: String?
    public let residentModels: [String]
    public let advertisedModels: [String]
    public let inferenceActive: Bool?
    public let activeRequests: Int?
    public let tokensPerSecond: Double?
    public let tokensGenerated: Int64?
    public let requestsServed: Int64?
    public let gpuUtilizationPercent: Double?
    public let gpuMemoryGB: Double?
    public let powerWatts: Double?
    public let autopilotPhase: String?

    public init(
        id: UUID = UUID(), observedAt: Date = Date(), sourceCapturedAt: Date? = nil,
        quality: PerformanceSampleQuality = .unavailable, providerSession: String? = nil,
        model: String? = nil, residentModels: [String] = [], advertisedModels: [String] = [],
        inferenceActive: Bool? = nil, activeRequests: Int? = nil, tokensPerSecond: Double? = nil,
        tokensGenerated: Int64? = nil, requestsServed: Int64? = nil,
        gpuUtilizationPercent: Double? = nil, gpuMemoryGB: Double? = nil,
        powerWatts: Double? = nil, autopilotPhase: String? = nil
    ) {
        self.id = id
        self.observedAt = observedAt
        self.sourceCapturedAt = sourceCapturedAt
        self.quality = quality
        self.providerSession = providerSession
        self.model = model
        self.residentModels = residentModels
        self.advertisedModels = advertisedModels
        self.inferenceActive = inferenceActive
        self.activeRequests = activeRequests
        self.tokensPerSecond = tokensPerSecond
        self.tokensGenerated = tokensGenerated
        self.requestsServed = requestsServed
        self.gpuUtilizationPercent = gpuUtilizationPercent
        self.gpuMemoryGB = gpuMemoryGB
        self.powerWatts = powerWatts
        self.autopilotPhase = autopilotPhase
    }

    var hasActiveInference: Bool? {
        inferenceActive ?? activeRequests.map { $0 > 0 }
    }

    static func validTimestamp(_ value: Date) -> Bool {
        let seconds = value.timeIntervalSince1970
        return seconds.isFinite && (0...253_402_300_799).contains(seconds)
    }

    var isValid: Bool {
        guard Self.validTimestamp(observedAt),
              sourceCapturedAt.map(Self.validTimestamp) ?? true,
              sourceCapturedAt.map({ $0 <= observedAt }) ?? true,
              model.map(Self.validModel) ?? true,
              residentModels.count <= 256, advertisedModels.count <= 256,
              residentModels.allSatisfy(Self.validModel), advertisedModels.allSatisfy(Self.validModel),
              providerSession.map(Self.validSession) ?? true,
              autopilotPhase.map(KnownAutopilotPhase.contains) ?? true,
              activeRequests.map({ (0...1_000_000).contains($0) }) ?? true,
              tokensGenerated.map({ $0 >= 0 }) ?? true,
              requestsServed.map({ $0 >= 0 }) ?? true else { return false }
        return Self.validMetric(tokensPerSecond, maximum: 1_000_000_000)
            && Self.validMetric(gpuUtilizationPercent, maximum: 100)
            && Self.validMetric(gpuMemoryGB, maximum: 1_000_000)
            && Self.validMetric(powerWatts, maximum: 10_000_000)
    }

    private static func validModel(_ value: String) -> Bool {
        validIdentifier(value, maximumBytes: 160) && !value.hasPrefix("/") && !value.contains(":/")
            && value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static let allowedIdentifierCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/+-")

    private static func validIdentifier(_ value: String, maximumBytes: Int) -> Bool {
        !value.isEmpty && value.utf8.count <= maximumBytes
            && value.unicodeScalars.allSatisfy(allowedIdentifierCharacters.contains)
    }

    private static func validSession(_ value: String) -> Bool {
        guard value.utf8.count <= 80 else { return false }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let pid = UInt64(parts[0]), pid > 0,
              let start = Double(parts[1]), start.isFinite, start >= 0 else { return false }
        return parts[0].allSatisfy({ $0.isASCII && $0.isNumber })
            && parts[1].allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." })
    }

    private static func validMetric(_ value: Double?, maximum: Double) -> Bool {
        value.map { $0.isFinite && (0...maximum).contains($0) } ?? true
    }
}

/// Conservative integration of adjacent measurements. Input order is retained:
/// gaps, bad captures, model changes, resets, and sessions are never bridged.
public struct PerformanceSummary: Equatable, Sendable {
    public let sampleCount: Int
    public let coveredSeconds: TimeInterval
    public let activeSeconds: TimeInterval
    /// Covered intervals where activity is known at both endpoints, including idle.
    public let activeCoveredSeconds: TimeInterval
    public let averageTokenRate: Double?
    public let averageGPUUtilizationPercent: Double?
    /// Whole-Mac readings bracketed by observed idle inference and unchanged
    /// request counters. This is a proxy, not attribution to other processes.
    public let averageIdleGPUUtilizationPercent: Double?
    public let idleGPUCoveredSeconds: TimeInterval
    public let completedRequests: Int64?
    public let generatedTokens: Int64?

    public init(samples: [PerformanceSample], model: String? = nil) {
        sampleCount = samples.filter { model == nil || $0.model == model }.count
        var covered = 0.0
        var active = 0.0
        var activeCovered = 0.0
        let validity = samples.map(\.isValid)
        var tokenIntegral = 0.0
        var tokenSeconds = 0.0
        var gpuIntegral = 0.0
        var gpuSeconds = 0.0
        var idleGPUIntegral = 0.0
        var idleGPUSeconds = 0.0
        var requests: Int64?
        var tokens: Int64?
        var requestsOverflow = false
        var tokensOverflow = false
        for index in samples.indices.dropFirst() {
            let first = samples[index - 1]
            let second = samples[index]
            guard validity[index - 1], validity[index], Self.validPair(first, second),
                  model == nil || (first.model == model && second.model == model) else { continue }
            let duration = second.observedAt.timeIntervalSince(first.observedAt)
            covered += duration
            let firstActive = first.hasActiveInference
            let secondActive = second.hasActiveInference
            if firstActive != nil && secondActive != nil { activeCovered += duration }
            let activePair = firstActive == true && secondActive == true
            if activePair { active += duration }
            if activePair, first.model != nil, first.model == second.model,
               let firstRate = first.tokensPerSecond, let secondRate = second.tokensPerSecond {
                tokenIntegral += (firstRate / 2 + secondRate / 2) * duration
                tokenSeconds += duration
            }
            if let firstGPU = first.gpuUtilizationPercent, let secondGPU = second.gpuUtilizationPercent {
                gpuIntegral += (firstGPU / 2 + secondGPU / 2) * duration
                gpuSeconds += duration
                if firstActive == false, secondActive == false,
                   let before = first.requestsServed, let after = second.requestsServed, before == after {
                    idleGPUIntegral += (firstGPU / 2 + secondGPU / 2) * duration
                    idleGPUSeconds += duration
                }
            }
            // Provider counters are global. A last-used model at both ends
            // cannot prove which models served requests between observations.
            if model == nil, let before = first.requestsServed, let after = second.requestsServed {
                requests = Self.add(after - before, to: requests, overflow: &requestsOverflow)
            }
            if model == nil, let before = first.tokensGenerated, let after = second.tokensGenerated {
                tokens = Self.add(after - before, to: tokens, overflow: &tokensOverflow)
            }
        }
        coveredSeconds = covered
        activeSeconds = active
        activeCoveredSeconds = activeCovered
        averageTokenRate = tokenSeconds > 0 ? tokenIntegral / tokenSeconds : nil
        averageGPUUtilizationPercent = gpuSeconds > 0 ? gpuIntegral / gpuSeconds : nil
        averageIdleGPUUtilizationPercent = idleGPUSeconds > 0 ? idleGPUIntegral / idleGPUSeconds : nil
        idleGPUCoveredSeconds = idleGPUSeconds
        completedRequests = requests
        generatedTokens = tokens
    }

    static func validPair(_ first: PerformanceSample, _ second: PerformanceSample) -> Bool {
        guard first.quality == .current, second.quality == .current,
              let session = first.providerSession, session == second.providerSession,
              let firstCapture = first.sourceCapturedAt, let secondCapture = second.sourceCapturedAt,
              secondCapture > firstCapture else { return false }
        let duration = second.observedAt.timeIntervalSince(first.observedAt)
        let firstAge = first.observedAt.timeIntervalSince(firstCapture)
        let secondAge = second.observedAt.timeIntervalSince(secondCapture)
        guard duration > 0, duration <= 90, (0...90).contains(firstAge), (0...90).contains(secondAge),
              secondCapture.timeIntervalSince(firstCapture) <= 90 else { return false }
        if let before = first.requestsServed, let after = second.requestsServed, after < before { return false }
        if let before = first.tokensGenerated, let after = second.tokensGenerated, after < before { return false }
        return true
    }

    private static func add(_ increment: Int64, to total: Int64?, overflow: inout Bool) -> Int64? {
        guard !overflow else { return nil }
        let (value, didOverflow) = (total ?? 0).addingReportingOverflow(increment)
        overflow = didOverflow
        return didOverflow ? nil : value
    }
}
