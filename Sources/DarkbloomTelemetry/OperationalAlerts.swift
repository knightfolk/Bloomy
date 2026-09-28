import Foundation

/// Closed alert codes keep persisted history and exported support packets free
/// of provider error prose, process metadata, and caller-controlled labels.
public enum OperationalAlertCode: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case providerOffline = "provider_offline"
    case lifecycleTimedOut = "lifecycle_timed_out"
    case lifecycleForced = "lifecycle_forced"
    case modelInsufficientMemory = "model_insufficient_memory"
    case modelUnavailable = "model_unavailable"
    case modelUnsupported = "model_unsupported"
    case modelIntegrityFailure = "model_integrity_failure"
    case modelTimedOut = "model_timed_out"
    case modelBackendUnavailable = "model_backend_unavailable"
    case modelUnknown = "model_unknown"

    public var title: String {
        switch self {
        case .providerOffline: "Provider unavailable"
        case .lifecycleTimedOut: "Provider operation timed out"
        case .lifecycleForced: "Provider required a forced stop"
        case .modelInsufficientMemory: "Model could not load: memory unavailable"
        case .modelUnavailable: "Model could not load: unavailable"
        case .modelUnsupported: "Model could not load: unsupported"
        case .modelIntegrityFailure: "Model could not load: integrity check failed"
        case .modelTimedOut: "Model load timed out"
        case .modelBackendUnavailable: "Model backend unavailable"
        case .modelUnknown: "Model load failed"
        }
    }

    public var isLifecycleFailure: Bool {
        self == .lifecycleTimedOut || self == .lifecycleForced
    }

    public var isModelFailure: Bool {
        switch self {
        case .modelInsufficientMemory, .modelUnavailable, .modelUnsupported,
             .modelIntegrityFailure, .modelTimedOut, .modelBackendUnavailable, .modelUnknown:
            true
        case .providerOffline, .lifecycleTimedOut, .lifecycleForced:
            false
        }
    }

    fileprivate init(modelFailureCode: ModelLoadFailureCode) {
        switch modelFailureCode {
        case .insufficientMemory: self = .modelInsufficientMemory
        case .modelUnavailable: self = .modelUnavailable
        case .unsupported: self = .modelUnsupported
        case .integrityFailure: self = .modelIntegrityFailure
        case .timedOut: self = .modelTimedOut
        case .backendUnavailable: self = .modelBackendUnavailable
        case .unknown: self = .modelUnknown
        }
    }
}

public enum AlertTransitionKind: String, Codable, Equatable, Sendable {
    case raised
    case recovered
    case suppressed
}

/// One evidence-backed state change. Numeric evidence is bounded and all
/// human-readable copy comes from the closed alert-code templates above.
public struct AlertTransition: Codable, Equatable, Sendable {
    public let code: OperationalAlertCode
    public let kind: AlertTransitionKind
    public let occurredAt: Date
    public let observedDurationSeconds: Int?
    public let observationCount: Int

    public init(
        code: OperationalAlertCode,
        kind: AlertTransitionKind,
        occurredAt: Date,
        observedDurationSeconds: Int? = nil,
        observationCount: Int = 1
    ) {
        self.code = code
        self.kind = kind
        self.occurredAt = occurredAt
        self.observedDurationSeconds = observedDurationSeconds
        self.observationCount = observationCount
    }
}

/// A persisted transition row. The database-generated sequence is local to
/// the host and is not included in support exports.
public struct AlertRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let code: OperationalAlertCode
    public let kind: AlertTransitionKind
    public let occurredAt: Date
    public let observedDurationSeconds: Int?
    public let observationCount: Int

    init(
        id: Int64,
        code: OperationalAlertCode,
        kind: AlertTransitionKind,
        occurredAt: Date,
        observedDurationSeconds: Int?,
        observationCount: Int
    ) {
        self.id = id
        self.code = code
        self.kind = kind
        self.occurredAt = occurredAt
        self.observedDurationSeconds = observedDurationSeconds
        self.observationCount = observationCount
    }
}

public protocol AlertHistoryRecording: Sendable {
    func record(_ transitions: [AlertTransition]) async throws
    func recentHistory(limit: Int) async throws -> [AlertRecord]
    func activeAlertCodes() async throws -> Set<OperationalAlertCode>
}

