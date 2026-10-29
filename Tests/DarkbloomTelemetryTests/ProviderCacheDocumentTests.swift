import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Preserving cache write limits")
struct ProviderCacheDocumentTests {
    @Test("write limit preserves unknown fields, comments and volume selection")
    func preservesOtherSettings() throws {
        let source = """
        [backend]
        future_setting = 73
        [cache]
        directory = "/safe/folder"
        volume_uuid = "12345678-1234-1234-1234-123456789abc"
        daily_write_gb = 25.5 # operator note
        future_cache_setting = "keep"
        [future_section]
        keep = "unchanged"

        """
        let expected = ProviderCacheStatus(directory: "/safe/folder/darkbloom/kv3", dailyWriteBytes: 25_500_000_000,
            hasVolume: true, hasProblem: false, selectedDirectory: "/safe/folder")
        let output = try ProviderConfigDocument.renderingCacheDailyWrite(expected: expected, value: 12, in: Data(source.utf8))
        #expect(output == Data(source.replacingOccurrences(of: "daily_write_gb = 25.5", with: "daily_write_gb = 12.0").utf8))
    }

    @Test("missing cache table and missing limit are added without rewriting other data")
    func addsLimit() throws {
        let expected = ProviderCacheStatus(directory: "/builtin", dailyWriteBytes: nil, hasVolume: false, hasProblem: false)
        for source in ["[backend]\nfuture_setting = 73\n", "[cache]"] {
            let result = try ProviderConfigDocument.renderingCacheDailyWrite(expected: expected, value: 0, in: Data(source.utf8))
            let text = String(decoding: result, as: UTF8.self)
            #expect(text.contains("[cache]\n"))
            #expect(text.contains("daily_write_gb = 0.0"))
        }
    }

    @Test("stale limits and changed folder do not authorize edits")
    func rejectsStaleValues() {
        let source = Data("[cache]\ndirectory = '/folder'\nvolume_uuid = '12345678-1234-1234-1234-123456789abc'\ndaily_write_gb = 25.5\n".utf8)
        for expected in [ProviderCacheStatus(directory: "/folder/root", dailyWriteBytes: 1, hasVolume: true, hasProblem: false, selectedDirectory: "/folder"),
                         ProviderCacheStatus(directory: "/other/root", dailyWriteBytes: 25_500_000_000, hasVolume: true, hasProblem: false, selectedDirectory: "/other")] {
            #expect(throws: ProviderConfigError.changedExternally) {
                try ProviderConfigDocument.renderingCacheDailyWrite(expected: expected, value: 10, in: source)
            }
        }
    }

    @Test("unrecognized cache representations and incomplete volume pins fail safely")
    func rejectsAmbiguousConfig() {
        let expected = ProviderCacheStatus(directory: "/builtin", dailyWriteBytes: nil, hasVolume: false, hasProblem: false)
        for source in ["cache.daily_write_gb = 1\n", "cache = { daily_write_gb = 1 }\n", "[cache]\ndirectory = '/folder'\n"] {
            #expect(throws: (any Error).self) { try ProviderConfigDocument.renderingCacheDailyWrite(expected: expected, value: 10, in: Data(source.utf8)) }
        }
    }

    @Test("unqualified provider versions cannot write a cache limit")
    func rejectsUnknownVersion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let client = ProviderExtrasClient(policy: DarkbloomSourcePolicy(homeDirectory: root, environmentPath: ""),
            runner: CacheVersionRunner(), now: Date.init, testOnlyExecutable: root.appendingPathComponent("darkbloom"))
        let expected = try #require(await client.refreshCache().value)
        await #expect(throws: ProviderExtrasMutationError.unsupportedCacheSettingsVersion) {
            try await client.setCache(expected: expected, change: .dailyWriteGB(12))
        }
    }
}

private struct CacheVersionRunner: ProcessExecuting {
    func run(_ command: ProcessCommand, timeout: Duration, outputLimit: Int,
             onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws -> CommandResult {
        if command.arguments == ["--version"] {
            return .init(exitCode: 0, standardOutput: Data("0.99.0\n".utf8), standardError: Data())
        }
        if command.arguments.prefix(2) == ["cache", "status"] {
            return .init(exitCode: 0, standardOutput: Data(#"{"directory":"/cache","dailyWriteSource":"startup_environment_or_default","scope":"saved_settings"}"#.utf8), standardError: Data())
        }
        throw ProviderExtrasMutationError.commandFailed
    }
}
