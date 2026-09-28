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
                HStack(alignment: .firstTextBaseline, spacing: 16) {
                    amount("Electricity est.", earnings.electricityUSD, symbol: "bolt", prominent: false)
                    Spacer(minLength: 0)
                    amount("After electricity est.", earnings.afterElectricityUSD, symbol: "equal.circle", prominent: true)
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

    @ViewBuilder private var powerReading: some View {
        if let reading, (0...30).contains(now.timeIntervalSince(reading.date)) {
            Text("\(reading.watts, specifier: "%.0f") W adapter")
        }
    }

    private func amount(_ label: String, _ value: Double, symbol: String, prominent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD").precision(.fractionLength(2...4)))
                .font(.system(size: prominent ? 20 : 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(prominent && value < 0 ? Color.orange : .primary)
        }.accessibilityElement(children: .combine)
    }
}
