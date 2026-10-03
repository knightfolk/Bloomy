import Charts
import DarkbloomTelemetry
import SwiftUI

enum PerformanceMetricsPeriod: String, CaseIterable, Identifiable, Sendable {
    case last24Hours = "24 hours"
    case last7Days = "7 days"
    case last30Days = "30 days"

    var id: Self { self }
    var seconds: TimeInterval {
        switch self {
        case .last24Hours: 86_400
        case .last7Days: 7 * 86_400
        case .last30Days: 30 * 86_400
        }
    }

    func range(endingAt date: Date) -> DateInterval {
        DateInterval(start: date.addingTimeInterval(-seconds), end: date)
    }
}

enum MetricsRecordingFreshness {
    static func isCurrent(_ sample: PerformanceSample?, at now: Date, timelineDate: Date? = nil) -> Bool {
        guard let sample, sample.quality == .current,
              now.timeIntervalSinceReferenceDate.isFinite,
              timelineDate.map({ $0.timeIntervalSinceReferenceDate.isFinite }) ?? true else { return false }
        let age = now.timeIntervalSince(sample.observedAt)
        return age.isFinite && (0...90).contains(age)
    }

    static func status(_ sample: PerformanceSample?, storageError: String?, at now: Date, timelineDate: Date? = nil) -> String {
        if storageError != nil { return "Recording needs attention" }
        return isCurrent(sample, at: now, timelineDate: timelineDate) ? "Recording locally" : "Waiting for fresh measurements"
    }
}

struct PerformanceMetricsView: View {
    let history: PerformanceHistoryStore?
    var isVisible = true

    var body: some View {
        if let history {
            RecordedPerformanceMetricsView(history: history, isVisible: isVisible)
        } else {
            PerformanceMetricsContent(samples: [], recordingStartedAt: nil)
        }
    }
}

private struct RecordedPerformanceMetricsView: View {
    @ObservedObject var history: PerformanceHistoryStore
    let isVisible: Bool
    @State private var read = PerformanceMetricsRead.empty
    @State private var loading = false
    @State private var readError: String?
    @State private var period = PerformanceMetricsPeriod.last24Hours
    @State private var refreshID = 0

    var body: some View {
        TimelineView(MetricsTimelineSchedule(isVisible: isVisible)) { context in
            PerformanceMetricsContent(
                samples: read.samples,
                recordingStartedAt: history.recordingStartedAt,
                storageError: history.storageError ?? readError,
                loading: loading,
                isVisible: isVisible,
                // Reads can arrive between minute ticks. Judge their age against
                // render time; keep the tick as an explicit expiry dependency.
                now: Date(),
                timelineDate: context.date,
                readToken: read.token,
                readPeriod: read.period,
                onRefresh: { refreshID += 1 },
                onPeriodChange: { period = $0 }
            )
        }
        .task(id: PerformanceHistoryQuery(period: period, refreshID: refreshID, isVisible: isVisible)) {
            guard isVisible else { return }
            let requestedPeriod = period
            // Capture stays immediate; aggregate display work is coalesced.
            // Period changes, reopening, and explicit refresh start a new task.
            await MetricsRefreshLoop.run(interval: .seconds(30)) {
                loading = read.samples.isEmpty || read.period != requestedPeriod
                do {
                    // Retain every model so summaries cannot bridge intervening
                    // nonmatching observations or uncertain boundaries.
                    let endingAt = Date()
                    read = try await read.refreshing(endingAt: endingAt, period: requestedPeriod) {
                        try await history.samples(in: requestedPeriod.range(endingAt: endingAt))
                    }
                    readError = nil
                } catch {
                    guard !Task.isCancelled else { return }
                    readError = "Local metrics could not be read."
                }
                loading = false
            }
        }
    }
}

/// Retained hidden content gets an initial date, without scheduling wake-ups.
struct MetricsTimelineSchedule: TimelineSchedule {
    let isVisible: Bool
    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(nextDate: startDate, repeats: isVisible)
    }
    struct Entries: Sequence, IteratorProtocol {
        var nextDate: Date?
        let repeats: Bool
        mutating func next() -> Date? {
            guard let date = nextDate else { return nil }
            nextDate = repeats ? date.addingTimeInterval(60) : nil
            return date
        }
    }
}

