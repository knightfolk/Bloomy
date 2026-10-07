import DarkbloomTelemetry
import SwiftUI

struct ActionTimelineInspector: View {
    let bucket: ActionTimelineData.Bucket
    let inspect: (Date) -> Void

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 4) {
            Text("Recorded actions · \(bucket.start.formatted(date: .abbreviated, time: .standard)) – \(bucket.end.formatted(date: .abbreviated, time: .standard))")
                .font(.caption.weight(.medium))
                .accessibilityIdentifier("activity.metrics.inspection.actions")
            Text("Grouping interval; exact recorded times below. Actions do not establish work or payment.")
                .font(.caption2).foregroundStyle(.secondary)
            ForEach(bucket.events) { event in
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: symbol(event.outcome)).foregroundStyle(color(event.outcome))
                        .frame(width: 14).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ActionHistoryPresentation.actionLabel(event)).fontWeight(.medium)
                            Spacer(minLength: 6)
                            Text(event.occurredAt.formatted(date: .abbreviated, time: .standard)).monospacedDigit()
                        }
                        Text(details(event)).font(.caption2).foregroundStyle(.secondary)
                            .help(event.model ?? "Global action")
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(ActionHistoryPresentation.actionLabel(event)), \(event.occurredAt.formatted(date: .abbreviated, time: .standard)); \(details(event)); \(event.model ?? "Global action")")
                    .accessibilityIdentifier("activity.metrics.inspection.action.\(event.id.uuidString)")
                    Button { inspect(event.occurredAt) } label: { Image(systemName: "scope") }
                        .buttonStyle(.borderless)
                        .help("Inspect this recorded action time")
                        .accessibilityLabel("Inspect \(ActionHistoryPresentation.actionLabel(event)) at \(event.occurredAt.formatted(date: .abbreviated, time: .standard)); \(event.model ?? "Global action")")
                        .accessibilityIdentifier("activity.metrics.inspection.action.inspect.\(event.id.uuidString)")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
            }
        }
        .font(.caption)
    }

    private func details(_ event: ActionHistoryEvent) -> String {
        var parts = [ActionHistoryPresentation.titleCase(event.trigger.rawValue),
                     ActionHistoryPresentation.titleCase(event.outcome.rawValue),
                     event.model.map(ModelDisplayName.short) ?? "Global"]
        if let reason = event.reason, reason != .none, reason != .completed {
            parts.append(ActionHistoryPresentation.titleCase(reason.rawValue))
        }
        return parts.joined(separator: " · ")
    }

    private func symbol(_ outcome: ActionHistoryOutcome) -> String {
        switch outcome {
        case .succeeded: "checkmark.circle.fill"
        case .failed: "xmark.circle.fill"
        case .started: "clock"
        case .skipped: "arrow.uturn.forward.circle"
        case .cancelled, .interrupted: "stop.circle"
        case .unconfirmed: "questionmark.circle"
        }
    }
    private func color(_ outcome: ActionHistoryOutcome) -> Color {
        switch outcome {
        case .succeeded: .green
        case .failed: .red
        case .started, .unconfirmed: .orange
        case .skipped, .cancelled, .interrupted: .secondary
        }
    }
}
