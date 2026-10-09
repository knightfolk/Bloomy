import Foundation

public enum LegacyLogParser {
    public static func parse(_ text: String, limit: Int) -> [LogEvent] {
        guard limit > 0 else { return [] }
        return parse(text, limit: limit, formatter: dateFormatter())
    }

    static func dateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return formatter
    }

    static func parse(_ text: String, limit: Int, formatter: DateFormatter,
                      capture: ((LegacyLogLinePosition) -> Void)? = nil) -> [LogEvent] {
        guard limit > 0 else { return [] }
        var events: [LogEvent] = []
        // The caller needs the last matching events, not every event in the tail.
        // Work backward so older messages never pay for date parsing or allocation.
        let lines = text.split(whereSeparator: \.isNewline)
        for index in lines.indices.reversed() {
            if let event = parseLine(lines[index], date: { formatter.date(from: $0) }) {
                events.append(event)
                capture?(.init(ordinal: index, date: event.timestamp))
                if events.count == limit { break }
            }
        }
        return events.reversed()
    }

    /// Reconstruct raw fields from this read; cached positions retain no text.
    /// Positions follow the same oldest-to-newest order as a normal parse.
    static func replay(_ text: String, positions: [LegacyLogLinePosition]) -> [LogEvent]? {
        guard !positions.isEmpty else { return [] }
        let lines = text.split(whereSeparator: \.isNewline)
        var events: [LogEvent] = []
        for position in positions {
            guard lines.indices.contains(position.ordinal),
                  let event = parseLine(lines[position.ordinal], date: { _ in position.date }) else { return nil }
            events.append(event)
        }
        return events
    }

    private static func parseLine(_ line: Substring, date: (String) -> Date?) -> LogEvent? {
        let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
        guard fields.count == 4, let severity = severity(String(fields[1])) else { return nil }

        let rawCategory = String(fields[2])
        let category = rawCategory.hasSuffix(":") ? String(rawCategory.dropLast()) : rawCategory
        let message = String(fields[3])
        guard severity == .warning || severity == .error || isLifecycle(message) else { return nil }

        return LogEvent(
            timestamp: date(String(fields[0])),
            severity: severity,
            category: category,
            message: message,
            source: .legacy,
            processID: nil,
            processImage: nil
        )
    }

    private static func severity(_ value: String) -> LogSeverity? {
        switch value.lowercased() {
        case "info": .info
        case "notice": .notice
        case "warning", "warn": .warning
        case "error", "fault": .error
        default: nil
        }
    }

    private static func isLifecycle(_ message: String) -> Bool {
        lifecycleMessage(message)
    }
}

struct LegacyLogLinePosition: Sendable {
    let ordinal: Int
    /// Nil is a cached invalid timestamp, not a missing cache entry.
    let date: Date?
}

public enum UnifiedLogParser {
    public static func parse(line: Data) -> LogEvent? {
        guard let record = try? JSONDecoder().decode(UnifiedLogRecord.self, from: line),
              let severity = severity(record.messageType)
        else {
            return nil
        }

        let message = record.eventMessage == "<private>"
            ? "Message unavailable (privacy redacted)"
            : record.eventMessage
        guard severity == .warning || severity == .error || lifecycleMessage(message) else {
            return nil
        }

        return LogEvent(
            timestamp: unifiedLogDate(record.timestamp),
            severity: severity,
            category: record.category,
            message: message,
            source: .unified,
            processID: record.processID,
            processImage: record.processImagePath
        )
    }

    private static func severity(_ value: String) -> LogSeverity? {
        switch value.lowercased() {
        case "debug", "info": .info
        case "notice", "default": .notice
        case "warning", "warn": .warning
        case "error", "fault": .error
        default: nil
        }
    }
}

private struct UnifiedLogRecord: Decodable {
    let timestamp: String
    let messageType: String
    let category: String
    let processID: Int32?
    let processImagePath: String?
    let eventMessage: String
}

private let lifecycleKeywords: Set<String> = [
    "started", "starting", "stopped", "stopping", "loaded", "loading",
    "unloaded", "unloading", "connected", "connecting", "disconnected",
]

private func lifecycleMessage(_ message: String) -> Bool {
    return message.lowercased()
        .split { !$0.isLetter && !$0.isNumber }
        .contains { lifecycleKeywords.contains(String($0)) }
}

private func unifiedLogDate(_ timestamp: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZZZZZ"
    return formatter.date(from: timestamp)
}
