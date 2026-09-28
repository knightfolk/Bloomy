import DarkbloomTelemetry
import SwiftUI

struct EventRow: View {
    let event: LogEvent

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            VStack(spacing: 3) {
                Image(systemName: Self.severitySymbol(for: event.severity))
                    .foregroundStyle(Self.severityColor(for: event.severity))
                Text(event.severity.rawValue.capitalized)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 65)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.category)
                    .font(.callout.weight(.semibold))
                    .monospaced()
                    .textSelection(.enabled)
                    .help(event.category)
                Text(TelemetryFormatting.timestamp(event.timestamp))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Text(event.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .help(event.message)

                Text(metadata)
                    .font(.callout)
                    .monospaced()
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .help(metadata)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(event.severity.rawValue.capitalized) event, \(TelemetryFormatting.timestamp(event.timestamp)), category \(event.category), \(event.message), \(metadata)"
        )
    }

    private var metadata: String {
        var values = [event.source.rawValue.capitalized]
        if let processImage {
            values.append(processImage)
        }
        if let processID = event.processID {
            values.append("PID \(processID)")
        }
        return values.joined(separator: " · ")
    }

    private var processImage: String? {
        guard let value = event.processImage, !value.isEmpty else { return nil }
        return value
    }

    static func severitySymbol(for severity: LogSeverity) -> String {
        switch severity {
        case .info: "info.circle.fill"
        case .notice: "bell.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    static func severityColor(for severity: LogSeverity) -> Color {
        switch severity {
        case .info: .blue
        case .notice: .secondary
        case .warning: .orange
        case .error: .red
        }
    }
}
