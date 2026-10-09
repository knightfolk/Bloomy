import DarkbloomTelemetry
import SwiftUI

struct HealthView: View {
    @ObservedObject var store: MonitorStore
    var openReadinessDestination: ((ProviderReadinessPresentation.Destination) -> Void)? = nil
    /// A popup owns its display lifecycle independently of the dashboard window.
    var visibilityOverride: Bool? = nil
    var showsTitle = true
    @State private var showsLogs = false
    @State private var showsProvider = false
    @State private var showsDaemon = false
    @State private var showsThermal = false
    @State private var expanded = false

    private var isVisible: Bool { visibilityOverride ?? store.dashboardVisible }

    var displaySchedule: VisibilityTimelineSchedule<PeriodicTimelineSchedule> {
        VisibilityTimelineSchedule(base: .periodic(from: .now, by: 5), isVisible: isVisible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsTitle { Text("Health & Logs").font(.largeTitle.bold()) }
            Picker("View", selection: $showsLogs) {
                Text("Source health").tag(false)
                Text("Logs").tag(true)
            }
            .pickerStyle(.segmented)
            if showsLogs {
                LogsView(feed: store.snapshot.eventFeed)
            } else {
                TimelineView(displaySchedule) { _ in
                    // A scheduled entry can predate newly published telemetry.
                    let now = Date()
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            ProviderReadinessSummaryView(presentation: store.providerReadiness(at: now),
                                showsEvidence: true, openDestination: openReadinessDestination)
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
                                VStack(alignment: .leading, spacing: 10) {
                                    daemonDetails
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 10)
                            } label: {
                                sectionLabel("Daemon details", symbol: "server.rack")
                            }
                            DisclosureGroup(isExpanded: $showsThermal) {
                                VStack(alignment: .leading, spacing: 10) {
                                    if let extras = store.providerExtras {
                                        ProviderThermalView(store: extras, isVisible: isVisible && showsThermal)
                                    }
                                    Text("macOS reports thermal state independently of provider health.")
                                        .font(.callout).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 10)
                            } label: {
                                HStack {
                                    sectionLabel("Thermal details", symbol: "thermometer.medium")
                                    Spacer()
                                    Text(store.thermalState.displayName).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                            AdvancedSection(snapshot: store.snapshot, isExpanded: $expanded)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(showsTitle ? 24 : 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func issues(at now: Date) -> some View {
        let warning = HealthPresentation.daemonWarning(store.snapshot.state, at: now)
        let diagnostics = store.snapshot.diagnostics
        let failures = store.snapshot.state.value?.modelLoadFailures ?? []
        let hasReportedIssues = warning != nil || !diagnostics.isEmpty || !failures.isEmpty
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel(
                hasReportedIssues ? "Needs attention" : allSourcesAvailable ? "Reported health" : "Readings incomplete",
                symbol: hasReportedIssues ? "exclamationmark.triangle" : allSourcesAvailable ? "waveform.path.ecg" : "clock")
                .accessibilityAddTraits(.isHeader)
            if let warning {
                Label(daemonAttentionTitle, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(warning)
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
            VStack(spacing: 0) {
                HealthSourceFreshnessRow(title: "Daemon state", source: store.snapshot.state)
                Divider()
                HealthSourceFreshnessRow(title: "Loaded models", source: store.snapshot.loadedModels)
                Divider()
                HealthSourceFreshnessRow(title: "CLI status", source: store.snapshot.status)
                Divider()
                HealthSourceFreshnessRow(title: "Events", source: store.snapshot.eventFeed)
            }
            .padding(.horizontal, 12)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
            Text("Captured time shows when data was read; it does not establish current health.")
                .font(.callout).foregroundStyle(.secondary)
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

    /// Keep the overview scannable; full source reasons remain selectable below.
    private var daemonAttentionTitle: String {
        switch store.snapshot.state {
        case .available: "Daemon timestamp is not current"
        case .stale: "Using last-known daemon details"
        case .unavailable: "Daemon details unavailable"
        }
    }

    private func isAvailable<Value>(_ source: SourceAvailability<Value>) -> Bool
    where Value: Equatable & Sendable {
        if case .available = source { return true }
        return false
    }


}

/// Keep source status scannable without discarding its diagnostic evidence.
struct HealthSourceFreshnessRow: View {
    let title: String
    private let capturedAt: Date?
    private let reason: String?
    private let isStale: Bool
    @State private var isExpanded: Bool

    init<Value>(title: String, source: SourceAvailability<Value>, isExpanded: Bool = false)
    where Value: Equatable & Sendable {
        self.title = title
        switch source {
        case .available(_, let capturedAt):
            self.capturedAt = capturedAt; reason = nil; isStale = false
        case .stale(_, let capturedAt, let reason):
            self.capturedAt = capturedAt; self.reason = reason; isStale = true
        case .unavailable(let reason):
            capturedAt = nil; self.reason = reason; isStale = false
        }
        _isExpanded = State(initialValue: isExpanded)
    }

    var body: some View {
        Group {
            if let reason {
                DisclosureGroup(isExpanded: $isExpanded) {
                    VStack(alignment: .leading, spacing: 7) {
                        if let capturedAt {
                            Text("Last capture: \(TelemetryFormatting.timestamp(capturedAt))")
                                .foregroundStyle(.secondary)
                        }
                        Text(reason)
                    }
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 7)
                    .padding(.bottom, 3)
                } label: {
                    heading
                }
            } else {
                heading
            }
        }
        .padding(.vertical, 10)
    }

    private var heading: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                Text(title).fontWeight(.medium)
                Spacer(minLength: 4)
                status
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fontWeight(.medium)
                status
            }
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(statusText)")
        .help(evidence)
    }

    private var status: some View {
        Label(statusText, systemImage: reason == nil ? "clock" : (isStale ? "clock.fill" : "xmark.circle.fill"))
            .foregroundStyle(reason == nil ? Color.secondary : (isStale ? .orange : .red))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var statusText: String {
        if reason != nil { return isStale ? "Stale" : "Unavailable" }
        return capturedAt.map { "Captured \(TelemetryFormatting.timestamp($0))" } ?? "Unavailable"
    }

    private var evidence: String {
        [capturedAt.map { "Captured \(TelemetryFormatting.timestamp($0))" }, reason]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