/// Value-driven content also supports synthetic native rendering evidence.
struct PerformanceMetricsContent: View {
    let samples: [PerformanceSample]
    let recordingStartedAt: Date?
    var storageError: String? = nil
    var loading = false
    var isVisible = true
    var now = Date()
    var timelineDate: Date?
    var readToken: PerformanceMetricsReadToken?
    var readPeriod: PerformanceMetricsPeriod?
    var onRefresh: (() -> Void)? = nil
    var onPeriodChange: (PerformanceMetricsPeriod) -> Void = { _ in }
    @State private var period = PerformanceMetricsPeriod.last24Hours
    @State private var model: String?
    @State private var showsRecordingDetails = false
    @State private var rendered = PerformanceMetricsRender.empty
    @State private var initialAnalysisEndingAt: Date

    init(
        samples: [PerformanceSample], recordingStartedAt: Date?, storageError: String? = nil,
        loading: Bool = false, isVisible: Bool = true, now: Date = Date(), timelineDate: Date? = nil,
        readToken: PerformanceMetricsReadToken? = nil, readPeriod: PerformanceMetricsPeriod? = nil,
        initialPeriod: PerformanceMetricsPeriod = .last24Hours, onRefresh: (() -> Void)? = nil,
        onPeriodChange: @escaping (PerformanceMetricsPeriod) -> Void = { _ in }
    ) {
        self.samples = samples
        self.recordingStartedAt = recordingStartedAt
        self.storageError = storageError
        self.loading = loading
        self.isVisible = isVisible
        self.now = now
        self.timelineDate = timelineDate
        self.readToken = readToken
        self.readPeriod = readPeriod
        _period = State(initialValue: initialPeriod)
        _initialAnalysisEndingAt = State(initialValue: now)
        self.onRefresh = onRefresh
        self.onPeriodChange = onPeriodChange
    }

    var analysisQuery: PerformanceMetricsQuery {
        // Value-driven callers have no read generation. New observations may
        // advance their window, while freshness-label time alone must not.
        let inputEndingAt = max(initialAnalysisEndingAt, samples.last?.observedAt ?? initialAnalysisEndingAt)
        return PerformanceMetricsQuery(
            period: readPeriod ?? period, model: model, count: samples.count, lastID: samples.last?.id,
            readToken: readToken ?? PerformanceMetricsReadToken(generation: 0, endingAt: inputEndingAt),
            isVisible: isVisible
        )
    }
    private var presentation: PerformanceMetricsSnapshot { rendered.snapshot }
    private var renderedQuery: PerformanceMetricsQuery { rendered.query(pending: analysisQuery) }
    private var range: DateInterval { renderedQuery.range }
    private var summary: PerformanceSummary { presentation.summary }
    private var models: [String] { presentation.models }
    private var ratePoints: [PerformanceRatePoint] { presentation.ratePoints }
    private var transitions: [PerformanceModelTransition] { presentation.transitions }

    var retainedPeriodNotice: String? {
        let shownPeriod = rendered.completedQuery?.period ?? readPeriod
        guard let shownPeriod, shownPeriod != period else { return nil }
        return "Showing the last \(shownPeriod.rawValue) until results for \(period.rawValue) are available."
    }

    private var retainedModelNotice: String? {
        guard let completed = rendered.completedQuery, completed.model != model else { return nil }
        let previous = completed.model.map(ModelDisplayName.short) ?? "All models"
        let requested = model.map(ModelDisplayName.short) ?? "All models"
        return "Showing \(previous) until results for \(requested) are ready."
    }

