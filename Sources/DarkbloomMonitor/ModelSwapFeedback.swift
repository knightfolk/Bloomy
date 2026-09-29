import SwiftUI

/// Confirm residency independently even after a local request completes.
struct ModelSwapFeedback: View {
    let status: ModelSwapStatus
    var openHosting: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(message, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("popover.swap.status")
            if case .failed(_, .endpointUnavailable, _) = status {
                Button("Open Hosting", action: openHosting)
                    .font(.caption)
                    .accessibilityIdentifier("popover.swap.hosting")
            }
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
            "Swap could not verify the provider’s local API. Open Hosting to check that unified mode is running on this Mac (127.0.0.1), then refresh."
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
