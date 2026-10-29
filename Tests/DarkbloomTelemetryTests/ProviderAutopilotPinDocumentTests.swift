import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Preserving Autopilot pin edits")
struct ProviderAutopilotPinDocumentTests {
    private let source = """
    # operator notes
    [backend]
    enabled_models = ["org/a", "org/b", "org/c"]
    preload_models = []
    max_model_slots = 3
    unknown = { keep = "yes" }
    [backend.model_autopilot] # enrolled policy
    enabled = true # retain enrollment
    consent_recorded = true
    paused = false
    selected_models = ["org/a", "org/b", "org/c"]
    # pin notes
    pinned_models = ["org/a"] # retain trailing note
    revision = 'r1' # retain revision note
    future_policy = "keep"
    [future]
    value = "untouched"

    """
    private var status: ProviderAutopilotStatus {
        .init(configuredEnabled: true, consentRecorded: true, configuredPaused: false,
              selectedModels: ["org/a", "org/b", "org/c"], pinnedModels: ["org/a"], configuredRevision: "r1")
    }
    private let revision = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Test("replacement sorts pins and preserves all other bytes and comments")
    func replacement() throws {
        let result = try ProviderConfigDocument.renderingAutopilotPins(["org/c", "org/b"], expected: status,
                                                                     in: Data(source.utf8), revision: revision)
        let expected = source.replacingOccurrences(of: "pinned_models = [\"org/a\"]", with: "pinned_models = [\"org/b\", \"org/c\"]")
            .replacingOccurrences(of: "revision = 'r1'", with: "revision = \"\(revision.uuidString)\"")
        #expect(result == Data(expected.utf8))
    }

    @Test("clearing pins leaves an explicit empty array")
    func clearsPins() throws {
        let result = try ProviderConfigDocument.renderingAutopilotPins([], expected: status, in: Data(source.utf8), revision: revision)
        let expected = source.replacingOccurrences(of: "pinned_models = [\"org/a\"]", with: "pinned_models = []")
            .replacingOccurrences(of: "revision = 'r1'", with: "revision = \"\(revision.uuidString)\"")
        #expect(result == Data(expected.utf8))
    }

    @Test("absent pin array is inserted in its table using existing line endings")
    func insertsMissingPins() throws {
        let input = source.replacingOccurrences(of: "pinned_models = [\"org/a\"] # retain trailing note\n", with: "")
            .replacingOccurrences(of: "\n", with: "\r\n")
        let empty = ProviderAutopilotStatus(configuredEnabled: true, consentRecorded: true, configuredPaused: false,
            selectedModels: status.selectedModels, pinnedModels: [], configuredRevision: "r1")
        let result = try ProviderConfigDocument.renderingAutopilotPins(["org/b"], expected: empty, in: Data(input.utf8), revision: revision)
        let expected = input.replacingOccurrences(of: "[backend.model_autopilot] # enrolled policy\r\n",
            with: "[backend.model_autopilot] # enrolled policy\r\npinned_models = [\"org/b\"]\r\n")
            .replacingOccurrences(of: "revision = 'r1'", with: "revision = \"\(revision.uuidString)\"")
        #expect(result == Data(expected.utf8))
    }

    @Test("unchanged sets do not rewrite the revision or array formatting")
    func noOp() throws {
        let result = try ProviderConfigDocument.renderingAutopilotPins(["org/a"], expected: status, in: Data(source.utf8))
        #expect(result == Data(source.utf8))
    }

