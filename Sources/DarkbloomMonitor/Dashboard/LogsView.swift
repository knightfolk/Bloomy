import DarkbloomTelemetry
import SwiftUI

struct LogsQuery {
    var severity: LogSeverity? = nil
    var source: LogSource? = nil
    var text = ""

    func apply(_ events: [LogEvent]) -> [LogEvent] {
        let search = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter { event in
            (severity == nil || event.severity == severity)
                && (source == nil || event.source == source)
                && (search.isEmpty || event.message.localizedCaseInsensitiveContains(search)
                    || event.category.localizedCaseInsensitiveContains(search))
        }
    }
}

struct LogsView: View {
    let feed: SourceAvailability<EventFeed>
    @State private var query = LogsQuery()
    @State private var selectedID: LogTableRow.ID?
    @State private var exportPreview: LogExportSnapshot?
    @State private var exportFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent logs").font(.title2.bold())
            toolbar
            sourceStatus
            if exportFailed {
                Label("Could not prepare an export from this snapshot.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let message = feed.eventEmptyMessage {
                Text(message).foregroundStyle(.secondary)
            } else {
                if rows.isEmpty {
                    Text("No events match these filters.").foregroundStyle(.secondary)
                } else {
                    Table(rows, selection: $selectedID) {
                        TableColumn("Local time") { row in
                            Text(Self.compactTimestamp(row.event.timestamp))
                                .monospacedDigit()
                                .lineLimit(1)
                                .help(TelemetryFormatting.timestamp(row.event.timestamp))
                        }
                        .width(100)
                        TableColumn("Severity") { row in
                            Label(row.event.severity.rawValue.capitalized,
                                  systemImage: EventRow.severitySymbol(for: row.event.severity))
                                .foregroundStyle(EventRow.severityColor(for: row.event.severity))
                                .lineLimit(1)
                        }
                        .width(85)
                        TableColumn("Source") { row in
                            Text(row.event.source.rawValue.capitalized).lineLimit(1)
                        }
                        .width(65)
                        TableColumn("Message") { row in
                            Text(row.event.message)
                                .lineLimit(1)
                                .help(row.event.message)
                        }
                    }
                    .frame(minHeight: 180)
                    .accessibilityLabel("Recent log events")
                    if let event = selectedEvent {
                        eventDetails(event)
                    } else {
                        Text("Select an event to see its full details.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            Text("Export preview withholds known sensitive fields and omits oversized events. Review it before sharing.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $exportPreview) { snapshot in
            LogExportPreviewView(snapshot: snapshot)
        }
        .onChange(of: rows.map(\.id)) { _, _ in
            selectedID = LogTableRow.retainedSelection(selectedID, in: rows)
        }
    }

    private static func compactTimestamp(_ date: Date?) -> String {
        guard let date else { return "Unknown" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MM/dd HH:mm"
        return formatter.string(from: date)
    }

    private var rows: [LogTableRow] {
        LogTableRow.make(events: feed.value?.events ?? [], query: query)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                searchField.frame(minWidth: 180)
                severityPicker
                sourcePicker
                exportButton
            }
            VStack(alignment: .leading, spacing: 8) {
                searchField
                HStack(spacing: 8) {
                    severityPicker
                    sourcePicker
                    Spacer(minLength: 0)
                    exportButton
                }
            }
        }
    }

    private var searchField: some View {
        TextField("Search logs", text: $query.text)
            .textFieldStyle(.roundedBorder)
            .accessibilityLabel("Search message or category")
    }

    private var severityPicker: some View {
        Picker("Severity", selection: $query.severity) {
            Text("All severities").tag(nil as LogSeverity?)
            ForEach([LogSeverity.info, .notice, .warning, .error], id: \.rawValue) {
                Text($0.rawValue.capitalized).tag(Optional($0))
            }
        }
        .labelsHidden()
        .accessibilityLabel("Severity")
        .frame(width: 125)
    }

    private var sourcePicker: some View {
        Picker("Source", selection: $query.source) {
            Text("All sources").tag(nil as LogSource?)
            Text("Legacy").tag(Optional(LogSource.legacy))
            Text("Unified").tag(Optional(LogSource.unified))
        }
        .labelsHidden()
        .accessibilityLabel("Source")
        .frame(width: 110)
    }

    private var exportButton: some View {
        Button {
            prepareExport()
        } label: {
            Label("Preview export", systemImage: "square.and.arrow.up")
        }
        .disabled(rows.isEmpty)
    }

    private var selectedEvent: LogEvent? {
        guard let selectedID else { return nil }
        return rows.first(where: { $0.id == selectedID })?.event
    }

    @ViewBuilder
    private var sourceStatus: some View {
        switch feed {
        case .available(_, let capturedAt):
            Label("Events captured \(TelemetryFormatting.timestamp(capturedAt))", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .stale(_, let capturedAt, let reason):
            Label("Stale events from \(TelemetryFormatting.timestamp(capturedAt)) · \(reason)",
                  systemImage: "clock.fill")
                .foregroundStyle(.orange)
        case .unavailable(let reason):
            Label("Logs unavailable · \(reason)", systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
        }
    }

    private func eventDetails(_ event: LogEvent) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Event details").font(.headline)
            ScrollView {
                EventRow(event: event)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 170)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func prepareExport() {
        exportFailed = false
        let capturedAt: Date
        let stale: Bool
        switch feed {
        case .available(_, let date): capturedAt = date; stale = false
        case .stale(_, let date, _): capturedAt = date; stale = true
        case .unavailable: return
        }
        do {
            exportPreview = try LogExportSnapshot.make(events: query.apply(feed.value?.events ?? []),
                sourceCapturedAt: capturedAt, sourceIsStale: stale, createdAt: Date())
        } catch {
            exportFailed = true
        }
    }
}

struct LogTableRow: Identifiable {
    struct ID: Hashable {
        fileprivate let event: EventKey
        let occurrence: Int
    }

    let id: ID
    let event: LogEvent

    static func make(events: [LogEvent], query: LogsQuery) -> [LogTableRow] {
        var occurrences: [EventKey: Int] = [:]
        return events.compactMap { event in
            let key = EventKey(event)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            // Assign before filtering so a filter cannot renumber matching rows.
            guard !query.apply([event]).isEmpty else { return nil }
            return LogTableRow(id: ID(event: key, occurrence: occurrence), event: event)
        }
    }

    static func retainedSelection(_ selectedID: ID?, in rows: [LogTableRow]) -> ID? {
        guard let selectedID, rows.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }
}

// A value key survives prepends and reordering. The ordinal keeps equal payloads
// separately selectable without claiming a source occurrence ID the feed lacks.
// When equal occurrences change, retain the displayed payload while its ordinal exists.
fileprivate struct EventKey: Hashable {
    let timestamp: Date?
    let severity: String
    let category: String
    let message: String
    let source: String
    let processID: Int32?
    let processImage: String?

    init(_ event: LogEvent) {
        timestamp = event.timestamp
        severity = event.severity.rawValue
        category = event.category
        message = event.message
        source = event.source.rawValue
        processID = event.processID
        processImage = event.processImage
    }
}