public struct OperationalAlertPolicy: Equatable, Sendable {
    public let sustainedOutageDuration: TimeInterval
    public let coldStartGraceDuration: TimeInterval
    public let maximumEvidenceGap: TimeInterval
    public let maximumSnapshotAge: TimeInterval

    public init(
        sustainedOutageDuration: TimeInterval = 60,
        coldStartGraceDuration: TimeInterval = 30,
        maximumEvidenceGap: TimeInterval = 20,
        maximumSnapshotAge: TimeInterval = 10
    ) {
        self.sustainedOutageDuration = Self.bounded(
            sustainedOutageDuration, fallback: 60, minimum: 1, maximum: 3_600
        )
        self.coldStartGraceDuration = Self.bounded(
            coldStartGraceDuration, fallback: 30, minimum: 0, maximum: 3_600
        )
        self.maximumEvidenceGap = Self.bounded(
            maximumEvidenceGap, fallback: 20, minimum: 1, maximum: 120
        )
        self.maximumSnapshotAge = Self.bounded(
            maximumSnapshotAge, fallback: 10, minimum: 1, maximum: 60
        )
    }

    private static func bounded(
        _ value: TimeInterval,
        fallback: TimeInterval,
        minimum: TimeInterval,
        maximum: TimeInterval
    ) -> TimeInterval {
        guard value.isFinite else { return fallback }
        return min(max(value, minimum), maximum)
    }
}

/// A deterministic state machine. A provider outage requires repeated fresh
/// offline evidence, a sustained interval, and completion of the cold-start
/// grace. Stale or missing state never raises or recovers an alert.
public struct OperationalAlertEngine: Sendable {
    private struct PendingOutage: Sendable {
        var firstObservedAt: Date
        var lastObservedAt: Date
        var observationCount: Int
    }

    public let policy: OperationalAlertPolicy
    private var activeCodes: Set<OperationalAlertCode> = []
    private var pendingOutage: PendingOutage?
    private var firstSnapshotAt: Date?
    private var lastSnapshotAt: Date?

    public init(policy: OperationalAlertPolicy = .init()) {
        self.policy = policy
    }

    /// Restores deduplication state from the durable active-alert index.
    public mutating func restoreActiveAlerts(_ codes: Set<OperationalAlertCode>) {
        activeCodes = codes
    }

    public var activeAlertCodes: Set<OperationalAlertCode> { activeCodes }

    public mutating func transitions(for snapshot: TelemetrySnapshot) -> [AlertTransition] {
        let now = snapshot.capturedAt
        guard now.timeIntervalSince1970.isFinite else { return [] }

        if let previousSnapshotAt = lastSnapshotAt, now < previousSnapshotAt {
            // A wall-clock correction breaks continuity. Wait for new evidence
            // instead of turning reordered samples into an outage or recovery.
            pendingOutage = nil
            firstSnapshotAt = now
            lastSnapshotAt = now
            return []
        }
        if firstSnapshotAt == nil { firstSnapshotAt = now }
        lastSnapshotAt = now

        guard let daemon = freshDaemon(from: snapshot, at: now) else {
            pendingOutage = nil
            return []
        }

        var result: [AlertTransition] = []
        let isScheduledIdle = daemon.availability?.phase == .waitingForSchedule

        if isScheduledIdle {
            pendingOutage = nil
            if activeCodes.remove(.providerOffline) != nil {
                result.append(makeTransition(.providerOffline, .suppressed, at: now))
            }
        } else {
            result.append(contentsOf: evaluateProviderState(daemon, at: now))
        }

        result.append(contentsOf: evaluateLifecycle(daemon.lifecycle?.outcome, at: now))
        result.append(contentsOf: evaluateModelFailures(daemon.modelLoadFailures, at: now))
        return result
    }

