import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Encrypted inference cache settings")
struct ProviderCacheTests {
    @Test("a configuration change during a cache read is not published as fresh")
    func changedDuringRead() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent(".config/darkbloom")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = directory.appendingPathComponent("provider.toml")
        try Data("[cache]\ndaily_write_gb=1\n".utf8).write(to: config)
        let runner = CacheRunner(config: config)
        await runner.replaceOnNextRead(Data("[cache]\ndaily_write_gb=2\n".utf8))
        let client = ProviderExtrasClient(policy: DarkbloomSourcePolicy(homeDirectory: root, environmentPath: ""),
            runner: runner, now: Date.init, testOnlyExecutable: root.appendingPathComponent("darkbloom"))
        if case .available = await client.refreshCache() { Issue.record("Changed configuration was presented as fresh") }
    }
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

    @Test("volume identity requires a clean canonical selection and UUID")
    func validatesVolumeIdentity() throws {
        let valid = Data(#"{"scope":"saved_settings","volume":{"directory":"/private/var/example","uuid":"12345678-1234-1234-1234-123456789abc"}}"#.utf8)
        let identity = try ProviderCacheParser.parseVolumeIdentity(valid)
        #expect(identity.directory == "/private/var/example")
        for json in [#"{"scope":"saved_settings","volume":{"directory":"/var/example","uuid":"12345678-1234-1234-1234-123456789abc"}}"#,
                     #"{"scope":"saved_settings","volume":{"directory":"/safe","uuid":"bad"}}"#,
                     #"{"scope":"saved_settings","volume":{"directory":"/safe","uuid":"00000000-0000-0000-0000-000000000000"}}"#,
                     #"{"scope":"saved_settings","problem":"bad","volume":{"directory":"/safe","uuid":"12345678-1234-1234-1234-123456789abc"}}"#] {
            #expect(throws: (any Error).self) { try ProviderCacheParser.parseVolumeIdentity(Data(json.utf8)) }
        }
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
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let directory = root.appendingPathComponent(".config/darkbloom")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let config = directory.appendingPathComponent("provider.toml")
        try Data("[backend]\nenabled_models=[]\npreload_models=[]\n".utf8).write(to: config)
        let runner = CacheRunner(config: config)
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
        let reconciled = try #require(await client.refreshCache().value)
        #expect(reconciled.dailyWriteBytes == 9_000_000_000)
        try await client.setCache(expected: reconciled, change: .directory("/fixture/new-cache"))
        guard case .available(let moved, _) = await client.refreshCache() else { Issue.record("Expected changed directory"); return }
        #expect(moved.selectedDirectory == "/fixture/new-cache")
        #expect(moved.directory == "/fixture/new-cache/namespace/kv3")
        #expect(moved.dailyWriteBytes == 9_000_000_000)
        try await client.setCache(expected: moved, change: .resetDirectory)
        guard case .available(let reset, _) = await client.refreshCache() else { Issue.record("Expected reset"); return }
        #expect(!reset.hasVolume && reset.directory == "/cache")
        #expect(reset.dailyWriteBytes == moved.dailyWriteBytes)
    }
}

private actor CacheRunner: ProcessExecuting {
    var bytes: Int64?
    var writes = 0
    var ignored = false
    var staleReadback = false
    var nextReadReplacement: Data?
    let config: URL
    init(config: URL) { self.config = config }
    func ignoreNextWrite() { ignored = true }
    func replaceOnNextRead(_ data: Data) { nextReadReplacement = data }
    func run(_ command: ProcessCommand, timeout: Duration, outputLimit: Int,
             onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws -> CommandResult {
        if command.arguments == ["--version"] { return CommandResult(exitCode: 0, standardOutput: Data("0.10.4\n".utf8), standardError: Data()) }
        if command.arguments.first == "status" {
            writes += 1
            if ignored { ignored = false; staleReadback = true }
            return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
        }
        if command.arguments.prefix(2) == ["cache", "status"] {
            let argument = try #require(command.arguments.firstIndex(of: "--config"))
            let path = URL(fileURLWithPath: command.arguments[argument + 1])
            if let replacement = nextReadReplacement, path.standardizedFileURL == config.standardizedFileURL {
                nextReadReplacement = nil
                try replacement.write(to: path)
            }
            let text = try String(contentsOf: path, encoding: .utf8)
            func value(_ key: String) -> String? {
                text.components(separatedBy: .newlines).compactMap { line in
                    let parts = line.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    return parts.count == 2 && parts[0] == key ? parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) : nil
                }.last
            }
            let readBytes = value("daily_write_gb").flatMap(Double.init).map { Int64($0 * 1_000_000_000) }
            let actual = path.standardizedFileURL == config.standardizedFileURL
            let shownBytes: Int64?
            if actual && staleReadback { staleReadback = false; shownBytes = bytes }
            else { shownBytes = readBytes; if actual { bytes = readBytes } }
            let selected = value("directory")
            var payload: [String: Any] = ["directory": selected.map { $0 + "/namespace/kv3" } ?? "/cache", "scope": "saved_settings",
                "dailyWriteSource": shownBytes == nil ? "startup_environment_or_default" : "saved_settings"]
            if let shownBytes { payload["dailyWriteBytes"] = shownBytes; payload["unlimited"] = shownBytes == 0 }
            if let selected { payload["volume"] = ["directory": selected, "uuid": value("volume_uuid") ?? ""] }
            return CommandResult(exitCode: 0, standardOutput: try JSONSerialization.data(withJSONObject: payload), standardError: Data())
        }
        guard command.arguments.prefix(2) == ["cache", "set"] else { throw ProviderExtrasMutationError.commandFailed }
        guard let index = command.arguments.firstIndex(of: "--directory"), index + 1 < command.arguments.count,
              let configIndex = command.arguments.firstIndex(of: "--config"), configIndex + 1 < command.arguments.count else { throw ProviderExtrasMutationError.commandFailed }
        let path = command.arguments[index + 1]
        try Data("[cache]\ndirectory=\"\(path)\"\nvolume_uuid=\"12345678-1234-1234-1234-123456789abc\"\n".utf8)
            .write(to: URL(fileURLWithPath: command.arguments[configIndex + 1]))
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}
