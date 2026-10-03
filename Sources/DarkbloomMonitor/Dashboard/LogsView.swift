import DarkbloomTelemetry
import SwiftUI

struct LogsQuery {
    var severity: LogSeverity? = nil
    var source: LogSource? = nil
    var text = ""

    func apply(_ events: [LogEvent]) -> [LogEvent] {
        events.filter(matcher())
    }

    fileprivate func matcher() -> (LogEvent) -> Bool {
        let search = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return { event in
            (severity == nil || event.severity == severity)
                && (source == nil || event.source == source)
                && (search.isEmpty || event.message.localizedCaseInsensitiveContains(search)
                    || event.category.localizedCaseInsensitiveContains(search))
        }
    }
}

struct LogsView: View {
    let feed: SourceAvailability<EventFeed>
    @Environment(\.locale) private var locale
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var timeZone
    @State private var query = LogsQuery()
    @State private var selectedID: LogTableRow.ID?
    @State private var exportPreview: LogExportSnapshot?
    @State private var exportFailed = false

    var body: some View {
        let presentation = LogsPresentation.make(events: feed.value?.events ?? [], query: query,
            selectedID: selectedID, sourceCapturedAt: sourceCapturedAt,
            formattingContext: LogsFormattingContext(locale: locale, calendar: calendar, timeZone: timeZone))
        return GeometryReader { geometry in
            ScrollView {
                content(tableHeight: max(180, geometry.size.height * 0.6), presentation: presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(item: $exportPreview) { snapshot in
            LogExportPreviewView(snapshot: snapshot)
        }
        .onChange(of: presentation.rowIDs) { _, _ in
            selectedID = presentation.retainedSelection(selectedID)
        }
    }

    private func content(tableHeight: CGFloat, presentation: LogsPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent logs").font(.title2.bold())
            toolbar(hasRows: !presentation.rows.isEmpty)
            sourceStatus(timestamp: presentation.sourceTimestamp)
            if exportFailed {
                Label("Could not prepare an export from this snapshot.", systemImage: "exclamationmark.triangle")
                    .font(.callout).foregroundStyle(.orange)
            }
            if let message = feed.eventEmptyMessage {
                Text(message).foregroundStyle(.secondary)
            } else {
                if presentation.rows.isEmpty {
                    Text("No events match these filters.").foregroundStyle(.secondary)
                } else {
                    Table(presentation.rows, selection: $selectedID) {
                        TableColumn("Local time") { row in
                            Text(row.compactTimestamp)
                                .monospacedDigit()
                                .lineLimit(1)
                                .help(row.fullTimestamp)
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
                    // Bound the table's own scrolling region so the outer page
                    // can scroll to event details in a compact dashboard.
                    .frame(height: tableHeight)
                    .accessibilityLabel("Recent log events")
                    if let event = presentation.selectedEvent {
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
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var sourceCapturedAt: Date? {
        switch feed {
        case .available(_, let date), .stale(_, let date, _): date
        case .unavailable: nil
        }
    }

    private func toolbar(hasRows: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                searchField.frame(minWidth: 180)
                severityPicker
                sourcePicker
                exportButton(hasRows: hasRows)
            }
            VStack(alignment: .leading, spacing: 8) {
                searchField
                HStack(spacing: 8) {
                    severityPicker
                    sourcePicker
                    Spacer(minLength: 0)
                    exportButton(hasRows: hasRows)
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

    private func exportButton(hasRows: Bool) -> some View {
        Button {
            prepareExport()
        } label: {
            Label("Preview export", systemImage: "square.and.arrow.up")
        }
        .disabled(!hasRows)
    }

    @ViewBuilder
    private func sourceStatus(timestamp: String?) -> some View {
        switch feed {
        case .available:
            Label("Events captured \(timestamp ?? "Unavailable — Timestamp unavailable")", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        case .stale(_, _, let reason):
            Label("Stale events from \(timestamp ?? "Unavailable — Timestamp unavailable") · \(reason)",
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
        let matches = query.matcher()
        return events.compactMap { event in
            let key = EventKey(event)
            let occurrence = occurrences[key, default: 0]
            occurrences[key] = occurrence + 1
            // Assign before filtering so a filter cannot renumber matching rows.
            guard matches(event) else { return nil }
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
