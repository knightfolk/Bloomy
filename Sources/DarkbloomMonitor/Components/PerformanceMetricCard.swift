import SwiftUI

/// Fractions are only for measurements with a defined, observed denominator.
/// Unknown and invalid values do not become an empty, known-zero indicator.
enum PerformanceMetricFraction {
    static func measured(_ numerator: Double?, outOf denominator: Double) -> Double? {
        guard let numerator, numerator.isFinite, denominator.isFinite,
              denominator > 0, numerator >= 0, numerator <= denominator else { return nil }
        return numerator / denominator
    }
}

struct PerformanceMetricCard: View {
    enum Graphic {
        case none
        case coverage(Double?)
        case utilization(Double?)
    }

    let id: String
    let title: String
    let symbol: String
    let value: String
    let detail: String
    var graphic = Graphic.none

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if case .utilization(let fraction) = graphic {
                    utilization(fraction)
                }
                Text(value).font(.title3.weight(.semibold)).monospacedDigit()
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .coverage(let fraction) = graphic {
                if let fraction {
                    ProgressView(value: fraction).progressViewStyle(.linear)
                        .accessibilityHidden(true)
                } else {
                    Capsule().fill(.quaternary).frame(height: 4)
                        .accessibilityHidden(true)
                }
            }
            Text(detail).font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(value), \(detail)")
        .accessibilityIdentifier("activity.metrics.\(id)")
        .help("\(title): \(value). \(detail)")
    }

    private func utilization(_ fraction: Double?) -> some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            if let fraction {
                Circle().trim(from: 0, to: fraction)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                Image(systemName: "questionmark").font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 28, height: 28)
        .accessibilityHidden(true)
    }
}
