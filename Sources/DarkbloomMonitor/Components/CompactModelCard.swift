import DarkbloomTelemetry
import SwiftUI

/// Shared display names never replace canonical IDs used for selection or attribution.
enum ModelDisplayName {
    static func short(_ id: String) -> String {
        switch id {
        case "EigenLabs/Qwen3.8-27B-4bit-mtp": return "Qwen 3.8 · 27B"
        case "gemma-4-26b-qat-4bit": return "Gemma 4 · 26B"
        case "qwen3-vl-30b-a3b-instruct": return "Qwen VL · 30B A3B"
        case "qwen3.5-35b-a3b": return "Qwen 3.5 · 35B A3B"
        case "qwen3.6-35b-a3b-vl-mtp-mxfp8": return "Qwen 3.6 VL · 35B"
        case "gpt-oss-20b": return "GPT-OSS · 20B"
        case "nvidia-nemotron-3.5-lightning": return "Nemotron 3.5 Lightning"
        case "ternary-bonsai-2-27b": return "Bonsai 2 · 27B"
        default:
            // Keep variant information for unknown models rather than guessing an alias.
            let name = id.split(separator: "/").last.map(String.init) ?? id
            if name != id { return short(name) }
            let pattern = #"(?i)^(qwen|gemma|llama|deepseek|nemotron|gpt-oss)[-_]?([0-9]+(?:\.[0-9]+)?)(?:[-_](vl))?[-_]([0-9]+b)(.*)$"#
            if let expression = try? NSRegularExpression(pattern: pattern),
               let match = expression.firstMatch(in: name, range: NSRange(name.startIndex..., in: name)) {
                func part(_ index: Int) -> String {
                    guard let range = Range(match.range(at: index), in: name) else { return "" }
                    return String(name[range])
                }
                let family = part(1).lowercased() == "gpt-oss" ? "GPT-OSS" : part(1).capitalized
                let vision = part(3).isEmpty ? "" : " VL"
                // Preserve unknown variants; visual truncation is paired with full-ID help.
                let variant = part(5).replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
                return "\(family) \(part(2))\(vision) · \(part(4).uppercased())\(variant)"
            }
            return name.replacingOccurrences(of: "_", with: " ")
        }
    }
}

struct ModelCardMetric: Identifiable {
    let id: String
    let symbol: String
    let value: String
    let caption: String
}

/// A network reading keeps its source freshness separate from its timestamp.
struct ModelCardDemand: Equatable {
    let model: NetworkModelCapacity?
    let isCurrent: Bool

    var title: String {
        guard let model else { return "Demand unavailable" }
        return isCurrent ? "\(model.demandBand.rawValue.capitalized) demand" : "Demand stale"
    }

    var counts: String {
        guard let model else { return "Waiting for network" }
        return "\(model.activeRequests.formatted()) active · \(model.queuedRequests.formatted()) queued"
    }

