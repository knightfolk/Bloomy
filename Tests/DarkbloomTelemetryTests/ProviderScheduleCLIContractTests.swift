import Foundation
import Testing
@testable import DarkbloomTelemetry

/// Explicit opt-in because this invokes an installed CLI. Only disposable
/// configuration files are touched; no provider lifecycle action is issued.
@Suite("Provider schedule CLI contract")
struct ProviderScheduleCLIContractTests {
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
