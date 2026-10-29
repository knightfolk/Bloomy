import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Encrypted inference cache settings")
struct ProviderCacheTests {
    @Test("unset, unlimited and explicit limits remain distinct")
    func parsesLimits() throws {
        let unset = try ProviderCacheParser.parse(Data(#"{"directory":"/cache","dailyWriteSource":"startup_environment_or_default","scope":"saved_settings"}"#.utf8))
        #expect(unset.dailyWriteBytes == nil)
        let unlimited = try ProviderCacheParser.parse(Data(#"{"directory":"/cache","dailyWriteBytes":0,"unlimited":true,"dailyWriteSource":"saved_settings","scope":"saved_settings"}"#.utf8))
        #expect(unlimited.dailyWriteBytes == 0)
        let limited = try ProviderCacheParser.parse(Data(#"{"directory":"/cache","dailyWriteBytes":2500000000,"unlimited":false,"dailyWriteSource":"saved_settings","scope":"saved_settings","volume":{},"problem":"private error"}"#.utf8))
        #expect(limited.dailyWriteBytes == 2_500_000_000)
        #expect(limited.hasVolume && limited.hasProblem)
        let selected = try ProviderCacheParser.parse(Data(#"{"directory":"/parent/namespace/kv3","dailyWriteSource":"startup_environment_or_default","scope":"saved_settings","volume":{"directory":"/parent"}}"#.utf8))
        #expect(selected.selectedDirectory == "/parent")
        #expect(selected.directory == "/parent/namespace/kv3")
    }

    @Test("rejects inconsistent and unbounded input")
    func rejectsInvalid() throws {
        for json in [#"{"directory":"relative","dailyWriteSource":"startup_environment_or_default","scope":"saved_settings"}"#,
                     #"{"directory":"/cache","dailyWriteBytes":0,"unlimited":false,"dailyWriteSource":"saved_settings","scope":"saved_settings"}"#,
                     #"{"directory":"/cache","dailyWriteBytes":2,"dailyWriteSource":"startup_environment_or_default","scope":"saved_settings"}"#] {
            #expect(throws: (any Error).self) { try ProviderCacheParser.parse(Data(json.utf8)) }
        }
        #expect(ProviderCacheParser.validDailyWriteGB(0))
        #expect(ProviderCacheParser.validDailyWriteGB(25.5))
        #expect(!ProviderCacheParser.validDailyWriteGB(-1))
        #expect(!ProviderCacheParser.validDailyWriteGB(.infinity))
        #expect(!ProviderCacheParser.validDailyWriteGB(0.0000000001))
        #expect(ProviderCacheParser.normalizedSelectedDirectory("/var/folders/example") == "/private/var/folders/example")
        #expect(ProviderCacheParser.normalizedSelectedDirectory("/tmp/cache") == "/private/tmp/cache")
        #expect(ProviderCacheParser.normalizedSelectedDirectory("/safe/../other") == nil)
    }

    @Test("commands touch only the chosen cache setting")
    func commandMapping() {
        let executable = URL(fileURLWithPath: "/fixture/darkbloom")
        let config = URL(fileURLWithPath: "/fixture/provider.toml")
        #expect(ProviderExtrasCommand.cacheSet(executable: executable, config: config, change: .dailyWriteGB(25.5)).arguments ==
                ["cache", "set", "--config", config.path, "--daily-write-gb", "25.5"])
        #expect(ProviderExtrasCommand.cacheSet(executable: executable, config: config, change: .directory("/safe path")).arguments ==
                ["cache", "set", "--config", config.path, "--directory", "/safe path"])
        #expect(ProviderExtrasCommand.cacheSet(executable: executable, config: config, change: .resetDirectory).arguments ==
                ["cache", "set", "--config", config.path, "--reset-directory"])
    }

    @Test("write rechecks evidence and verifies actual readback")
    func mutation() async throws {
        let runner = CacheRunner()
        let root = URL(fileURLWithPath: "/fixture")
        let client = ProviderExtrasClient(policy: DarkbloomSourcePolicy(homeDirectory: root, environmentPath: ""),
            runner: runner, now: Date.init, testOnlyExecutable: root.appendingPathComponent("darkbloom"))
        guard case .available(let initial, _) = await client.refreshCache() else { Issue.record("Expected cache status"); return }
        try await client.setCache(expected: initial, change: .dailyWriteGB(25.5))
        #expect(await runner.writes == 1)
        await #expect(throws: ProviderExtrasMutationError.self) { try await client.setCache(expected: initial, change: .dailyWriteGB(1)) }
        #expect(await runner.writes == 1)
        guard case .available(let changed, _) = await client.refreshCache() else { Issue.record("Expected cache status"); return }
        await runner.ignoreNextWrite()
        await #expect(throws: ProviderExtrasMutationError.self) { try await client.setCache(expected: changed, change: .dailyWriteGB(9)) }
        try await client.setCache(expected: changed, change: .directory("/fixture/new-cache"))
        guard case .available(let moved, _) = await client.refreshCache() else { Issue.record("Expected changed directory"); return }
        #expect(moved.selectedDirectory == "/fixture/new-cache")
        #expect(moved.directory == "/fixture/new-cache/namespace/kv3")
        #expect(moved.dailyWriteBytes == 25_500_000_000)
        try await client.setCache(expected: moved, change: .resetDirectory)
        guard case .available(let reset, _) = await client.refreshCache() else { Issue.record("Expected reset"); return }
        #expect(!reset.hasVolume && reset.directory == "/cache")
        #expect(reset.dailyWriteBytes == moved.dailyWriteBytes)
    }
}

private actor CacheRunner: ProcessExecuting {
    var bytes: Int64?
    var directory = "/cache"
    var selectedDirectory: String?
    var custom = false
    var writes = 0
    var ignored = false
    func ignoreNextWrite() { ignored = true }
    func run(_ command: ProcessCommand, timeout: Duration, outputLimit: Int,
             onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws -> CommandResult {
        if command.arguments.prefix(2) == ["cache", "status"] {
            var payload: [String: Any] = ["directory": directory, "scope": "saved_settings",
                "dailyWriteSource": bytes == nil ? "startup_environment_or_default" : "saved_settings"]
            if let bytes { payload["dailyWriteBytes"] = bytes; payload["unlimited"] = bytes == 0 }
            if custom { payload["volume"] = ["directory": selectedDirectory ?? ""] }
            return CommandResult(exitCode: 0, standardOutput: try JSONSerialization.data(withJSONObject: payload), standardError: Data())
        }
        guard command.arguments.prefix(2) == ["cache", "set"] else { throw ProviderExtrasMutationError.commandFailed }
        writes += 1
        if ignored { ignored = false }
        else if let index = command.arguments.firstIndex(of: "--daily-write-gb"), index + 1 < command.arguments.count,
                let gb = Double(command.arguments[index + 1]) { bytes = Int64(gb * 1_000_000_000) }
        else if let index = command.arguments.firstIndex(of: "--directory"), index + 1 < command.arguments.count {
            selectedDirectory = command.arguments[index + 1]; directory = command.arguments[index + 1] + "/namespace/kv3"; custom = true
        } else if command.arguments.contains("--reset-directory") { directory = "/cache"; selectedDirectory = nil; custom = false }
        else { throw ProviderExtrasMutationError.commandFailed }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}
