import DarkbloomTelemetry
import SwiftUI

struct HealthView: View {
    @ObservedObject var store: MonitorStore
    @State private var showsLogs = false
    @State private var showsProvider = false
    @State private var showsDaemon = false
    @State private var showsThermal = false
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Health & Logs").font(.largeTitle.bold())
            Picker("View", selection: $showsLogs) {
                Text("Source health").tag(false)
                Text("Logs").tag(true)
            }
            .pickerStyle(.segmented)
            if showsLogs {
                LogsView(feed: store.snapshot.eventFeed)
            } else {
                TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 5), isVisible: store.dashboardVisible)) { _ in
                    let now = Date()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            overview
                            issues(at: now)
                            sourceFreshness
                            DisclosureGroup(isExpanded: $showsProvider) {
                                VStack(alignment: .leading, spacing: 14) {
                                    ProviderVersionView(snapshot: store.snapshot, now: now)
                                    ProviderVerificationView(snapshot: store.snapshot, now: now)
                                }
                                .padding(.top, 10)
                            } label: {
                                sectionLabel("Provider & verification", symbol: "checkmark.shield")
                            }
                            DisclosureGroup(isExpanded: $showsDaemon) {
                                daemonDetails.padding(.top, 10)
                            } label: {
                                sectionLabel("Daemon details", symbol: "server.rack")
                            }
                            DisclosureGroup(isExpanded: $showsThermal) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let extras = store.providerExtras {
                                        ProviderThermalView(store: extras, isVisible: store.dashboardVisible && showsThermal)
                                    }
                                    Text("macOS reports thermal state independently of provider health.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                .padding(.top, 10)
                            } label: {
                                sectionLabel("Thermal details", symbol: "thermometer.medium")
                            }
                            AdvancedSection(snapshot: store.snapshot, isExpanded: $expanded)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var overview: some View {
        HStack(alignment: .top, spacing: 12) {
            overviewCard("Monitor", value: statusTitle, symbol: statusSymbol, color: statusColor)
            overviewCard("Mac thermal", value: store.thermalState.displayName,
                         symbol: "thermometer.medium", color: .secondary)
        }
    }

    private func overviewCard(_ title: String, value: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium)).foregroundStyle(color)
            Text(value).font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    @ViewBuilder
    private func issues(at now: Date) -> some View {
        let warning = HealthPresentation.daemonWarning(store.snapshot.state, at: now)
        let diagnostics = store.snapshot.diagnostics
        let failures = store.snapshot.state.value?.modelLoadFailures ?? []
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Needs attention", symbol: "exclamationmark.triangle")
            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !diagnostics.isEmpty {
                Label("\(diagnostics.count) acquisition issue\(diagnostics.count == 1 ? "" : "s")",
                      systemImage: "waveform.path.ecg").foregroundStyle(.orange)
            }
            if !failures.isEmpty {
                Label("\(failures.count) reported model-load issue\(failures.count == 1 ? "" : "s")",
                      systemImage: "shippingbox").foregroundStyle(.orange)
            }
            if warning == nil && diagnostics.isEmpty && failures.isEmpty && allSourcesAvailable {
                Label("No issues reported by current sources", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            } else if warning == nil && diagnostics.isEmpty && failures.isEmpty {
                Label("Check source freshness below", systemImage: "clock.fill")
                    .foregroundStyle(.orange)
            }
            if !failures.isEmpty {
                DisclosureGroup("Model-load history") {
                    ProviderLoadFailuresView(failures: failures).padding(.top, 8)
                }
            }
            if !diagnostics.isEmpty {
                Text("Acquisition details are in Advanced telemetry.")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceFreshness: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("Source freshness", symbol: "clock.arrow.circlepath")
            freshnessRow("Daemon state", store.snapshot.state)
            freshnessRow("Loaded models", store.snapshot.loadedModels)
            freshnessRow("CLI status", store.snapshot.status)
            freshnessRow("Events", store.snapshot.eventFeed)
            Text("Captured time shows when data was read; it does not establish current health.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func freshnessRow<Value>(_ title: String, _ source: SourceAvailability<Value>) -> some View
    where Value: Equatable & Sendable {
        let presentation = freshness(source)
        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.callout.weight(.medium))
                .frame(width: 110, alignment: .leading)
            Image(systemName: presentation.symbol)
                .foregroundStyle(presentation.color)
                .accessibilityHidden(true)
            Text(presentation.text)
                .font(.callout).foregroundStyle(presentation.color)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(presentation.text)")
    }

    private func freshness<Value>(_ source: SourceAvailability<Value>) -> (text: String, symbol: String, color: Color)
    where Value: Equatable & Sendable {
        switch source {
        case .available(_, let capturedAt):
            return ("Captured \(TelemetryFormatting.timestamp(capturedAt))", "clock", .secondary)
        case .stale(_, let capturedAt, let reason):
            return ("Stale · \(TelemetryFormatting.timestamp(capturedAt)) · \(reason)", "clock.fill", .orange)
        case .unavailable(let reason):
            return ("Unavailable · \(reason)", "xmark.circle.fill", .red)
        }
    }

    @ViewBuilder
    private var daemonDetails: some View {
        if let state = store.snapshot.state.value {
            Text("Snapshot written \(TelemetryFormatting.timestamp(Date(timeIntervalSince1970: state.writtenAt)))")
                .font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), alignment: .leading)],
                      alignment: .leading, spacing: 12) {
                ForEach(HealthPresentation.daemonRows(state)) { row in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(row.label).font(.callout).foregroundStyle(.secondary)
                        Text(row.value).font(.headline).monospacedDigit().textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
                }
            }
            Text("Memory is daemon-reported GPU allocation. Reported slots are not a configured capacity limit.")
                .font(.callout).foregroundStyle(.secondary)
            if !state.slots.isEmpty {
                Text("Reported model slots").font(.headline)
                Text("KV is the attention-cache backend. MTP is multi-token prediction; enabled and active are separate states.")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(Array(state.slots.enumerated()), id: \.offset) { _, slot in
                    SlotCard(slot: slot)
                }
            }
        } else {
            Text("Daemon details unavailable.").foregroundStyle(.secondary)
        }
    }

    private func sectionLabel(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol).font(.headline)
    }

    private var allSourcesAvailable: Bool {
        isAvailable(store.snapshot.state)
            && isAvailable(store.snapshot.loadedModels)
            && isAvailable(store.snapshot.status)
            && isAvailable(store.snapshot.eventFeed)
    }

    private func isAvailable<Value>(_ source: SourceAvailability<Value>) -> Bool
    where Value: Equatable & Sendable {
        if case .available = source { return true }
        return false
    }

    private var statusTitle: String {
        switch store.snapshot.menuStatus {
        case .online: "Online"
        case .stale: "Stale"
        case .offline: "Offline"
        case .unavailable: "Unavailable"
        }
    }

    private var statusSymbol: String {
        switch store.snapshot.menuStatus {
        case .online: "checkmark.circle.fill"
        case .stale: "clock.fill"
        case .offline: "xmark.circle.fill"
        case .unavailable: "questionmark.circle.fill"
        }
    }

    private var statusColor: Color {
        switch store.snapshot.menuStatus {
        case .online: .green
        case .stale: .orange
        case .offline: .red
        case .unavailable: .secondary
        }
    }
}
