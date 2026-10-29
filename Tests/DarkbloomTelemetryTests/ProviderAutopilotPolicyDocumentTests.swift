import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Preserving Autopilot policy edits")
struct ProviderAutopilotPolicyDocumentTests {
    private let source = """
    [backend]
    future_setting = 73
    [backend.model_autopilot]
    enabled = true # keep
    consent_recorded = true
    paused = false
    selected_models = ["org/model"]
    pinned_models = ["org/model"]
    revision = "rev-1"
    future_policy = "keep"
    [future_section]
    value = "untouched"

    """
    private var status: ProviderAutopilotStatus {
        .init(configuredEnabled: true, consentRecorded: true, configuredPaused: false,
              selectedModels: ["org/model"], pinnedModels: ["org/model"], configuredRevision: "rev-1")
    }

    @Test("pause replaces only the pause and revision values")
    func preservesEverythingElse() throws {
        let revision = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let output = try ProviderConfigDocument.renderingAutopilotPolicy(.pause, expected: status, in: Data(source.utf8), revision: revision)
        let expected = source.replacingOccurrences(of: "paused = false", with: "paused = true")
            .replacingOccurrences(of: "revision = \"rev-1\"", with: "revision = \"\(revision.uuidString)\"")
        #expect(output == Data(expected.utf8))
    }

    @Test("disable preserves unrelated data and clears paused")
    func disables() throws {
        let output = try ProviderConfigDocument.renderingAutopilotPolicy(.disable, expected: status, in: Data(source.utf8))
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("enabled = false # keep"))
        #expect(text.contains("consent_recorded = true"))
        #expect(text.contains("future_policy = \"keep\""))
        #expect(text.contains("[future_section]\nvalue = \"untouched\""))
    }

    @Test("stale revision or independently changed selection fails before any rewrite")
    func rejectsChangedPolicy() {
        for modified in [source.replacingOccurrences(of: "rev-1", with: "rev-2"),
                         source.replacingOccurrences(of: "selected_models = [\"org/model\"]", with: "selected_models = [\"other/model\"]")] {
            #expect(throws: ProviderConfigError.changedExternally) {
                try ProviderConfigDocument.renderingAutopilotPolicy(.pause, expected: status, in: Data(modified.utf8))
            }
        }
    }

    @Test("missing pause field uses provider default and retains the rest")
    func insertsPaused() throws {
        let input = source.replacingOccurrences(of: "paused = false\n", with: "")
        let result = try ProviderConfigDocument.renderingAutopilotPolicy(.pause, expected: status, in: Data(input.utf8))
        #expect(String(decoding: result, as: UTF8.self).contains("[backend.model_autopilot]\npaused = true\n"))
    }

    @Test("an unqualified CLI version cannot change the saved policy")
    func refusesUnknownCLIVersion() async throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyPolicyVersion-\(UUID().uuidString)")
        let configDir = home.appendingPathComponent(".config/darkbloom")
        let binDir = home.appendingPathComponent(".darkbloom/bin")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: binDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let config = configDir.appendingPathComponent("provider.toml")
        try Data(source.utf8).write(to: config)
        let executable = binDir.appendingPathComponent("darkbloom")
        try Data("#!/bin/sh\nprintf '0.99.0\\n'\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
        let client = ProviderExtrasClient(policy: DarkbloomSourcePolicy(homeDirectory: home, environmentPath: ""))
        await #expect(throws: ProviderExtrasMutationError.unsupportedAutopilotPolicyVersion) { try await client.setAutopilotPolicy(.pause) }
        #expect(try Data(contentsOf: config) == Data(source.utf8))
    }
}
