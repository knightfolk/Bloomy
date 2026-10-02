import DarkbloomTelemetry
import SwiftUI

/// Read-only host utilization and provider-reported GPU resource context.
struct ProviderResourcesView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var store: MonitorStore
    @StateObject private var cpuUsage: SystemCPUUsageStore
    /// The dashboard shares the app-lifecycle GPU sampler with the menu-bar
    /// ring instead of owning a competing one.
    @ObservedObject private var gpuUsage: SystemGPUUsageStore

    private let columns = [GridItem(.adaptive(minimum: 220), spacing: 10)]

    init(store: MonitorStore, cpuUsage: SystemCPUUsageStore? = nil) {
        self.store = store
        self.gpuUsage = store.gpuUsage
        _cpuUsage = StateObject(wrappedValue: cpuUsage ?? SystemCPUUsageStore())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Provider resources")
                .font(.title3.bold())

            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cpuMetric
                gpuUtilizationMetric
                requestActivityMetric
                gpuMemoryMetric
            }

            if let extras = store.providerExtras {
                ProviderThermalView(store: extras, isVisible: store.dashboardVisible)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.24), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("provider-resources")
        .task(id: store.dashboardVisible) {
            guard !Task.isCancelled else { return }
            if store.dashboardVisible { cpuUsage.start() }
            else { cpuUsage.stop() }
        }
        .onDisappear {
            cpuUsage.stop()
        }
    }

    private var cpuMetric: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("Mac CPU", systemImage: "cpu")
                .font(.callout.weight(.medium))
            if let percentage = currentCPUPercentage {
                Text(percentage.formatted(.number.precision(.fractionLength(0))) + "%")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                ProgressView(value: percentage, total: 100)
                    .tint(.blue)
                    .accessibilityLabel("Mac-wide CPU utilization")
                    .accessibilityValue("\(percentage.formatted(.number.precision(.fractionLength(0)))) percent")
            } else {
                Text("Measuring…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Text("System-wide")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(cpuAccessibilityLabel)
        .accessibilityIdentifier("provider-resource.cpu")
    }

    private var gpuUtilizationMetric: some View {
        let reading = gpuUsage.reading()
        let percentage = reading.percentage
        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(.quaternary, lineWidth: 6)
                if let percentage {
                    Circle()
                        .trim(from: 0, to: percentage / 100)
                        .stroke(reading.isStale ? Color.secondary : Color.purple,
                                style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: percentage)
                    VStack(spacing: -2) {
                        Text(percentage.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(.headline, design: .rounded, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(reading.isStale ? Color.secondary : Color.primary)
                        Text("%")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text("GPU use")
                    .font(.callout.weight(.semibold))
                Text(percentage == nil ? "Not available" : reading.isStale ? "Last sample · whole Mac" : "System-wide")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(gpuAccessibilityLabel)
        .accessibilityIdentifier("provider-resource.gpu-utilization")
        .help("Best-effort whole-Mac GPU utilization. It includes all apps and is not attributed to Darkbloom.")
    }

    private var requestActivityMetric: some View {
        let presentation = ProviderRequestActivityPresentation.make(daemonState: daemonState)
        let requestSubtitle: String = switch presentation.mode {
        case .draining: "left · new work paused"
        case .stopped: "provider not serving"
        default: "running requests"
        }
        return HStack(spacing: 10) {
            Image(systemName: requestActivitySymbol(for: presentation.mode))
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(requestActivityColor(for: presentation.mode))
                .frame(width: 56, height: 56)
                .background(requestActivityColor(for: presentation.mode).opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(presentation.value)
                        .font(.title2.weight(.bold))
                        .monospacedDigit()
                    Text(presentation.status)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(requestActivityColor(for: presentation.mode))
                        .lineLimit(1)
                }
                Text(requestSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if daemonStateIsStale {
                    Text("Last report")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.detail)
        .accessibilityValue("\(presentation.value), \(presentation.status)")
        .accessibilityIdentifier("provider-resource.requests")
        .help(presentation.detail)
    }

    @ViewBuilder
    private var gpuMemoryMetric: some View {
        switch store.snapshot.state {
        case .available(let state, _):
            if let capacity = state.capacity {
                gpuMemoryCard(capacity, stale: daemonStateIsStale)
            }
        case .stale(let state, _, _):
            if let capacity = state.capacity {
                gpuMemoryCard(capacity, stale: true)
            }
        case .unavailable:
            EmptyView()
        }
    }

    private func gpuMemoryCard(_ capacity: MemoryCapacity, stale: Bool) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Label("GPU memory", systemImage: "memorychip")
                    .font(.callout.weight(.medium))
                if stale {
                    Text("Last report")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            Text("\(capacity.gpuMemoryActiveGB.formatted(.number.precision(.fractionLength(1)))) GB active")
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text("\(capacity.gpuMemoryCacheGB.formatted(.number.precision(.fractionLength(1)))) GB cached")
                .font(.callout)
                .monospacedDigit()
            Text("Provider-reported allocations")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
        .padding(11)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("GPU memory, \(capacity.gpuMemoryActiveGB.formatted(.number.precision(.fractionLength(1)))) gigabytes active, \(capacity.gpuMemoryCacheGB.formatted(.number.precision(.fractionLength(1)))) gigabytes cached\(stale ? ", last report" : "")")
        .accessibilityIdentifier("provider-resource.gpu-memory")
    }

    private var daemonState: DaemonState? { store.snapshot.state.value }

    private var daemonStateIsStale: Bool {
        HealthPresentation.daemonWarning(store.snapshot.state, at: Date()) != nil
    }

    private var currentCPUPercentage: Double? {
        guard let sampledAt = cpuUsage.sampledAt else { return nil }
        let age = Date().timeIntervalSince(sampledAt)
        guard age.isFinite, (0...10).contains(age) else { return nil }
        return cpuUsage.percentage
    }

    private var cpuAccessibilityLabel: String {
        guard let percentage = currentCPUPercentage else { return "Mac-wide CPU utilization is being measured" }
        return "Mac-wide CPU utilization, \(percentage.formatted(.number.precision(.fractionLength(0)))) percent"
    }

    private var gpuAccessibilityLabel: String {
        switch gpuUsage.reading() {
        case .current(let percentage, _):
            return "System-wide GPU utilization, \(percentage.formatted(.number.precision(.fractionLength(0)))) percent"
        case .stale(let percentage, let sampledAt):
            return "System-wide GPU utilization, last sample \(percentage.formatted(.number.precision(.fractionLength(0)))) percent, captured \(sampledAt.formatted(date: .abbreviated, time: .standard))"
        case .unavailable:
            return "System-wide GPU utilization is unavailable"
        }
    }

    private func requestActivitySymbol(for mode: ProviderRequestActivityMode) -> String {
        switch mode {
        case .idle: "checkmark.circle.fill"
        case .active: "arrow.triangle.2.circlepath"
        case .draining: "hourglass.circle.fill"
        case .stopped: "stop.circle.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    private func requestActivityColor(for mode: ProviderRequestActivityMode) -> Color {
        switch mode {
        case .idle, .stopped: .secondary
        case .active: .blue
        case .draining: .orange
        case .unavailable: .secondary
        }
    }
}
