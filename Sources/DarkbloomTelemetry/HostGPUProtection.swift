import Foundation

/// Whole-Mac GPU activity observed while the provider is idle is a host-load
/// proxy. It does not identify the process responsible for that activity.
public enum HostGPUProtectionMode: String, Codable, CaseIterable, Sendable {
    case off
    case warn
    case automaticPause
}

public struct HostGPUProtectionSettings: Codable, Equatable, Sendable {
    public var mode: HostGPUProtectionMode
    public var ceilingPercent: Double
    public var resumePercent: Double
    public var breachSeconds: TimeInterval
    public var recoverySeconds: TimeInterval
    public var minimumPausedSeconds: TimeInterval
    public var throughputFloorPercent: Double
    public var slowdownSeconds: TimeInterval

    public init(mode: HostGPUProtectionMode = .off, ceilingPercent: Double = 80,
                resumePercent: Double = 60, breachSeconds: TimeInterval = 15,
                recoverySeconds: TimeInterval = 60, minimumPausedSeconds: TimeInterval = 120,
                throughputFloorPercent: Double = 60, slowdownSeconds: TimeInterval = 30) {
        self.mode = mode
        self.ceilingPercent = ceilingPercent
        self.resumePercent = resumePercent
        self.breachSeconds = breachSeconds
        self.recoverySeconds = recoverySeconds
        self.minimumPausedSeconds = minimumPausedSeconds
        self.throughputFloorPercent = throughputFloorPercent
        self.slowdownSeconds = slowdownSeconds
    }

    private enum CodingKeys: String, CodingKey {
        case mode, ceilingPercent, resumePercent, breachSeconds, recoverySeconds, minimumPausedSeconds
        case throughputFloorPercent, slowdownSeconds
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(mode: try values.decodeIfPresent(HostGPUProtectionMode.self, forKey: .mode) ?? .off,
                  ceilingPercent: try values.decodeIfPresent(Double.self, forKey: .ceilingPercent) ?? 80,
                  resumePercent: try values.decodeIfPresent(Double.self, forKey: .resumePercent) ?? 60,
                  breachSeconds: try values.decodeIfPresent(Double.self, forKey: .breachSeconds) ?? 15,
                  recoverySeconds: try values.decodeIfPresent(Double.self, forKey: .recoverySeconds) ?? 60,
                  minimumPausedSeconds: try values.decodeIfPresent(Double.self, forKey: .minimumPausedSeconds) ?? 120,
                  throughputFloorPercent: try values.decodeIfPresent(Double.self, forKey: .throughputFloorPercent) ?? 60,
                  slowdownSeconds: try values.decodeIfPresent(Double.self, forKey: .slowdownSeconds) ?? 30)
    }

    public var isValid: Bool { validationError == nil }

    public var validationError: String? {
        guard ceilingPercent.isFinite, (1...100).contains(ceilingPercent),
              resumePercent.isFinite, (0...99).contains(resumePercent),
              resumePercent < ceilingPercent else {
            return "GPU thresholds must be between 0 and 100%, with resume below the ceiling."
        }
        guard breachSeconds.isFinite, (3...600).contains(breachSeconds),
              recoverySeconds.isFinite, (3...3_600).contains(recoverySeconds),
              minimumPausedSeconds.isFinite, (0...3_600).contains(minimumPausedSeconds) else {
            return "Use 3–600 seconds above the ceiling, 3–3,600 seconds for recovery, and 0–3,600 seconds minimum pause."
        }
        guard throughputFloorPercent.isFinite, (10...90).contains(throughputFloorPercent),
              slowdownSeconds.isFinite, (15...600).contains(slowdownSeconds) else {
            return "Use a throughput floor of 10–90% and a slowdown window of 15–600 seconds."
        }
        return nil
    }
}

public struct HostGPUProtectionSample: Equatable, Sendable {
    public let percent: Double
    public let capturedAt: Date

    public init(percent: Double, capturedAt: Date) {
        self.percent = percent
        self.capturedAt = capturedAt
    }
}

/// The integration owner establishes idle eligibility from fresh daemon state,
/// excluding inference, preloading, switching, and drain transitions.
public struct HostGPUProtectionProviderContext: Equatable, Sendable {
    public let running: Bool
    public let idle: Bool
    public let capturedAt: Date
    public let identity: String?
    public let isTransitioning: Bool