    var tint: Color {
        guard isCurrent, let model else { return .secondary }
        switch model.demandBand {
        case .low: return .green
        case .moderate: return .yellow
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct CompactModelCard: View {
    static let accountAttribution = "History-based and account-derived: earnings recorded for this model on the account, divided by this Mac’s observed active serving hours. The account may include other machines, so this is not measured income on this Mac. Gross excludes electricity; estimated net subtracts estimated incremental power where a measured idle baseline exists. Not a guaranteed payout."
    static let popupHeight: CGFloat = 168
    static let horizontalPopupHeight: CGFloat = 52
    let modelID: String
    let status: String
    var symbol: String = "cpu"
    var tint: Color = .accentColor
    var metrics: [ModelCardMetric] = []
    var selected: Bool = false
    var compact: Bool = false
    var compactWidth: CGFloat? = nil
    var contentOnly = false
    var horizontal = false
    var liveThroughput: ProviderLiveThroughput? = nil
    var throughputPeak: Double? = nil
    var isVisible = true
    var demand: ModelCardDemand? = nil
    var demandScale: ModelDemandScale? = nil
    var demandHistory: ModelDemandHistorySeries? = nil
    var activate: (() -> Void)? = nil
    var activationUnavailableReason: String? = nil
    var activationHelp: String = "Add this model to the provider selection"
    var swapModel: (() -> Void)? = nil
    var swapUnavailableReason: String? = nil
    var switchModel: (() -> Void)? = nil
    var switchUnavailableReason: String? = nil

    var body: some View {
        Group {
        if horizontal { horizontalBody } else {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(alignment: .top, spacing: 7) {
                familyImage
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ModelDisplayName.short(modelID))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(compact ? 2 : 1, reservesSpace: compact && compactWidth != nil)
                        .help(modelID)
                    Label(status, systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(tint)
                        .lineLimit(1)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }
            if let demand {
                HStack(spacing: 6) {
                    Label(demand.title, systemImage: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(demand.tint)
                    Spacer(minLength: 4)
                    Text(demand.counts).foregroundStyle(.secondary).monospacedDigit()
                }
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(demand.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 7))
                .help("Network-wide requests for this model. \(demand.isCurrent ? "Current reading." : "A fresh reading is unavailable; retained counts are last known.")")
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("model.\(modelID).demand")
                if let demandScale {
                    ModelDemandRuler(modelID: modelID, demand: demand, scale: demandScale)
                }
            }
            if let demandHistory {
                ModelDemandHistorySparkline(modelID: modelID, series: demandHistory)
            }
            if compact && metrics.count == 1 && metrics.first?.id == "unknown" {
                Label("No history yet", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Speed and earnings appear after this model serves requests")
            } else if !metrics.isEmpty {
                (compact ? AnyLayout(VStackLayout(alignment: .leading, spacing: 5))
                         : AnyLayout(HStackLayout(alignment: .top, spacing: 10))) {
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: 3) {
                            Label(metric.value, systemImage: metric.symbol)
                                .font(.subheadline.weight(.semibold)).monospacedDigit()
                                .lineLimit(1)
                            Text(metric.caption).font(.caption2).foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .help(metric.caption.contains("active h") ? Self.accountAttribution : metric.caption)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            if compact && compactWidth != nil {
                Spacer(minLength: 0)
            }
            actionButtons
        }
        }
        }
        .padding(.horizontal, contentOnly ? 0 : horizontal ? 10 : compact ? 10 : 12)
        .padding(.vertical, contentOnly ? 0 : horizontal ? 8 : compact ? 10 : 12)
        .frame(maxWidth: .infinity, minHeight: contentOnly || horizontal ? nil : compact ? 104 : 92, alignment: .topLeading)
        .frame(width: compact ? compactWidth : nil,
               height: compact && compactWidth != nil ? (horizontal ? Self.horizontalPopupHeight : Self.popupHeight) : nil,
               alignment: .topLeading)
        .background(contentOnly ? Color.clear : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? tint : .primary.opacity(0.07), lineWidth: contentOnly ? 0 : selected ? 1.5 : 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(modelID), \(status)")
        .accessibilityValue(metrics.map { "\($0.value) \($0.caption)" }.joined(separator: ", "))
    }
    /// A 36pt face leaves 8pt above and below in the 52pt popup row.
    /// Historical averages stay separate from the attributed live provider rate.
    private var horizontalBody: some View {
        HStack(alignment: .center, spacing: 8) {
            horizontalIdentity
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            VStack(alignment: .trailing, spacing: 3) {
                if let liveThroughput {
                    LiveTelemetryMeter(label: "Provider tok/s", symbol: "speedometer",
                        reading: liveThroughput.reading,
                        scale: throughputPeak.map { .observed(minimum: 0, maximum: $0) } ?? .unscaled,
                        tint: tint, isVisible: isVisible, style: .inline, showsScale: false)
                        .help("\(liveThroughput.detail). Provider-wide counter delta; not exclusive income or throughput for this model. Scale is the highest measured rate in this observed provider process, not a hardware limit. \(metricsHelp)")
                        .accessibilityIdentifier("model.\(modelID).liveProviderRate")
                } else {
                    horizontalMetrics
                }
                if let demand {
                    HStack(spacing: 5) {
                        Text(demand.title)
                            .foregroundStyle(demand.tint).lineLimit(1)
                        if let demandScale {
                            denseDemandTrack(demand, scale: demandScale)
                                .frame(width: 30, height: 8)
                        }
                        if let demandHistory {
                            denseHistory(demandHistory)
                                .frame(width: 36, height: 12)
                        }
                    }
                    .font(.caption2)
                    .help(demandHelp(demand))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("model.\(modelID).demand")
                } else if let demandHistory {
                    denseHistory(demandHistory).frame(width: 68, height: 12)
                }
            }
            .frame(minWidth: 166, maxWidth: .infinity, alignment: .trailing)
            actionButtons
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: 36)
    }

    private var horizontalIdentity: some View {
        HStack(alignment: .center, spacing: 7) {
            familyImage.foregroundStyle(tint)
                .frame(width: 26, height: 26)
                .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ModelDisplayName.short(modelID)).font(.system(size: 12, weight: .semibold))
                    .lineLimit(1).truncationMode(.tail).help(modelID + "\n" + metricsHelp)
                Label(status, systemImage: "circle.fill").font(.caption2).foregroundStyle(tint)
                    .lineLimit(1).help(status)
            }
        }
    }

    private var metricsHelp: String {
        metrics.map { "\($0.value) \($0.caption)." + ($0.caption.contains("active h") ? " " + Self.accountAttribution : "") }
            .joined(separator: "\n")
    }

    private var horizontalMetrics: some View {
        HStack(spacing: 8) {
            ForEach(metrics) { metric in
                Label(horizontalMetricValue(metric), systemImage: metric.symbol)
                    .font(.caption.weight(.medium)).monospacedDigit().lineLimit(1)
                    .help(metric.caption.contains("active h") ? Self.accountAttribution : metric.caption)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(metric.caption)
                    .accessibilityValue(metric.value)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func horizontalMetricValue(_ metric: ModelCardMetric) -> String {
        switch metric.id {
        case "unknown": return "No history"
        case "speed": return "avg \(metric.value) tok/s"
        case "earnings":
            return "\(metric.caption.contains("net") ? "est." : "derived") \(metric.value)/h"
        default: return metric.value
        }
    }

    private func demandHelp(_ demand: ModelCardDemand) -> String {
        "Network-wide \(demand.title.lowercased()): \(demand.counts). \(demand.isCurrent ? "Current reading." : "Retained reading; not current.") Demand does not predict work or earnings on this Mac."
    }

    private func denseDemandTrack(_ demand: ModelCardDemand, scale: ModelDemandScale) -> some View {
        let fraction = demand.model.flatMap(scale.fraction)
        let pressure = demand.model.flatMap(ModelDemandScale.pressure)
        let reading = pressure.map { (demand.isCurrent ? "Current " : "Last known ") + ModelDemandScale.label($0) + " requests per loaded provider" }
            ?? (demand.model?.warmProviders == 0
                ? "Unavailable; no loaded providers. This is not zero."
                : "Unavailable; no valid pressure reading. This is not zero.")
        let description = "\(reading). \(demand.counts). Shared network scale 0 to \(ModelDemandScale.label(scale.upperBound)); filtering does not change it."
        return GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 3)
                if let fraction {
                    Circle().fill(demand.isCurrent ? demand.tint : .clear)
                        .overlay(Circle().stroke(demand.tint, lineWidth: 1))
                        .frame(width: 6, height: 6)
                        .offset(x: max(0, geometry.size.width - 6) * fraction)
                } else {
                    Capsule().strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                        .frame(height: 3)
                }
            }.frame(height: 8)
        }
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network requests per loaded provider for \(modelID)")
        .accessibilityValue(description)
        .accessibilityIdentifier("model.\(modelID).demandRuler")
    }

    /// The compact history uses the same accepted segments and shared scale as
    /// the detailed graph. Missing samples remain visible gaps, never zeroes.
    private func denseHistory(_ series: ModelDemandHistorySeries) -> some View {
        let state: String = switch series.state {
        case .pending: "Reading history"
        case .unavailable: "History unavailable"
        case .available: series.validCount == 0 ? "No valid samples" : "\(series.validCount) samples"
        case .retained: "Last read · \(series.validCount) samples"
        }
        let range = series.range.map { " Observed \($0.start.formatted(date: .abbreviated, time: .shortened)) to \($0.end.formatted(date: .abbreviated, time: .shortened))." } ?? " Observed range unavailable."
        let read = series.readAt.map { " Read \($0.formatted(date: .abbreviated, time: .shortened))." } ?? ""
        let median = series.median.map { " Dashed line: sample median \(ModelDemandScale.label($0))." }
            ?? " Median appears after twelve valid samples."
        let description = "Observed network demand history. \(state).\(range)\(read) Shared scale 0 to \(ModelDemandScale.label(series.upperBound)) requests per loaded provider; filtering does not change it. Missing five-minute buckets and zero loaded providers are gaps.\(median) Sampled pressure does not predict work or earnings."
        return GeometryReader { geometry in
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: geometry.size.height - 1))
                    path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 1))
                }.stroke(.quaternary, lineWidth: 1)
                if let median = series.median {
                    Path { path in
                        let y = 1 + max(0, geometry.size.height - 2) * (1 - min(1, max(0, median / series.upperBound)))
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: y))
                    }.stroke(.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }
                ForEach(Array(series.segments.enumerated()), id: \.offset) { _, points in
                    Path { path in
                        for (index, point) in points.enumerated() {
                            let position = historyPosition(point, series: series, size: geometry.size)
                            if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                        }
                    }.stroke(series.state == .retained ? Color.secondary : Color.accentColor, lineWidth: 1)
                    if let first = points.first, points.count == 1 {
                        Circle().fill(series.state == .retained ? Color.secondary : Color.accentColor)
                            .frame(width: 3, height: 3)
                            .position(historyPosition(first, series: series, size: geometry.size))
                    }
                }
                if series.validCount == 0 {
                    Image(systemName: series.state == .pending ? "hourglass" : "chart.xyaxis.line")
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Observed network demand history for \(modelID)")
        .accessibilityValue(description)
        .accessibilityIdentifier("model.\(modelID).demandHistory")
    }

