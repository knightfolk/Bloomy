import DarkbloomTelemetry
import SwiftUI

/// Passive presentation of the app's existing samplers. No extra acquisition,
/// inference, history queries or animation clocks are owned by this panel.
struct PopupLivePerformanceView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject private var gpu: SystemGPUUsageStore
    let now: Date
    let isVisible: Bool

    init(store: MonitorStore, now: Date, isVisible: Bool) {
        self.store = store; self.now = now; self.isVisible = isVisible
        _gpu = ObservedObject(wrappedValue: store.gpuUsage)
    }

    var body: some View {
        let reading = gpu.reading(at: now)
        let sampledAt: Date? = switch reading {
        case .current(_, let date), .stale(_, let date): date
        case .unavailable: nil
        }
        let indicators = MenuBarIndicators.make(snapshot: store.snapshot,
            utilization: reading.percentage, sampledAt: sampledAt,
            utilizationIsCurrent: !reading.isStale,
            fanStatus: store.providerExtras?.snapshot?.fanStatus, now: now)
        let throughput = ProviderLiveThroughput.make(snapshot: store.snapshot, now: now)
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("Live performance", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(indicators.temperature.value.map { "\(Int($0))°C\(indicators.temperature.freshness == .current ? "" : " · last")" } ?? "Temperature —")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .help("Measured GPU temperature. A last reading is retained, not current.")
            }
            HStack(alignment: .top, spacing: 14) {
                LiveTelemetryMeter(label: "Provider", symbol: "speedometer", reading: throughput.reading,
                    scale: store.providerThroughputPeak.value.map { .observed(minimum: 0, maximum: $0) } ?? .unscaled,
                    tint: .green, isVisible: isVisible, showsScale: false)
                    .help("\(throughput.detail). Counter-derived tokens/sec across this provider. The bar compares with the highest accepted rate in this observed provider process; it is not a model capacity or a model-specific rate.")
                    .frame(maxWidth: .infinity)
                LiveTelemetryMeter(label: "Mac GPU", symbol: "cpu",
                    reading: meterReading(indicators.gpu), scale: .percent, tint: .purple,
                    isVisible: isVisible, style: .gauge, showsScale: false)
                    .frame(maxWidth: .infinity)
                    .help("Whole-Mac GPU utilization, including other applications.")
                LiveTelemetryMeter(label: "Fans", symbol: "fan",
                    reading: meterReading(indicators.fanSpeed), scale: .percent, tint: .blue,
                    isVisible: isVisible, style: .gauge, showsScale: false)
                    .frame(maxWidth: .infinity)
                    .help("Measured RPM divided by each fan's reported maximum. Policy targets do not establish actual speed.")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("popover.livePerformance")
    }

    private func meterReading(_ value: MenuBarIndicators.Reading) -> LiveTelemetryReading {
        .init(value: value.value, unit: .percent, age: value.sampledAt.map { now.timeIntervalSince($0) },
            freshness: value.freshness == .current ? .current : value.freshness == .stale ? .stale : .unavailable)
    }
}
