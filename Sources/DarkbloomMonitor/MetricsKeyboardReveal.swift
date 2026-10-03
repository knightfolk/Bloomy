import SwiftUI

enum MetricsFocusTarget: Hashable, Sendable {
    case period, model, refresh, visitFilter, moreVisits, recordingDetails
}

private struct MetricsFocusRevealKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (MetricsFocusTarget) -> Void)? = nil
}

extension EnvironmentValues {
    var metricsFocusReveal: (@MainActor @Sendable (MetricsFocusTarget) -> Void)? {
        get { self[MetricsFocusRevealKey.self] }
        set { self[MetricsFocusRevealKey.self] = newValue }
    }
}

/// Preserve each native control's key behavior; reveal it only within Metrics.
struct MetricsKeyboardReveal: ViewModifier {
    let target: MetricsFocusTarget
    @Environment(\.metricsFocusReveal) private var reveal
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if let reveal {
            content.id(target).focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused { reveal(target) }
                }
        } else {
            content
        }
    }
}
