import DarkbloomTelemetry
import SwiftUI

/// One obvious entry to cooling controls, with fresh sensor readings on its face.
struct PopupFanSummary: View {
    @ObservedObject var store: ProviderExtrasStore
    let now: Date
    var isVisible: Bool = true
    var ownsVisibleFanPolling: Bool = true
    var compact = false
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
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: "fan").font(.system(size: 16))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(status?.displayedTemperatureCelsius.map { String(format: "%.0f°C", $0) } ?? "Cooling —")
                            .font(.caption.weight(.medium))
                        Text(readingsAreFresh ? status?.displayedFans.compactMap(\.actualRPM).max().map { "\(Int($0)) RPM" } ?? state : state)
                            .font(.caption2).foregroundStyle(.secondary)
                    }.monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(readingsAreFresh ? Color.primary : .secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Cooling, \(state)")
                .accessibilityValue(compactReadings)
            } else {
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
        }
        .buttonStyle(.plain)
        .help("Fan helper and cooling readings · \(state)")
        .accessibilityIdentifier("popup.fans")
        .modifier(PopupKeyboardReveal())
        .task(id: isVisible && ownsVisibleFanPolling) {
            guard isVisible && ownsVisibleFanPolling else { return }
            await store.observeVisibleFan()
        }
    }

    private var compactReadings: String {
        let temperature = status?.displayedTemperatureCelsius.map { String(format: "%.0f degrees Celsius", $0) }
            ?? "Temperature unavailable"
        let speed = status?.displayedFans.compactMap(\.actualRPM).max().map { "Highest fan speed \(Int($0)) RPM" }
            ?? "Fan speed unavailable"
        return "\(readingsAreFresh ? "" : "Last readings, ")\(temperature), \(speed)"
    }
}