    private func freshDaemon(from snapshot: TelemetrySnapshot, at now: Date) -> DaemonState? {
        guard case .available(let daemon, let sourceCapturedAt) = snapshot.state,
              sourceCapturedAt.timeIntervalSince1970.isFinite,
              daemon.writtenAt.isFinite else { return nil }
        let sourceAge = now.timeIntervalSince(sourceCapturedAt)
        let stateAge = now.timeIntervalSince1970 - daemon.writtenAt
        guard (0...policy.maximumSnapshotAge).contains(sourceAge),
              (0...policy.maximumSnapshotAge).contains(stateAge) else { return nil }
        return daemon
    }

    private mutating func evaluateProviderState(_ daemon: DaemonState, at now: Date) -> [AlertTransition] {
        guard let trust = daemon.trust?.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            pendingOutage = nil
            return []
        }

        if trust == "offline" {
            if let pendingOutage,
               now.timeIntervalSince(pendingOutage.lastObservedAt) <= policy.maximumEvidenceGap,
               now >= pendingOutage.lastObservedAt {
                var updated = pendingOutage
                if now > updated.lastObservedAt {
                    updated.observationCount = min(updated.observationCount + 1, 1_000_000)
                    updated.lastObservedAt = now
                }
                self.pendingOutage = updated
            } else {
                pendingOutage = PendingOutage(
                    firstObservedAt: now,
                    lastObservedAt: now,
                    observationCount: 1
                )
            }

            guard !activeCodes.contains(.providerOffline), let pendingOutage,
                  pendingOutage.observationCount >= 2,
                  now.timeIntervalSince(pendingOutage.firstObservedAt) >= policy.sustainedOutageDuration,
                  now.timeIntervalSince(firstSnapshotAt ?? now) >= policy.coldStartGraceDuration else {
                return []
            }
            activeCodes.insert(.providerOffline)
            self.pendingOutage = nil
            return [makeTransition(
                .providerOffline,
                .raised,
                at: now,
                duration: boundedDuration(now.timeIntervalSince(pendingOutage.firstObservedAt)),
                observations: pendingOutage.observationCount
            )]
        }

        pendingOutage = nil
        if trust == "online", activeCodes.remove(.providerOffline) != nil {
            return [makeTransition(.providerOffline, .recovered, at: now)]
        }
        return []
    }

    private mutating func evaluateLifecycle(
        _ outcome: ProviderLifecycleOutcome?,
        at now: Date
    ) -> [AlertTransition] {
        guard let outcome else { return [] }
        let failure: OperationalAlertCode?
        switch outcome {
        case .timedOut: failure = .lifecycleTimedOut
        case .forced: failure = .lifecycleForced
        case .serving, .draining, .drained, .stopped: failure = nil
        case .busy, .unknown: return []
        }

        var result: [AlertTransition] = []
        for code in activeCodes.filter(\.isLifecycleFailure).sorted(by: { $0.rawValue < $1.rawValue })
        where code != failure {
            activeCodes.remove(code)
            result.append(makeTransition(code, .recovered, at: now))
        }
        if let failure, activeCodes.insert(failure).inserted {
            result.append(makeTransition(failure, .raised, at: now))
        }
        return result
    }

    private mutating func evaluateModelFailures(
        _ failures: [ModelLoadFailure],
        at now: Date
    ) -> [AlertTransition] {
        let current = Set(failures.map { OperationalAlertCode(modelFailureCode: $0.code) })
        var result: [AlertTransition] = []
        for code in activeCodes.filter(\.isModelFailure).sorted(by: { $0.rawValue < $1.rawValue })
        where !current.contains(code) {
            activeCodes.remove(code)
            result.append(makeTransition(code, .recovered, at: now))
        }
        for code in current.sorted(by: { $0.rawValue < $1.rawValue })
        where activeCodes.insert(code).inserted {
            result.append(makeTransition(code, .raised, at: now))
        }
        return result
    }

    private func makeTransition(
        _ code: OperationalAlertCode,
        _ kind: AlertTransitionKind,
        at date: Date,
        duration: Int? = nil,
        observations: Int = 1
    ) -> AlertTransition {
        AlertTransition(
            code: code,
            kind: kind,
            occurredAt: date,
            observedDurationSeconds: duration,
            observationCount: observations
        )
    }

    private func boundedDuration(_ seconds: TimeInterval) -> Int {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        return Int(min(seconds.rounded(.down), 86_400))
    }
}
