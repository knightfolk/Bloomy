import DarkbloomTelemetry
import SwiftUI

/// The compact summary and detailed rows render the same immutable evidence.
/// This view owns neither acquisition nor provider commands.
struct ProviderReadinessSummaryView: View {
    let presentation: ProviderReadinessPresentation
    var showsEvidence = false
    var openDestination: ((ProviderReadinessPresentation.Destination) -> Void)?

    var body: some View {
        let observation = observationDescription
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: presentation.symbolName)
                    .font(.title2)
                    .foregroundStyle(color(presentation.tone))
                    .frame(width: 28, height: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(presentation.title).font(.headline)
                    Text(presentation.detail)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Readiness: \(presentation.title). \(presentation.detail)")
                .accessibilityIdentifier("readiness.summary")
                if let openDestination, let destination = buttonDestination {
                    Button { openDestination(destination) } label: {
                        Label(buttonTitle(destination), systemImage: "arrow.up.right")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("readiness.openDetails")
                    .help("Open \(destination == .health ? "Health & Logs" : buttonTitle(destination)) for the supporting readings and controls.")
                }
            }
            if showsEvidence {
                Divider()
                VStack(spacing: 0) {
                    ForEach(presentation.evidence, id: \.id) { row in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(row.title).font(.callout.weight(.medium))
                                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Text(row.value).font(.callout.weight(.medium))
                                .foregroundStyle(color(row.tone))
                                .multilineTextAlignment(.trailing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 8)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(row.title): \(row.value). \(row.detail)")
                        .accessibilityIdentifier("readiness.evidence.\(row.id.rawValue)")
                    }
                }
                .accessibilityElement(children: .contain)
                Text(observation).font(.caption).foregroundStyle(.secondary)
                Text("Readiness describes observed provider state. It does not establish this Mac's earnings or guarantee new work.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(showsEvidence ? "health.readiness" : "overview.readiness")
        .help(observation)
    }

    private var buttonDestination: ProviderReadinessPresentation.Destination? {
        if showsEvidence { return presentation.suggestedAction == .health ? nil : presentation.suggestedAction }
        return presentation.suggestedAction ?? .health
    }

    private var observationDescription: String {
        guard presentation.observedAt.timeIntervalSince1970.isFinite else { return "Observation time unavailable." }
        return "Captured \(TelemetryFormatting.timestamp(presentation.observedAt)). Check evidence freshness before acting."
    }

    private func buttonTitle(_ destination: ProviderReadinessPresentation.Destination) -> String {
        switch destination {
        case .health: "Details"
        case .hosting: "Hosting"
        case .models: "Models"
        }
    }

    private func color(_ tone: ProviderReadinessPresentation.Tone) -> Color {
        switch tone {
        case .neutral: .secondary
        case .positive: .green
        case .caution: .orange
        }
    }
}
