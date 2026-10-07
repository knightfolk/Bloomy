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
    var activity: PerformanceActivityHistory? = nil
    private var rowOffset: Int { activity == nil ? 0 : 1 }
    @State private var rawSelectedDate: Date?
    @State private var inspectedDate: Date?
    private var selection: ModelVisitTimelineSelection? {
        ModelVisitTimelineSelection(date: inspectedDate, data: data, activity: activity)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Chart {
                if let selection {
                    RuleMark(x: .value("Inspected moment", selection.date))
                        .foregroundStyle(Color.primary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .accessibilityHidden(true)
                }
                if let activity {
                    ForEach(activity.segments) { segment in
                        RectangleMark(xStart: .value("First activity reading", segment.start),
                                      xEnd: .value("Last activity reading", segment.end),
                                      y: .value("Model row", 0), height: .fixed(12))
                            .foregroundStyle(segment.evidence.color.opacity(0.3))
                        PointMark(x: .value("Activity evidence", segment.start.addingTimeInterval(segment.end.timeIntervalSince(segment.start) / 2)),
                                  y: .value("Model row", 0))
                            .symbol(segment.evidence.shape).symbolSize(18)
                            .foregroundStyle(segment.evidence.color)
                    }
                }
                ForEach(data.entries) { entry in
                    let style = ModelVisitEvidenceStyle(entry.visit)
                    let row = (data.modelPositions[entry.visit.model] ?? 0) + rowOffset
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
            .chartYScale(domain: -0.5...(Double(max(1, data.models.count + rowOffset)) - 0.5))
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(0..<max(1, data.models.count + rowOffset))) { value in
                    AxisValueLabel(centered: false) {
                        if let row = value.as(Int.self), rowOffset == 1 && row == 0 {
                            Text("Provider · all").font(.caption).help("Provider-wide activity, independent of the model and visit filters")
                        } else if let row = value.as(Int.self), data.models.indices.contains(row - rowOffset) {
                            let model = data.models[row - rowOffset]
                            Text(ModelDisplayName.short(model)).font(.caption)
                                .lineLimit(1).truncationMode(.middle)
                                .help(model)
                        }
                    }
                }
            }
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
            .chartLegend(.hidden)
            .chartXSelection(value: $rawSelectedDate)
            .chartGesture { proxy in
                DragGesture(minimumDistance: 0)
                    .onChanged { proxy.selectXValue(at: $0.location.x) }
            }
            .onChange(of: rawSelectedDate) { _, date in
                if let date { inspectedDate = date }
            }
            .onChange(of: data.range) { _, _ in
                if selection == nil {
                    inspectedDate = nil
                    rawSelectedDate = nil
                }
            }
            .frame(height: CGFloat(max(1, data.models.count + rowOffset)) * 32 + 32)
            // Charts can aggregate coincident point observations into a series
            // summary. Expose each retained visit explicitly, including points.
            .accessibilityRepresentation {
                VStack {
                    if let activity {
                        ForEach(activity.segments) { segment in
                            Button {
                                rawSelectedDate = segment.start
                                inspectedDate = segment.start
                            } label: { Text(activityLabel(segment)) }
                                .accessibilityLabel(activityLabel(segment))
                                .accessibilityHint("Inspect this activity interval")
                                .accessibilityIdentifier("activity.metrics.activity.\(segment.id.uuidString)")
                        }
                    }
                    ForEach(data.entries) { entry in
                        Button {
                            rawSelectedDate = entry.start
                            inspectedDate = entry.start
                        } label: { accessibilityLabel(entry) }
                            .accessibilityLabel(accessibilityLabel(entry))
                            .accessibilityHint("Inspect this visit observation")
                            .accessibilityIdentifier("activity.metrics.visit.\(entry.id.uuidString)")
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("activity.metrics.visits.timeline")
                .accessibilityLabel("Observed model residence. \(withoutWorkOnly ? "Only visits without observed work are displayed." : "Retained visits for the selected models are displayed.") Visit evidence does not mean continuous inference. Blank time has no displayed visit; it may be unobserved, filtered out, or outside retained history.")
            }

            selectionInspector

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
            if let activity {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 125), alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(PerformanceActivityHistory.Evidence.allCases, id: \.self) { evidence in
                        Label { Text(evidence.title).foregroundStyle(.secondary) } icon: {
                            Image(systemName: evidence.symbol).foregroundStyle(evidence.color).frame(width: 14)
                        }.font(.caption)
                    }
                }
                Text("Provider row covers all models · activity between readings is approximate\(activity.totalSegmentCount > activity.segments.count ? " · latest \(activity.segments.count) of \(activity.totalSegmentCount) segments" : "")")
                    .font(.caption2).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .help("Bands show observation times, not exact loading or inference times. Symbols describe evidence from the entire visit. Blank time can be unobserved, filtered out, or outside retained visit history. A last-loaded visit may already have ended. Short work between readings can be missed.")
    }

    private var selectionInspector: some View {
        ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 5) {
            if let selection {
                HStack(alignment: .firstTextBaseline) {
                    Label(selection.date.formatted(date: .abbreviated, time: .standard), systemImage: "scope")
                        .font(.caption.weight(.medium)).monospacedDigit()
                        .accessibilityIdentifier("activity.metrics.inspectedTime")
                    Spacer(minLength: 8)
                    Button {
                        inspectedDate = nil
                        rawSelectedDate = nil
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .accessibilityLabel("Clear inspected time")
                        .accessibilityIdentifier("activity.metrics.inspection.clear")
                        .help("Clear the selected moment")
                }
                if selection.visits.isEmpty {
                    Label("No displayed visit at this time", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(selection.visits) { entry in
                        let style = ModelVisitEvidenceStyle(entry.visit)
                        Label {
                            Text("\(ModelDisplayName.short(entry.visit.model)) · visit: \(style.title)")
                                .help(entry.visit.model)
                        } icon: { Image(systemName: style.symbol).foregroundStyle(style.color) }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(accessibilityLabel(entry))
                        .accessibilityIdentifier("activity.metrics.inspection.visit.\(entry.id.uuidString)")
                    }
                }
                if let segment = selection.activity {
                    Label {
                        Text("Provider interval · all: \(segment.evidence.title)")
                    } icon: { Image(systemName: segment.evidence.symbol).foregroundStyle(segment.evidence.color) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(activityLabel(segment))
                    .accessibilityIdentifier("activity.metrics.inspection.activity")
                    Text("\(segment.start.formatted(date: .abbreviated, time: .standard)) – \(segment.end.formatted(date: .abbreviated, time: .standard))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                } else if activity != nil {
                    Label("No displayed provider activity at this time", systemImage: "minus.circle")
                        .foregroundStyle(.secondary)
                }
                Text("Visit evidence describes the full visit; activity is approximate between readings.")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Label("Click or drag a time to inspect", systemImage: "scope")
                    .foregroundStyle(.secondary)
                Text("Visit evidence and all-model activity stay separate.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(height: 128)
        .padding(10)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("activity.metrics.inspection")
    }

    private func activityLabel(_ segment: PerformanceActivityHistory.Segment) -> String {
        "All-model provider activity, \(segment.start.formatted(date: .abbreviated, time: .standard)) to \(segment.end.formatted(date: .abbreviated, time: .standard)); \(segment.evidence.title). Based on adjacent readings, not exact request duration or payment."
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

private extension PerformanceActivityHistory.Evidence {
    var title: String {
        switch self {
        case .active: "Active readings"
        case .betweenReadings: "Work between readings"
        case .idle: "Idle readings"
        case .uncertain: "Activity uncertain"
        }
    }
    var symbol: String {
        switch self {
        case .active: "circle.fill"
        case .betweenReadings: "diamond.fill"
        case .idle: "square.fill"
        case .uncertain: "triangle.fill"
        }
    }
    var shape: BasicChartSymbolShape {
        switch self {
        case .active: .circle
        case .betweenReadings: .diamond
        case .idle: .square
        case .uncertain: .triangle
        }
    }
    var color: Color {
        switch self {
        case .active: .teal
        case .betweenReadings: .purple
        case .idle: .secondary
        case .uncertain: .orange
        }
    }
}
