import Foundation

/// Consolidate identical public explanations without hiding distinct action
/// blockers. Errors win over validation warnings and availability descriptions.
struct ModelActionFeedback: Equatable, Identifiable, Sendable {
    enum Kind: String { case error, validation, availability }
    let kind: Kind
    let text: String
    var id: Kind { kind }

    static let applyLiveExplanation =
        "Apply Live switches the running provider to the saved model selection without restarting it."

    @MainActor static func error(_ value: String?, sanitize: (String) -> String) -> Self? {
        make(kind: .error, value: value, sanitize: sanitize)
    }

    @MainActor static func messages(validation: String?, applyLiveReason: String?, error: String?,
                         isRefreshing: Bool, sanitize: (String) -> String) -> [Self] {
        var messages: [Self] = []
        var seen = Set<String>()
        for (kind, value) in [(Kind.error, error), (.validation, isRefreshing ? nil : validation),
                              (.availability, applyLiveReason)] {
            guard let message = make(kind: kind, value: value, sanitize: sanitize),
                  seen.insert(message.text).inserted else { continue }
            messages.append(message)
        }
        if messages.isEmpty {
            messages.append(.init(kind: .availability, text: applyLiveExplanation))
        }
        return messages
    }

    @MainActor private static func make(kind: Kind, value: String?, sanitize: (String) -> String) -> Self? {
        guard let value else { return nil }
        let text = sanitize(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : .init(kind: kind, text: text)
    }
}
