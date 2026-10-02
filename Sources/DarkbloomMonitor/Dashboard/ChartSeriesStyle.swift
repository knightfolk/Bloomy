import Charts
import SwiftUI

/// Color stays useful, but a stable number, shape, and stroke also identify
/// each series. Build this from the full domain so filtering does not remap it.
struct ChartSeriesStyle: Identifiable {
    let series: String
    let number: Int
    let symbol: ChartSeriesSymbol
    let dash: [CGFloat]

    var id: String { series }
    var stroke: StrokeStyle { StrokeStyle(lineWidth: 1.6, dash: dash) }
}

enum ChartSeriesSymbol: Int, CaseIterable {
    case circle, square, triangle, diamond, pentagon, plus, cross, asterisk

    var shape: BasicChartSymbolShape {
        switch self {
        case .circle: .circle
        case .square: .square
        case .triangle: .triangle
        case .diamond: .diamond
        case .pentagon: .pentagon
        case .plus: .plus
        case .cross: .cross
        case .asterisk: .asterisk
        }
    }
}

struct ChartSeriesStyles {
    let entries: [ChartSeriesStyle]
    private let bySeries: [String: ChartSeriesStyle]

    init(domain: [String]) {
        var seen = Set<String>()
        let unique = domain.filter { seen.insert($0).inserted }
        let dashes: [[CGFloat]] = [[], [6, 3], [2, 3], [7, 3, 2, 3]]
        entries = unique.enumerated().map { index, series in
            ChartSeriesStyle(series: series, number: index + 1,
                symbol: ChartSeriesSymbol.allCases[index % ChartSeriesSymbol.allCases.count],
                dash: dashes[index % dashes.count])
        }
        bySeries = Dictionary(uniqueKeysWithValues: entries.map { ($0.series, $0) })
    }

    subscript(series: String) -> ChartSeriesStyle {
        bySeries[series] ?? ChartSeriesStyle(series: series, number: 0, symbol: .circle, dash: [])
    }

    func visibleEntries(in series: [String]) -> [ChartSeriesStyle] {
        let visible = Set(series)
        return entries.filter { visible.contains($0.series) }
    }
}

struct ChartSeriesLegend: View {
    let entries: [ChartSeriesStyle]
    var showsLine = false
    let color: (String) -> Color

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 6) {
            ForEach(entries) { entry in
                HStack(spacing: 5) {
                    if showsLine {
                        ChartLegendLine().stroke(color(entry.series), style: entry.stroke)
                            .frame(width: 22, height: 10)
                            .accessibilityHidden(true)
                    }
                    entry.symbol.shape.fill(color(entry.series))
                        .frame(width: 9, height: 9)
                        .accessibilityHidden(true)
                    Text("\(entry.number)").monospacedDigit().fontWeight(.semibold)
                    Text(ModelDisplayName.short(entry.series))
                        .lineLimit(1).truncationMode(.middle)
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.series)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Series \(entry.number), \(entry.series)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart series")
    }
}

private struct ChartLegendLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

struct ChartSeriesBadge: View {
    let number: Int
    var body: some View {
        Text("\(number)")
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .padding(.horizontal, 3)
            .frame(minWidth: 14, minHeight: 14)
            .background(.background, in: RoundedRectangle(cornerRadius: 3))
            .accessibilityHidden(true)
    }
}

/// Select only one existing, nonzero mark per series for a small direct label.
/// Prefer its largest magnitude, where the label has the most room to fit.
enum ChartSeriesCueSelection {
    /// Area annotations use the very same series and bucket values as the
    /// plotted marks. Totals-only clients can attribute a selected model here
    /// even when the separate bar-segment fallback still names aggregate Work.
    static func areaCues(_ values: [ActivityChartValue]) -> [ActivityChartSegment] {
        var cursors: [Date: (positive: Double, negative: Double)] = [:]
        var selected: [String: ActivityChartSegment] = [:]
        var seriesOrder: [String] = []
        for value in values where value.amountUSD.isFinite && value.amountUSD != 0 {
            var cursor = cursors[value.interval.start] ?? (positive: 0, negative: 0)
            let beginning = value.amountUSD > 0 ? cursor.positive : cursor.negative
            let end = beginning + value.amountUSD
            guard end.isFinite else { continue }
            if value.amountUSD > 0 { cursor.positive = end } else { cursor.negative = end }
            cursors[value.interval.start] = cursor
            let segment = ActivityChartSegment(interval: value.interval, series: value.series,
                startUSD: beginning, endUSD: end)
            if let previous = selected[value.series] {
                if abs(value.amountUSD) > abs(previous.endUSD - previous.startUSD) {
                    selected[value.series] = segment
                }
            } else {
                seriesOrder.append(value.series)
                selected[value.series] = segment
            }
        }
        return seriesOrder.compactMap { selected[$0] }
    }

    static func values(_ values: [ActivityChartValue]) -> Set<String> {
        strongest(values.map { ($0.id, $0.series, abs($0.amountUSD)) })
    }

    static func segments(_ segments: [ActivityChartSegment]) -> Set<String> {
        strongest(segments.map { ($0.id, $0.series, abs($0.endUSD - $0.startUSD)) })
    }

    private static func strongest(_ candidates: [(id: String, series: String, magnitude: Double)]) -> Set<String> {
        var selected: [String: (id: String, magnitude: Double)] = [:]
        for candidate in candidates where candidate.magnitude.isFinite && candidate.magnitude > 0 {
            if candidate.magnitude > (selected[candidate.series]?.magnitude ?? 0) {
                selected[candidate.series] = (candidate.id, candidate.magnitude)
            }
        }
        return Set(selected.values.map(\.id))
    }
}
