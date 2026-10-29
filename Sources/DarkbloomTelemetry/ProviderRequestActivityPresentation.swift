import Foundation

public enum ProviderRequestActivityMode: Equatable, Sendable {
    case idle
    case active
    case draining
    case stopped
    case unavailable
}

/// Honest request-count copy for the provider panel. The serving daemon only
/// reports a Boolean inference signal, so an active value is a lower bound;
/// the native drain lifecycle reports an exact remaining count.
public struct ProviderRequestActivityPresentation: Equatable, Sendable {
    public let mode: ProviderRequestActivityMode
    public let value: String
    public let status: String
    public let detail: String

    public static func make(daemonState: DaemonState?) -> Self {
        guard let daemonState else {
            return Self(
                mode: .unavailable,
                value: "—",
                status: "Unavailable",
                detail: "Provider request activity is not available."
            )
        }

        if let lifecycle = daemonState.lifecycle {
            switch lifecycle.outcome {
            case .busy:
                return Self(
                    mode: .draining,
                    value: lifecycle.remainingRequests.map(String.init) ?? "—",
                    status: "Busy",
                    detail: "Another lifecycle action is in progress; new work may remain paused."
                )
            case .forced:
                return Self(
                    mode: .stopped,
                    value: daemonState.inferenceActive || daemonState.requestWorkPending == true ? "—" : "0",
                    status: "Forced stop",
                    detail: "The provider reported a forced stop; accepted work may have been interrupted."
                )
            case .timedOut:
                return Self(
                    mode: .draining,
                    value: lifecycle.remainingRequests.map(String.init) ?? "—",
                    status: "Timed out",
                    detail: "The drain deadline expired; new work remains paused until lifecycle control is reconciled."
                )
            default:
                break
            }
        }

        if let modelSwitch = daemonState.modelSwitch,
           [.validating, .draining, .switching].contains(modelSwitch.outcome) {
            return Self(
                mode: .draining,
                value: modelSwitch.remainingRequests.map(String.init) ?? "—",
                status: modelSwitch.outcome == .validating ? "Validating" : "Switching",
                detail: modelSwitch.outcome == .validating
                    ? "The provider is validating a model selection; this does not establish that new work is paused."
                    : "The provider is applying a live model selection; new work is paused during the switch."
            )
        }

        if daemonState.startupPreloadPendingModels?.isEmpty == false {
            return Self(
                mode: daemonState.requestWorkPending == true || daemonState.inferenceActive ? .active : .idle,
                value: daemonState.requestWorkPending == true || daemonState.inferenceActive ? "1+" : "—",
                status: "Preloading",
                detail: "Configured startup models are still loading; other warm models may continue serving."
            )
        }

        if daemonState.availability?.phase == .waitingForSchedule {
            if daemonState.inferenceActive || daemonState.requestWorkPending == true {
                return Self(mode: .active, value: "1+", status: "Work pending",
                            detail: "Work is reported while the provider is waiting for its scheduled window.")
            }
            return Self(
                mode: .stopped,
                value: "0",
                status: "Scheduled idle",
                detail: "The provider is healthy and waiting for its next configured serving window."
            )
        }

        if let lifecycle = daemonState.lifecycle, lifecycle.outcome == .draining {
            guard let remaining = lifecycle.remainingRequests else {
                return Self(
                    mode: .draining,
                    value: "—",
                    status: "Draining",
                    detail: "New requests are paused; waiting for a remaining-request count."
                )
            }
            if remaining == 0, lifecycle.coordinatorAcknowledged == false {
                return Self(
                    mode: .draining,
                    value: "0",
                    status: "Finishing",
                    detail: "Requests have finished; confirming usage before shutdown."
                )
            }
            return Self(
                mode: .draining,
                value: String(remaining),
                status: "Draining",
                detail: "Accepted requests remaining; new requests are paused."
            )
        }

        if let lifecycle = daemonState.lifecycle,
           lifecycle.outcome == .drained || lifecycle.outcome == .stopped {
            if daemonState.inferenceActive || daemonState.requestWorkPending == true {
                return Self(mode: .unavailable, value: "—", status: "Unconfirmed",
                            detail: "Provider stop and work observations conflict; refresh to check the current state.")
            }
            return Self(
                mode: .stopped,
                value: "0",
                status: "Stopped",
                detail: "No provider requests are running."
            )
        }

        if daemonState.inferenceActive {
            return Self(
                mode: .active,
                value: "1+",
                status: "Active",
                detail: "At least one request is active; an exact live count is not reported while serving."
            )
        }

        if daemonState.requestWorkPending == true {
            return Self(mode: .active, value: "1+", status: "Work pending",
                        detail: "Accepted or queued work is reported; the exact count is unavailable.")
        }
        if daemonState.loadTransitionActive == true {
            return Self(mode: .idle, value: "—", status: "Loading",
                        detail: "A model load is in progress; the exact request count is unavailable.")
        }
        return Self(
            mode: .idle,
            value: "0",
            status: "Idle",
            detail: daemonState.requestWorkPending == false
                ? "No active inference or accepted or queued work is reported."
                : "No inference is currently active; queued requests are not reported."
        )
    }
}
