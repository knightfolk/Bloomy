import DarkbloomTelemetry
import SwiftUI

/// Compact cooling keeps control posture separate from measured fan rotation.
@MainActor
struct PopupCoolingPresentation {
    enum State: Equatable {
        case on, off, attention, checkHelper, retained, unverified, unavailable

        var title: String {
            switch self {
            case .on: "Helper on"
            case .off: "Helper off"
            case .attention: "Needs attention"
            case .checkHelper: "Check helper"
            case .retained: "Last readings · stale"
            case .unverified: "Readings unverified"
            case .unavailable: "Readings unavailable"
            }
        }
    }

    let thermal: ProviderThermalPresentation?
    let state: State
    var readingsAreFresh: Bool { thermal?.cliFreshness == .current }
    var maximumFan: ProviderThermalPresentation.FanReading? { thermal?.displayedFans.max { $0.actualRPM < $1.actualRPM } }

    init(source: SourceAvailability<ProviderFanStatus>?, at now: Date) {
        let thermal = ProviderThermalPresentation.make(from: source, at: now)
        self.thermal = thermal
        guard let thermal else { state = .unavailable; return }
        guard thermal.cliFreshness == .current else {
            state = thermal.cliFreshness == .invalid ? .unverified : .retained
            return
        }
        let status = thermal.status
        if status.helperErrorPresent || status.diagnosticErrorPresent
            || (thermal.helperFreshness == .current && status.loaded && status.helper?.mode == "error") {
            state = .attention
        } else if let enabled = ProviderFanControlSettingsView.toggleState(status, at: now) {
            state = enabled ? .on : .off
        } else {
            state = .checkHelper
        }
    }

    var temperatureLabel: String {
        guard let thermal, let value = thermal.displayedTemperatureCelsius else { return "Cooling —" }
        let prefix = thermal.temperatureFreshness == .current ? "" : thermal.temperatureFreshness == .invalid ? "Unverified " : "Last "
        return prefix + String(format: "%.0f°C", value)
    }

    var compactDetail: String {
        // A measured RPM never proves that the optional helper is enabled or healthy.
        guard state == .on else {
            return state == .unavailable ? "Unavailable" : state == .retained ? "Last readings" : state == .unverified ? "Unverified" : state.title
        }
        guard let fan = maximumFan else { return state.title }
        return "\(fan.freshness == .current ? "" : "Last ")\(Int(fan.actualRPM)) RPM"
    }

    var help: String {
        let detail = state == .attention || state == .checkHelper
            ? "Open Cooling to check status and refresh." : thermal?.helperPosture.message ?? ""
        return "Fan helper and cooling readings · \(state.title). \(detail)"
    }

    var accessibilityReadings: String {
        let temperature: String
        if let thermal, let value = thermal.displayedTemperatureCelsius {
            let qualifier = thermal.temperatureFreshness.readingQualifier.map { $0 + " " } ?? ""
            temperature = qualifier + String(format: "%.0f degrees Celsius", value)
        } else { temperature = "Temperature unavailable" }
        let fan = maximumFan.map {
            "\($0.freshness.readingQualifier.map { $0 + " " } ?? "")highest fan speed \(Int($0.actualRPM)) RPM"
        } ?? "Fan speed unavailable"
        return "\(temperature), \(fan)"
    }
}

/// One obvious entry to cooling controls, with fresh sensor readings on its face.
struct PopupFanSummary: View {
    @ObservedObject var store: ProviderExtrasStore
    let now: Date
    var isVisible: Bool = true
    var ownsVisibleFanPolling: Bool = true
    var compact = false
    let open: () -> Void

    var body: some View {
        // Child observations may arrive between parent ticks. Evaluate once at render time.
        let presentation = PopupCoolingPresentation(source: store.snapshot?.fanStatus, at: Date())
        return Button(action: open) {
            if compact {
                HStack(spacing: 6) {
                    Image(systemName: presentation.state == .attention ? "exclamationmark.triangle.fill" : "fan")
                        .font(.system(size: 16))
                        .foregroundStyle(presentation.state == .attention ? Color.orange : .secondary)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.temperatureLabel)
                            .font(.caption.weight(.medium))
                        Text(presentation.compactDetail)
                            .font(.caption2)
                            .foregroundStyle(presentation.state == .attention ? Color.orange : .secondary)
                    }.monospacedDigit()
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
                }
                .foregroundStyle(presentation.readingsAreFresh ? Color.primary : .secondary)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Cooling, \(presentation.state.title)")
                .accessibilityValue(presentation.accessibilityReadings)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "fan")
                        .font(.system(size: 22)).foregroundStyle(.secondary)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Cooling").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 4)
                            Text(presentation.state.title).font(.caption2).foregroundStyle(.secondary)
                        }
                        HStack(spacing: 12) {
                            if presentation.thermal?.displayedTemperatureCelsius != nil {
                                Label(presentation.temperatureLabel, systemImage: "thermometer.medium")
                            }
                            if let fans = presentation.thermal?.displayedFans, let maximum = presentation.maximumFan {
                                Text("\(fans.count) \(fans.count == 1 ? "fan" : "fans") · \(maximum.freshness == .current ? "" : "Last ")\(Int(maximum.actualRPM)) RPM max")
                                    .help(fans.map { fan in
                                        "\(fan.freshness.readingQualifier.map { $0 + " " } ?? "")Fan \(fan.index + 1): \(Int(fan.actualRPM)) RPM"
                                    }.joined(separator: " · "))
                                    .accessibilityLabel(presentation.accessibilityReadings)
                            }
                            if presentation.thermal?.hasReadings != true {
                                Text("Waiting for readings").foregroundStyle(.secondary)
                            }
                        }
                        .font(.caption).monospacedDigit()
                        .frame(minHeight: 15, alignment: .leading)
                        .foregroundStyle(presentation.readingsAreFresh ? .primary : .secondary)
                    }
                    Image(systemName: "chevron.right").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
        .buttonStyle(.plain)
        .help(presentation.help)
        .accessibilityIdentifier("popup.fans")
        .modifier(PopupKeyboardReveal())
        .task(id: isVisible && ownsVisibleFanPolling) {
            guard isVisible && ownsVisibleFanPolling else { return }
            await store.observeVisibleFan()
        }
    }

}
