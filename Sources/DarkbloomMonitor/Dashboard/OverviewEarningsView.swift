import Charts
import DarkbloomTelemetry
import SwiftUI

/// One local calendar-history read per visible query revision. Telemetry ticks
/// do not restart it; hidden dashboards cancel it without adding a poller.
struct OverviewEarningsView: View {
    @ObservedObject var store: MonitorStore
    var openActivity: (() -> Void)?
    @State private var read = ActivityReadState()
    @State private var refreshID = 0

    var body: some View {
        TimelineView(VisibilityTimelineSchedule(base: .everyMinute, isVisible: store.dashboardVisible)) { context in
            let query = store.dashboardVisible ? ActivityQuery(
                period: .today, selectedDate: context.date, endDate: context.date, now: context.date,
                calendar: .current, model: nil, revision: store.activityRevision, refreshID: refreshID,
                context: store.financialContext, ledgerReady: store.financialLedgerReady, sessionEpoch: store.financialSessionEpoch
            ) : nil
            OverviewEarningsCard(read: read.presentation(context: store.financialContext,
                ledgerReady: store.financialLedgerReady, sessionEpoch: store.financialSessionEpoch), refresh: { refreshID += 1 }, openActivity: openActivity)
                .task(id: query) {
                    guard let query, !Task.isCancelled else { return }
                    let ticket = read.begin(query)
                    do {
                        let session = await store.synchronizeFinancialSession()
                        try Task.checkCancellation()
                        guard let capturedContext = query.context, capturedContext == session.context,
                              query.ledgerReady, session.ledgerReady else {
                            read.unavailable(ActivityReadState.unavailableMessage(context: session.context,
                                ledgerReady: session.ledgerReady), for: ticket)
                            return
                        }
                        guard let snapshot = try await ActivityReadSnapshot.fetch(query: query, store: store) else {
                            try Task.checkCancellation()
                            read.fail("Local earnings history is unavailable.", for: ticket)
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
                        else { read.fail("Could not read local earnings history.", for: ticket) }
                    }
                }
        }
    }
}

/// Pure rendering keeps the retained report's date, coverage and amounts
/// together, including during a failed read or a calendar-day transition.
struct OverviewEarningsCard: View {
    let read: ActivityReadState
    let refresh: () -> Void
    var openActivity: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Hourly account credits", systemImage: "chart.bar")
                        .font(.headline)
                    if let snapshot = read.completed, let range = snapshot.query.range {
                        Text(range.start, format: Date.FormatStyle(date: .abbreviated, time: .omitted,
                            calendar: snapshot.query.calendar, timeZone: snapshot.query.calendar.timeZone))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("overview.earnings.date")
                            .help("\(snapshot.query.calendar.timeZone.identifier) · \(read.status)")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if let openActivity {
                    Button(action: openActivity) { Label("Activity", systemImage: "arrow.up.right") }
                        .accessibilityIdentifier("overview.earnings.activity")
                }
                Button(action: refresh) { Image(systemName: "arrow.clockwise") }
                    .accessibilityLabel("Refresh hourly account credits")
                    .accessibilityIdentifier("overview.earnings.refresh")
                    .help("Read local earnings history again. No network request is sent.")
            }
            .buttonStyle(.borderless)
            if let snapshot = read.completed, let range = snapshot.query.range, snapshot.hasRecordedActivity {
                OverviewHourlyChart(snapshot: snapshot, range: range)
                HStack(spacing: 12) {
                    Label("Work", systemImage: "circle.fill").foregroundStyle(Color.accentColor)
                    Label("Base rewards", systemImage: "circle.fill").foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                Text("\(snapshot.buckets.filter { $0.totals != nil }.count)/\(snapshot.buckets.count) hours recorded · gaps are unknown")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("overview.earnings.coverage")
            } else if read.completed == nil && read.message == nil {
                ProgressView("Reading local history…")
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                ContentUnavailableView(
                    read.completed == nil ? "History unavailable" : read.completed?.hasBoundaryUncertainty == true
                        ? "History boundaries are uncertain" : "No recorded hourly history",
                    systemImage: "chart.bar",
                    description: Text(read.completed?.hasBoundaryUncertainty == true
                        ? "Local calendar boundaries cannot be attributed precisely."
                        : "Missing history is unknown, not zero earnings.")
                )
                .frame(minHeight: 140)
            }
            if read.completed != nil || read.message != nil {
                Label(read.status, systemImage: read.message == nil ? "clock" : "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .accessibilityIdentifier("overview.earnings.readStatus")
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary, lineWidth: 1))
        .accessibilityElement(children: .contain)
        .help("Gross credits retained in local account history, including signed corrections. Records may be incomplete and are not attributable to this Mac alone. Future and missing hours are unknown. Open Activity for detailed scope and amounts.")
    }
}

private struct OverviewHourlyChart: View {
    let snapshot: ActivityReadSnapshot
    let range: DateInterval

    var body: some View {
        let values = ActivityChartData.values(buckets: snapshot.buckets, models: [],
                                             modelWorkByBucket: [:], selectedModel: nil)
        let segments = ActivityChartData.segments(values: values)
        let bounds = ActivityChartData.profitBounds(values: values, stacked: true)
        let axis = bounds.minimum < 0
            ? ActivityChartAxis.signedYAxis(minimum: bounds.minimum, maximum: bounds.maximum)
            : ActivityChartAxis.yAxis(maximum: bounds.maximum)
        let zeros = ActivityChartData.recordedZeroValues(values)
        Chart {
            ForEach(segments) { segment in
                RectangleMark(
                    xStart: .value("Start", segment.interval.start.addingTimeInterval(segment.interval.duration * 0.08)),
                    xEnd: .value("End", segment.interval.end.addingTimeInterval(-segment.interval.duration * 0.08)),
                    yStart: .value("Start USD", segment.startUSD), yEnd: .value("End USD", segment.endUSD))
                    .foregroundStyle(by: .value("Credit", segment.series))
                    .accessibilityLabel("\(segment.series), \(segment.interval.start.formatted(snapshot.query.dateAndTimeFormat))")
                    .accessibilityValue(ActivityAmountPresentation.hourlyAmount(segment.endUSD - segment.startUSD))
            }
            ForEach(zeros) { value in
                PointMark(x: .value("Hour", value.interval.start.addingTimeInterval(value.interval.duration / 2)),
                          y: .value("Recorded USD", 0))
                    .foregroundStyle(Color.secondary).symbolSize(20)
                    .accessibilityLabel("Recorded zero, \(value.interval.start.formatted(snapshot.query.dateAndTimeFormat))")
                    .accessibilityValue("0 US dollars")
            }
        }
        .chartForegroundStyleScale(domain: ["Work", "Base rewards"], range: [Color.accentColor, Color.secondary])
        .chartLegend(.hidden)
        .chartXScale(domain: range.start...range.end)
        .chartYScale(domain: axis.lowerBound...axis.upperBound,
                     range: .plotDimension(startPadding: zeros.isEmpty ? 0 : 4, endPadding: 0))
        .chartXAxis {
            AxisMarks(values: ActivityChartAxis.xValues(in: range, unit: .hour, calendar: snapshot.query.calendar)) { value in
                AxisValueLabel {
                    if let date = value.as(Date.self) { Text(date, format: snapshot.query.dateFormat.hour()) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: axis.values) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount, format: .currency(code: "USD").precision(.fractionLength(axis.fractionDigits)))
                    }
                }
            }
        }
        .frame(height: 150)
        .accessibilityIdentifier("overview.earnings.chart")
    }
}
