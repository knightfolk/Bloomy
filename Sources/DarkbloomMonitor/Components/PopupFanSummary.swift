import DarkbloomTelemetry
import SwiftUI

/// One obvious entry to cooling controls, with fresh sensor readings on its face.
struct PopupFanSummary: View {
    @ObservedObject var store: ProviderExtrasStore
    let now: Date
    var isVisible: Bool = true
    var ownsVisibleFanPolling: Bool = true
    let open: () -> Void

    private var status: ProviderFanStatus? {
        switch store.snapshot?.fanStatus {
        case .available(let value, _), .stale(let value, _, _):
            return readingsAreFresh && !value.helperIsFresh(at: Date()) ? value.withoutHelper() : value
        case .unavailable, nil:
            return nil
        }
    }

    private var readingsAreFresh: Bool {
        guard case .available(_, let capturedAt) = store.snapshot?.fanStatus else { return false }
        // This child observes the fan store independently of its parent's
        // timeline; a new reading can be newer than the supplied tick date.
        return (0...ProviderExtrasSnapshot.maximumSourceAge).contains(Date().timeIntervalSince(capturedAt))
    }

    private var state: String {
        guard let status else { return "Readings unavailable" }
        guard readingsAreFresh else { return "Last readings · stale" }
        if status.helperErrorPresent || status.diagnosticErrorPresent || status.helper?.mode == "error" { return "Needs attention" }
        guard let enabled = ProviderFanControlSettingsView.toggleState(status) else { return "Check helper" }
        return enabled ? "Helper on" : "Helper off"
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 10) {
                Image(systemName: "fan")
                    .font(.system(size: 22)).foregroundStyle(.secondary)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text("Cooling").font(.subheadline.weight(.semibold))
                        Spacer(minLength: 4)
                        Text(state).font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 12) {
                        if let temperature = status?.displayedTemperatureCelsius {
                            Label(String(format: "%.0f°C", temperature), systemImage: "thermometer.medium")
                        }
                        if let fans = status?.displayedFans,
                           let maximum = fans.compactMap(\.actualRPM).max() {
                            Text("\(fans.count) \(fans.count == 1 ? "fan" : "fans") · \(Int(maximum)) RPM max")
                                .help(fans.compactMap { fan in
                                    fan.actualRPM.map { "Fan \(fan.index + 1): \(Int($0)) RPM" }
                                }.joined(separator: " · "))
                                .accessibilityLabel("\(fans.count) fans, highest speed \(Int(maximum)) RPM")
                        }
                        if status?.displayedTemperatureCelsius == nil &&
                            status?.displayedFans.compactMap(\.actualRPM).max() == nil {
                            Text("Waiting for readings").foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption).monospacedDigit()
                    .frame(minHeight: 15, alignment: .leading)
                    .foregroundStyle(readingsAreFresh ? .primary : .secondary)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Fan helper and cooling readings")
        .accessibilityIdentifier("popup.fans")
        .task(id: isVisible && ownsVisibleFanPolling) {
            guard isVisible && ownsVisibleFanPolling else { return }
            await store.observeVisibleFan()
        }
    }
}