    private func historyPosition(_ point: ModelDemandHistoryPoint, series: ModelDemandHistorySeries, size: CGSize) -> CGPoint {
        let duration = series.range?.duration ?? 0
        let fraction = duration > 0 ? point.capturedAt.timeIntervalSince(series.range!.start) / duration : 0
        return CGPoint(x: 1 + max(0, size.width - 2) * min(1, max(0, fraction)),
            y: 1 + max(0, size.height - 2) * (1 - min(1, max(0, (point.pressure ?? 0) / series.upperBound))))
    }

    @ViewBuilder private var actionButtons: some View {
            if activate != nil || swapModel != nil || switchModel != nil {
                HStack(spacing: 5) {
                    if let activate {
                        Button(action: activate) {
                            Label("Add", systemImage: "plus.circle.fill")
                                .frame(maxWidth: horizontal ? nil : .infinity)
                        }
                        .disabled(activationUnavailableReason != nil)
                        .help(activationUnavailableReason ?? "Activate · \(activationHelp)")
                        .accessibilityLabel("Activate \(ModelDisplayName.short(modelID))")
                        .accessibilityHint(activationUnavailableReason ?? activationHelp)
                        .modifier(PopupKeyboardReveal())
                    }
                    if let swapModel {
                        Button(action: swapModel) {
                            Label("Swap", systemImage: "arrow.triangle.2.circlepath")
                                .frame(maxWidth: horizontal ? nil : .infinity)
                        }
                        .disabled(swapUnavailableReason != nil)
                        .help(swapUnavailableReason ?? "Load this model while keeping all advertised models available")
                        .accessibilityLabel("Swap to \(ModelDisplayName.short(modelID))")
                        .accessibilityHint(swapUnavailableReason ?? "Keep all advertised models available")
                        .modifier(PopupKeyboardReveal())
                    }
                    if let switchModel {
                        Button(action: switchModel) {
                            Label(activate == nil && swapModel == nil ? "Use only" : "Only", systemImage: "1.circle")
                                .frame(maxWidth: horizontal ? nil : .infinity)
                        }
                        .disabled(switchUnavailableReason != nil)
                        .help(switchUnavailableReason ?? "Make this the only advertised model. Current work drains before switching.")
                        .accessibilityLabel("Switch to \(ModelDisplayName.short(modelID)) only")
                        .modifier(PopupKeyboardReveal())
                        .accessibilityHint(switchUnavailableReason ?? "Make this the only advertised model")
                    }
                }
                .modifier(CompactModelActionLabelStyle(iconOnly: horizontal))
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
    }

    @ViewBuilder private var familyImage: some View {
        let family = ModelFamilyIcon.select(status: .online, activeModel: modelID)
        if family != .darkbloom, let image = DarkbloomLogoAsset.modelImage(family: family) {
            Image(nsImage: image).resizable().renderingMode(.template).scaledToFit().padding(4)
        } else {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        }
    }

}

struct CompactGPUGauge: View {
    @ObservedObject var usage: SystemGPUUsageStore
    let now: Date
    var compact = false

