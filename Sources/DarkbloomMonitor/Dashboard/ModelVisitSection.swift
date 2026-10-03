import DarkbloomTelemetry
import SwiftUI

struct ModelVisitSection: View {
    let visits: [ModelVisit]
    let withoutWorkVisits: [ModelVisit]
    let summary: ModelVisitSummary
    @State private var withoutWorkOnly = false
    @State private var visibleLimit = 8

    init(visits: [ModelVisit], withoutWorkVisits: [ModelVisit]? = nil, summary: ModelVisitSummary? = nil) {
        self.visits = visits
        self.withoutWorkVisits = withoutWorkVisits ?? visits.filter { $0.outcome == .noObservedWork }
        self.summary = summary ?? ModelVisitSummary(visits: visits)
    }
    private var displayed: [ModelVisit] {
        Array((withoutWorkOnly ? withoutWorkVisits : visits).suffix(visibleLimit).reversed())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    heading
                    Spacer(minLength: 10)
                    filter
                }
                VStack(alignment: .leading, spacing: 8) { heading; filter }
            }
            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.swap").foregroundStyle(.orange)
                Text("\(summary.completedNoObservedWorkCount) \(summary.completedNoObservedWorkCount == 1 ? "visit" : "visits") without observed work")
                    .font(.callout.weight(.medium))
                Spacer(minLength: 0)
                Text(Self.duration(summary.completedNoObservedWorkSeconds))
                    .font(.callout.weight(.semibold)).monospacedDigit()
            }
            .padding(10)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityElement(children: .combine)

            if displayed.isEmpty {
                Text(withoutWorkOnly ? "No completed visits without observed work in this history." : "Model visits appear as fresh loaded-model observations arrive.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(displayed) { visit in
                ModelVisitRow(visit: visit)
            }
            if (withoutWorkOnly ? withoutWorkVisits.count : visits.count) > visibleLimit {
                Button("Show more visits") { visibleLimit += 12 }
                    .controlSize(.small)
                    .modifier(MetricsKeyboardReveal(target: .moreVisits))
            }
            Text("Observed time; gaps and shared residency stay uncertain. Short requests between readings may be missed.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if summary.visitCount > 500 {
                Text("Counts use all visits; each filter lists its latest 500.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Model visits and switches without observed work")
    }

    private var heading: some View { Label("Model visits", systemImage: "clock.arrow.circlepath").font(.headline) }
    private var filter: some View {
        Picker("Visit filter", selection: $withoutWorkOnly) {
            Text("All visits").tag(false)
            Text("Without work").tag(true)
        }
        .labelsHidden().pickerStyle(.segmented).frame(width: 225)
        .onChange(of: withoutWorkOnly) { _, _ in visibleLimit = 8 }
        .modifier(MetricsKeyboardReveal(target: .visitFilter))
    }

    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "Unknown" }
        let value = Int(seconds.rounded(.down))
        if value >= 3_600 { return "\(value / 3_600)h \(value % 3_600 / 60)m" }
        if value >= 60 { return "\(value / 60)m \(value % 60)s" }
        return "\(value)s"
    }
}

struct ModelVisitRow: View {
    let visit: ModelVisit

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { model; Spacer(minLength: 4); evidence; elapsed }
            VStack(alignment: .leading, spacing: 6) {
                HStack { model; Spacer(minLength: 4); elapsed }
                evidence
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .help("\(visit.model) · \(visit.observedStart.formatted()) to \(visit.observedEnd.formatted()) · \(ModelVisitSection.duration(visit.coveredSeconds)) covered · \(ModelVisitSection.duration(visit.observedIdleSeconds)) observed idle")
    }

    private var model: some View {
        HStack(spacing: 8) {
            Group {
                if let image = DarkbloomLogoAsset.modelImage(family: ModelFamilyIcon.select(status: .online, activeModel: visit.model)) {
                    Image(nsImage: image)
                        .resizable()
                        .renderingMode(.template)
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20, height: 20)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(ModelDisplayName.short(visit.model)).font(.callout.weight(.medium))
                    .lineLimit(1).truncationMode(.middle)
                Text("\(visit.observedStart.formatted(date: .abbreviated, time: .shortened)) – \(visit.observedEnd.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private var elapsed: some View {
        Text(ModelVisitSection.duration(visit.durationSeconds))
            .font(.callout.weight(.semibold)).monospacedDigit().fixedSize()
            .frame(minWidth: 50, alignment: .trailing)
    }

    private var evidence: some View {
        Label(statusText, systemImage: statusSymbol)
            .font(.caption).foregroundStyle(statusColor)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(width: 150, height: 22, alignment: .leading)
            .background(statusColor.opacity(0.1), in: Capsule())
            .fixedSize()
    }
    var statusText: String {
        switch visit.outcome {
        case .worked: "Work observed"
        case .noObservedWork: "No work observed"
        case .unknown: "Uncertain"
        case .stillLoaded: visit.workEvidence == .observedWork ? "Last loaded · worked" : "Loaded at last reading"
        }
    }
    private var statusSymbol: String {
        switch visit.outcome {
        case .worked: "checkmark"
        case .noObservedWork: "minus"
        case .unknown: "questionmark"
        case .stillLoaded: "circle.fill"
        }
    }
    private var statusColor: Color {
        switch visit.outcome {
        case .worked: .green
        case .noObservedWork: .orange
        case .unknown: .secondary
        case .stillLoaded: .blue
        }
    }
}
