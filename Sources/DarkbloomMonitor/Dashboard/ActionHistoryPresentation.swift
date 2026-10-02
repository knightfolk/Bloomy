import DarkbloomTelemetry
import Foundation

enum ActionHistoryFilter: String, CaseIterable, Identifiable {
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

/// One value snapshot per render; no retained cache can hide a same-ID update.
struct ActionHistoryPresentation {
    let events: [ActionHistoryEvent]
    let selectedEvent: ActionHistoryEvent?

    static func make(
        events: [ActionHistoryEvent], filter: ActionHistoryFilter, searchText: String, selectedID: UUID?
    ) -> Self {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let visible = events.filter { event in
            guard filter.includes(event) else { return false }
            guard !query.isEmpty else { return true }
            return matches(event, query: query)
        }.sorted {
            if $0.occurredAt != $1.occurredAt { return $0.occurredAt > $1.occurredAt }
            return $0.id.uuidString > $1.id.uuidString
        }
        return Self(events: visible, selectedEvent: selectedID.flatMap { id in visible.first { $0.id == id } })
    }

    private static func matches(_ event: ActionHistoryEvent, query: String) -> Bool {
        func contains(_ text: String?) -> Bool { text?.localizedCaseInsensitiveContains(query) == true }
        // Preserve every search field, but defer display/number formatting until
        // cheaper raw fields have failed. A canonical ID never needs an alias.
        if contains(event.action.rawValue) || contains(event.trigger.rawValue)
            || contains(event.outcome.rawValue) || contains(event.model)
            || contains(event.reason?.rawValue) || contains(event.correlationID?.uuidString) { return true }
        if let job = event.job,
           contains(String(job.earningID)) || contains(String(job.promptTokens)) || contains(String(job.completionTokens)) {
            return true
        }
        if let model = event.model, contains(displayModel(model)) { return true }
        if contains(actionLabel(event)) { return true }
        return event.job.map { contains(currency($0.amountMicroUSD)) } ?? false
    }

    static func actionLabel(_ event: ActionHistoryEvent) -> String {
        if event.model?.caseInsensitiveCompare("base_reward") == .orderedSame
            || event.action.rawValue.caseInsensitiveCompare("baseReward") == .orderedSame {
            return "Base Reward"
        }
        return titleCase(event.action.rawValue)
    }

    static func displayModel(_ model: String) -> String {
        if model.caseInsensitiveCompare("base_reward") == .orderedSame { return "Base reward" }
        return ModelDisplayName.short(model)
    }

    static func titleCase(_ rawValue: String) -> String {
        let spaced = rawValue
            .replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
        return spaced.split(whereSeparator: \.isWhitespace).map { component in
            component.prefix(1).uppercased() + component.dropFirst()
        }.joined(separator: " ")
    }

    static func currency(_ amountMicroUSD: Int64) -> String {
        (Decimal(amountMicroUSD) / Decimal(1_000_000)).formatted(.currency(code: "USD").precision(.fractionLength(6)))
    }
}
