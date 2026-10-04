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
        HStack(spacing: 16) {
            amountComparison
            VStack(alignment: .leading, spacing: 8) {
                if let metrics {
                    amount("Today · observed", value: metrics.totalUSD, symbol: "banknote", prominent: true)
                }
                HStack(spacing: 20) {
                    if let metrics {
                        amount("Per observed h", value: metrics.perHourUSD, symbol: "clock")
                    }
                    if let week {
                        amount(week.title, value: week.totalUSD, symbol: "calendar")
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Observed earnings")
    }

    private var amountComparison: some View {
        let comparison = PopupEarningsComparison(today: metrics?.totalUSD, week: week?.totalUSD)
        return HStack(alignment: .bottom, spacing: 9) {
            comparisonColumn(fraction: comparison.fraction(comparison.today),
                symbol: "sun.max", title: "Today", color: .green)
            comparisonColumn(fraction: comparison.fraction(comparison.week),
                symbol: "calendar", title: "Week", color: .accentColor)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recorded amount comparison")
        .accessibilityValue("Today \(metrics.map { ActivityAmountPresentation.hourlyAmount($0.totalUSD) } ?? "unavailable"), week \(week.map { ActivityAmountPresentation.hourlyAmount($0.totalUSD) } ?? "unavailable")")
        .help("Today and week amounts on the same dollar scale. Each period can have partial observation coverage. Bars compare recorded amounts; they do not indicate a target, trend or guaranteed payout.")
    }

    private func comparisonColumn(fraction: Double?, symbol: String, title: String, color: Color) -> some View {
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                if let fraction, fraction > 0 {
                    RoundedRectangle(cornerRadius: 5).fill(color.opacity(0.8))
                        .frame(height: max(1, 66 * fraction))
                }
                if fraction == nil {
                    Image(systemName: "questionmark").font(.caption2).foregroundStyle(.secondary)
                }
            }.frame(width: 23, height: 66)
            Image(systemName: symbol).font(.caption2).foregroundStyle(.secondary)
        }.help(title).accessibilityHidden(true)
    }

    private func amount(_ title: String, value: Double, symbol: String, prominent: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: symbol).font(.caption2).foregroundStyle(.secondary)
            Text(ActivityAmountPresentation.hourlyAmount(value))
                .font(.system(size: prominent ? 27 : 16, weight: .semibold, design: .rounded))
                .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
        }.accessibilityElement(children: .combine)
    }
}
