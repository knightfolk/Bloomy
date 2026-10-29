import Foundation
import Testing
@testable import DarkbloomTelemetry

/// Explicit opt-in because this invokes an installed CLI. Only disposable
/// configuration files are touched; no provider lifecycle action is issued.
@Suite("Provider schedule CLI contract")
struct ProviderScheduleCLIContractTests {
    @Test("preserving cache limits are accepted by Darkbloom", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func cacheDailyWriteContract() async throws {
        let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyCacheLimitContract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("provider.toml")
        try Data("[provider]\nname='Synthetic cache limit'\nauto_update=false\n[backend]\nfuture_setting=73\n[future_section]\nkeep='untouched'\n".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let runner = CappedProcessRunner()
        let command = ProviderExtrasCommand.cacheStatus(executable: executable, config: url)
        let initial = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        let expected = try ProviderCacheParser.parse(initial.standardOutput)
        let store = LocalProviderConfigStore(configURL: url, executable: executable, runner: runner)
        try await store.saveCacheDailyWrite(expected: expected, value: 25.5)
        let output = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        let observed = try ProviderCacheParser.parse(output.standardOutput)
        #expect(observed.dailyWriteBytes == 25_500_000_000)
        #expect(observed.directory == expected.directory)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("future_setting=73") && text.contains("[future_section]\nkeep='untouched'"))
    }
    @Test("cache directory client confirms Darkbloom's selected folder", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func cacheDirectoryClientContract() async throws {
        let cli = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"]))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyCacheClient-\(UUID().uuidString)")
        let configDir = home.appendingPathComponent(".config/darkbloom")
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let selected = home.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let configURL = configDir.appendingPathComponent("provider.toml")
        try Data("[provider]\nname='Synthetic cache client'\nauto_update=false\n".utf8).write(to: configURL)
        let policy = DarkbloomSourcePolicy(homeDirectory: home, environmentPath: cli.deletingLastPathComponent().path)
        let client = ProviderExtrasClient(policy: policy, runner: CappedProcessRunner())
        let initial = try #require(await client.refreshCache().value)
        try await client.setCache(expected: initial, change: .directory(selected.path))
        let observed = try #require(await client.refreshCache().value)
        #expect(observed.selectedDirectory == ProviderCacheParser.normalizedSelectedDirectory(selected.path))
        #expect(observed.hasVolume && !observed.hasProblem)
        let handle = try FileHandle(forWritingTo: configURL)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n[future_section]\nkeep='untouched'\n".utf8))
        try handle.close()
        let current = try #require(await client.refreshCache().value)
        try await client.setCache(expected: current, change: .dailyWriteGB(12.5))
        let limited = try #require(await client.refreshCache().value)
        #expect(limited.dailyWriteBytes == 12_500_000_000)
        #expect(limited.selectedDirectory == observed.selectedDirectory)
        #expect(try String(contentsOf: configURL, encoding: .utf8).contains("[future_section]\nkeep='untouched'"))
    }
    @Test("cache status distinguishes selected folder from the effective root", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func cacheDirectoryContract() async throws {
        let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"]))
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("BloomyCacheContract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: root) }
        let selected = root.appendingPathComponent("selected")
        try FileManager.default.createDirectory(at: selected, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let config = root.appendingPathComponent("provider.toml")
        try Data("[provider]\nname='Synthetic cache contract'\nauto_update=false\n".utf8).write(to: config)
        let runner = CappedProcessRunner()
        let set = ProviderExtrasCommand.cacheSet(executable: executable, config: config, change: .directory(selected.path))
        let written = try await runner.run(set, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(written.exitCode == 0)
        let read = try await runner.run(ProviderExtrasCommand.cacheStatus(executable: executable, config: config), timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        let status = try ProviderCacheParser.parse(read.standardOutput)
        let canonical = try #require(ProviderCacheParser.normalizedSelectedDirectory(selected.path))
        #expect(status.selectedDirectory == canonical)
        #expect(status.directory.hasPrefix(canonical + "/"))
        #expect(status.directory != status.selectedDirectory)
    }
    @Test("download controls preserve unfamiliar settings with the qualified CLI", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func downloadsClientContract() async throws {
        let cli = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"]))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyDownloadsClient-\(UUID().uuidString)")
        let directory = home.appendingPathComponent(".config/darkbloom")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let url = directory.appendingPathComponent("provider.toml")
        try Data("""
        [provider]
        name = "Synthetic downloads client"
        auto_update = false
        [backend]
        enabled_models = []
        preload_models = []
        future_setting = 73
        [backend.autopilot_downloads]
        enabled = true
        max_storage_gb = 120
        max_models = 3
        reserve_gb = 50
        [future_section]
        keep = "untouched"
        """.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let policy = DarkbloomSourcePolicy(homeDirectory: home, environmentPath: cli.deletingLastPathComponent().path)
        let client = ProviderExtrasClient(policy: policy, runner: CappedProcessRunner())
        let initial = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 120, maxModels: 3, reserveGB: 50)
        let disabled = AutopilotDownloadPolicy(enabled: false, maxStorageGB: 120, maxModels: 3, reserveGB: 50)
        let limited = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 80, reserveGB: 50)
        try await client.setAutopilotDownloads(expected: initial, desired: disabled)
        try await client.setAutopilotDownloads(expected: disabled, desired: limited)
        #expect(await client.refreshAutopilot().value?.downloads == limited)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("future_setting = 73") && text.contains("[future_section]\nkeep = \"untouched\""))
    }
    @Test("preserving download limits are accepted by Darkbloom", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func downloadsContract() async throws {
        let executable = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"]))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyDownloadsContract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("provider.toml")
        try Data("""
        [provider]
        name = "Synthetic downloads contract"
        auto_update = false
        [backend]
        enabled_models = []
        preload_models = []
        future_setting = 73
        [backend.autopilot_downloads]
        enabled = true
        max_storage_gb = 120
        max_models = 3
        reserve_gb = 50
        [future_section]
        keep = "untouched"
        """.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let runner = CappedProcessRunner()
        let store = LocalProviderConfigStore(configURL: url, executable: executable, runner: runner)
        let command = ProviderExtrasCommand.autopilotStatus(executable: executable, config: url)
        let initial = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 120, maxModels: 3, reserveGB: 50)
        let disabled = AutopilotDownloadPolicy(enabled: false, maxStorageGB: 120, maxModels: 3, reserveGB: 50)
        let limited = AutopilotDownloadPolicy(enabled: true, maxStorageGB: 80, reserveGB: 50)
        try await store.saveAutopilotDownloads(expected: initial, desired: disabled)
        var result = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(try ProviderExtrasParser.parseAutopilot(result.standardOutput).downloads == disabled)
        try await store.saveAutopilotDownloads(expected: disabled, desired: limited)
        result = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(try ProviderExtrasParser.parseAutopilot(result.standardOutput).downloads == limited)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("future_setting = 73") && text.contains("[future_section]\nkeep = \"untouched\""))
    }
    @Test("Autopilot controls use preserving writes with the qualified CLI", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func autopilotClientContract() async throws {
        let cli = URL(fileURLWithPath: try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"]))
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyAutopilotClient-\(UUID().uuidString)")
        let configDirectory = home.appendingPathComponent(".config/darkbloom")
        try FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: home) }
        let url = configDirectory.appendingPathComponent("provider.toml")
        try Data("""
        [provider]
        name = "Synthetic client contract"
        auto_update = false
        [backend]
        enabled_models = ["test/model"]
        preload_models = []
        future_setting = 73
        [backend.model_autopilot]
        enabled = true
        consent_recorded = true
        paused = false
        selected_models = ["test/model"]
        pinned_models = []
        revision = "synthetic-revision"
        [future_section]
        keep = "untouched"
        """.utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let policy = DarkbloomSourcePolicy(homeDirectory: home, environmentPath: cli.deletingLastPathComponent().path)
        let client = ProviderExtrasClient(policy: policy, runner: CappedProcessRunner())
        for action in [ProviderAutopilotPolicyAction.pause, .resume, .disable] {
            try await client.setAutopilotPolicy(action)
            let observation = await client.refreshAutopilot()
            #expect(observation.value?.confirms(action) == true)
        }
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("future_setting = 73"))
        #expect(saved.contains("[future_section]\nkeep = \"untouched\""))
    }
    @Test("preserving Autopilot pause, resume and disable are accepted by Darkbloom", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func autopilotPauseContract() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"])
        let executable = URL(fileURLWithPath: path)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyAutopilotContract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("provider.toml")
        let source = Data("""
        [provider]
        name = "Synthetic autopilot contract"
        auto_update = false
        [backend]
        enabled_models = ["test/model"]
        preload_models = []
        future_setting = 73
        [backend.model_autopilot]
        enabled = true
        consent_recorded = true
        paused = false
        selected_models = ["test/model"]
        pinned_models = []
        revision = "synthetic-revision"
        [future_section]
        keep = "untouched"
        """.utf8)
        try source.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let runner = CappedProcessRunner()
        let command = ProviderExtrasCommand.autopilotStatus(executable: executable, config: url)
        let before = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(before.exitCode == 0)
        let expected = try ProviderExtrasParser.parseAutopilot(before.standardOutput)
        let store = LocalProviderConfigStore(configURL: url, executable: executable, runner: runner)
        try await store.saveAutopilotPolicy(.pause, expected: expected)
        let after = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(after.exitCode == 0)
        let paused = try ProviderExtrasParser.parseAutopilot(after.standardOutput)
        #expect(paused.confirms(.pause))
        try await store.saveAutopilotPolicy(.resume, expected: paused)
        let resumedOutput = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        let resumed = try ProviderExtrasParser.parseAutopilot(resumedOutput.standardOutput)
        #expect(resumedOutput.exitCode == 0 && resumed.confirms(.resume))
        try await store.saveAutopilotPolicy(.disable, expected: resumed)
        let disabledOutput = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(disabledOutput.exitCode == 0)
        #expect(try ProviderExtrasParser.parseAutopilot(disabledOutput.standardOutput).confirms(.disable))
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("future_setting = 73"))
        #expect(saved.contains("[future_section]\nkeep = \"untouched\""))
    }
    @Test("Bloomy saves a schedule Darkbloom can read", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"] != nil))
    func savesForRealCLI() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["BLOOMY_SCHEDULE_TEST_CLI"])
        let executable = URL(fileURLWithPath: path)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("BloomyScheduleContract-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("provider.toml")
        let original = Data("""
        [provider]
        name = "Synthetic schedule contract"
        auto_update = false
        [backend]
        enabled_models = []
        preload_models = []
        future_setting = 73
        [schedule]
        enabled = false
        [future_section]
        keep = "untouched"
        """.utf8)
        try original.write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let runner = CappedProcessRunner()
        let store = LocalProviderConfigStore(configURL: url, executable: executable, runner: runner)
        let expected = try await store.loadScheduleDraft()
        let schedule = ProviderSchedule(enabled: true, windows: [.init(days: [.monday, .wednesday], start: "22:00", end: "02:00")])
        _ = try await store.saveSchedule(schedule, expected: expected)
        let command = ProcessCommand(executable: executable, arguments: ["schedule", "--show", "--config", url.path])
        let result = try await runner.run(command, timeout: .seconds(15), outputLimit: 262_144, onOutput: nil)
        #expect(result.exitCode == 0)
        let output = String(decoding: result.standardOutput, as: UTF8.self)
        #expect(output.contains("22:00") && output.contains("02:00") && output.contains("following day"))
        let saved = try String(contentsOf: url, encoding: .utf8)
        #expect(saved.contains("future_setting = 73"))
        #expect(saved.contains("[future_section]\nkeep = \"untouched\""))
        #expect(try await store.loadSchedule() == schedule)
    }
}
