import DarkbloomTelemetry
import SwiftUI

struct DashboardOverviewView: View {
    @ObservedObject var store: MonitorStore
    let controlStore: ProviderControlStore?
    var openActivity: (() -> Void)? = nil
    var openReadinessDestination: ((ProviderReadinessPresentation.Destination) -> Void)? = nil
    @AppStorage("overview.hardwareExpanded") private var hardwareExpanded = false

    var body: some View {
        TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 1), isVisible: store.dashboardVisible)) { _ in
            // Telemetry can arrive between scheduled expiry redraws.
            overviewContent(at: Date())
        }
    }

    private func overviewContent(at now: Date) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Overview").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text(Host.current().localizedName ?? "This Mac").foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .accessibilityElement(children: .contain)
                ProviderReadinessSummaryView(presentation: store.providerReadiness(at: now),
                    openDestination: openReadinessDestination)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) { summaryMetrics }.frame(minWidth: 700)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        summaryMetrics
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Today's observed metrics")
                .accessibilityIdentifier("overview.metrics")
                OverviewEarningsView(store: store, openActivity: openActivity)
                DashboardModelSummary(store: store, controlStore: controlStore)
                if !hardwareExpanded, let protection = store.hostGPUProtection {
                    HostGPUProtectionSummaryView(protection: protection, slowdownWarning: store.servingSlowdownWarning)
                }
                DisclosureGroup("Hardware & cooling", isExpanded: $hardwareExpanded) {
                    if hardwareExpanded {
                        ProviderResourcesView(store: store)
                            .padding(.top, 8)
                    }
                }
                .accessibilityIdentifier("overview.hardware")
                if let controlStore {
                    DisclosureGroup("Running and saved selection") {
                        ProviderSelectionView(store: store, controlStore: controlStore)
                    }.font(.callout)
                }
                Text("Account credits may include other owned machines. Missing measurements are unknown, not zero.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task { await store.refreshModelServingProfitability() }
    }

    private var summaryMetrics: some View {
        Group {
            let reading = store.displayedTodayEarnings
            let earnings = PopupEarningsMetrics.make(from: reading?.value, isRetained: reading?.isRetained == true)
            let retained = earnings?.lastReadAt != nil
            let help = earnings?.lastReadAt.map { "Last successful read \($0.formatted(date: .abbreviated, time: .standard)). This retained observation is not current." }
                ?? "Recorded account earnings with observed calendar coverage. " + LocalFinancialAttributionPresentation.accountHelp
            DashboardMetric(id: "today", title: "Observed today",
                value: earnings.map { money($0.totalUSD) } ?? "—",
                unit: earnings == nil ? "Awaiting earnings" : retained ? "USD · last read" : "USD",
                symbol: "dollarsign.circle", accessibilityUnit: retained ? "US dollars, last read" : "US dollars")
                .help(help)
            DashboardMetric(id: "hourly", title: "Per observed hour",
                value: earnings?.perHourUSD.map(money) ?? "—",
                unit: earnings?.perHourUSD == nil ? "Awaiting coverage" : retained ? "USD / h · last read" : "USD / hour",
                symbol: "clock", accessibilityUnit: retained ? "US dollars per observed hour, last read" : "US dollars per observed hour")
                .help(help)
            DashboardMetric(id: "speed", title: "Average speed today",
                value: store.currentDayAverageTokenRate.map(number) ?? "—",
                unit: store.currentDayAverageTokenRate == nil ? "Awaiting samples" : "tok/s",
                symbol: "speedometer", accessibilityUnit: "tokens per second")
            DashboardMetric(id: "jobs", title: "Work credits today",
                value: store.currentJobSummary.map { $0.completedToday.formatted() } ?? "—",
                unit: store.currentJobSummary == nil ? "Awaiting credits" : "credits",
                symbol: "checkmark.circle")
        }
    }

    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
    private func money(_ value: Double) -> String { ActivityAmountPresentation.numberAmount(value) }
}

private struct DashboardMetric: View {
    let id: String
    let title: String
    let value: String
    let unit: String
    var symbol: String = "chart.bar"
    var accessibilityUnit: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(unit).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value == "—" ? unit : "\(value) \(accessibilityUnit ?? unit)")
        .accessibilityIdentifier("overview.metric.\(id)")
    }
}

private struct DashboardModelSummary: View {
    @ObservedObject var store: MonitorStore
    let controlStore: ProviderControlStore?

    var body: some View {
        TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 1), isVisible: store.dashboardVisible)) { _ in
            let now = Date()
            VStack(alignment: .leading, spacing: 12) {
                Text("Models").font(.title3.bold())
                let presentation = PopupModelPresentation.make(
                    input: PopupModelSourceInput(snapshot: store.snapshot, controlSnapshot: controlStore?.snapshot),
                    currentTime: now
                )
                if case .models(let models) = presentation {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 10)], spacing: 10) {
                        ForEach(models) { model in
                            CompactModelCard(modelID: model.name, status: label(model.state),
                                             tint: color(model.state), metrics: metrics(for: model.name),
                                             selected: model.state == .active)
                        }
                    }
                } else {
                    Text("Model state is unavailable. Check Health & Logs for source details.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func metrics(for id: String) -> [ModelCardMetric] {
        var result: [ModelCardMetric] = []
        if let rate = store.currentModelTokenRateAverages.first(where: { $0.model == id }) {
            result.append(ModelCardMetric(id: "speed", symbol: "speedometer",
                value: String(format: "%.1f", rate.tokensPerSecond), caption: "avg tok/s today"))
        }
        if let serving = store.modelServingProfitAverages.first(where: { $0.model == id }) {
            let value = serving.profitUSDPerActiveHour ?? serving.grossUSDPerActiveHour
            result.append(ModelCardMetric(id: "earnings", symbol: "dollarsign.circle",
                value: ActivityAmountPresentation.hourlyAmount(value),
                caption: serving.profitUSDPerActiveHour == nil ? "derived gross / active h" : "est. net / active h"))
        }
        if result.isEmpty {
            result.append(ModelCardMetric(id: "learning", symbol: "clock", value: "Learning", caption: "No measured averages"))
        }
        return result
    }

    private func color(_ state: DashboardModelState) -> Color {
        switch state { case .active: .green; case .loadedIdle: .yellow; case .availableUnloaded: .gray }
    }
    private func label(_ state: DashboardModelState) -> String {
        switch state { case .active: "Active"; case .loadedIdle: "Loaded · idle"; case .availableUnloaded: "Available" }
    }
}
