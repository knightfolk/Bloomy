import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Preserving cache write limits")
struct ProviderCacheDocumentTests {
    @Test("cache folder changes preserve unrelated fields and pinned write limit")
    func cacheFolderEdits() throws {
        let source = "[cache]\ndirectory='/old'\nvolume_uuid='12345678-1234-1234-1234-123456789abc'\ndaily_write_gb=25.5\nfuture='keep'\n[other]\nvalue='untouched'\n"
        let expected = ProviderCacheStatus(directory: "/old/darkbloom/kv3", dailyWriteBytes: 25_500_000_000,
            hasVolume: true, hasProblem: false, selectedDirectory: "/old", volumeUUID: "12345678-1234-1234-1234-123456789abc")
        let selection = ProviderCacheVolumeIdentity(directory: "/new/folder", uuid: "87654321-4321-4321-4321-cba987654321")
        let output = try ProviderConfigDocument.renderingCacheDirectory(expected: expected, selected: selection, in: Data(source.utf8))
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("directory=\"/new/folder\""))
        #expect(text.contains("volume_uuid=\"87654321-4321-4321-4321-cba987654321\""))
        #expect(text.contains("daily_write_gb=25.5\nfuture='keep'\n[other]\nvalue='untouched'"))
        let reset = try ProviderConfigDocument.renderingCacheDirectory(expected: expected, selected: nil, in: Data(source.utf8))
        let resetText = String(decoding: reset, as: UTF8.self)
        #expect(!resetText.contains("directory="))
        #expect(!resetText.contains("volume_uuid="))
        #expect(resetText.contains("daily_write_gb=25.5\nfuture='keep'"))
    }

    @Test("cache folder changes reject stale state and comments on removed fields")
    func cacheFolderConflicts() {
        let source = "[cache]\ndirectory='/old' # keep\nvolume_uuid='12345678-1234-1234-1234-123456789abc'\n"
        let current = ProviderCacheStatus(directory: "/old/root", dailyWriteBytes: nil, hasVolume: true, hasProblem: false, selectedDirectory: "/old", volumeUUID: "12345678-1234-1234-1234-123456789abc")
        let stale = ProviderCacheStatus(directory: "/different/root", dailyWriteBytes: nil, hasVolume: true, hasProblem: false, selectedDirectory: "/different", volumeUUID: "12345678-1234-1234-1234-123456789abc")
        #expect(throws: (any Error).self) { try ProviderConfigDocument.renderingCacheDirectory(expected: current, selected: nil, in: Data(source.utf8)) }
        #expect(throws: ProviderConfigError.changedExternally) { try ProviderConfigDocument.renderingCacheDirectory(expected: stale, selected: nil, in: Data(source.utf8)) }
    }

    @Test("an unavailable selected volume can be reset without guessing another folder")
    func resetsUnavailableVolume() throws {
        let source = Data("[cache]\ndirectory='/missing'\nvolume_uuid='12345678-1234-1234-1234-123456789abc'\n".utf8)
        let expected = ProviderCacheStatus(directory: "/missing/darkbloom/kv3", dailyWriteBytes: nil, hasVolume: false, hasProblem: true).withSourceRevision("synthetic")
        let output = try ProviderConfigDocument.renderingCacheDirectory(expected: expected, selected: nil, in: source)
        #expect(!String(decoding: output, as: UTF8.self).contains("directory="))
        let changed = ProviderCacheStatus(directory: "/other/darkbloom/kv3", dailyWriteBytes: nil, hasVolume: false, hasProblem: true).withSourceRevision("synthetic")
        #expect(throws: ProviderConfigError.changedExternally) {
            try ProviderConfigDocument.renderingCacheDirectory(expected: changed, selected: nil, in: source)
        }
    }

    @Test("a reported volume mismatch can be repaired only with a bound source revision")
    func repairsMismatchedVolume() throws {
        let source = Data("[cache]\ndirectory='/folder'\nvolume_uuid='12345678-1234-1234-1234-123456789abc'\n".utf8)
        let status = ProviderCacheStatus(directory: "/folder/darkbloom/kv3", dailyWriteBytes: nil, hasVolume: true,
            hasProblem: true, selectedDirectory: "/folder", volumeUUID: "87654321-4321-4321-4321-cba987654321")
        #expect(throws: ProviderConfigError.changedExternally) {
            try ProviderConfigDocument.renderingCacheDirectory(expected: status, selected: nil, in: source)
        }
        let output = try ProviderConfigDocument.renderingCacheDirectory(expected: status.withSourceRevision("synthetic"), selected: nil, in: source)
        #expect(!String(decoding: output, as: UTF8.self).contains("directory="))
    }

    @Test("new cache folder settings are inserted without touching existing sections")
    func addsCacheFolder() throws {
        let source = Data("[backend]\nfuture=73\n".utf8)
        let expected = ProviderCacheStatus(directory: "/builtin", dailyWriteBytes: nil, hasVolume: false, hasProblem: false)
        let selected = ProviderCacheVolumeIdentity(directory: "/new", uuid: "12345678-1234-1234-1234-123456789abc")
        let output = try ProviderConfigDocument.renderingCacheDirectory(expected: expected, selected: selected, in: source)
        let text = String(decoding: output, as: UTF8.self)
        #expect(text.contains("[backend]\nfuture=73\n"))
        #expect(text.contains("[cache]\ndirectory = \"/new\"\nvolume_uuid = \"12345678-1234-1234-1234-123456789abc\""))
    }
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
            hasVolume: true, hasProblem: false, selectedDirectory: "/safe/folder", volumeUUID: "12345678-1234-1234-1234-123456789abc")
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
        for expected in [ProviderCacheStatus(directory: "/folder/root", dailyWriteBytes: 1, hasVolume: true, hasProblem: false, selectedDirectory: "/folder", volumeUUID: "12345678-1234-1234-1234-123456789abc"),
                         ProviderCacheStatus(directory: "/other/root", dailyWriteBytes: 25_500_000_000, hasVolume: true, hasProblem: false, selectedDirectory: "/other", volumeUUID: "12345678-1234-1234-1234-123456789abc"),
                         ProviderCacheStatus(directory: "/folder/root", dailyWriteBytes: 25_500_000_000, hasVolume: true, hasProblem: false, selectedDirectory: "/folder", volumeUUID: "87654321-4321-4321-4321-cba987654321")] {
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
