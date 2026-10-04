import DarkbloomTelemetry
import SwiftUI

/// Compare recorded dollar amounts on one scale. These periods can have
/// different observation coverage; the bars do not represent targets or trends.
struct PopupEarningsComparison: Equatable {
    let today: Double?
    let week: Double?
    let maximum: Double

    init(today: Double?, week: Double?) {
        self.today = today.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        self.week = week.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        maximum = max(self.today ?? 0, self.week ?? 0)
    }

    func fraction(_ value: Double?) -> Double? {
        guard let value, value.isFinite, value >= 0 else { return nil }
        return maximum > 0 ? min(1, value / maximum) : 0
    }
}

struct PopupEarningsGraphic: View {
    let metrics: PopupEarningsMetrics?
    let week: PopupWeekEarningsMetric?

    var body: some View {
        let comparison = PopupEarningsComparison(today: metrics?.totalUSD, week: week?.totalUSD)
        HStack(alignment: .top, spacing: 8) {
            amountTile("Today", qualifier: "observed", value: metrics?.totalUSD,
                symbol: "sun.max.fill", color: .green,
                fraction: comparison.fraction(comparison.today))
            rateTile
            amountTile("Week", qualifier: week?.title == "This week" ? "this week" : "observed",
                value: week?.totalUSD, symbol: "calendar", color: .accentColor,
                fraction: comparison.fraction(comparison.week))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Observed earnings")
    }

    private func amountTile(_ title: String, qualifier: String, value: Double?,
                            symbol: String, color: Color, fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: symbol).foregroundStyle(color).font(.system(size: 18))
                Text(title).font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            amount(value)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(color.opacity(0.10))
                    if let fraction, fraction > 0 {
                        RoundedRectangle(cornerRadius: 4).fill(color.gradient)
                            .frame(width: max(1, geometry.size.width * fraction))
                    }
                    if fraction == nil {
                        Image(systemName: "questionmark").font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }.frame(height: 14).accessibilityHidden(true)
            Text(qualifier).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(qualifier) earnings")
        .accessibilityValue(value.map { ActivityAmountPresentation.hourlyAmount($0) } ?? "Unavailable")
        .help("Recorded \(title.lowercased()) earnings. Today and week bars use the same dollar scale, with partial observation coverage. They are not targets or payout guarantees.")
    }

    private var rateTile: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "clock").foregroundStyle(.orange).font(.system(size: 18))
                Text("Per hour").font(.caption.weight(.medium))
                Spacer(minLength: 0)
            }
            amount(metrics?.perHourUSD)
            HStack(spacing: 3) {
                Image(systemName: "dollarsign.circle")
                Image(systemName: "divide").font(.system(size: 9))
                Image(systemName: "clock")
            }.font(.caption2).foregroundStyle(.secondary).frame(height: 14)
            Text("observed hours").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Earnings per observed hour")
        .accessibilityValue(metrics.map { ActivityAmountPresentation.hourlyAmount($0.perHourUSD) } ?? "Unavailable")
        .help("Recorded earnings divided by observed hours today. This is not a forecast or a guaranteed hourly rate.")
    }

    private func amount(_ value: Double?) -> some View {
        Text(value.map { ActivityAmountPresentation.hourlyAmount($0) } ?? "—")
            .font(.system(size: 23, weight: .semibold, design: .rounded))
            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.65)
    }
}
