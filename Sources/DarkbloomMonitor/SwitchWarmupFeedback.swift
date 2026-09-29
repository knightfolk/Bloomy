import SwiftUI

/// Compact popup feedback for the emergency post-switch inference check.
/// A result is deliberately phrased as history, not current residency.
struct SwitchWarmupFeedback: View {
    let status: SwitchWarmupStatus

    var body: some View {
        Label(message, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .help("This result is from one free test on an owned provider. It may be outdated after provider changes and does not guarantee public jobs.")
    }

    private var message: String {
        switch status {
        case .checking(let modelID): "Testing \(ModelDisplayName.short(modelID))…"
        case .result(let modelID, .sent, let at):
            "Last test · \(ModelDisplayName.short(modelID)) responded at \(at.formatted(date: .omitted, time: .shortened))"
        case .result(_, .missingKey, _): "Test skipped · add an API key in Chat"
        case .result(_, .modelUnavailable, _): "Test skipped · selected model unavailable"
        case .result(_, .keyRejected, _): "Test skipped · check your Chat API key"
        case .result(_, .failed, _): "Test failed · check provider status"
        }
    }

    private var icon: String {
        switch status {
        case .checking: "hourglass"
        case .result(_, .sent, _): "checkmark.circle"
        case .result: "exclamationmark.circle"
        }
    }
}
