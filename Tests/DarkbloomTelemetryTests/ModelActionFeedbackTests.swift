import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model action feedback")
@MainActor
struct ModelActionFeedbackTests {
    @Test("the same error, validation, and Apply Live blocker appears once as an error")
    func repeatedBlockerKeepsErrorSeverity() {
        let rows = messages(
            validation: "Refresh the model catalog before applying changes.",
            applyLiveReason: "Refresh the model catalog before applying changes.",
            error: "Refresh the model catalog before applying changes."
        )

        #expect(rows == [ModelActionFeedback(
            kind: .error, text: "Refresh the model catalog before applying changes."
        )])
    }

    @Test("pairwise duplicates retain their highest severity and other blockers")
    func pairwiseCollisions() {
        #expect(messages(validation: "Catalog unavailable.",
                         applyLiveReason: "Provider stopped.",
                         error: "Catalog unavailable.") == [
            ModelActionFeedback(kind: .error, text: "Catalog unavailable."),
            ModelActionFeedback(kind: .availability, text: "Provider stopped."),
        ])
        #expect(messages(validation: "Catalog unavailable.",
                         applyLiveReason: "Catalog unavailable.",
                         error: "Download failed.") == [
            ModelActionFeedback(kind: .error, text: "Download failed."),
            ModelActionFeedback(kind: .validation, text: "Catalog unavailable."),
        ])
        #expect(messages(validation: "Model selection is empty.",
                         applyLiveReason: "Provider stopped.",
                         error: "Provider stopped.") == [
            ModelActionFeedback(kind: .error, text: "Provider stopped."),
            ModelActionFeedback(kind: .validation, text: "Model selection is empty."),
        ])
    }

    @Test("distinct blockers with similar prefixes are preserved in severity order")
    func similarPrefixesRemainDistinct() {
        let rows = messages(
            validation: "Cannot apply changes: select an enabled model.",
            applyLiveReason: "Cannot apply changes: start the provider.",
            error: "Cannot apply changes: model catalog is unavailable."
        )

        #expect(rows == [
            ModelActionFeedback(kind: .error,
                                text: "Cannot apply changes: model catalog is unavailable."),
            ModelActionFeedback(kind: .validation,
                                text: "Cannot apply changes: select an enabled model."),
            ModelActionFeedback(kind: .availability,
                                text: "Cannot apply changes: start the provider."),
        ])
        #expect(rows.map(\.id) == [.error, .validation, .availability])
    }

    @Test("whitespace is trimmed before comparing visible diagnostics")
    func whitespaceDoesNotCreateDuplicates() {
        #expect(messages(validation: "  Provider stopped. \n",
                         applyLiveReason: "\tProvider stopped.\t",
                         error: "\nProvider stopped.  ") == [
            ModelActionFeedback(kind: .error, text: "Provider stopped."),
        ])
    }

    @Test("sanitized visible text determines duplicates and never returns raw private paths")
    func sanitizerRunsBeforeDuplicateComparison() {
        let privatePaths = [
            "/Users/fixture-alice/private/cache",
            "/Users/fixture-bob/private/cache",
            "/Users/fixture-charlie/private/cache",
        ]
        let rows = messages(
            validation: "Could not read \(privatePaths[1]).",
            applyLiveReason: "Provider cannot apply changes.",
            error: "Could not read \(privatePaths[0]).",
            sanitize: { input in
                privatePaths.reduce(input) { text, path in
                    text.replacingOccurrences(of: path, with: "<model cache>")
                }
            }
        )

        #expect(rows == [
            ModelActionFeedback(kind: .error, text: "Could not read <model cache>."),
            ModelActionFeedback(kind: .availability, text: "Provider cannot apply changes."),
        ])
        #expect(rows.allSatisfy { row in
            !row.text.contains("/Users/") && privatePaths.allSatisfy { !row.text.contains($0) }
        })

        let allCollide = messages(
            validation: "Could not read \(privatePaths[1]).",
            applyLiveReason: "Could not read \(privatePaths[2]).",
            error: "Could not read \(privatePaths[0]).",
            sanitize: { input in
                privatePaths.reduce(input) { text, path in
                    text.replacingOccurrences(of: path, with: "<model cache>")
                }
            }
        )
        #expect(allCollide == [
            ModelActionFeedback(kind: .error, text: "Could not read <model cache>."),
        ])
    }

    @Test("blank inputs and messages erased by sanitization do not create empty rows")
    func blankRowsAreOmitted() {
        #expect(messages(validation: " \n\t", applyLiveReason: "Provider stopped.",
                         error: "") == [
            ModelActionFeedback(kind: .availability, text: "Provider stopped."),
        ])
        #expect(messages(validation: "erased diagnostic", applyLiveReason: "Provider stopped.",
                         error: nil, sanitize: { $0 == "erased diagnostic" ? " \n" : $0 }) == [
            ModelActionFeedback(kind: .availability, text: "Provider stopped."),
        ])
    }

    @Test("a refresh hides validation while preserving distinct errors and Apply Live blockers")
    func refreshingOnlySuppressesValidation() {
        let rows = messages(
            validation: "Select an enabled model.",
            applyLiveReason: "Wait for the provider to start.",
            error: "Download failed.",
            isRefreshing: true
        )

        #expect(rows == [
            ModelActionFeedback(kind: .error, text: "Download failed."),
            ModelActionFeedback(kind: .availability, text: "Wait for the provider to start."),
        ])
        #expect(messages(validation: "Provider stopped.", applyLiveReason: "Provider stopped.",
                         error: nil, isRefreshing: true) == [
            ModelActionFeedback(kind: .availability, text: "Provider stopped."),
        ])
        #expect(messages(validation: "Provider stopped.", applyLiveReason: "Provider stopped.",
                         error: "Provider stopped.", isRefreshing: true) == [
            ModelActionFeedback(kind: .error, text: "Provider stopped."),
        ])
    }

    @Test("no blocker produces one nonblank availability explanation")
    func noBlockerHasDefaultExplanation() throws {
        let baseline = messages()
        let row = try #require(baseline.first)

        #expect(baseline.count == 1)
        #expect(row.kind == .availability)
        #expect(!row.text.isEmpty)
        #expect(row.text == row.text.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(messages(validation: " \n", applyLiveReason: "\t", error: " ") == baseline)
    }

    private func messages(
        validation: String? = nil,
        applyLiveReason: String? = nil,
        error: String? = nil,
        isRefreshing: Bool = false,
        sanitize: (String) -> String = { $0 }
    ) -> [ModelActionFeedback] {
        ModelActionFeedback.messages(
            validation: validation,
            applyLiveReason: applyLiveReason,
            error: error,
            isRefreshing: isRefreshing,
            sanitize: sanitize
        )
    }
}
