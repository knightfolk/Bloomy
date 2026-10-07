import Foundation

/// A bounded explanation of one observation, not a serving permission or a
/// recovery policy. All text is authored here; upstream prose and identifiers
/// never enter the presentation. No process, filesystem or network reads occur.
public struct ProviderReadinessPresentation: Equatable, Sendable {
    public enum State: String, Equatable, Sendable {
        case unavailable, stale, unconfirmed, scheduledWaiting, transitioning
        case stopped, interrupted, busy, offline, authorizationRequired
        case ready, serving, onDemand, modelsUnknown
    }

    public enum Tone: String, Equatable, Sendable { case neutral, positive, caution }
    public enum Destination: String, Equatable, Sendable { case health, hosting, models }
    public enum EvidenceKind: String, Equatable, Hashable, Sendable { case source, connection, authorization, models, work }

    public struct EvidenceRow: Equatable, Sendable, Identifiable {
        public let id: EvidenceKind
        public let title: String
        public let value: String
        public let detail: String
        public let tone: Tone
    }

    public let state: State
    public let title: String
    public let detail: String
    public let symbolName: String
    public let tone: Tone
    public let observedAt: Date
    public let evidence: [EvidenceRow]
    public let suggestedAction: Destination?

    /// Daemon observations update frequently. CLI status is normally polled
    /// every 30 seconds; two polling intervals is the maximum configuration age.
    /// Unlike verification's compatibility API, this presentation rejects all
    /// future timestamps, including small clock skew, and nonfinite dates.
    public static let daemonMaximumAge: TimeInterval = ProviderVerification.snapshotMaxAge
    public static let statusMaximumAge: TimeInterval = 60

