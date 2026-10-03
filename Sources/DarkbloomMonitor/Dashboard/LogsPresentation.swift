import DarkbloomTelemetry
import Foundation

struct LogsFormattingContext {
    let locale: Locale
    let calendar: Calendar
    let timeZone: TimeZone
}

/// One current display snapshot; formatters live only for this derivation so
/// locale, calendar, and time-zone changes cannot leave a persistent cache stale.
struct LogsPresentation {
    struct Row: Identifiable {
        let id: LogTableRow.ID
        let event: LogEvent
        let compactTimestamp: String
        let fullTimestamp: String
    }

    let rows: [Row]
    let selectedEvent: LogEvent?
    let sourceTimestamp: String?
    var rowIDs: [LogTableRow.ID] { rows.map(\.id) }

    func retainedSelection(_ selectedID: LogTableRow.ID?) -> LogTableRow.ID? {
        guard let selectedID, rows.contains(where: { $0.id == selectedID }) else { return nil }
        return selectedID
    }

    static func make(events: [LogEvent], query: LogsQuery, selectedID: LogTableRow.ID?,
                     sourceCapturedAt: Date? = nil, formattingContext: LogsFormattingContext? = nil, makeFormatter: () -> DateFormatter = { DateFormatter() }) -> Self {
        var compactFormatter: DateFormatter?
        var fullFormatter: DateFormatter?
        func compact(_ date: Date?) -> String {
            guard let date else { return "Unknown" }
            if compactFormatter == nil {
                let formatter = makeFormatter()
                if let context = formattingContext {
                    formatter.locale = context.locale
                    formatter.calendar = context.calendar
                    formatter.timeZone = context.timeZone
                }
                formatter.dateFormat = "MM/dd HH:mm"
                compactFormatter = formatter
            }
            return compactFormatter!.string(from: date)
        }
        func full(_ date: Date?) -> String {
            guard let date else { return "Unavailable — Timestamp unavailable" }
            if fullFormatter == nil {
                let formatter = makeFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss 'UTC'"
                fullFormatter = formatter
            }
            return fullFormatter!.string(from: date)
        }
        let sourceRows = LogTableRow.make(events: events, query: query)
        let rows = sourceRows.map { row in
            Row(id: row.id, event: row.event, compactTimestamp: compact(row.event.timestamp),
                fullTimestamp: full(row.event.timestamp))
        }
        return Self(rows: rows, selectedEvent: selectedID.flatMap { id in sourceRows.first { $0.id == id }?.event },
            sourceTimestamp: sourceCapturedAt.map { full($0) })
    }
}
