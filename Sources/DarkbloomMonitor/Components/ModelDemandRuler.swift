import DarkbloomTelemetry
import SwiftUI

/// One linear scale for the complete network snapshot, independent of search,
/// enabled selection, or card order. Zero loaded providers is not zero demand.
struct ModelDemandScale: Equatable, Sendable {
    let upperBound: Double

    init(models: [NetworkModelCapacity]) {
        upperBound = max(1, models.compactMap(Self.pressure).max() ?? 1)
    }

    static func pressure(_ model: NetworkModelCapacity) -> Double? {
        guard model.activeRequests >= 0, model.queuedRequests >= 0,
              model.warmProviders > 0, let value = model.demandPerWarmProvider,
              value.isFinite, value >= 0 else { return nil }
        return value
    }

    func fraction(for model: NetworkModelCapacity) -> Double? {
        Self.pressure(model).map { min(1, max(0, $0 / upperBound)) }
    }

    static func label(_ value: Double) -> String {
        // Preserve nonzero tiny readings rather than rounding them to zero.
        if value > 0 && value < 0.001 || value >= 1_000_000 {
            return value.formatted(.number.notation(.scientific).precision(.significantDigits(1...3)))
        }
        return value.formatted(.number.precision(.significantDigits(1...3)))
    }
}

struct ModelDemandRuler: View {
    let modelID: String
    let demand: ModelCardDemand
    let scale: ModelDemandScale

    private var pressure: Double? { demand.model.flatMap(ModelDemandScale.pressure) }
    private var fraction: Double? { demand.model.flatMap(scale.fraction) }
    private var value: String {
        pressure.map { (demand.isCurrent ? "" : "Last ") + ModelDemandScale.label($0) } ?? "Unavailable"
    }
    private var missingReason: String {
        demand.model?.warmProviders == 0 ? "No loaded providers" : "No valid reading"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text("Requests / loaded provider")
                Spacer(minLength: 4)
                Text(value).monospacedDigit().fontWeight(.medium)
            }.font(.caption2).foregroundStyle(.secondary)
            GeometryReader { geometry in
                let width = max(0, geometry.size.width - 8)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 3)
                    ForEach(0..<5) { tick in
                        Rectangle().fill(.secondary.opacity(0.35)).frame(width: 1, height: 7)
                            .offset(x: 4 + width * Double(tick) / 4)
                    }
                    if let fraction {
                        Circle().fill(demand.isCurrent ? Color.accentColor : .clear)
                            .overlay(Circle().stroke(demand.isCurrent ? Color.accentColor : .secondary, lineWidth: 1.5))
                            .frame(width: 8, height: 8).offset(x: width * fraction)
                    }
                }.frame(height: 8)
            }.frame(height: 8).accessibilityHidden(true)
            HStack {
                Text(pressure == nil ? missingReason : "0")
                Spacer(minLength: 4)
                Text(ModelDemandScale.label(scale.upperBound))
            }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
        .help("Network-wide active plus queued requests divided by loaded providers. All cards share the full snapshot's linear scale, from 0 to \(ModelDemandScale.label(scale.upperBound)); filtering does not change it. \(demand.isCurrent ? "Current reading." : "Retained reading; not current.") Demand does not predict work or earnings on this Mac.")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Network requests per loaded provider for \(modelID)")
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("model.\(modelID).demandRuler")
    }

    private var accessibilityValue: String {
        let reading = pressure.map { (demand.isCurrent ? "Current " : "Last known ") + ModelDemandScale.label($0) + " requests per loaded provider" }
            ?? "Unavailable. \(missingReason)"
        let counts = demand.model.map { "; \($0.activeRequests) active, \($0.queuedRequests) queued, \($0.warmProviders) loaded providers" } ?? ""
        return "\(reading)\(counts); shared scale 0 to \(ModelDemandScale.label(scale.upperBound)). Network-wide, not expected earnings."
    }
}