    public static func make(
        snapshot: TelemetrySnapshot,
        now: Date,
        liveProcessIdentity: ProcessIdentity?
    ) -> Self {
        guard let daemon = snapshot.state.value else {
            return Self(
                state: .unavailable, title: "Provider observation unavailable",
                detail: "Waiting for daemon telemetry.", symbolName: "questionmark.circle",
                tone: .neutral, observedAt: snapshot.capturedAt,
                evidence: unavailableEvidence, suggestedAction: .health
            )
        }
        let sourceFresh = fresh(snapshot.capturedAt, now: now, maximumAge: daemonMaximumAge)
            && availableFresh(snapshot.state, now: now, maximumAge: daemonMaximumAge)
            && fresh(daemon.writtenAt, now: now, maximumAge: daemonMaximumAge)
        let statusFresh = availableFresh(snapshot.status, now: now, maximumAge: statusMaximumAge)
        let expectedCoordinator = statusFresh ? snapshot.status.value?.coordinator : nil
        let verification = ProviderVerification.evaluateObservedIdentity(
            state: daemon, expectedCoordinator: expectedCoordinator, now: now,
            liveProcessIdentity: liveProcessIdentity
        )
        let processFresh = sourceFresh && verification.processMatches
        let trustFresh: Bool
        if let trust = daemon.trust {
            trustFresh = fresh(trust.receivedAt, now: now, maximumAge: daemonMaximumAge)
        } else {
            trustFresh = false
        }
        let connectionCurrent = processFresh && statusFresh
            && verification.coordinatorMatches && trustFresh
            && verification.receivedAfterStarted
        let authorized = connectionCurrent && verification.isVerified
        let modelWarm = daemon.advertisedModels?.contains {
            !empty($0) && daemon.warmModels.contains($0)
        } == true
        let advertised = daemon.advertisedModels?.contains(where: { !empty($0) }) == true

        let rows = evidenceRows(
            daemon: daemon, sourceFresh: sourceFresh, statusFresh: statusFresh,
            processFresh: processFresh, connectionCurrent: connectionCurrent,
            verification: verification, authorized: authorized,
            modelWarm: modelWarm, advertised: advertised
        )
        func result(_ state: State, _ title: String, _ detail: String,
                    _ symbol: String, _ tone: Tone, _ action: Destination? = nil) -> Self {
            Self(state: state, title: title, detail: detail, symbolName: symbol,
                 tone: tone, observedAt: snapshot.capturedAt, evidence: rows, suggestedAction: action)
        }

        guard sourceFresh else {
            return result(.stale, "Provider observation needs refresh", "The daemon observation is missing a current, valid timestamp.", "clock.badge.questionmark", .caution, .health)
        }
        guard processFresh else {
            return result(.unconfirmed, "Provider process unconfirmed", "This observation cannot be matched to the current provider process.", "questionmark.circle", .caution, .health)
        }
        if daemon.trust != nil && !trustFresh {
            return result(.stale, "Connection observation needs refresh", "Coordinator trust is missing a current, valid timestamp.", "clock.badge.questionmark", .caution, .health)
        }
        if let lifecycle = daemon.lifecycle {
            switch lifecycle.outcome {
            case .stopped:
                return result(.stopped, "Provider stopped", "The provider reports that serving has stopped.", "stop.circle", .neutral, .hosting)
            case .drained:
                if daemon.availability?.phase != .waitingForSchedule {
                    return result(.stopped, "Provider stopped", "The provider reports that serving has stopped.", "stop.circle", .neutral, .hosting)
                }
            case .forced:
                return result(.interrupted, "Provider forced to stop", "Accepted work may have been interrupted.", "exclamationmark.circle", .caution, .health)
            case .timedOut:
                return result(.interrupted, "Drain deadline expired", "New work remains paused; accepted work may still be finishing.", "exclamationmark.circle", .caution, .health)
            case .busy:
                return result(.busy, "Provider control is busy", "Another lifecycle action is in progress; serving readiness is unconfirmed.", "hourglass", .neutral, .hosting)
            case .draining:
                return result(.transitioning, "Finishing accepted work", "New requests are paused while accepted work finishes.", "hourglass", .neutral)
            case .unknown:
                return result(.unconfirmed, "Provider phase unconfirmed", "The provider reports a lifecycle phase this monitor cannot interpret.", "questionmark.circle", .caution, .health)
            case .serving: break
            }
        }
        if daemon.availability?.phase == .waitingForSchedule {
            return result(.scheduledWaiting, "Waiting for scheduled window", "The provider is intentionally waiting for its next configured serving window.", "calendar.badge.clock", .neutral, .hosting)
        }
        if daemon.availability?.phase == .unknown {
            return result(.unconfirmed, "Provider availability unconfirmed", "The provider reports an availability phase this monitor cannot interpret.", "questionmark.circle", .caution, .health)
        }
        if let modelSwitch = daemon.modelSwitch {
            switch modelSwitch.outcome {
            case .validating:
                return result(.transitioning, "Validating model selection", "The provider is checking a requested model selection; validation does not confirm that serving is paused.", "arrow.triangle.2.circlepath", .neutral)
            case .draining, .switching:
                return result(.transitioning, "Applying model selection", "New work is paused while the provider changes its serving models.", "arrow.triangle.2.circlepath", .neutral)
            case .timedOut, .failed:
                return result(.interrupted, "Model change needs review", "The latest model change did not complete; current serving readiness is unconfirmed.", "exclamationmark.circle", .caution, .models)
            case .busy:
                return result(.busy, "Model change is busy", "Another model change is in progress; current serving readiness is unconfirmed.", "hourglass", .neutral, .models)
            case .unknown:
                return result(.unconfirmed, "Model change phase unconfirmed", "The provider reports a model change phase this monitor cannot interpret.", "questionmark.circle", .caution, .models)
            case .serving, .switched: break
            }
        }
        if daemon.startupPreloadPendingModels?.isEmpty == false {
            return result(.transitioning, "Preparing models", "Configured startup models are still pending; other warm models may continue serving.", "hourglass", .neutral)
        }
        guard statusFresh && verification.coordinatorMatches else {
            return result(.unconfirmed, "Connection unconfirmed", "A current CLI configuration and matching coordinator observation are required.", "questionmark.circle", .caution, .health)
        }
        if connectionCurrent && !verification.online {
            return result(.offline, "Provider connection offline", "The current coordinator observation does not report an online connection.", "network.slash", .caution, .hosting)
        }
        guard authorized else {
            return result(.authorizationRequired, "Authorization unconfirmed", "Current coordinator authorization has not been verified for this process.", "lock.circle", .caution, .health)
        }
        guard modelWarm else {
            if advertised {
                return result(.onDemand, "Models available on demand", "The provider advertises serving models; none is currently reported warm.", "square.stack.3d.up", .neutral, .models)
            }
            return result(.modelsUnknown, "Model readiness unconfirmed", "A current advertised serving model has not been reported.", "questionmark.circle", .neutral, .models)
        }
        if daemon.inferenceActive {
            return result(.serving, "Serving now", "A verified connection and warm serving model are present; inference is active.", "bolt.fill", .positive)
        }
        return result(.ready, "Ready · no active work", "A verified connection and warm serving model are present; waiting for requests.", "checkmark.circle", .positive)
    }

