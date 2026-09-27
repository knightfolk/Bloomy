import Foundation

/// Closed, non-sensitive presentation of the provider's current operational
/// phase. Provider messages and request identifiers are intentionally excluded.
public struct ProviderRuntimePresentation: Equatable, Sendable {
    public let title: String
    public let detail: String

    public static func make(_ state: DaemonState) -> Self {
        switch state.lifecycle?.outcome {
        case .busy:
            return Self(
                title: "Lifecycle busy",
                detail: remainingDetail(state.lifecycle?.remainingRequests, suffix: "accepted requests remain; retry after the current lifecycle action finishes.")
            )
        case .forced:
            return Self(
                title: "Forced stop",
                detail: "The provider reported a forced lifecycle completion. Accepted work may have been interrupted."
            )
        case .timedOut:
            return Self(
                title: "Drain timed out",
                detail: remainingDetail(state.lifecycle?.remainingRequests, suffix: "accepted requests remain and new work stays paused.")
            )
        default:
            break
        }

        if let modelSwitch = state.modelSwitch {
            switch modelSwitch.outcome {
            case .validating, .draining, .switching:
                let models = modelSwitch.models.isEmpty ? "the saved selection" : modelSwitch.models.joined(separator: ", ")
                return Self(title: "Switching models", detail: "Applying \(models) without restarting the provider.")
            case .busy:
                return Self(title: "Model switch busy", detail: "Another provider lifecycle action is in progress.")
            case .timedOut:
                return Self(title: "Model switch timed out", detail: "New work remains paused until the switch is reconciled.")
            case .failed:
                return Self(title: "Model switch failed", detail: "The provider did not apply the requested live selection.")
            case .serving, .switched, .unknown:
                break
            }
        }

        if state.lifecycle?.outcome == .draining {
            return Self(
                title: "Draining",
                detail: remainingDetail(state.lifecycle?.remainingRequests, suffix: "accepted requests remain; new work is paused.")
            )
        }

        if let pending = state.startupPreloadPendingModels, !pending.isEmpty {
            return Self(
                title: "Preloading",
                detail: "Preparing \(pending.joined(separator: ", ")) before normal serving begins."
            )
        }

        if state.availability?.phase == .waitingForSchedule {
            let nextWindow = state.availability?.nextWindowAt.map {
                Date(timeIntervalSince1970: $0).formatted(date: .abbreviated, time: .shortened)
            }
            return Self(
                title: "Waiting for schedule",
                detail: nextWindow.map { "The provider is healthy and waiting for its next configured serving window at \($0)." }
                    ?? "The provider is healthy and waiting for its next configured serving window."
            )
        }

        if state.lifecycle?.outcome == .drained || state.lifecycle?.outcome == .stopped {
            return Self(title: "Stopped", detail: "No provider requests are running.")
        }

        let onDemand = Set(state.advertisedModels ?? []).subtracting(state.warmModels)
        if !onDemand.isEmpty {
            return Self(
                title: "Serving · on demand",
                detail: "Some advertised models will load when requested."
            )
        }
        return Self(title: "Serving", detail: "The provider is available for requests.")
    }

    private static func remainingDetail(_ remaining: Int?, suffix: String) -> String {
        guard let remaining else { return suffix.prefix(1).uppercased() + suffix.dropFirst() }
        return "\(remaining) \(suffix)"
    }
}

public struct ProviderModelRuntimePresentation: Equatable, Sendable {
    public let status: String
    public let detail: String

    public static func make(modelID: String, state: DaemonState) -> Self {
        if let modelSwitch = state.modelSwitch,
           [.validating, .draining, .switching].contains(modelSwitch.outcome),
           modelSwitch.models.contains(modelID) {
            return Self(status: "Switching", detail: "This model is part of the live selection being applied.")
        }
        if state.startupPreloadPendingModels?.contains(modelID) == true {
            return Self(status: "Preloading", detail: "This configured startup model is still loading.")
        }
        if state.inferenceActive, state.currentModel == modelID {
            return Self(status: "Active", detail: "This model is serving a request.")
        }
        if state.warmModels.contains(modelID) || state.slots.contains(where: { $0.model == modelID }) {
            return Self(status: "Loaded", detail: "This model is resident and ready.")
        }
        if state.advertisedModels?.contains(modelID) == true {
            return Self(status: "On demand", detail: "This advertised model will load when requested.")
        }
        return Self(status: "Not loaded", detail: "The provider does not report this model as resident.")
    }
}