    private var filterAnalysisPending: Bool {
        guard let completed = rendered.completedQuery else { return true }
        return completed.period != analysisQuery.period || completed.model != analysisQuery.model
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    controls
                    recordingHealth
                    if let retainedPeriodNotice {
                        Text(retainedPeriodNotice).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("activity.metrics.retainedPeriod")
                    }
                    if let retainedModelNotice {
                        Text(retainedModelNotice).font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if loading || filterAnalysisPending {
                        ProgressView(loading ? "Reading local metrics…" : "Updating metrics…").font(.callout)
                    }
                    if presentation.sampleCount == 0 {
                        if !loading && !filterAnalysisPending {
                            ContentUnavailableView(
                                "Metrics are accumulating",
                                systemImage: "waveform.path.ecg",
                                description: Text("Local recording runs while Bloomy is open. Covered time and model speed appear as fresh measurements arrive.")
                            )
                            .frame(minHeight: 160)
                        }
                    } else {
                        summaryGrid
                        ModelVisitSection(visits: presentation.visits, withoutWorkVisits: presentation.withoutWorkVisits, summary: presentation.visitSummary)
                        speedChart
                        modelTimeline
                    }
                    recordingDetails
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.automatic)
            .environment(\.metricsFocusReveal, { target in reader.scrollTo(target, anchor: .center) })
        }
        .onChange(of: period) { _, value in onPeriodChange(value) }
        .task(id: analysisQuery) {
            guard isVisible else { return }
            let input = samples
            let query = analysisQuery
            guard let result = await PerformanceMetricsAnalysis.make(samples: input, range: query.range, model: query.model), !Task.isCancelled else { return }
            rendered = PerformanceMetricsRender(snapshot: result, completedQuery: query)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                periodPicker
                Spacer(minLength: 8)
                modelPicker
            }
            VStack(alignment: .leading, spacing: 10) {
                periodPicker
                modelPicker
            }
        }
        .controlSize(.regular)
    }

    private var periodPicker: some View {
        Picker("Metrics period", selection: $period) {
            ForEach(PerformanceMetricsPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 240)
        .modifier(MetricsKeyboardReveal(target: .period))
    }

    private var modelPicker: some View {
        Picker("Model", selection: $model) {
            Text("All models").tag(String?.none)
            ForEach(models, id: \.self) { name in
                Text(ModelDisplayName.short(name)).tag(Optional(name))
            }
            if let model, !models.contains(model) {
                Text(ModelDisplayName.short(model)).tag(Optional(model))
            }
        }
        .frame(maxWidth: 230, alignment: .leading)
        .help(model ?? "All observed models")
        .modifier(MetricsKeyboardReveal(target: .model))
    }

    private var recordingHealth: some View {
        let last = presentation.latest
        let isCurrent = storageError == nil && MetricsRecordingFreshness.isCurrent(last, at: now, timelineDate: timelineDate)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: storageError != nil ? "exclamationmark.triangle" : isCurrent ? "record.circle" : "clock")
                        .foregroundStyle(storageError != nil ? Color.orange : isCurrent ? Color.green : Color.secondary)
                        .accessibilityHidden(true)
                    Text(MetricsRecordingFreshness.status(last, storageError: storageError, at: now, timelineDate: timelineDate))
                        .font(.callout.weight(.medium))
                    Spacer(minLength: 0)
                    Text("\(presentation.sampleCount.formatted()) samples")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                if let storageError {
                    Text(storageError).font(.caption).foregroundStyle(.secondary)
                } else if let last {
                    Text("Latest observation \(last.observedAt.formatted(date: .abbreviated, time: .standard)) · \(last.quality.rawValue)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            if let onRefresh {
                Button(action: onRefresh) { Label("Refresh metrics", systemImage: "arrow.clockwise") }
                    .labelStyle(.iconOnly)
                    .controlSize(.regular)
                    .accessibilityLabel("Refresh metrics")
                    .accessibilityIdentifier("activity.metrics.refresh")
                    .help("Read local metrics again. This view also refreshes every 30 seconds while open.")
                    .modifier(MetricsKeyboardReveal(target: .refresh))
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], alignment: .leading, spacing: 10) {
            metric("Covered time", symbol: "clock", value: duration(summary.coveredSeconds), detail: "\(coveragePercent) of \(renderedQuery.period.rawValue)")
            metric("Active time", symbol: "bolt", value: activeTime, detail: "Observed inference intervals")
            metric("Model speed", symbol: "speedometer", value: summary.averageTokenRate.map { "\(number($0)) tok/s" } ?? "Unknown", detail: "Average during measured work")
            metric("GPU use", symbol: "cpu", value: summary.averageGPUUtilizationPercent.map { "\(number($0))%" } ?? "Unknown", detail: "Whole Mac · covered intervals")
            metric("Requests completed", symbol: "checkmark.circle", value: summary.completedRequests.map { $0.formatted() } ?? "Unknown", detail: renderedQuery.model == nil ? "Provider-wide counter increases" : "Provider-wide · choose All models")
            metric("Tokens generated", symbol: "text.word.spacing", value: summary.generatedTokens.map { $0.formatted() } ?? "Unknown", detail: renderedQuery.model == nil ? "Provider-wide counter increases" : "Provider-wide · choose All models")
        }
    }

    private var coveragePercent: String {
        (min(1, summary.coveredSeconds / range.duration)).formatted(.percent.precision(.fractionLength(1)))
    }

    private var activeTime: String {
        guard summary.activeCoveredSeconds > 0 else { return "Unknown" }
        return duration(summary.activeSeconds)
    }

    private func metric(_ title: String, symbol: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Text(value).font(.title3.weight(.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
            Text(detail).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .topLeading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var speedChart: some View {
        let styles = ChartSeriesStyles(domain: models)
        let colors = models.map { model in
            let components = ActivityChartPalette.components(for: model)
            return Color(hue: components.hue, saturation: components.saturation, brightness: components.brightness)
        }
        let colorsByModel = Dictionary(uniqueKeysWithValues: zip(models, colors))
        return VStack(alignment: .leading, spacing: 8) {
            Label("Measured model speed", systemImage: "waveform.path").font(.headline)
            if ratePoints.isEmpty {
                Text("No attributed speed measurements in this period.")
                    .font(.callout).foregroundStyle(.secondary).frame(maxWidth: .infinity, minHeight: 110)
            } else {
                Chart(ratePoints) { point in
                    LineMark(x: .value("Observed", point.date), y: .value("Tokens per second", point.rate), series: .value("Measured run", point.run))
                        .foregroundStyle(by: .value("Model", point.model))
                        .lineStyle(by: .value("Model", point.model))
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Observed", point.date), y: .value("Tokens per second", point.rate))
                        .foregroundStyle(by: .value("Model", point.model))
                        .symbol(by: .value("Model", point.model))
                        .symbolSize(24)
                }
                .chartXScale(domain: range.start...range.end)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
                .chartYAxisLabel("tok/s")
                .chartSymbolScale(domain: styles.entries.map(\.series), range: styles.entries.map { $0.symbol.shape })
                .chartLineStyleScale(domain: styles.entries.map(\.series), range: styles.entries.map(\.stroke))
                .chartForegroundStyleScale(domain: models, range: colors)
                .chartLegend(.hidden)
                .frame(height: 190)
                ChartSeriesLegend(entries: styles.visibleEntries(in: ratePoints.map(\.model)),
                    showsLine: true, color: { colorsByModel[$0] ?? .secondary })
            }
            Text("Fresh observations only. Lines stop at unknown gaps, model changes, and provider restarts.")
                .font(.caption).foregroundStyle(.secondary)
            if presentation.chartWasReduced {
                Text("Chart shows up to 600 measured observations. Totals use all saved measurements.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Measured model speed in tokens per second by observation time")
    }

    private var modelTimeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Provider model history", systemImage: "arrow.triangle.swap").font(.headline)
                Spacer(minLength: 0)
                if presentation.transitionCount > 8 {
                    Text("Latest 8 of \(presentation.transitionCount)").font(.caption).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(transitions.suffix(8).reversed())) { transition in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(transition.date, format: .dateTime.month(.abbreviated).day().hour().minute())
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit().frame(width: 110, alignment: .leading)
                    Text(transition.model.map(ModelDisplayName.short) ?? "Unknown model")
                        .font(.callout).lineLimit(1).truncationMode(.middle)
                        .help(transition.model ?? "No current model measurement")
                    Spacer(minLength: 0)
                    if let phase = transition.autopilotPhase {
                        Text(phase == "waiting_inventory" ? "Refresh model inventory" : phase)
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
            }
            Text("Provider reports may name the most recently used model. Loaded-model visits are tracked above.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var recordingDetails: some View {
        DisclosureGroup(isExpanded: $showsRecordingDetails) {
            VStack(alignment: .leading, spacing: 8) {
                if let recordingStartedAt {
                    Text("Recording started \(recordingStartedAt.formatted(date: .abbreviated, time: .shortened)).")
                }
                Text("\(presentation.staleCount) stale · \(presentation.unavailableCount) unavailable observations. Unobserved time is unknown; it is not recorded as idle or zero.")
                Text("Saved locally while Bloomy is open. The display refreshes every 30 seconds, or when you tap Refresh. Up to 30 days / 100,000 samples are retained. Counters use increasing readings within the same provider session; resets and gaps are excluded.")
                Text("GPU use and power describe the whole Mac and include other apps. Model filtering does not isolate a model’s hardware consumption. GPU memory is reported by the provider.")
                if let latest = presentation.latestForModel,
                   MetricsRecordingFreshness.isCurrent(latest, at: now, timelineDate: timelineDate) {
                    let memory = latest.gpuMemoryGB.map { "\(number($0)) GB" } ?? "Unknown"
                    let power = latest.powerWatts.map { "\(number($0)) W" } ?? "Unknown"
                    Text("Latest provider GPU memory: \(memory) · whole-Mac power: \(power).")
                }
                Text("Visit times follow observed residency. Switches entirely between readings can be missed, so shared counter work attribution is approximate.")
                Text("Only measurement fields are stored. Prompts, responses, credentials, and raw logs are excluded. Latency and time to first token are unavailable.")
            }
            .padding(.top, 6)
            .font(.caption)
            .foregroundStyle(.secondary)
        } label: {
            Label("Recording, gaps & privacy", systemImage: "lock.shield").font(.callout)
        }
        .modifier(MetricsKeyboardReveal(target: .recordingDetails))
    }

    private func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int(max(0, seconds) / 60)
        if minutes >= 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(Int(max(0, seconds)))s"
    }
}

struct PerformanceRatePoint: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let rate: Double
    let model: String
    let run: Int
}

struct PerformanceModelTransition: Identifiable, Sendable {
    let id: String
    let date: Date
    let model: String?
    let autopilotPhase: String?
}

enum PerformanceMetricsPresentation {
    /// A sole loaded slot establishes resident identity even when the daemon's
    /// last-used label still names a previous model. Activity/rate for that old
    /// label cannot be reassigned. A globally idle provider is known idle.
    static func residentMeasurements(_ samples: [PerformanceSample]) -> [PerformanceSample] {
        samples.map { sample in
            guard Set(sample.residentModels).count == 1,
                  let resident = sample.residentModels.first, resident != sample.model else { return sample }
            return PerformanceSample(
                id: sample.id, observedAt: sample.observedAt, sourceCapturedAt: sample.sourceCapturedAt,
                quality: sample.quality, providerSession: sample.providerSession, model: resident,
                residentModels: sample.residentModels, advertisedModels: sample.advertisedModels,
                inferenceActive: sample.inferenceActive == false ? false : nil,
                tokensPerSecond: nil, tokensGenerated: sample.tokensGenerated, requestsServed: sample.requestsServed,
                gpuUtilizationPercent: sample.gpuUtilizationPercent, gpuMemoryGB: sample.gpuMemoryGB,
                powerWatts: sample.powerWatts, autopilotPhase: sample.autopilotPhase
            )
        }
    }

    static func ratePoints(samples: [PerformanceSample], model: String? = nil) -> [PerformanceRatePoint] {
        var result: [PerformanceRatePoint] = []
        var previous: PerformanceSample?
        var run = 0
        for sample in samples {
            guard sample.quality == .current, let name = sample.model,
                  model == nil || name == model,
                  sample.inferenceActive == true || (sample.inferenceActive == nil && (sample.activeRequests ?? 0) > 0),
                  sample.providerSession != nil,
                  let rate = sample.tokensPerSecond, rate.isFinite, rate >= 0,
                  let capture = sample.sourceCapturedAt,
                  (0...90).contains(sample.observedAt.timeIntervalSince(capture)) else {
                previous = nil
                continue
            }
            let continuous = previous.map {
                let delta = sample.observedAt.timeIntervalSince($0.observedAt)
                return delta > 0 && delta <= 90 && $0.model == sample.model
                    && $0.providerSession != nil && $0.providerSession == sample.providerSession
                    && $0.sourceCapturedAt.map { capture > $0 && capture.timeIntervalSince($0) <= 90 } == true
                    && !counterReset(before: $0.tokensGenerated, after: sample.tokensGenerated)
                    && !counterReset(before: $0.requestsServed, after: sample.requestsServed)
            } ?? false
            if !continuous { run += 1 }
            result.append(PerformanceRatePoint(id: sample.id, date: sample.observedAt, rate: rate, model: name, run: run))
            previous = sample
        }
        return result
    }

    static func reducedRatePoints(_ points: [PerformanceRatePoint], limit: Int = 600) -> [PerformanceRatePoint] {
        guard limit > 1, points.count > limit else { return points }
        // Keep actual observations and their original run keys. Sampling never
        // merges two runs separated by a missing/stale source or model change.
        return (0..<limit).map { index in
            points[Int(Double(index) * Double(points.count - 1) / Double(limit - 1))]
        }
    }

    static func transitions(samples: [PerformanceSample]) -> [PerformanceModelTransition] {
        var result: [PerformanceModelTransition] = []
        var previous: PerformanceSample?
        for sample in samples {
            let model = sample.quality == .current ? sample.model : nil
            let phase = sample.quality == .current ? sample.autopilotPhase : nil
            let previousModel = previous.flatMap { $0.quality == .current ? $0.model : nil }
            let previousPhase = previous.flatMap { $0.quality == .current ? $0.autopilotPhase : nil }
            let gap = previous.map { sample.observedAt.timeIntervalSince($0.observedAt) > 90 } == true
            if gap, let previous, previousModel != nil {
                result.append(PerformanceModelTransition(id: previous.id.uuidString + "-gap", date: previous.observedAt.addingTimeInterval(90), model: nil, autopilotPhase: nil))
            }
            if previous == nil || previousModel != model || gap
                || previous?.providerSession != sample.providerSession
                || previousPhase != phase {
                result.append(PerformanceModelTransition(id: sample.id.uuidString, date: sample.observedAt, model: model, autopilotPhase: phase))
            }
            previous = sample
        }
        return result
    }

    private static func counterReset(before: Int64?, after: Int64?) -> Bool {
        guard let before, let after else { return false }
        return after < before
    }
}

/// Rows and their successful-read identity publish together. Failed or cancelled
/// reads leave the preceding result intact, including its analysis interval.
struct PerformanceMetricsRead: Sendable {
    let samples: [PerformanceSample]
    let token: PerformanceMetricsReadToken?
    let period: PerformanceMetricsPeriod?

    init(samples: [PerformanceSample], token: PerformanceMetricsReadToken?, period: PerformanceMetricsPeriod? = nil) {
        self.samples = samples
        self.token = token
        self.period = period
    }

    static let empty = PerformanceMetricsRead(samples: [], token: nil)

    @MainActor
    func refreshing(endingAt: Date, period: PerformanceMetricsPeriod? = nil,
                    load: () async throws -> [PerformanceSample]) async throws -> Self {
        let samples = try await load()
        try Task.checkCancellation()
        return Self(samples: samples, token: PerformanceMetricsReadToken(
            generation: (token?.generation ?? 0) + 1, endingAt: endingAt
        ), period: period)
    }
}

struct PerformanceMetricsReadToken: Hashable, Sendable {
    let generation: Int
    let endingAt: Date
}

struct PerformanceMetricsQuery: Hashable, Sendable {
    let period: PerformanceMetricsPeriod
    let model: String?
    let count: Int
    let lastID: UUID?
    let readToken: PerformanceMetricsReadToken
    let isVisible: Bool

    var range: DateInterval { period.range(endingAt: readToken.endingAt) }
}

/// Publish calculated rows and their range/filter together. New reads may finish
/// before their analysis; retained results keep their own axes and denominator.
struct PerformanceMetricsRender: Sendable {
    let snapshot: PerformanceMetricsSnapshot
    let completedQuery: PerformanceMetricsQuery?
    static let empty = Self(snapshot: .empty, completedQuery: nil)

    func query(pending: PerformanceMetricsQuery) -> PerformanceMetricsQuery {
        completedQuery ?? pending
    }
}

private struct PerformanceHistoryQuery: Hashable {
    let period: PerformanceMetricsPeriod
    let refreshID: Int
    let isVisible: Bool
}

@MainActor
enum MetricsRefreshLoop {
    static func run(interval: Duration, read: @MainActor () async -> Void) async {
        while !Task.isCancelled {
            await read()
            guard !Task.isCancelled else { return }
            do { try await Task.sleep(for: interval) }
            catch { return }
        }
    }
}

/// The view owns its background analysis. Cancelling a period/filter/visibility
/// task also cancels the worker, so obsolete results neither draw nor queue work.
enum PerformanceMetricsAnalysis {
    static func make(samples: [PerformanceSample], range: DateInterval, model: String?) async -> PerformanceMetricsSnapshot? {
        guard !Task.isCancelled else { return nil }
        let worker = Task.detached(priority: .userInitiated) { () -> PerformanceMetricsSnapshot? in
            guard !Task.isCancelled else { return nil }
            let result = PerformanceMetricsSnapshot(
                samples: samples, range: range, model: model,
                cancellationRequested: { Task.isCancelled }
            )
            return Task.isCancelled ? nil : result
        }
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

struct PerformanceMetricsSnapshot: Sendable {
    let summary: PerformanceSummary
    let sampleCount: Int
    let staleCount: Int
    let unavailableCount: Int
    let models: [String]
    let latest: PerformanceSample?
    let latestForModel: PerformanceSample?
    let ratePoints: [PerformanceRatePoint]
    let chartWasReduced: Bool
    let transitions: [PerformanceModelTransition]
    let transitionCount: Int
    let visits: [ModelVisit]
    let withoutWorkVisits: [ModelVisit]
    let visitSummary: ModelVisitSummary

    static let empty = PerformanceMetricsSnapshot(samples: [], range: DateInterval(start: .distantPast, end: .distantFuture), model: nil)

    init(samples: [PerformanceSample], range: DateInterval, model: String?, cancellationRequested: @Sendable () -> Bool = { false }) {
        if cancellationRequested() { self = Self.empty; return }
        let inPeriod = samples.filter { $0.observedAt >= range.start && $0.observedAt <= range.end }
        let residentMeasurements = PerformanceMetricsPresentation.residentMeasurements(inPeriod)
        let latestForModel = residentMeasurements.last { model == nil || $0.model == model }
        if cancellationRequested() { self = Self.empty; return }
        let summary = PerformanceSummary(samples: residentMeasurements, model: model)
        var staleCount = 0
        var unavailableCount = 0
        var modelIDs = Set<String>()
        for sample in inPeriod {
            if sample.quality == .stale { staleCount += 1 }
            if sample.quality == .unavailable { unavailableCount += 1 }
            if let id = sample.model { modelIDs.insert(id) }
            modelIDs.formUnion(sample.residentModels)
        }
        let models = modelIDs.sorted()
        if cancellationRequested() { self = Self.empty; return }
        let points = PerformanceMetricsPresentation.ratePoints(samples: residentMeasurements, model: model)
        let ratePoints = PerformanceMetricsPresentation.reducedRatePoints(points)
        if cancellationRequested() { self = Self.empty; return }
        let changes = PerformanceMetricsPresentation.transitions(samples: inPeriod)
        if cancellationRequested() { self = Self.empty; return }
        let analyzedVisits = ModelVisitHistory(samples: samples, period: range, maximumVisits: 100_000).visits.filter { model == nil || $0.model == model }
        if cancellationRequested() { self = Self.empty; return }
        self.summary = summary
        sampleCount = inPeriod.count
        self.staleCount = staleCount
        self.unavailableCount = unavailableCount
        self.models = models
        latest = inPeriod.last
        self.latestForModel = latestForModel
        chartWasReduced = points.count > 600
        self.ratePoints = ratePoints
        transitionCount = changes.count
        transitions = Array(changes.suffix(100))
        visitSummary = ModelVisitSummary(visits: analyzedVisits)
        visits = Array(analyzedVisits.suffix(500))
        withoutWorkVisits = Array(analyzedVisits.filter { $0.outcome == .noObservedWork }.suffix(500))
    }
}