    private static func evidenceRows(
        daemon: DaemonState, sourceFresh: Bool, statusFresh: Bool, processFresh: Bool,
        connectionCurrent: Bool, verification: ProviderVerification, authorized: Bool,
        modelWarm: Bool, advertised: Bool
    ) -> [EvidenceRow] {
        func row(_ id: EvidenceKind, _ title: String, _ value: String, _ detail: String,
                 _ tone: Tone = .neutral) -> EvidenceRow {
            EvidenceRow(id: id, title: title, value: value, detail: detail, tone: tone)
        }
        let source = row(.source, "Observation", sourceFresh ? "Current" : "Unavailable or stale",
                         sourceFresh ? (statusFresh ? "Daemon and CLI configuration are current." : "Daemon is current; CLI configuration needs refresh.") : "Current daemon capture and write timestamps are required.", sourceFresh ? .neutral : .caution)
        let connection: EvidenceRow
        if !processFresh {
            connection = row(.connection, "Connection", "Unconfirmed", "A current observation matched to a live provider process is required.", .caution)
        } else if !connectionCurrent {
            connection = row(.connection, "Connection", "Unconfirmed", "A matching coordinator and current trust observation are required.", .caution)
        } else {
            connection = row(.connection, "Connection", verification.online ? "Online" : "Offline",
                             "Current coordinator trust is matched to this provider process.", verification.online ? .positive : .caution)
        }
        let authorization: EvidenceRow
        if authorized {
            authorization = row(.authorization, "Authorization", verification.state == .legacy ? "Legacy verified" : "Verified",
                                "Current coordinator authorization is present for this process; provider controls may still pause serving.", .positive)
        } else if connectionCurrent && verification.state == .expired {
            authorization = row(.authorization, "Authorization", "Expired or missing lease", "The current authorization lease is missing or expired.", .caution)
        } else {
            authorization = row(.authorization, "Authorization", "Unconfirmed", "Online status alone does not establish serving authorization.", .caution)
        }
        let models: EvidenceRow
        if !processFresh {
            models = row(.models, "Models", "Unknown", "Current model residency and advertisement cannot be confirmed.")
        } else if modelWarm {
            models = row(.models, "Models", "Warm advertised model", "At least one advertised model is currently reported warm; residency alone does not establish active serving.", .positive)
        } else if advertised {
            models = row(.models, "Models", "On demand", "Advertised models are reported; none is currently warm.")
        } else {
            models = row(.models, "Models", "Unknown", "No current advertised serving model is reported.")
        }
        let work: EvidenceRow
        if !processFresh {
            work = row(.work, "Observed work", "Unknown", "A current observation matched to a live process is required.")
        } else if let lifecycle = daemon.lifecycle, lifecycle.outcome == .draining || lifecycle.outcome == .timedOut {
            let value = lifecycle.remainingRequests.map { "\($0) accepted remaining" } ?? "Finishing accepted work"
            work = row(.work, "Observed work", value, "New requests are paused; this observation does not predict completion time.")
        } else if let lifecycle = daemon.lifecycle,
                  lifecycle.outcome == .stopped || lifecycle.outcome == .forced
                    || (lifecycle.outcome == .drained && daemon.availability?.phase != .waitingForSchedule) {
            work = row(.work, "Observed work", "Stopped", "The provider reports that serving has stopped.")
        } else if let modelSwitch = daemon.modelSwitch, modelSwitch.outcome == .draining {
            let value = modelSwitch.remainingRequests.map { "\($0) accepted remaining" } ?? "Finishing accepted work"
            work = row(.work, "Observed work", value, "New requests are paused during the model change; completion time is not reported.")
        } else if daemon.inferenceActive {
            work = row(.work, "Observed work", "Inference active", "At least one request is active; exact live count and progress are not reported.")
        } else if daemon.availability?.phase == .waitingForSchedule {
            work = row(.work, "Observed work", "Scheduled idle", "The provider is intentionally waiting outside its configured serving window; no active inference is reported.")
        } else {
            work = row(.work, "Observed work", "No active inference", "Queued requests and future demand are not reported.")
        }
        return [source, connection, authorization, models, work]
    }

    private static var unavailableEvidence: [EvidenceRow] {
        [
            EvidenceRow(id: .source, title: "Observation", value: "Unavailable or stale", detail: "Current daemon capture and write timestamps are required.", tone: .caution),
            EvidenceRow(id: .connection, title: "Connection", value: "Unconfirmed", detail: "A current observation matched to a live provider process is required.", tone: .caution),
            EvidenceRow(id: .authorization, title: "Authorization", value: "Unconfirmed", detail: "Online status alone does not establish serving authorization.", tone: .caution),
            EvidenceRow(id: .models, title: "Models", value: "Unknown", detail: "Current model residency and advertisement cannot be confirmed.", tone: .neutral),
            EvidenceRow(id: .work, title: "Observed work", value: "Unknown", detail: "A current observation matched to a live process is required.", tone: .neutral),
        ]
    }

    private static func empty(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func fresh(_ date: Date, now: Date, maximumAge: TimeInterval) -> Bool {
        fresh(date.timeIntervalSince1970, now: now, maximumAge: maximumAge)
    }

    private static func fresh(_ timestamp: TimeInterval, now: Date, maximumAge: TimeInterval) -> Bool {
        let current = now.timeIntervalSince1970
        guard timestamp.isFinite, current.isFinite else { return false }
        let age = current - timestamp
        return age >= 0 && age <= maximumAge
    }

    private static func availableFresh<Value: Equatable & Sendable>(
        _ source: SourceAvailability<Value>, now: Date, maximumAge: TimeInterval
    ) -> Bool {
        guard case .available(_, let capturedAt) = source else { return false }
        return fresh(capturedAt, now: now, maximumAge: maximumAge)
    }
}