    @Test("changes to revision, enrollment, selected models or old pins reject the edit")
    func stalePolicy() {
        for (before, after) in [("'r1'", "'r2'"), ("enabled = true", "enabled = false"),
                                ("consent_recorded = true", "consent_recorded = false"),
                                ("paused = false", "paused = true"),
                                ("selected_models = [\"org/a\", \"org/b\", \"org/c\"]", "selected_models = [\"org/b\"]"),
                                ("pinned_models = [\"org/a\"]", "pinned_models = []")] {
            let input = source.replacingOccurrences(of: before, with: after)
            #expect(throws: ProviderConfigError.changedExternally) {
                try ProviderConfigDocument.renderingAutopilotPins(["org/b"], expected: status, in: Data(input.utf8))
            }
        }
    }

    @Test("invalid, duplicate and unselected model IDs cannot be saved")
    func invalidPins() {
        for pins in [[""], ["org/a", "org/a"], ["org/missing"], ["org/a\n"], ["org/\"a"], ["org/😀"], [String(repeating: "a", count: 257)]] {
            #expect(throws: ProviderConfigError.self) {
                try ProviderConfigDocument.renderingAutopilotPins(pins, expected: status, in: Data(source.utf8))
            }
        }
    }

    @Test("unenrolled policy cannot authorize an edit")
    func invalidEnrollment() {
        let unenrolled = ProviderAutopilotStatus(configuredEnabled: false, consentRecorded: true, configuredPaused: false,
            selectedModels: status.selectedModels, pinnedModels: status.pinnedModels, configuredRevision: "r1")
        #expect(throws: ProviderConfigError.changedExternally) {
            try ProviderConfigDocument.renderingAutopilotPins(["org/b"], expected: unenrolled, in: Data(source.utf8))
        }
    }

    @Test("legacy unselected pins can be removed one at a time")
    func removesOrphanPins() throws {
        let input = source.replacingOccurrences(of: "pinned_models = [\"org/a\"]", with: "pinned_models = [\"org/orphan-a\", \"org/orphan-b\"]")
        let legacy = ProviderAutopilotStatus(configuredEnabled: true, consentRecorded: true, configuredPaused: false,
            selectedModels: status.selectedModels, pinnedModels: ["org/orphan-a", "org/orphan-b"], configuredRevision: "r1")
        let result = try ProviderConfigDocument.renderingAutopilotPins(["org/orphan-b"], expected: legacy, in: Data(input.utf8), revision: revision)
        #expect(String(decoding: result, as: UTF8.self).contains("pinned_models = [\"org/orphan-b\"]"))
        #expect(throws: ProviderConfigError.self) {
            try ProviderConfigDocument.renderingAutopilotPins(["org/orphan-b", "org/new-orphan"], expected: legacy, in: Data(input.utf8))
        }
    }

    @Test("comments within a replaced array fail safely while unchanged comments remain")
    func arrayCommentSafety() throws {
        let input = source.replacingOccurrences(of: "pinned_models = [\"org/a\"]", with: "pinned_models = [\n # keep with org/a\n \"org/a\",\n]")
        #expect(throws: ProviderConfigError.self) {
            try ProviderConfigDocument.renderingAutopilotPins(["org/b"], expected: status, in: Data(input.utf8))
        }
        #expect(try ProviderConfigDocument.renderingAutopilotPins(["org/a"], expected: status, in: Data(input.utf8)) == Data(input.utf8))
    }

    @Test("ambiguous pin or table syntax is rejected")
    func duplicatePinsOrTable() {
        for suffix in ["pinned_models = []\n", "[backend.model_autopilot]\npinned_models = []\n"] {
            let input = source.replacingOccurrences(of: "[future]", with: suffix + "[future]")
            #expect(throws: ProviderConfigError.self) {
                try ProviderConfigDocument.renderingAutopilotPins(["org/b"], expected: status, in: Data(input.utf8))
            }
        }
    }

    @Test("store rejects a stale full-file revision even when policy fields still match")
    func staleFileRevision() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyPinRevision-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let config = folder.appendingPathComponent("provider.toml")
        try Data(source.utf8).write(to: config)
        let runner = PinDocumentTestExecutor()
        let store = LocalProviderConfigStore(configURL: config, executable: folder.appendingPathComponent("unused"), runner: runner)
        let expectedRevision = try await store.cacheSourceRevision()
        let external = source.replacingOccurrences(of: "max_model_slots = 3", with: "max_model_slots = 1")
        try Data(external.utf8).write(to: config)
        await #expect(throws: ProviderConfigError.changedExternally) {
            try await store.saveAutopilotPins(["org/b"], expected: status, expectedSourceRevision: expectedRevision)
        }
        #expect(try Data(contentsOf: config) == Data(external.utf8))
        #expect(await runner.calls == 0)
    }
}

private actor PinDocumentTestExecutor: ProcessExecuting {
    private(set) var calls = 0
    func run(_ command: ProcessCommand, timeout: Duration, outputLimit: Int,
             onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws -> CommandResult {
        calls += 1
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}
