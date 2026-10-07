import Charts
import DarkbloomTelemetry
import SwiftUI

enum ActivityTab: String, CaseIterable, Identifiable {
    case earnings = "Earnings"
    case metrics = "Metrics"
    var id: Self { self }
}

enum ActivityFilterPresentation {
    /// A retained filter remains reachable even when this period has no work for it.
    static func models(available: [String], selected: String?) -> [String] {
        guard let selected, !available.contains(selected) else { return available }
        return available + [selected]
    }

    static func allModelsLabel(metric: ActivityChartMetric, showsBaseRewards: Bool) -> String {
        guard metric == .earnings else { return "Show all model results" }
        return showsBaseRewards ? "Show all models and base rewards" : "Show all models; base rewards remain hidden"
    }
}

struct ActivityView: View {
    @ObservedObject var store: MonitorStore
    @State private var tab = ActivityTab.earnings
    @State private var period = ActivityPeriod.today
    @State private var selectedDate = Date()
    @State private var endDate = Date()
    @State private var read = ActivityReadState()
    @State private var showsModelHourlyAverages = false
    @State private var refreshID = 0
    @State private var model: String?
    @State private var chartMetric = ActivityChartMetric.earnings
    @State private var chartStyle = ActivityChartStyle.bars
    @State private var barArrangement = ActivityBarArrangement.stacked
    @State private var showsBaseRewards = true
    private var visibleRead: ActivityReadState {
        read.presentation(context: store.financialContext, ledgerReady: store.financialLedgerReady, sessionEpoch: store.financialSessionEpoch)
    }
    private var buckets: [ActivityBucket] { visibleRead.completed?.buckets ?? [] }
    private var models: [String] { visibleRead.completed?.models ?? [] }
    private var modelWorkByBucket: [Date: [String: Int64]] { visibleRead.completed?.modelWorkByBucket ?? [:] }
    private var modelHourlyAverages: [ModelHourlyEarningsAverage] { visibleRead.completed?.modelHourlyAverages ?? [] }
    private var modelHourlyProfits: [ModelHourlyProfit] { visibleRead.completed?.modelHourlyProfits ?? [] }
    private var modelHourlyProfitAverages: [ModelHourlyProfitAverage] { visibleRead.completed?.modelHourlyProfitAverages ?? [] }
    private var tokenRates: [Date: ModelRateBucket] { visibleRead.completed?.tokenRates ?? [:] }
    private var renderedModel: String? { visibleRead.completed?.query.model }
    private var renderedMetric: ActivityChartMetric { visibleRead.completed?.query.metric ?? chartMetric }

