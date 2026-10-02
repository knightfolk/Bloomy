import DarkbloomTelemetry
import SwiftUI

private enum ActionHistoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case actions = "Actions"
    case jobs = "Jobs"

    var id: String { rawValue }

    func includes(_ event: ActionHistoryEvent) -> Bool {
        switch self {
        case .all: true
        case .actions: event.job == nil
        case .jobs: event.job != nil
        }
    }
}

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
                    if filteredEvents.isEmpty {
                        emptyState
                    } else {
                        Table(filteredEvents, selection: $selectedID) {
                            TableColumn("Time") { event in
                                Text(event.occurredAt, format: .dateTime.month().day().hour().minute())
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .help(event.occurredAt.formatted(date: .complete, time: .complete))
                            }
                            .width(min: 112, ideal: 145)

                            TableColumn("Action") { event in
                                Text(Self.actionLabel(event))
                                    .lineLimit(1)
                                    .help(Self.actionLabel(event))
                            }
                            .width(min: 100, ideal: 135)

                            TableColumn("Trigger") { event in
                                Text(Self.titleCase(event.trigger.rawValue))
                                    .lineLimit(1)
                            }
                            .width(min: 72, ideal: 100)

                            TableColumn("Result") { event in
                                Label(Self.titleCase(event.outcome.rawValue), systemImage: Self.outcomeSymbol(event.outcome.rawValue))
                                    .foregroundStyle(Self.outcomeColor(event.outcome.rawValue))
                                    .lineLimit(1)
                                    .help(Self.titleCase(event.outcome.rawValue))
                            }
                            .width(min: 94, ideal: 118)

                            TableColumn("Model") { event in
                                Text(Self.modelLabel(event))
                                    .lineLimit(1)
                                    .help(event.model ?? "No model recorded")
                            }
                            .width(min: 110, ideal: 190)
                        }
                        .frame(minHeight: 180, idealHeight: 300, maxHeight: 320)
                        .accessibilityLabel("Action and job history")

                        if let selectedEvent {
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

    private var filteredEvents: [ActionHistoryEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.events
            .filter(filter.includes)
            .filter { event in
                guard !query.isEmpty else { return true }
                let searchable = [
                    Self.actionLabel(event), event.action.rawValue, event.trigger.rawValue,
                    event.outcome.rawValue, event.model.map(Self.displayModel),
                    event.reason?.rawValue, event.correlationID?.uuidString,
                    event.job.map { String($0.earningID) },
                    event.job.map { String($0.promptTokens) },
                    event.job.map { String($0.completionTokens) },
                    event.job.map { Self.currency($0.amountMicroUSD) },
                ].compactMap { $0 }
                return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
                return $0.id.uuidString > $1.id.uuidString
            }
    }

    private var selectedEvent: ActionHistoryEvent? {
        guard let selectedID else { return nil }
        return filteredEvents.first { $0.id == selectedID }
    }

    private func details(for event: ActionHistoryEvent) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entry details").font(.headline)
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
    }

    private static func actionLabel(_ event: ActionHistoryEvent) -> String {
        if event.model?.caseInsensitiveCompare("base_reward") == .orderedSame
            || event.action.rawValue.caseInsensitiveCompare("baseReward") == .orderedSame {
            return "Base Reward"
        }
        return titleCase(event.action.rawValue)
    }

    private static func modelLabel(_ event: ActionHistoryEvent) -> String {
        guard let model = event.model else { return "—" }
        if model.caseInsensitiveCompare("base_reward") == .orderedSame { return "Base reward" }
        return displayModel(model)
    }

    private static func displayModel(_ model: String) -> String {
        if model.caseInsensitiveCompare("base_reward") == .orderedSame { return "Base reward" }
        return ModelDisplayName.short(model)
    }

    /// Converts enum raw values without coupling the view to current case names.
    private static func titleCase(_ rawValue: String) -> String {
        let spaced = rawValue
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        return spaced.split(whereSeparator: \.isWhitespace).map { component in
            component.prefix(1).uppercased() + component.dropFirst()
        }.joined(separator: " ")
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
        (Decimal(amountMicroUSD) / Decimal(1_000_000)).formatted(.currency(code: "USD").precision(.fractionLength(6)))
    }
}