    public init(running: Bool, idle: Bool, capturedAt: Date, identity: String?, isTransitioning: Bool = false) {
        self.running = running
        self.idle = idle
        self.capturedAt = capturedAt
        self.identity = identity
        self.isTransitioning = isTransitioning
    }
}

public struct HostGPUProtectionPolicy: Sendable {
    public enum Decision: Equatable, Sendable {
        case off
        case watching
        case unavailable(String)
        case breached
        case recovered
    }

    public let settings: HostGPUProtectionSettings
    private var lastSampleAt: Date?
    private var lastObservedAt: Date?
    private var providerIdentity: String?
    private var breachSince: Date?
    private var recoverySince: Date?
    public static let maximumObservationAge: TimeInterval = 10

    public init(settings: HostGPUProtectionSettings = .init()) {
        self.settings = settings
    }

    public mutating func reset() {
        lastSampleAt = nil
        lastObservedAt = nil
        providerIdentity = nil
        breachSince = nil
        recoverySince = nil
    }

    public mutating func observe(sample: HostGPUProtectionSample?, provider: HostGPUProtectionProviderContext?,
                                 at now: Date, pausedSince: Date? = nil) -> Decision {
        guard settings.mode != .off else { reset(); return .off }
        if let error = settings.validationError { return reject(error) }
        guard let sample, sample.percent.isFinite, (0...100).contains(sample.percent),
              fresh(sample.capturedAt, at: now) else {
            return reject("Waiting for a current whole-Mac GPU reading.")
        }
        if let lastSampleAt {
            let gap = sample.capturedAt.timeIntervalSince(lastSampleAt)
            if gap == 0 {
                // UI/daemon updates may re-deliver the current sampler value.
                // Such delivery neither advances time nor erases sound GPU
                // evidence, but fresh active/changed provider state breaks it.
                if pausedSince != nil {
                    return .unavailable("Waiting for a distinct current GPU reading.")
                }
                if let provider, provider.running, provider.idle, !provider.isTransitioning,
                   let identity = provider.identity, !identity.isEmpty,
                   providerIdentity == identity, fresh(provider.capturedAt, at: now) {
                    return .unavailable("Waiting for a distinct current GPU reading.")
                }
            }
            guard gap.isFinite, gap > 0 else {
                return reject("Waiting for a distinct current GPU reading.")
            }
            if gap > Self.maximumObservationAge { reset() }
        }
        if let lastObservedAt {
            let elapsed = now.timeIntervalSince(lastObservedAt)
            if !elapsed.isFinite || elapsed < 0 || elapsed > Self.maximumObservationAge { reset() }
        }
        lastSampleAt = sample.capturedAt
        lastObservedAt = now

        if let pausedSince {
            breachSince = nil
            providerIdentity = nil
            let pausedFor = now.timeIntervalSince(pausedSince)
            guard pausedFor.isFinite, pausedFor >= 0 else {
                return reject("Pause timing needs a current clock.")
            }
            guard sample.percent < settings.resumePercent else {
                recoverySince = nil
                return .watching
            }
            if recoverySince == nil { recoverySince = sample.capturedAt }
            if let recoverySince,
               sample.capturedAt.timeIntervalSince(recoverySince) >= settings.recoverySeconds,
               pausedFor >= settings.minimumPausedSeconds { return .recovered }
            return .watching
        }

        recoverySince = nil
        guard let provider, provider.running, provider.idle, !provider.isTransitioning,
              let identity = provider.identity, !identity.isEmpty,
              fresh(provider.capturedAt, at: now) else {
            return reject("Watching requires fresh idle provider state; active work is protected.")
        }
        if providerIdentity != identity { breachSince = nil }
        providerIdentity = identity
        guard sample.percent >= settings.ceilingPercent else {
            breachSince = nil
            return .watching
        }
        if breachSince == nil { breachSince = sample.capturedAt }
        if let breachSince, sample.capturedAt.timeIntervalSince(breachSince) >= settings.breachSeconds {
            return .breached
        }
        return .watching
    }

    private func fresh(_ date: Date, at now: Date) -> Bool {
        let age = now.timeIntervalSince(date)
        return age.isFinite && (0...Self.maximumObservationAge).contains(age)
    }

    private mutating func reject(_ reason: String) -> Decision {
        reset()
        return .unavailable(reason)
    }
}
