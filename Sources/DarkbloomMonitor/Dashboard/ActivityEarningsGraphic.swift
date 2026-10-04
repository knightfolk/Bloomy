import Charts
import DarkbloomTelemetry
import SwiftUI

struct EarningsComposition: Equatable {
    struct Part: Equatable, Identifiable {
        let name: String
        let usd: Double
        var id: String { name }
    }
    let parts: [Part]
    let totalUSD: Double?
    var canShowShare: Bool { totalUSD.map { $0 > 0 } == true && parts.allSatisfy { $0.usd >= 0 } }

    init(values: [ActivityChartValue]) {
        // Use exactly the rendered series: filters and the reward switch apply here too.
        guard !values.isEmpty, values.allSatisfy({ $0.amountUSD.isFinite }) else {
            parts = []; totalUSD = nil; return
        }
        var sums: [String: Double] = [:]
        var total = 0.0
        for value in values {
            sums[value.series, default: 0] += value.amountUSD
            total += value.amountUSD
        }
        guard total.isFinite, sums.values.allSatisfy(\.isFinite) else {
            parts = []; totalUSD = nil; return
        }
        let unsorted: [Part] = sums.map { Part(name: $0.key, usd: $0.value) }
        parts = unsorted.sorted {
            if abs($0.usd) == abs($1.usd) { return $0.name < $1.name }
            return abs($0.usd) > abs($1.usd)
        }
        totalUSD = total
    }
}

struct ActivityEarningsGraphic: View {
    let values: [ActivityChartValue]
    let buckets: [ActivityBucket]
    let color: (String) -> Color

    private var composition: EarningsComposition { EarningsComposition(values: values) }
    private var recorded: Int { buckets.filter { $0.totals != nil }.count }
    private var jobs: Decimal { buckets.compactMap(\.totals).reduce(Decimal(0)) { $0 + Decimal($1.jobs) } }

    var body: some View {
        let composition = composition
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 24) {
                total(composition)
                distribution(composition).frame(width: 110, height: 110)
                breakdown(composition).frame(maxWidth: 380, alignment: .leading)
                Spacer(minLength: 0)
                observations.frame(width: 140)
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 20) {
                    total(composition)
                    Spacer(minLength: 0)
                    distribution(composition).frame(width: 96, height: 96)
                }
                HStack(alignment: .top, spacing: 20) {
                    breakdown(composition).frame(maxWidth: .infinity, alignment: .leading)
                    observations.frame(width: 130)
                }
            }
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Recorded earnings summary")
    }

    private func total(_ composition: EarningsComposition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Recorded gross", systemImage: "banknote").font(.caption).foregroundStyle(.secondary)
            Text(composition.totalUSD.map { ActivityAmountPresentation.hourlyAmount($0) } ?? "—")
                .font(.system(size: 30, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.8)
                .accessibilityIdentifier("activity.earnings.total")
            Label("Local ledger", systemImage: "internaldrive").font(.caption2).foregroundStyle(.secondary)
        }
        .help("Sum of displayed recorded earnings, including signed corrections. Hidden rewards are excluded. Missing history remains unknown; this is not proof of complete account income or a payout.")
        .fixedSize(horizontal: true, vertical: false)
    }

    @ViewBuilder private func distribution(_ composition: EarningsComposition) -> some View {
        if composition.canShowShare {
            Chart(composition.parts) { part in
                SectorMark(angle: .value("Recorded USD", part.usd), innerRadius: .ratio(0.76), angularInset: 2)
                    .foregroundStyle(color(part.name))
                    .accessibilityLabel(part.name)
                    .accessibilityValue(ActivityAmountPresentation.hourlyAmount(part.usd))
            }
            .chartLegend(.hidden)
            .chartBackground { _ in
                Image(systemName: "chart.pie").font(.title2).foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        } else if composition.parts.contains(where: { $0.usd != 0 }) {
            // Negative corrections cannot truthfully be a slice of a positive pie.
            Chart(composition.parts) { part in
                BarMark(x: .value("Signed USD", part.usd), y: .value("Series", part.name))
                    .foregroundStyle(color(part.name))
                    .accessibilityLabel(part.name)
                    .accessibilityValue(ActivityAmountPresentation.hourlyAmount(part.usd))
            }.chartLegend(.hidden).chartXAxis(.hidden).chartYAxis(.hidden)
        } else {
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 10)
                Image(systemName: composition.totalUSD == nil ? "questionmark" : "banknote")
                    .font(.title2).foregroundStyle(.secondary)
            }.accessibilityLabel(composition.totalUSD == nil ? "No recorded earnings" : "Recorded zero earnings")
        }
    }

    private func breakdown(_ composition: EarningsComposition) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(composition.parts) { part in
                HStack(spacing: 7) {
                    Circle().fill(color(part.name)).frame(width: 7, height: 7).accessibilityHidden(true)
                    Text(ModelDisplayName.short(part.name)).lineLimit(1).help(part.name)
                    Spacer(minLength: 6)
                    Text(ActivityAmountPresentation.hourlyAmount(part.usd)).monospacedDigit()
                }.font(.caption).accessibilityElement(children: .combine)
            }
        }
    }

    private var observations: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(jobs.formatted(.number) + " jobs", systemImage: "checkmark.circle").font(.headline)
            HStack(spacing: 6) {
                Image(systemName: "clock")
                Text("\(recorded)/\(buckets.count) intervals").monospacedDigit()
            }.font(.caption).foregroundStyle(.secondary)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(Color.accentColor.opacity(0.7))
                        .frame(width: geometry.size.width * (buckets.isEmpty ? 0 : Double(recorded) / Double(buckets.count)))
                }
            }.frame(height: 5).accessibilityHidden(true)
        }
        .help("\(recorded) of \(buckets.count) displayed calendar intervals contain ledger entries. Other intervals are unknown, including future intervals. Entries do not establish complete account coverage.")
        .accessibilityElement(children: .combine)
    }
}
