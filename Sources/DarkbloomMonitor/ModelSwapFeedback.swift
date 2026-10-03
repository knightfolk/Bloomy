import SwiftUI

/// Confirm residency independently even after a local request completes.
struct ModelSwapFeedback: View {
    let status: ModelSwapStatus
    var nudgeStatus: SwitchWarmupStatus? = nil
    var openHosting: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("popover.swap.status")
            if let nudgeStatus {
                Label(nudgeMessage(nudgeStatus), systemImage: "network")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("popover.swap.nudgeStatus")
            }
            if case .failed(_, .endpointUnavailable, _) = status {
                Button("Open Hosting", action: openHosting)
                    .font(.caption)
                    .accessibilityIdentifier("popover.swap.hosting")
                    .modifier(PopupKeyboardReveal())
            }
        }
    }

    private func nudgeMessage(_ status: SwitchWarmupStatus) -> String {
        switch status {
        case .checking: "Sending network nudge…"
        case .result(_, .sent, _): "Network nudge responded. Public work is not guaranteed."
        case .result(_, .missingKey, _): "Network nudge skipped · open Nudge to set up your key."
        case .result(_, .modelUnavailable, _): "Network nudge skipped · the exact model was unavailable."
        case .result(_, .keyRejected, _): "Network nudge skipped · check your key in Nudge."
        case .result(_, .failed, _): "Network nudge skipped or failed · the local swap was confirmed."
        }
    }

    private var message: String {
        switch status {
        case .checking(let modelID):
            "Requesting \(ModelDisplayName.short(modelID)) · checking this Mac…"
        case .confirmed(let modelID, let at):
            "\(ModelDisplayName.short(modelID)) loaded on this Mac at \(at.formatted(date: .omitted, time: .shortened)). All advertised models kept."
        case .unconfirmed(let modelID, _):
            "Request sent · \(ModelDisplayName.short(modelID)) was not confirmed loaded on this Mac. All advertised models kept."
        case .failed(_, .endpointUnavailable, _):
            "Swap could not verify the provider’s local API. Open Hosting to check that Fleet + local API is running on this Mac (127.0.0.1), then refresh."
        case .failed(_, .modelUnavailable, _):
            "Swap unavailable · the local API did not offer this exact model. All advertised models kept."
        case .failed(_, _, _):
            "Swap could not be confirmed. Refresh model controls before trying again."
        }
    }

    private var icon: String {
        switch status {
        case .checking: "hourglass"
        case .confirmed: "checkmark.circle"
        case .unconfirmed, .failed: "exclamationmark.circle"
        }
    }
}
