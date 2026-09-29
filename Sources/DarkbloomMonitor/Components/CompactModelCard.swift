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

struct CompactModelCard: View {
    static let accountAttribution = "History-based and account-derived: earnings recorded for this model on the account, divided by this Mac’s observed active serving hours. The account may include other machines, so this is not measured income on this Mac. Gross excludes electricity; estimated net subtracts estimated incremental power where a measured idle baseline exists. Not a guaranteed payout."
    let modelID: String
    let status: String
    var symbol: String = "cpu"
    var tint: Color = .accentColor
    var metrics: [ModelCardMetric] = []
    var selected: Bool = false
    var compact: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 7 : 10) {
            HStack(alignment: .top, spacing: 7) {
                familyImage
                    .foregroundStyle(tint)
                    .frame(width: 25, height: 25)
                    .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 3) {
                    Text(ModelDisplayName.short(modelID))
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(compact ? 2 : 1).help(modelID)
                    Label(status, systemImage: "circle.fill")
                        .font(.caption).foregroundStyle(tint)
                        .lineLimit(1)
                        .labelStyle(.titleAndIcon)
                }
                Spacer(minLength: 0)
            }
            if !metrics.isEmpty {
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
        }
        .padding(compact ? 10 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 104 : 92, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? tint : .primary.opacity(0.07), lineWidth: selected ? 1.5 : 1))
        .help(modelID)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(modelID), \(status)")
        .accessibilityValue(metrics.map { "\($0.value) \($0.caption)" }.joined(separator: ", "))
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

    private var current: Double? {
        guard let date = usage.sampledAt, (0...10).contains(now.timeIntervalSince(date)) else { return nil }
        return usage.percentage
    }

    var body: some View {
        HStack(spacing: 9) {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 5)
                if let current {
                    Circle().trim(from: 0, to: current / 100)
                        .stroke(.purple, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Text(current.map { String(format: "%.0f", $0) } ?? "—")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold)).monospacedDigit()
            }.frame(width: 43, height: 43)
            VStack(alignment: .leading, spacing: 2) {
                Text("GPU %").font(.caption.weight(.semibold))
                Text(current == nil ? "Unavailable" : "Whole Mac")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .help("Whole-Mac GPU use, including other apps. Unavailable readings are not zero.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Whole-Mac GPU utilization")
        .accessibilityValue(current.map { "\(Int($0)) percent" } ?? "Unavailable")
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
