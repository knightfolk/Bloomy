import DarkbloomTelemetry
import SwiftUI

struct ActionHistoryView: View {
    @ObservedObject var store: ActionHistoryStore
    @State private var filter = ActionHistoryFilter.all
    @State private var searchText = ""
    @State private var selectedID: UUID?
    @State private var showsRecordingNotes: Bool

    init(store: ActionHistoryStore, selectedID: UUID? = nil, showsRecordingNotes: Bool = false) {
        self.store = store
        _selectedID = State(initialValue: selectedID)
        _showsRecordingNotes = State(initialValue: showsRecordingNotes)
    }

    var body: some View {
        let presentation = ActionHistoryPresentation.make(
            events: store.events, filter: filter, searchText: searchText, selectedID: selectedID
        )
        VStack(alignment: .leading, spacing: 12) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    recordingNotes
                    if let storageError = store.storageError {
                        Label(storageError, systemImage: "exclamationmark.triangle.fill")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("actionHistory.storageError")
                    }
                    controls
                    if presentation.events.isEmpty {
                        emptyState
                    } else {
                        GeometryReader { geometry in
                            historyTable(presentation.events, width: geometry.size.width)
                        }
                        // Reserve a header and comfortable native rows, while
                        // keeping short search results close to their details.
                        .frame(height: max(72, min(320, 40 + CGFloat(min(presentation.events.count, 10)) * 28)))
                        .accessibilityLabel("Action and job history")

                        if let selectedEvent = presentation.selectedEvent {
                            ScrollView { details(for: selectedEvent) }
                                .frame(minHeight: 100, idealHeight: 160, maxHeight: 180)
                        } else {
                            Text("Select an entry to see its details.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task { store.refresh() }
        .onChange(of: filter) { _, _ in selectedID = nil }
        .onChange(of: searchText) { _, _ in selectedID = nil }
        .onChange(of: store.events.map(\.id)) { _, ids in
            if let selectedID, !ids.contains(selectedID) { self.selectedID = nil }
        }
    }

    @ViewBuilder
    private func historyTable(_ events: [ActionHistoryEvent], width: CGFloat) -> some View {
        // Keep the model in view at the dashboard's compact width. Trigger is
        // still available in selected-entry details. Separate builders support
        // macOS 14.0, before conditional table columns became available.
        if width < 700 {
            Table(events, selection: $selectedID) {
                timeColumn(compact: true)
                actionColumn(compact: true)
                resultColumn(compact: true)
                modelColumn(compact: true)
            }
        } else {
            Table(events, selection: $selectedID) {
                timeColumn(compact: false)
                actionColumn(compact: false)
                TableColumn("Trigger") { event in
                    Text(Self.titleCase(event.trigger.rawValue)).lineLimit(1)
                }.width(min: 72, ideal: 100)
                resultColumn(compact: false)
                modelColumn(compact: false)
            }
        }
    }

    private func timeColumn(compact: Bool) -> some TableColumnContent<ActionHistoryEvent, Never> {
        TableColumn("Time") { (event: ActionHistoryEvent) in
            Text(event.occurredAt, format: .dateTime.month().day().hour().minute())
                .monospacedDigit().lineLimit(1)
                .help(event.occurredAt.formatted(date: .complete, time: .complete))
        }.width(min: compact ? 116 : 112, ideal: compact ? 124 : 145, max: compact ? 128 : .infinity)
    }

    private func actionColumn(compact: Bool) -> some TableColumnContent<ActionHistoryEvent, Never> {
        TableColumn("Action") { (event: ActionHistoryEvent) in
            Text(Self.actionLabel(event)).lineLimit(1).help(Self.actionLabel(event))
        }.width(min: compact ? 68 : 100, ideal: compact ? 76 : 135, max: compact ? 82 : .infinity)
    }

    private func resultColumn(compact: Bool) -> some TableColumnContent<ActionHistoryEvent, Never> {
        TableColumn("Result") { (event: ActionHistoryEvent) in
            Label(Self.titleCase(event.outcome.rawValue), systemImage: Self.outcomeSymbol(event.outcome.rawValue))
                .foregroundStyle(Self.outcomeColor(event.outcome.rawValue)).lineLimit(1)
                .help(Self.titleCase(event.outcome.rawValue))
        }.width(min: compact ? 92 : 94, ideal: compact ? 100 : 118, max: compact ? 106 : .infinity)
    }

    private func modelColumn(compact: Bool) -> some TableColumnContent<ActionHistoryEvent, Never> {
        TableColumn("Model") { (event: ActionHistoryEvent) in
            Text(Self.modelLabel(event)).lineLimit(1).help(event.model ?? "No model recorded")
        }.width(min: compact ? 100 : 110, ideal: compact ? 136 : 190, max: compact ? 150 : .infinity)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("History").font(.largeTitle.bold())
            Spacer()
            Button { store.refresh() } label: {
                Label("Refresh history", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("Refresh history")
            .accessibilityLabel("Refresh history")
        }
    }

    private var recordingNotes: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(recordingStartLabel, systemImage: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup("About this history", isExpanded: $showsRecordingNotes) {
                // Keep long wrapping notes from contributing an unbounded
                // ideal height during native split-view size negotiation.
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Action tracking starts from that date; older actions are not backfilled. Reported jobs and base rewards may include up to 30 days of earlier account history, subject to the server’s history limit. Entries are retained for up to 30 days, with a 5,000-entry limit.")
                        Text("Job and reward records come from account-wide earnings history and may be incomplete because the server limits history. They may reflect another owned machine and do not prove this Mac served the work.")
                    }
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 140)
            }.font(.caption)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var recordingStartLabel: String {
        guard let startedAt = store.recordingStartedAt else {
            return "Recording start time unavailable"
        }
        return "Recording since \(startedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                filterPicker
                searchField
            }
            VStack(alignment: .leading, spacing: 8) {
                filterPicker
                searchField
            }
        }
    }

    private var filterPicker: some View {
        Picker("History type", selection: $filter) {
            ForEach(ActionHistoryFilter.allCases) { option in
                Text(option.rawValue).tag(option)
            }
        }
        .pickerStyle(.segmented)
        .fixedSize()
        .accessibilityLabel("Filter history by type")
    }

    private var searchField: some View {
        TextField("Search history", text: $searchText)
            .textFieldStyle(.roundedBorder)
            .frame(minWidth: 180, maxWidth: 360)
            .accessibilityLabel("Search action and job history")
    }

    @ViewBuilder
    private var emptyState: some View {
        if store.events.isEmpty {
            ContentUnavailableView(
                "No history recorded yet",
                systemImage: "clock.arrow.circlepath",
                description: Text("App actions will appear here as they happen. Reported account-wide jobs and rewards may include recent history.")
            )
        } else {
            ContentUnavailableView(
                "No matching entries",
                systemImage: "line.3.horizontal.decrease.circle",
                description: Text("Try another history type or search term.")
            )
        }
    }

    private func details(for event: ActionHistoryEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entry details").font(.headline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 7) {
                detailRow("Time", event.occurredAt.formatted(date: .complete, time: .complete))
                detailRow("Action", Self.actionLabel(event))
                detailRow("Trigger", Self.titleCase(event.trigger.rawValue))
                detailRow("Result", Self.titleCase(event.outcome.rawValue))
                if let model = event.model {
                    detailRow("Model", Self.displayModel(model), help: model)
                }
                if let reason = event.reason {
                    detailRow("Reason", Self.titleCase(reason.rawValue))
                }
                if let correlationID = event.correlationID {
                    detailRow("Related action ID", correlationID.uuidString)
                }
                if let job = event.job {
                    detailRow("Earning ID (not request ID)", job.earningID.formatted())
                    detailRow("Prompt tokens", job.promptTokens.formatted())
                    detailRow("Completion tokens", job.completionTokens.formatted())
                    detailRow("Reported amount", Self.currency(job.amountMicroUSD))
                }
            }
            if event.job != nil {
                Label("Account-wide earnings record; this work may have been served by another owned machine and the server may limit older records.", systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if event.action.rawValue.caseInsensitiveCompare("nudge") == .orderedSame {
                Label("Succeeded means the self-route returned a response. It does not guarantee public work or show that a later job came from this nudge.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("actionHistory.details")
    }

    private func detailRow(_ label: String, _ value: String, help: String? = nil) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .trailing)
            Text(value)
                .font(.callout)
                .textSelection(.enabled)
                .help(help ?? value)
        }
        // Keep the native label and selectable value together as one field
        // group, without collapsing the whole entry or relabeling selectable
        // text (which can recurse through the macOS accessibility bridge).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("actionHistory.field.\(label)")
    }

    private static func actionLabel(_ event: ActionHistoryEvent) -> String {
        ActionHistoryPresentation.actionLabel(event)
    }

    private static func modelLabel(_ event: ActionHistoryEvent) -> String {
        guard let model = event.model else { return "—" }
        if model.caseInsensitiveCompare("base_reward") == .orderedSame { return "Base reward" }
        return displayModel(model)
    }

    private static func displayModel(_ model: String) -> String {
        ActionHistoryPresentation.displayModel(model)
    }

    private static func titleCase(_ rawValue: String) -> String {
        ActionHistoryPresentation.titleCase(rawValue)
    }

    private static func outcomeSymbol(_ rawValue: String) -> String {
        switch rawValue.lowercased() {
        case "succeeded", "success": "checkmark.circle.fill"
        case "failed": "xmark.circle.fill"
        case "skipped", "unconfirmed", "cancelled", "interrupted": "exclamationmark.circle.fill"
        default: "circle"
        }
    }

    private static func outcomeColor(_ rawValue: String) -> Color {
        switch rawValue.lowercased() {
        case "succeeded", "success": .green
        case "failed", "interrupted": .red
        case "skipped", "unconfirmed", "cancelled": .orange
        default: .secondary
        }
    }

    static func currency(_ amountMicroUSD: Int64) -> String {
        ActionHistoryPresentation.currency(amountMicroUSD)
    }
}
