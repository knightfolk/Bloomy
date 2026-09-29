import DarkbloomTelemetry
import SwiftUI

/// One obvious entry to cooling controls, with fresh sensor readings on its face.
struct PopupFanSummary: View {
    @ObservedObject var store: ProviderExtrasStore
    let now: Date
    let open: () -> Void

    private var status: ProviderFanStatus? {
        guard case .available(let value, let capturedAt) = store.snapshot?.fanStatus,
              (0...ProviderExtrasSnapshot.maximumSourceAge).contains(now.timeIntervalSince(capturedAt)) else { return nil }
        return value.helperIsFresh(at: now) ? value : value.withoutHelper()
    }

    private var state: String {
        guard let status else { return "Readings unavailable" }
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
                    }
                    .font(.caption).monospacedDigit()
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Fan helper and live cooling readings")
        .accessibilityIdentifier("popup.fans")
        .task {
            while !Task.isCancelled {
                await store.refreshFan()
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }
}
