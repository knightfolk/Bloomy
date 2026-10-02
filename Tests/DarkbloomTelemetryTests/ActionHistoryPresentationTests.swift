import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Action history presentation")
struct ActionHistoryPresentationTests {
    @Test("visible events preserve all existing filters and searchable fields",
          arguments: ActionHistoryFilter.allCases,
          ["", "  NuDgE  ", "automatic", "manual", "provider", "failed", "cancelled",
           "saveSettings", "save settings", "notConfirmed", "Base Reward",
           "Gemma 4 · 26B", "308", "613", "754", "not-a-match"])
    func baselineParity(filter: ActionHistoryFilter, query: String) {
        let events = fixtures()
        let actual = ActionHistoryPresentation.make(events: events, filter: filter, searchText: query,
            selectedID: events[1].id)
        let expected = reference(events, filter: filter, searchText: query)
        #expect(actual.events == expected)
        #expect(actual.selectedEvent == expected.first { $0.id == events[1].id })
    }

    @Test("canonical IDs and aliases both find the same account-wide job")
    func canonicalModelSearch() {
        let job = fixtures()[1]
        for query in [" EigenLabs/Qwen3.8-27B-4bit-mtp ", "eigenlabs/qwen3.8", "Qwen 3.8 · 27B"] {
            let presentation = ActionHistoryPresentation.make(events: fixtures(), filter: .jobs,
                searchText: query, selectedID: job.id)
            #expect(presentation.events == [job])
            #expect(presentation.selectedEvent == job)
        }
        #expect(reference(fixtures(), filter: .jobs, searchText: job.model!).isEmpty)
        #expect(ActionHistoryPresentation.make(events: fixtures(), filter: .actions,
            searchText: job.model!, selectedID: job.id).events.isEmpty)
    }

    @Test("currency and correlation IDs remain searchable without losing subcent precision")
    func numericAndCorrelationSearch() {
        let job = fixtures()[1]
        let action = fixtures()[0]
        let amount = ActionHistoryPresentation.currency(job.job!.amountMicroUSD)
        #expect(amount.contains("0.001250"))
        for (query, expected) in [(amount, job), (action.correlationID!.uuidString.lowercased(), action)] {
            let presentation = ActionHistoryPresentation.make(events: fixtures(), filter: .all,
                searchText: query, selectedID: expected.id)
            #expect(presentation.events == [expected])
            #expect(presentation.selectedEvent == expected)
        }
    }

    @Test("ordering uses descending date then UUID even when the source order changes")
    func exactOrdering() {
        let source = fixtures()
        // Rows 0 and 1 share a date; UUID, rather than incoming source position, breaks the tie.
        let expected = [source[1], source[0], source[2], source[3]]
        for input in [source, Array(source.reversed()), [source[2], source[0], source[3], source[1]]] {
            #expect(ActionHistoryPresentation.make(events: input, filter: .all,
                searchText: "", selectedID: nil).events == expected)
        }
    }

    @Test("same-ID middle-row corrections update matching and selected details immediately")
    func sameIDUpdates() {
        let original = fixtures()
        let previous = original[1]
        let replacement = ActionHistoryEvent(id: previous.id, occurredAt: previous.occurredAt,
            updatedAt: previous.updatedAt.addingTimeInterval(20), action: previous.action,
            trigger: previous.trigger, outcome: .failed, model: previous.model, reason: .requestFailed,
            job: .init(earningID: 308, promptTokens: 901, completionTokens: 902, amountMicroUSD: 56))
        var corrected = original
        corrected[1] = replacement
        #expect(corrected.map(\.id) == original.map(\.id))
        let before = ActionHistoryPresentation.make(events: original, filter: .jobs,
            searchText: "succeeded", selectedID: previous.id)
        #expect(before.selectedEvent == previous)
        let excluded = ActionHistoryPresentation.make(events: corrected, filter: .jobs,
            searchText: "succeeded", selectedID: previous.id)
        #expect(excluded.events == [original[2]])
        #expect(excluded.selectedEvent == nil)
        let after = ActionHistoryPresentation.make(events: corrected, filter: .jobs,
            searchText: "0.000056", selectedID: previous.id)
        #expect(after.events == [replacement])
        #expect(after.selectedEvent?.outcome == .failed)
        #expect(after.selectedEvent?.job?.completionTokens == 902)
        #expect(after.selectedEvent?.reason == .requestFailed)
    }

    @Test("selection follows visible records and never returns a removed or excluded payload")
    func visibleSelection() {
        let source = fixtures()
        let selected = source[1].id
        for (events, filter, query) in [([], ActionHistoryFilter.all, ""),
            (Array(source.dropFirst(2)), .all, ""), (source, .actions, ""), (source, .all, "missing")] {
            #expect(ActionHistoryPresentation.make(events: events, filter: filter,
                searchText: query, selectedID: selected).selectedEvent == nil)
        }
        #expect(ActionHistoryPresentation.make(events: source, filter: .all,
            searchText: "", selectedID: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!).selectedEvent == nil)
        #expect(ActionHistoryPresentation.make(events: source, filter: .jobs,
            searchText: "", selectedID: selected).selectedEvent == source[1])
    }

    private func fixtures() -> [ActionHistoryEvent] {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        func id(_ suffix: String) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-0000000000" + suffix)! }
        return [
            .init(id: id("01"), occurredAt: date, action: .nudge, trigger: .automatic,
                outcome: .failed, model: "gemma-4-26b-qat-4bit", reason: .notConfirmed, correlationID: id("90")),
            .init(id: id("02"), occurredAt: date, action: .job, trigger: .provider,
                outcome: .succeeded, model: "EigenLabs/Qwen3.8-27B-4bit-mtp",
                job: .init(earningID: 308, promptTokens: 613, completionTokens: 754, amountMicroUSD: 1_250)),
            .init(id: id("03"), occurredAt: date.addingTimeInterval(-10), action: .baseReward,
                trigger: .provider, outcome: .succeeded, model: "base_reward",
                job: .init(earningID: 309, promptTokens: 0, completionTokens: 0, amountMicroUSD: 75)),
            .init(id: id("04"), occurredAt: date.addingTimeInterval(-20), action: .saveSettings,
                trigger: .manual, outcome: .cancelled),
        ]
    }

    /// The pre-change query is an independent compatibility oracle. Canonical-ID
    /// search is intentionally tested separately because it adds a missing match.
    private func reference(_ events: [ActionHistoryEvent], filter: ActionHistoryFilter, searchText: String) -> [ActionHistoryEvent] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return events.filter(filter.includes).filter { event in
            guard !query.isEmpty else { return true }
            let action = event.model?.caseInsensitiveCompare("base_reward") == .orderedSame || event.action == .baseReward
                ? "Base Reward" : titleCase(event.action.rawValue)
            let searchable = [action, event.action.rawValue, event.trigger.rawValue, event.outcome.rawValue,
                event.model.map { $0.caseInsensitiveCompare("base_reward") == .orderedSame ? "Base reward" : ModelDisplayName.short($0) },
                event.reason?.rawValue, event.correlationID?.uuidString,
                event.job.map { String($0.earningID) }, event.job.map { String($0.promptTokens) },
                event.job.map { String($0.completionTokens) },
                event.job.map { (Decimal($0.amountMicroUSD) / Decimal(1_000_000)).formatted(.currency(code: "USD").precision(.fractionLength(6))) },
            ].compactMap { $0 }
            return searchable.contains { $0.localizedCaseInsensitiveContains(query) }
        }.sorted {
            $0.occurredAt != $1.occurredAt ? $0.occurredAt > $1.occurredAt : $0.id.uuidString > $1.id.uuidString
        }
    }

    private func titleCase(_ value: String) -> String {
        value.replacingOccurrences(of: "([a-z0-9])([A-Z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "([A-Z])([A-Z][a-z])", with: "$1 $2", options: .regularExpression)
            .replacingOccurrences(of: "[-_]+", with: " ", options: .regularExpression)
            .split(whereSeparator: \.isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