    var body: some View {
        // A sample can arrive after TimelineView's date but before this render.
        let reading = usage.reading(at: Date())
        let current = reading.percentage
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 5)
                if let current {
                    Circle().trim(from: 0, to: current / 100)
                        .stroke(reading.isStale ? Color.secondary : .purple,
                                style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                if compact {
                    Image(systemName: "cpu").font(.caption)
                } else {
                Text(current.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(reading.isStale ? .secondary : .primary)
                }
            }.frame(width: compact ? 26 : 43, height: compact ? 26 : 43)
            VStack(alignment: .leading, spacing: 2) {
                Text(compact ? "GPU \(current.map { String(format: "%.0f%%", $0) } ?? "—")" : "GPU %").font(.caption.weight(.semibold))
                if !compact {
                Text(current == nil ? "Unavailable" : reading.isStale ? "Last sample" : "Whole Mac")
                    .font(.caption2).foregroundStyle(.secondary)
                } else if reading.isStale {
                    Text("Last sample").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .help("Whole-Mac GPU use, including other apps. Unavailable readings are not zero.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Whole-Mac GPU utilization")
        .accessibilityValue(current.map { "\(reading.isStale ? "Last sample, " : "")\(Int($0)) percent" } ?? "Unavailable")
    }
}

/// Advertising is a fresh runtime fact, independent of saved or staged enablement.
enum PopupModelGroups {
    static func advertised(snapshot: TelemetrySnapshot, control: ProviderControlSnapshot?, now: Date) -> [String]? {
        if case .available(_, let capturedAt) = snapshot.status,
           (0...10).contains(now.timeIntervalSince(capturedAt)),
           ProviderLifecycleSourceInput(daemonState: snapshot.state, status: snapshot.status,
               controlDaemonState: control?.sources.daemon, currentTime: now).providerKnownRunning == false {
            return []
        }
        if let control, let ids = ProviderSelectionComparison.make(snapshot: control, now: now).advertised {
            return ids
        }
        guard case .available(let state, let capturedAt) = snapshot.state,
              (0...10).contains(now.timeIntervalSince(capturedAt)),
              state.writtenAt.isFinite,
              (0...10).contains(now.timeIntervalSince1970 - state.writtenAt) else { return nil }
        return state.advertisedModels.map { Array(Set($0)).sorted() }
    }
}

private struct CompactModelActionLabelStyle: ViewModifier {
    let iconOnly: Bool

    @ViewBuilder func body(content: Content) -> some View {
        if iconOnly { content.labelStyle(.iconOnly) }
        else { content.labelStyle(.titleAndIcon) }
    }
}
