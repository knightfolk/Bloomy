import Charts
import DarkbloomTelemetry
import SwiftUI

/// Display geometry only. Visit analysis and work attribution stay upstream.
struct ModelVisitTimelineData {
    struct Entry: Identifiable {
        let visit: ModelVisit
        let start: Date
        let end: Date
        var id: UUID { visit.id }
        var isPoint: Bool { start == end }
        var midpoint: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    }
    let range: DateInterval
    let entries: [Entry]
    let models: [String]
    let modelPositions: [String: Int]

    init(visits: [ModelVisit], range: DateInterval) {
        self.range = range
        entries = range.duration > 0 ? visits.compactMap { visit in
            guard visit.observedEnd >= visit.observedStart,
                  visit.observedStart < range.end, visit.observedEnd >= range.start else { return nil }
            // A completed visit ending at the opening boundary has no residence
            // in this period. A point observation at the boundary does.
            guard visit.observedEnd > range.start || visit.durationSeconds == 0 else { return nil }
            return Entry(visit: visit, start: max(visit.observedStart, range.start),
                         end: min(visit.observedEnd, range.end))
        } : []
        var seen = Set<String>()
        models = entries.compactMap { seen.insert($0.visit.model).inserted ? $0.visit.model : nil }
        modelPositions = Dictionary(uniqueKeysWithValues: models.enumerated().map { ($0.element, $0.offset) })
    }

    static func inferredRange(visits: [ModelVisit]) -> DateInterval? {
        guard let start = visits.map(\.observedStart).min(),
              let end = visits.map(\.observedEnd).max(), end > start else { return nil }
        return DateInterval(start: start, end: end)
    }
}

enum ModelVisitEvidenceStyle: String, CaseIterable, Identifiable {
    case worked, noWork, uncertain, lastLoaded
    var id: Self { self }
    init(_ visit: ModelVisit) {
        switch visit.outcome {
        case .worked: self = .worked
        case .noObservedWork: self = .noWork
        case .unknown: self = .uncertain
        case .stillLoaded: self = .lastLoaded
        }
    }
    var title: String {
        switch self {
        case .worked: "Work observed"
        case .noWork: "No work observed"
        case .uncertain: "Uncertain"
        case .lastLoaded: "Last loaded"
        }
    }
    var symbol: String {
        switch self {
        case .worked: "circle.fill"
        case .noWork: "square.fill"
        case .uncertain: "diamond.fill"
        case .lastLoaded: "triangle.fill"
        }
    }
    var shape: BasicChartSymbolShape {
        switch self {
        case .worked: .circle
        case .noWork: .square
        case .uncertain: .diamond
        case .lastLoaded: .triangle
        }
    }
    var color: Color {
        switch self {
        case .worked: .green
        case .noWork: .orange
        case .uncertain: .secondary
        case .lastLoaded: .blue
        }
    }
}

struct ModelVisitTimeline: View {
    let data: ModelVisitTimelineData
    var withoutWorkOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                ForEach(data.entries) { entry in
                    let style = ModelVisitEvidenceStyle(entry.visit)
                    let row = data.modelPositions[entry.visit.model] ?? 0
                    if entry.isPoint {
                        PointMark(x: .value("Observed time", entry.start),
                                  y: .value("Model row", row))
                            .symbol(style.shape).symbolSize(36)
                            .foregroundStyle(style.color)
                            .accessibilityLabel(accessibilityLabel(entry))
                    } else {
                        RectangleMark(xStart: .value("First observation", entry.start),
                                      xEnd: .value("Last observation", entry.end),
                                      y: .value("Model row", row), height: .fixed(18))
                            .foregroundStyle(style.color.opacity(0.22))
                            .accessibilityLabel(accessibilityLabel(entry))
                        PointMark(x: .value("Visit evidence", entry.midpoint),
                                  y: .value("Model row", row))
                            .symbol(style.shape).symbolSize(20).foregroundStyle(style.color)
                            .accessibilityHidden(true)
                    }
                    if entry.visit.isStartTruncated || entry.start != entry.visit.observedStart {
                        PointMark(x: .value("Uncertain first boundary", entry.start),
                                  y: .value("Model row", row))
                            .symbol(.cross).symbolSize(12)
                            .foregroundStyle(style.color)
                            .accessibilityHidden(true)
                    }
                    if entry.visit.isEndTruncated || entry.end != entry.visit.observedEnd {
                        PointMark(x: .value("Uncertain last boundary", entry.end),
                                  y: .value("Model row", row))
                            .symbol(.cross).symbolSize(12)
                            .foregroundStyle(style.color)
                            .accessibilityHidden(true)
                    }
                }
            }
            .chartXScale(domain: data.range.start...data.range.end)
            .chartYScale(domain: -0.5...(Double(max(1, data.models.count)) - 0.5))
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(data.models.indices)) { value in
                    AxisValueLabel(centered: false) {
                        if let index = value.as(Int.self), data.models.indices.contains(index) {
                            let model = data.models[index]
                            Text(ModelDisplayName.short(model)).font(.caption)
                                .lineLimit(1).truncationMode(.middle)
                                .help(model)
                        }
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartLegend(.hidden)
            .frame(height: CGFloat(max(1, data.models.count)) * 32 + 32)
            // Charts can aggregate coincident point observations into a series
            // summary. Expose each retained visit explicitly, including points.
            .accessibilityRepresentation {
                VStack {
                    ForEach(data.entries) { entry in
                        accessibilityLabel(entry)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilityLabel(entry))
                            .accessibilityIdentifier("activity.metrics.visit.\(entry.id.uuidString)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activity.metrics.visits.timeline")
                .accessibilityLabel("Observed model residence. \(withoutWorkOnly ? "Only visits without observed work are displayed." : "Retained visits for the selected models are displayed.") Visit evidence does not mean continuous inference. Blank time has no displayed visit; it may be unobserved, filtered out, or outside retained history.")
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 6) {
                ForEach(ModelVisitEvidenceStyle.allCases) { style in
                    Label { Text(style.title).foregroundStyle(.secondary) } icon: {
                        Image(systemName: style.symbol).foregroundStyle(style.color).frame(width: 14)
                    }
                    .font(.caption)
                }
            }
            Text("\(withoutWorkOnly ? "Without-work visits only" : "Observed residence") · blank time has no displayed visit · crosses mark uncertain boundaries")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help("Bands show observation times, not exact loading or inference times. Symbols describe evidence from the entire visit. Blank time can be unobserved, filtered out, or outside retained visit history. A last-loaded visit may already have ended. Short work between readings can be missed.")
    }

    private func accessibilityLabel(_ entry: ModelVisitTimelineData.Entry) -> Text {
        let visit = entry.visit
        let evidence = ModelVisitEvidenceStyle(visit).title
        let work = visit.isOpen && visit.workEvidence == .observedWork ? "; work observed during visit" : ""
        let start = visit.isStartTruncated || entry.start != visit.observedStart ? "; first boundary uncertain or clipped" : ""
        let end = visit.isEndTruncated || entry.end != visit.observedEnd ? "; last boundary uncertain or clipped" : ""
        return Text("\(visit.model), \(entry.start.formatted(date: .abbreviated, time: .standard)) to \(entry.end.formatted(date: .abbreviated, time: .standard)); \(evidence)\(work)\(start)\(end). Observed residence, not continuous inference.")
    }
}
