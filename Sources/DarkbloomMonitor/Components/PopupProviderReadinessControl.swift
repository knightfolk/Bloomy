import DarkbloomTelemetry
import SwiftUI

/// Shares the dashboard's verified observation; running alone is not online.
struct PopupProviderReadinessControl: View {
    let presentation: ProviderReadinessPresentation
    let machineName: String
    let openDestination: (ProviderReadinessPresentation.Destination) -> Void

    var title: String {
        switch presentation.state {
        case .unavailable: "Unavailable"
        case .stale: "Needs refresh"
        case .unconfirmed: "Unconfirmed"
        case .scheduledWaiting: "Scheduled"
        case .transitioning: "Transitioning"
        case .stopped: "Stopped"
        case .interrupted: "Interrupted"
        case .busy: "Busy"
        case .offline: "Offline"
        case .authorizationRequired: "Check access"
        case .ready: "Ready"
        case .serving: "Serving"
        case .onDemand: "On demand"
        case .modelsUnknown: "Models unknown"
        }
    }

    private var color: Color {
        switch presentation.tone {
        case .neutral: .secondary
        case .positive: .green
        case .caution: .orange
        }
    }

    var body: some View {
        Button { openDestination(presentation.suggestedAction ?? .health) } label: {
            HStack(spacing: 5) {
                DarkbloomLogo(image: DarkbloomLogoAsset.sourceImage, tint: color)
                    .frame(width: 18, height: 20)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(color)
                    .fixedSize(horizontal: true, vertical: false)
            }
        }
        .buttonStyle(.plain)
        .help("\(machineName) · \(presentation.title). \(presentation.detail)")
        .accessibilityLabel("Provider readiness: \(presentation.title). \(presentation.detail) Open details.")
        .accessibilityIdentifier("popup.readiness.details")
        .modifier(PopupKeyboardReveal())
    }
}