    init(
        store: MonitorStore,
        initialModelFilter: String? = nil,
        initialChartStyle: ActivityChartStyle = .bars,
        initialBarArrangement: ActivityBarArrangement = .stacked,
        initialChartMetric: ActivityChartMetric = .earnings,
        initialTab: ActivityTab = .earnings
    ) {
        self.store = store
        _model = State(initialValue: initialModelFilter)
        _chartStyle = State(initialValue: initialChartStyle)
        _barArrangement = State(initialValue: initialBarArrangement)
        _chartMetric = State(initialValue: initialChartMetric)
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    Text("Activity").font(.largeTitle.bold())
                    Spacer(minLength: 8)
                    activityTabs
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("Activity").font(.largeTitle.bold())
                    activityTabs
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 8)
            if tab == .metrics {
                PerformanceMetricsView(history: store.performanceHistory, isVisible: store.dashboardVisible)
            } else {
                TimelineView(VisibilityTimelineSchedule(base: .everyMinute, isVisible: store.dashboardVisible)) { context in
                    content(query: ActivityQuery(
                        period: period, selectedDate: selectedDate, endDate: endDate, now: context.date,
                        calendar: .current, model: model, revision: store.activityRevision, refreshID: refreshID,
                        metric: chartMetric,
                        energyRevision: chartMetric == .estimatedProfit ? store.energy?.reading?.date : nil,
                        context: store.financialContext, ledgerReady: store.financialLedgerReady, sessionEpoch: store.financialSessionEpoch
                    ))
                }
            }
        }
    }

    private var activityTabs: some View {
        Picker("Activity section", selection: $tab) {
            ForEach(ActivityTab.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .controlSize(.regular)
        .frame(width: 220)
    }

    private func content(query: ActivityQuery) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 12) {
                activityHeader
                if period == .date || period == .dateRange { dateControls }
                modelFilters
                chartControls
                if let completed = visibleRead.completed, let range = completed.query.range {
                    HStack(spacing: 8) {
                        Label(completed.query.scopeSummary, systemImage: "calendar")
                            .accessibilityIdentifier("activity.earnings.completedScope")
                            .lineLimit(2).help(completed.query.scopeSummary)
                        Spacer(minLength: 0)
                        Image(systemName: visibleRead.pending == nil && visibleRead.message == nil ? "checkmark.circle" : "clock")
                            .accessibilityLabel(visibleRead.status)
                            .accessibilityIdentifier("activity.earnings.readStatus")
                            .help("\(visibleRead.status) · \(completed.query.calendar.timeZone.identifier)")
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if !completed.hasRecordedActivity && !completed.hasBoundaryUncertainty {
                        ContentUnavailableView(
                            "No recorded activity",
                            systemImage: "chart.bar",
                            description: Text("No local earnings entries were found for this selection. Missing history is not zero earnings.")
                        )
                    } else {
                        if !completed.hasRecordedActivity {
                            ContentUnavailableView(
                                "History boundaries are uncertain",
                                systemImage: "clock",
                                description: Text("This selection does not align with the ledger's recorded hour boundaries. Amounts remain unknown; entries may exist.")
                            )
                        } else if renderedMetric == .estimatedProfit && chartValues.isEmpty {
                            ContentUnavailableView(
                                "No covered profit hours",
                                systemImage: "bolt.horizontal",
                                description: Text("Profit estimates need saved whole-Mac power readings for a complete hour with recorded model work. Enable electricity cost in Settings and allow readings to accumulate.")
                            )
                        } else {
                            if renderedMetric == .earnings {
                                ActivityEarningsGraphic(values: chartValues, buckets: buckets, color: chartColor(for:))
                            }
                            activityChart(query: completed.query, range: range)
                                .padding(16)
                                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                        }
                        if renderedMetric == .estimatedProfit && !visibleModelHourlyProfitAverages.isEmpty {
                            profitAveragesDisclosure
                        } else if renderedMetric == .earnings && !visibleModelHourlyAverages.isEmpty {
                            earningsAveragesDisclosure
                        }
                        DisclosureGroup {
                            activityTable(query: completed.query)
                            Text("Recorded ledger events · \(completed.query.calendar.timeZone.identifier). Gaps are unknown, not zero. Recorded totals may be incomplete.")
                                .font(.caption).foregroundStyle(.secondary)
                            if renderedMetric == .estimatedProfit {
                                Text("Estimated per earning model-hour. Whole-Mac electricity is shared evenly among models with recorded work; other Mac use is included. Incomplete power hours are omitted.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        } label: {
                            Label("Ledger & coverage", systemImage: "list.bullet.rectangle")
                                .font(.subheadline.weight(.medium))
                        }
                        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
                    }
                } else if let message = visibleRead.message {
                    ContentUnavailableView(chartMetric == .estimatedProfit ? "Local profit unavailable" : "History unavailable",
                        systemImage: chartMetric == .estimatedProfit ? "desktopcomputer" : "chart.bar", description: Text(message))
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else {
                    ProgressView("Reading local history…")
                }
            }
            .focusSection()
            .coordinateSpace(name: "activity.earnings.document")
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .scrollIndicators(.automatic)
        .task(id: store.dashboardVisible ? query : nil) {
            if store.dashboardVisible {
                await load(query: query)
            } else if !Task.isCancelled, let ticket = read.pending {
                read.cancel(ticket)
            }
        }
    }

    private var activityHeader: some View {
        HStack(spacing: 8) {
            Label(renderedMetric == .estimatedProfit ? "Local profit history" : "Account credit history",
                systemImage: renderedMetric == .estimatedProfit ? "desktopcomputer" : "chart.bar").font(.headline)
                .help(renderedMetric == .estimatedProfit ? LocalFinancialAttributionPresentation.localHelp
                    : LocalFinancialAttributionPresentation.accountHelp)
            Spacer(minLength: 8)
            periodPicker
            refreshButton
        }
        .controlSize(.regular)
    }

    private var periodPicker: some View {
        Picker("Calendar period", selection: $period) {
            ForEach(ActivityPeriod.allCases) { Text($0.rawValue).tag($0) }
        }
        .labelsHidden()
        .accessibilityLabel("Calendar period")
        .frame(width: 130)
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private var refreshButton: some View {
        Button { refreshID += 1 } label: { Label("Refresh history", systemImage: "arrow.clockwise") }
            .labelStyle(.iconOnly)
            .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    @ViewBuilder
    private var dateControls: some View {
        let from = DatePicker(period == .dateRange ? "From" : "Date", selection: $selectedDate,
                              in: ...Date(), displayedComponents: .date)
            .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
        if period == .dateRange {
            let through = DatePicker("Through", selection: $endDate, in: ...Date(), displayedComponents: .date)
                .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { from; through }
                VStack(alignment: .leading, spacing: 8) { from; through }
            }
        } else {
            from
        }
    }

    @ViewBuilder
    private var modelFilters: some View {
        if !models.isEmpty || model != nil {
            VStack(alignment: .leading, spacing: 8) {
                AdaptiveChoiceLayout(minimumWidth: 125, spacing: 6, maximumWidth: 180) {
                    modelFilterChip(
                        title: "All models",
                        color: .secondary,
                        isSelected: model == nil,
                        accessibilityLabel: ActivityFilterPresentation.allModelsLabel(
                            metric: chartMetric, showsBaseRewards: showsBaseRewards
                        )
                    ) { model = nil }
                    ForEach(ActivityFilterPresentation.models(available: models, selected: model), id: \.self) { name in
                        modelFilterChip(
                            title: ModelDisplayName.short(name),
                            color: modelColor(name),
                            isSelected: model == name,
                            accessibilityLabel: model == name ? "Selected model \(name)" : "Filter to model \(name)",
                            help: name
                        ) {
                            model = model == name ? nil : name
                        }
                    }
                    if model == nil && chartMetric == .earnings {
                        modelFilterChip(
                            title: "Base rewards",
                            color: chartColor(for: "Base rewards"),
                            isSelected: showsBaseRewards,
                            accessibilityLabel: showsBaseRewards ? "Base rewards shown" : "Show base rewards"
                        ) { showsBaseRewards.toggle() }
                    }
                }
                .frame(maxWidth: 1_020, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Model filters")
            }
        }
    }

    private var chartControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { measurePicker; Spacer(minLength: 8); chartOptions }
            VStack(alignment: .leading, spacing: 8) { measurePicker; chartOptions }
        }
        .controlSize(.small)
    }

    private var measurePicker: some View {
        Picker("Activity measure", selection: $chartMetric) {
            Text("Gross earnings").tag(ActivityChartMetric.earnings)
            Text("Est. profit / h").tag(ActivityChartMetric.estimatedProfit)
        }
        .labelsHidden().pickerStyle(.segmented).frame(width: 280)
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private var chartOptions: some View {
        Menu {
            Picker("Chart style", selection: $chartStyle) {
                ForEach(ActivityChartStyle.allCases) { style in Text(style.rawValue).tag(style) }
            }
            Picker("Bar layout", selection: $barArrangement) {
                ForEach(ActivityBarArrangement.allCases) { arrangement in Text(arrangement.rawValue).tag(arrangement) }
            }.disabled(chartStyle != .bars)
        } label: {
            Label(chartStyle.rawValue, systemImage: chartStyle == .bars ? "chart.bar" : "chart.xyaxis.line")
        }
        .help("Chart style and bar layout")
        .accessibilityLabel("Chart options, \(chartStyle.rawValue), \(barArrangement.rawValue)")
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private var profitAveragesDisclosure: some View {
        DisclosureGroup(isExpanded: $showsModelHourlyAverages) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(visibleModelHourlyProfitAverages) { average in
                    VStack(alignment: .leading, spacing: 4) {
                        averageModelLabel(average.model)
                        Text(ActivityAmountPresentation.hourlyAmount(average.profitUSDPerHour))
                            .font(.headline)
                            .monospacedDigit()
                        Text("Profit / hour · \(average.coveredHours.formatted()) covered h")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .help("Estimated recorded model work minus an equal share of measured whole-Mac electricity in complete earning hours. Includes other Mac use, so it is not provider-only power cost.")
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Estimated profit per model-hour").font(.headline)
        }
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private var earningsAveragesDisclosure: some View {
        DisclosureGroup(isExpanded: $showsModelHourlyAverages) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(visibleModelHourlyAverages) { average in
                    VStack(alignment: .leading, spacing: 4) {
                        averageModelLabel(average.model)
                        Text(ActivityAmountPresentation.hourlyAmount(average.averageWorkUSDPerEarningHour))
                            .font(.headline)
                            .monospacedDigit()
                        Text("Work / hour · \(average.earningHours.formatted()) earning h")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .padding(10)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
                    .help("Gross recorded model work divided by hours with earnings ledger entries. Electricity and idle hours are not included.")
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, 8)
        } label: {
            Text("Work earnings per model-hour").font(.headline)
        }
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private func averageModelLabel(_ name: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Circle().fill(modelColor(name)).frame(width: 8, height: 8).padding(.top, 4)
            Text(ModelDisplayName.short(name))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(name)
        }
    }

    private func activityTable(query: ActivityQuery) -> some View {
        GeometryReader { geometry in
            activityTable(compact: geometry.size.width < 620, query: query)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 300)
    }

    private func activityTable(compact: Bool, query: ActivityQuery) -> some View {
        Table(buckets) {
            TableColumn("Period") { bucket in
                if compact {
                    Text(bucket.interval.start, format: query.dateFormat.month(.abbreviated).day().hour())
                } else {
                    Text(bucket.interval.start, format: query.dateFormat.month().day().hour().timeZone())
                }
            }.width(compact ? 100 : 130)
            TableColumn("Work USD") { bucket in amountCell(bucket.totals?.workMicroUSD) }
                .width(compact ? 80 : 85)
            TableColumn(compact ? (renderedModel == nil ? "Rewards" : "Tok/s") : (renderedModel == nil ? "Rewards USD" : "Avg tok/sec")) { bucket in
                if renderedModel == nil {
                    amountCell(bucket.totals?.rewardMicroUSD)
                } else if let rate = tokenRates[bucket.id], let average = rate.average {
                    Text(average, format: .number.precision(.fractionLength(1)))
                        .help(rateDescription(rate))
                        .accessibilityLabel(rateDescription(rate))
                } else {
                    Text("—").accessibilityLabel("No attributed throughput samples")
                }
            }.width(compact ? 80 : 85)
            TableColumn("Work credits") { bucket in Text(bucket.totals.map { $0.jobs.formatted() } ?? "—") }
                .width(88)
            TableColumn(compact ? "Status" : "Coverage") { bucket in
                Text(compact ? compactCoverage(bucket.coverage) : coverage(bucket.coverage))
                    .foregroundStyle(.secondary)
                    .help(coverage(bucket.coverage))
            }.width(compact ? 60 : 85)
        }
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private var chartValues: [ActivityChartValue] {
        if renderedMetric == .estimatedProfit {
            return ActivityChartData.profitValues(hourly: modelHourlyProfits, buckets: buckets, selectedModel: renderedModel)
        }
        return ActivityChartData.values(buckets: buckets, models: models, modelWorkByBucket: modelWorkByBucket,
                                        selectedModel: renderedModel, includeRewards: showsBaseRewards)
    }

    private var visibleModelHourlyAverages: [ModelHourlyEarningsAverage] {
        guard let model = renderedModel else { return modelHourlyAverages }
        return modelHourlyAverages.filter { $0.model == model }
    }

    private var visibleModelHourlyProfitAverages: [ModelHourlyProfitAverage] {
        guard let model = renderedModel else { return modelHourlyProfitAverages }
        return modelHourlyProfitAverages.filter { $0.model == model }
    }

    private var chartStyleDomain: [String] {
        ActivityChartData.colorScaleDomain(models: models, selectedModel: renderedModel)
    }

    private var chartStyleRange: [Color] {
        chartStyleDomain.map(chartColor(for:))
    }

    private func modelColor(_ model: String) -> Color {
        let components = ActivityChartPalette.components(for: model)
        return Color(hue: components.hue, saturation: components.saturation, brightness: components.brightness)
    }

    private func chartColor(for series: String) -> Color {
        switch series {
        case "Base rewards": Color(hue: 0.12, saturation: 0.30, brightness: 0.88)
        case "Work": Color(hue: 0.52, saturation: 0.25, brightness: 0.88)
        default: modelColor(series)
        }
    }

    private func modelFilterChip(
        title: String,
        color: Color,
        isSelected: Bool,
        accessibilityLabel: String,
        help: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 8) {
                Circle().fill(color).frame(width: 9, height: 9)
                Text(title)
                    .font(.callout.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 10)
            .frame(height: 30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isSelected ? color.opacity(0.15) : Color(nsColor: .controlBackgroundColor),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isSelected ? color.opacity(0.7) : Color.secondary.opacity(0.2), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(help ?? title)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .modifier(ScrollControlKeyboardReveal(documentSpace: "activity.earnings.document"))
    }

    private func activityChart(query: ActivityQuery, range: DateInterval) -> some View {
        let stacked = chartStyle == .area || (chartStyle == .bars && barArrangement == .stacked)
        let stackedBars = chartStyle == .bars && barArrangement == .stacked
        let values = chartValues
        let segments = stackedBars
            ? (renderedMetric == .estimatedProfit ? ActivityChartData.profitSegments(values: values) : ActivityChartData.segments(values: values))
            : []
        let amountsByID = ActivityChartData.originalAmounts(values: values)
        let valueCues = chartStyle == .area || stackedBars ? [] : ChartSeriesCueSelection.values(values)
        let segmentCues = stackedBars ? ChartSeriesCueSelection.segments(segments) : []
        let zeroValues = ActivityChartData.recordedZeroValues(values)
        let zeroIntervals = Set(zeroValues.map(\.interval.start))
        let isolatedArea = chartStyle == .area
            ? ChartSeriesCueSelection.isolatedAreaSegments(values).filter { !zeroIntervals.contains($0.interval.start) } : []
        let markValues = chartStyle == .area ? ChartSeriesCueSelection.areaMarkValues(values) : values
        let isolatedAreaIDs = Set(isolatedArea.map(\.id))
        let isolatedAreaAmounts: [String: Double] = isolatedArea.isEmpty ? [:] : values.reduce(into: [:]) { amounts, value in
            if isolatedAreaIDs.contains(value.id) { amounts[value.id] = value.amountUSD }
        }
        let areaCues = chartStyle == .area
            ? ChartSeriesCueSelection.areaCues(values).filter { !isolatedAreaIDs.contains($0.id) } : []
        let visibleSeries = stackedBars
            ? segments.map(\.series) : values.map(\.series)
        let styles = ChartSeriesStyles(domain: chartStyleDomain + visibleSeries)
        let yAxis: ActivityChartYAxis
        if renderedMetric == .estimatedProfit || values.contains(where: { $0.amountUSD < 0 }) {
            let bounds = ActivityChartData.profitBounds(values: values, stacked: stacked)
            yAxis = ActivityChartAxis.signedYAxis(minimum: bounds.minimum, maximum: bounds.maximum)
        } else {
            let maximum = ActivityChartData.maximumUSD(values: values, stacked: stacked)
            yAxis = ActivityChartAxis.yAxis(maximum: maximum)
        }

        return VStack(alignment: .leading, spacing: 2) {
            Text(renderedMetric == .estimatedProfit
                 ? "Estimated profit per earning model-hour · USD"
                 : "Gross recorded earnings · USD")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Chart {
                chartMarks(query: query, values: markValues, segments: segments,
                    originalAmounts: amountsByID, styles: styles, valueCues: valueCues, segmentCues: segmentCues)
                ForEach(zeroValues) { value in
                    PointMark(
                        x: .value("Period", value.interval.start.addingTimeInterval(value.interval.duration / 2)),
                        y: .value("Recorded USD", 0)
                    )
                    .foregroundStyle(Color.secondary)
                    .symbol(.circle)
                    .symbolSize(24)
                    .accessibilityLabel(Text("Recorded zero, period beginning \(value.interval.start.formatted(query.dateAndTimeFormat))"))
                    .accessibilityValue(Text("0 US dollars"))
                }
                // A single value cannot form an area. Place its symbol within
                // the recorded bucket, using the same signed stack endpoint.
                ForEach(isolatedArea) { segment in
                    if let originalAmount = isolatedAreaAmounts[segment.id] {
                        PointMark(
                            x: .value("Period", segment.interval.start.addingTimeInterval(segment.interval.duration / 2)),
                            y: .value("Recorded USD", segment.endUSD)
                        )
                        .foregroundStyle(by: .value("Series", segment.series))
                        .symbol(styles[segment.series].symbol.shape)
                        .symbolSize(48)
                        .annotation(position: .trailing, spacing: 4) {
                            ChartSeriesBadge(number: styles[segment.series].number)
                        }
                        .accessibilityLabel(Text("\(segment.series), recorded period beginning \(segment.interval.start.formatted(query.dateAndTimeFormat))"))
                        .accessibilityValue(Text(ChartSeriesCueSelection.pointAmountLabel(originalAmount)))
                    }
                }
            }
                .id(query.model)
                .chartXScale(domain: range.start...range.end)
                .chartYScale(domain: yAxis.lowerBound...yAxis.upperBound,
                             range: .plotDimension(startPadding: zeroValues.isEmpty ? 0 : 4, endPadding: 0))
                .chartXAxisLabel("Local time")
                .chartXAxis {
                    AxisMarks(values: ActivityChartAxis.xValues(in: range, unit: query.unit, calendar: query.calendar)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(0.38))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.7))
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                if query.unit == .hour {
                                    Text(date, format: query.dateFormat.hour())
                                } else {
                                    Text(date, format: query.dateFormat.month(.abbreviated).day())
                                }
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: yAxis.values) { value in
                        let isZeroBaseline = yAxis.lowerBound < 0 && value.as(Double.self) == 0
                        AxisGridLine(stroke: StrokeStyle(lineWidth: isZeroBaseline ? 1.2 : 0.7,
                                                        dash: isZeroBaseline ? [] : [3, 3]))
                            .foregroundStyle(Color.secondary.opacity(isZeroBaseline ? 0.7 : 0.38))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0.7))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount, format: .currency(code: "USD").precision(.fractionLength(yAxis.fractionDigits)))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                .chartForegroundStyleScale(domain: chartStyleDomain, range: chartStyleRange)
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let plotAnchor = proxy.plotFrame {
                            let plot = geometry[plotAnchor]
                            ForEach(areaCues) { segment in
                                if let x = proxy.position(forX: segment.interval.start),
                                   let y = proxy.position(forY: (segment.startUSD + segment.endUSD) / 2) {
                                    ChartSeriesBadge(number: styles[segment.series].number)
                                        .position(x: plot.minX + x, y: plot.minY + y)
                                }
                            }
                        }
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                .frame(height: 260)
            ChartSeriesLegend(entries: styles.visibleEntries(in: visibleSeries),
                showsLine: chartStyle == .lines, color: chartColor(for:))
                .padding(.top, 6)
            if !zeroValues.isEmpty {
                Label("Recorded zero", systemImage: "circle.fill")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(renderedMetric == .estimatedProfit
            ? "Estimated net profit per earning model-hour in US dollars by local time, with positive and negative values around zero. Numbered labels and the legend identify each series."
            : "Recorded gross earnings in US dollars by local time. Numbered labels and the legend identify the series. Aggregate totals and coverage are in the table below.")
    }

    @ChartContentBuilder
    private func chartMarks(
        query: ActivityQuery, values: [ActivityChartValue], segments: [ActivityChartSegment],
        originalAmounts: [String: Double],
        styles: ChartSeriesStyles, valueCues: Set<String>, segmentCues: Set<String>
    ) -> some ChartContent {
        if chartStyle == .bars && barArrangement == .stacked {
            ForEach(segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.interval.start.addingTimeInterval(segment.interval.duration * 0.08)),
                    xEnd: .value("End", segment.interval.end.addingTimeInterval(-segment.interval.duration * 0.08)),
                    yStart: .value("Recorded USD", segment.startUSD),
                    yEnd: .value("Recorded USD", segment.endUSD)
                )
                .foregroundStyle(by: .value("Series", segment.series))
                .accessibilityLabel(Text("\(segment.series), recorded period beginning \(segment.interval.start.formatted(query.dateAndTimeFormat))"))
                .accessibilityValue(Text(ChartSeriesCueSelection.pointAmountLabel(originalAmounts[segment.id] ?? (segment.endUSD - segment.startUSD))))
                .annotation(position: .overlay) {
                    if segmentCues.contains(segment.id) {
                        ChartSeriesBadge(number: styles[segment.series].number)
                    }
                }
            }
        } else {
            ForEach(values) { value in
                chartMark(value, query: query, style: styles[value.series], showsCue: valueCues.contains(value.id))
            }
        }
    }

    @ChartContentBuilder
    private func chartMark(
        _ value: ActivityChartValue, query: ActivityQuery, style: ChartSeriesStyle, showsCue: Bool
    ) -> some ChartContent {
        switch chartStyle {
        case .bars:
            barMark(value, query: query)
                .accessibilityLabel(Text("\(value.series), recorded period beginning \(value.interval.start.formatted(query.dateAndTimeFormat))"))
                .accessibilityValue(Text(ChartSeriesCueSelection.pointAmountLabel(value.amountUSD)))
                .annotation(position: .overlay) {
                    if showsCue { ChartSeriesBadge(number: style.number) }
                }
        case .lines:
            LineMark(
                x: .value("Period", value.interval.start),
                y: .value("Recorded USD", value.amountUSD),
                series: .value("Series run", value.runKey)
            )
            .foregroundStyle(by: .value("Series", value.series))
            .symbol(style.symbol.shape)
            .symbolSize(32)
            .lineStyle(style.stroke)
            .accessibilityLabel(Text("\(value.series), recorded period beginning \(value.interval.start.formatted(query.dateAndTimeFormat))"))
            .accessibilityValue(Text(ChartSeriesCueSelection.pointAmountLabel(value.amountUSD)))
            .interpolationMethod(.linear)
            .annotation(position: .top, spacing: 2) {
                if showsCue { ChartSeriesBadge(number: style.number) }
            }
        case .area:
            AreaMark(
                x: .value("Period", value.interval.start),
                y: .value("Recorded USD", value.amountUSD),
                series: .value("Series run", value.runKey),
                stacking: .standard
            )
            .foregroundStyle(by: .value("Series", value.series))
            .opacity(0.78)
            .accessibilityLabel(Text("\(value.series), recorded period beginning \(value.interval.start.formatted(query.dateAndTimeFormat))"))
            .accessibilityValue(Text(ChartSeriesCueSelection.pointAmountLabel(value.amountUSD)))
        }
    }

    @ChartContentBuilder
    private func barMark(_ value: ActivityChartValue, query: ActivityQuery) -> some ChartContent {
        let unit: Calendar.Component = query.unit == .hour ? .hour : .day
        BarMark(
            x: .value("Period", value.interval.start, unit: unit),
            y: .value("Recorded USD", value.amountUSD),
            stacking: .unstacked
        )
        .position(by: .value("Series", value.series))
        .foregroundStyle(by: .value("Series", value.series))
    }

    private func load(query: ActivityQuery) async {
        guard !Task.isCancelled else { return }
        let ticket = read.begin(query)
        guard query.range != nil else {
            read.fail("Choose an end date on or after the start date, with no more than 366 calendar days.", for: ticket)
            return
        }
        // Capture power alongside the request, before any local-read suspension.
        let powerIntervals = store.energy?.intervals ?? []
        do {
            let session = await store.synchronizeFinancialSession()
            try Task.checkCancellation()
            guard let context = query.context, context == session.context,
                  query.ledgerReady, session.ledgerReady else {
                read.unavailable(ActivityReadState.unavailableMessage(context: session.context,
                    ledgerReady: session.ledgerReady), for: ticket)
                return
            }
            guard let snapshot = try await ActivityReadSnapshot.fetch(query: query, store: store,
                powerIntervals: powerIntervals) else {
                try Task.checkCancellation()
                if query.metric == .estimatedProfit {
                    read.unavailable(LocalFinancialAttributionPresentation.unavailableMessage, for: ticket)
                } else {
                    read.fail("Account credit storage is unavailable.", for: ticket)
                }
                return
            }
            try Task.checkCancellation()
            read.finish(snapshot, for: ticket)
        } catch is CancellationError {
            read.cancel(ticket)
        } catch AccountEarningsClientError.sessionChanged {
            read.unavailable("The account changed. Reading its local credit history…", for: ticket)
            _ = await store.synchronizeFinancialSession()
        } catch {
            if Task.isCancelled { read.cancel(ticket) }
            else { read.fail("Could not read local earnings history. Try refreshing.", for: ticket) }
        }
    }

    private func amountCell(_ microUSD: Int64?) -> some View {
        let value = ActivityAmountPresentation.tableAmount(microUSD)
        return Text(value).monospacedDigit()
            .help(microUSD == nil ? "No recorded amount" : "\(value) USD")
    }

    private func rateDescription(_ rate: ModelRateBucket) -> String {
        guard let average = rate.average, let minimum = rate.minimum, let maximum = rate.maximum else {
            return "No attributed throughput samples"
        }
        return "Average \(average.formatted(.number.precision(.fractionLength(1)))) tok/sec; sampled range \(minimum.formatted(.number.precision(.fractionLength(1)))) to \(maximum.formatted(.number.precision(.fractionLength(1)))); \(rate.sampleCount) samples. Up to 31 days retained."
    }

    private func coverage(_ value: ActivityCoverage) -> String {
        switch value {
        case .recorded: "Recorded"
        case .unavailable: "Unknown"
        case .boundaryUncertain: "Boundary unknown"
        }
    }

    private func compactCoverage(_ value: ActivityCoverage) -> String {
        switch value {
        case .recorded: "Recorded"
        case .unavailable: "Unknown"
        case .boundaryUncertain: "Partial"
        }
    }
}
