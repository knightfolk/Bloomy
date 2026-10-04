import DarkbloomTelemetry
import SwiftUI

struct EnergySummaryView: View {
    let reading: EnergyReading?
    let earnings: EnergyEarnings?
    let now: Date
    var waitingMessage: String = "Collecting matched earnings data"

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let earnings {
                HStack(alignment: .center, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        costBar("Gross", symbol: "banknote", value: earnings.earningsUSD,
                            maximum: max(earnings.earningsUSD, earnings.electricityUSD), color: .green)
                        costBar("Power", symbol: "bolt.fill", value: earnings.electricityUSD,
                            maximum: max(earnings.earningsUSD, earnings.electricityUSD), color: .orange)
                    }
                    amount("After power est.", earnings.afterElectricityUSD, symbol: "equal.circle", prominent: true)
                        .fixedSize(horizontal: true, vertical: false)
                }
                HStack {
                    Text("Matched \(earnings.coveredSeconds / 3600, specifier: "%.1f") h today · partial")
                    Spacer(minLength: 0)
                    powerReading
                }.font(.caption2).foregroundStyle(.secondary)
            } else {
                HStack {
                    Label("Electricity estimate", systemImage: "bolt").font(.caption.weight(.semibold))
                    Spacer()
                    powerReading.font(.caption2).foregroundStyle(.secondary)
                }
                Label(waitingMessage, systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help("Whole-Mac DC adapter input, not wall power or Darkbloom-only consumption. Earnings after electricity includes only completed earnings intervals with uninterrupted energy readings. Excludes adapter losses, other expenses and unmeasured intervals. A complete matched hour is required before showing an estimate.")
    }

    private func costBar(_ title: String, symbol: String, value: Double, maximum: Double, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).frame(width: 13).foregroundStyle(color)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if maximum > 0, value > 0, maximum.isFinite, value.isFinite {
                        Capsule().fill(color.opacity(0.8)).frame(width: geometry.size.width * min(1, value / maximum))
                    }
                }
            }.frame(height: 6).accessibilityHidden(true)
            Text(ActivityAmountPresentation.hourlyAmount(value)).font(.caption2).monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Matched \(title)")
        .accessibilityValue(ActivityAmountPresentation.hourlyAmount(value))
        .help("\(title) in the same matched earnings intervals: \(ActivityAmountPresentation.hourlyAmount(value))")
    }

    @ViewBuilder private var powerReading: some View {
        if let reading, (0...30).contains(now.timeIntervalSince(reading.date)) {
            Text("\(reading.watts, specifier: "%.0f") W adapter")
        }
    }

    private func amount(_ label: String, _ value: Double, symbol: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(ActivityAmountPresentation.hourlyAmount(value))
                .font(.system(size: prominent ? 20 : 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(prominent && value < 0 ? Color.orange : .primary)
        }.accessibilityElement(children: .combine)
    }
}
