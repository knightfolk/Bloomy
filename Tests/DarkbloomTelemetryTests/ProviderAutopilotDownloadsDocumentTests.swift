import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Preserving Autopilot download settings")
struct ProviderAutopilotDownloadsDocumentTests {
    private let source = """
    [backend]
    future_setting = 73
    [backend.autopilot_downloads]
    enabled = true # keep
    max_storage_gb = 120
    max_models = 3
    reserve_gb = 50
    future_policy = "keep"
    [future_section]
    value = "untouched"

    """
    private var current: AutopilotDownloadPolicy { .init(enabled: true, maxStorageGB: 120, maxModels: 3, reserveGB: 50) }

    @Test("disabling keeps both limits and every unrelated byte")
    func disable() throws {
        let desired = AutopilotDownloadPolicy(enabled: false, maxStorageGB: 120, maxModels: 3, reserveGB: 50)
        let result = try ProviderConfigDocument.renderingAutopilotDownloads(expected: current, desired: desired, in: Data(source.utf8))
        #expect(result == Data(source.replacingOccurrences(of: "enabled = true # keep", with: "enabled = false # keep").utf8))
        let formatted = source.replacingOccurrences(of: "max_storage_gb = 120", with: "max_storage_gb = 1_20 # retained")
        let preserved = try ProviderConfigDocument.renderingAutopilotDownloads(expected: current, desired: desired, in: Data(formatted.utf8))
        #expect(String(decoding: preserved, as: UTF8.self).contains("max_storage_gb = 1_20 # retained"))
    }

    @Test("enabling replaces limits and retains unknown fields")
    func replaceLimits() throws {
        let desired = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 80, maxModels: nil, reserveGB: 50)
        let result = try ProviderConfigDocument.renderingAutopilotDownloads(expected: current, desired: desired, in: Data(source.utf8))
        let text = String(decoding: result, as: UTF8.self)
        #expect(text.contains("max_storage_gb = 80"))
        #expect(!text.contains("max_models ="))
        #expect(text.contains("reserve_gb = 50"))
        #expect(text.contains("future_policy = \"keep\""))
        #expect(text.contains("[future_section]\nvalue = \"untouched\""))
    }

    @Test("missing section uses official defaults and can be created")
    func createSection() throws {
        let input = Data("[backend]\nfuture_setting = 73\n".utf8)
        let expected = AutopilotDownloadPolicy(enabled: true)
        let desired = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 60, maxModels: 2)
        let result = try ProviderConfigDocument.renderingAutopilotDownloads(expected: expected, desired: desired, in: input)
        let text = String(decoding: result, as: UTF8.self)
        #expect(text.contains("future_setting = 73"))
        #expect(text.contains("[backend.autopilot_downloads]"))
        #expect(text.contains("max_storage_gb = 60"))
        #expect(text.contains("max_models = 2"))
    }

    @Test("stale settings and removal of a commented limit fail closed")
    func rejectsConflicts() {
        let desired = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 80, maxModels: nil, reserveGB: 50)
        #expect(throws: ProviderConfigError.changedExternally) {
            try ProviderConfigDocument.renderingAutopilotDownloads(expected: .init(enabled: true, maxStorageGB: 1, maxModels: 3, reserveGB: 50), desired: desired, in: Data(source.utf8))
        }
        let commented = source.replacingOccurrences(of: "max_models = 3", with: "max_models = 3 # keep this")
        #expect(throws: (any Error).self) {
            try ProviderConfigDocument.renderingAutopilotDownloads(expected: current, desired: desired, in: Data(commented.utf8))
        }
    }
}
