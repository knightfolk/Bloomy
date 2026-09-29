import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Provider extras")
@MainActor
struct ProviderExtrasTests {
    @Test("parses idle policy bounds and beta tri-state")
    func parsesStructuredPolicies() throws {
        let idle = try ProviderExtrasParser.parseIdle(Data(#"""
            {
              "idleTimeoutMins": 60,
              "policy": "free_when_idle",
              "summary": "free after 1 h idle",
              "pinned": true,
              "configPath": "/Users/private/.config/darkbloom/provider.toml"
            }
            """#.utf8))
        #expect(idle.idleTimeoutMinutes == 60)
        #expect(idle.pinned)
        #expect(idle.requiresRestart)

        let beta = try ProviderExtrasParser.parseBeta(Data(#"""
            [
              {
                "id": "mtp",
                "title": "Multi-token prediction",
                "state": "auto",
                "requiresRestart": true,
                "summary": "Automatic for eligible models."
              },
              {
                "id": "gemma-weighted-r1",
                "title": "Weighted R1",
                "state": "on",
                "enabled": true,
                "requiresRestart": true,
                "summary": "Default ON."
              }
            ]
            """#.utf8))
        #expect(beta.count == 2)
        #expect(beta[0].enabled == nil)
        #expect(beta[0].state == .auto)
        #expect(beta[1].enabled == true)
    }

    @Test("rejects unbounded idle, duplicate beta IDs, and unsafe fan readings")
    func rejectsUnsafePayloads() {
        #expect(throws: ProviderExtrasParseError.invalidValue) {
            try ProviderExtrasParser.parseIdle(Data(#"""
                {"idleTimeoutMins": 10081, "policy": "free_when_idle", "summary": "x", "pinned": true}
                """#.utf8))
        }

        #expect(throws: ProviderExtrasParseError.invalidValue) {
            try ProviderExtrasParser.parseBeta(Data(#"""
                [
                  {"id":"mtp","title":"a","state":"on","enabled":true,"requiresRestart":true,"summary":"a"},
                  {"id":"mtp","title":"b","state":"off","enabled":false,"requiresRestart":true,"summary":"b"}
                ]
                """#.utf8))
        }

        #expect(throws: ProviderExtrasParseError.invalidValue) {
            try ProviderExtrasParser.parseFan(Data(#"""
                {
                  "capability":"darkbloom-fan-helper-v1",
                  "installed":true,
                  "loaded":true,
                  "helper":null,
                  "helperError":null,
                  "diagnostic":{
                    "chip":"Apple",
                    "supported":true,
                    "gpuTemperatures":[],
                    "fans":[{"index":0,"actualRPM":200001,"targetRPM":null,"minimumRPM":null,"maximumRPM":null,"mode":"auto"}],
                    "error":null
                  }
                }
                """#.utf8))
        }
    }

    @Test("decodes Foundation reference-date fan timestamps and keeps direct diagnostics when helper is stale")
    func parsesFanTimestampAndFreshness() async throws {
        let status = try ProviderExtrasParser.parseFan(fanJSON(updatedAt: 100))
        #expect(status.helper?.updatedAt == Date(timeIntervalSinceReferenceDate: 100))
        #expect(status.displayedTemperatureCelsius == 65)

        let runner = ExtrasRunner(results: [
            "fan status": .success(fanJSON(updatedAt: 100)),
        ])
        let client = ProviderExtrasClient(
            policy: testPolicy(),
            runner: runner,
            now: { Date(timeIntervalSinceReferenceDate: 200) },
            testOnlyExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )
        let snapshot = await client.refresh()
        if case .available(let fan, _) = snapshot.fanStatus {
            #expect(fan.helper == nil)
            #expect(fan.displayedTemperatureCelsius == 65)
        } else {
            Issue.record("direct diagnostics should remain available when helper journal is stale")
        }
    }

    @Test("live fan refresh invokes only the read-only fan command")
    func fanOnlyRefresh() async {
        let runner = ExtrasRunner(results: ["fan status": .success(fanJSON(updatedAt: 100))])
        let client = ProviderExtrasClient(
            policy: testPolicy(), runner: runner,
            now: { Date(timeIntervalSinceReferenceDate: 100) },
            testOnlyExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )
        let result = await client.refreshFan()
        #expect(result.value != nil)
        let commands = await runner.commands
        #expect(commands.count == 1)
        #expect(commands.first?.arguments == ["fan", "status", "--json"])
    }

    @Test("fan helper updated during CLI read stays available in full and fan-only refreshes")
    func fanTimestampAfterCommandStart() async {
        let startedAt = Date(timeIntervalSinceReferenceDate: 100)
        let completedAt = Date(timeIntervalSinceReferenceDate: 101)
        let clock = ExtrasTestClock(startedAt)
        let runner = ExtrasRunner(
            results: ["fan status": .success(fanJSON(updatedAt: 101))],
            onFanRead: { clock.set(completedAt) }
        )
        let client = ProviderExtrasClient(
            policy: testPolicy(), runner: runner, now: { clock.now() },
            testOnlyExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )

        let snapshot = await client.refresh()
        if case .available(let fan, let capturedAt) = snapshot.fanStatus {
            #expect(fan.helper?.enabled == true)
            #expect(capturedAt == completedAt)
        } else {
            Issue.record("full refresh dropped the helper updated during the command")
        }

        clock.set(startedAt)
        let fanOnly = await client.refreshFan()
        if case .available(let fan, let capturedAt) = fanOnly {
            #expect(fan.helper?.enabled == true)
            #expect(capturedAt == completedAt)
        } else {
            Issue.record("fan-only refresh dropped the helper updated during the command")
        }
    }

    @Test("fan helper timestamps after command completion are still rejected")
    func rejectsFutureFanTimestamp() async {
        let completedAt = Date(timeIntervalSinceReferenceDate: 101)
        let client = ProviderExtrasClient(
            policy: testPolicy(),
            runner: ExtrasRunner(results: ["fan status": .success(fanJSON(updatedAt: 102))]),
            now: { completedAt },
            testOnlyExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )
        let result = await client.refreshFan()
        if case .available(let fan, let capturedAt) = result {
            #expect(fan.helper == nil)
            #expect(!fan.diagnostic.fans.isEmpty)
            #expect(capturedAt == completedAt)
        } else {
            Issue.record("direct diagnostics should remain available for a future helper timestamp")
        }
    }

    @Test("live fan refresh preserves other settings and never writes policy")
    func fanOnlyStoreRefresh() async {
        let client = StoreClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        let before = store.snapshot
        await store.refreshFan()
        #expect(await client.fanRefreshCount == 1)
        #expect(await client.refreshCount == 1)
        #expect(await client.saveCount == 0)
        #expect(store.snapshot?.idlePolicy == before?.idlePolicy)
        #expect(store.snapshot?.capturedAt == before?.capturedAt)
        await store.stop()
    }

    @Test("reads each source independently and does not expose command stderr")
    func independentAvailabilityAndPrivacy() async {
        let runner = ExtrasRunner(results: [
            "idle status": .success(Data(#"""
                {"idleTimeoutMins":0,"policy":"always_ready","summary":"always ready","pinned":true}
                """#.utf8)),
            "beta list": .failure,
            "fan status": .failureWithSecret,
            "autoupdate status": .success(Data("Auto-update is ENABLED\nConfig: /Users/private/secret.toml\n".utf8)),
        ])
        let client = ProviderExtrasClient(
            policy: testPolicy(),
            runner: runner,
            now: { Date(timeIntervalSinceReferenceDate: 100) },
            testOnlyExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )
        let snapshot = await client.refresh()

        #expect(snapshot.idlePolicy.value?.idleTimeoutMinutes == 0)
        if case .unavailable(let reason) = snapshot.betaFeatures {
            #expect(!reason.contains("secret"))
        } else {
            Issue.record("beta failure should not be promoted to available")
        }
        if case .unavailable(let reason) = snapshot.fanStatus {
            #expect(!reason.contains("secret"))
        } else {
            Issue.record("fan failure should not be promoted to available")
        }
        #expect(snapshot.autoUpdateStatus?.value?.enabled == true)
    }

    @Test("mutation commands are bounded and use the fixed beta allowlist")
    func validatesMutationsAndArguments() async throws {
        let runner = ExtrasRunner(results: [:])
        let client = ProviderExtrasClient(
            policy: testPolicy(),
            runner: runner,
            now: Date.init,
            testOnlyExecutable: URL(fileURLWithPath: "/usr/bin/true")
        )

        try await client.saveIdle(minutes: 0)
        try await client.saveIdle(minutes: 60)
        try await client.setBeta(id: "mtp", enabled: true)
        try await client.setAutoUpdate(enabled: true)
        let fanPolicy = try #require(ProviderFanPolicy(
            speedPercent: 82,
            triggerTemperatureCelsius: 47
        ))
        try await client.enableFan(policy: fanPolicy)
        try await client.configureFan(policy: fanPolicy)
        try await client.disableFan()
        try await client.uninstallFan()
        await #expect(throws: ProviderExtrasMutationError.invalidIdleMinutes) {
            try await client.saveIdle(minutes: 10_081)
        }
        await #expect(throws: ProviderExtrasMutationError.unsupportedBetaFeature) {
            try await client.setBeta(id: "unknown", enabled: true)
        }

        let commands = await runner.commands
        #expect(commands.contains {
            $0.arguments == ["idle", "keep-loaded", "--config", testPolicy().providerConfig.path]
        })
        #expect(commands.contains {
            $0.arguments == ["idle", "unload-after", "60", "--config", testPolicy().providerConfig.path]
        })
        #expect(commands.contains {
            $0.arguments == ["beta", "enable", "mtp", "--config", testPolicy().providerConfig.path]
        })
        #expect(commands.contains {
            $0.arguments == ["autoupdate", "enable", "--config", testPolicy().providerConfig.path]
        })
        #expect(commands.contains {
            $0.executable.path == "/usr/bin/osascript"
                && $0.arguments.suffix(6) == [
                    "/usr/bin/true", "enable", "--speed", "82.0", "--temperature", "47.0",
                ]
        })
        #expect(commands.contains {
            $0.executable.path == "/usr/bin/osascript"
                && $0.arguments.suffix(6) == [
                    "/usr/bin/true", "configure", "--speed", "82.0", "--temperature", "47.0",
                ]
        })
        #expect(commands.contains {
            $0.arguments.suffix(2) == ["/usr/bin/true", "disable"]
        })
        #expect(commands.contains {
            $0.arguments.suffix(2) == ["/usr/bin/true", "uninstall"]
        })
    }

    @Test("fan policies and privileged command construction stay bounded")
    func validatesFanPolicyAndPrivilegeBoundary() throws {
        #expect(ProviderFanPolicy(speedPercent: 60, triggerTemperatureCelsius: 15) != nil)
        #expect(ProviderFanPolicy(speedPercent: 90, triggerTemperatureCelsius: 125) != nil)
        #expect(ProviderFanPolicy(speedPercent: 59.9, triggerTemperatureCelsius: 45) == nil)
        #expect(ProviderFanPolicy(speedPercent: 90.1, triggerTemperatureCelsius: 45) == nil)
        #expect(ProviderFanPolicy(speedPercent: 80, triggerTemperatureCelsius: 14.9) == nil)
        #expect(ProviderFanPolicy(speedPercent: .infinity, triggerTemperatureCelsius: 45) == nil)

        let policy = try #require(ProviderFanPolicy(
            speedPercent: 80,
            triggerTemperatureCelsius: 45
        ))
        let command = ProviderExtrasCommand.privilegedFanMutation(
            executable: URL(fileURLWithPath: "/Applications/Test CLI/darkbloom"),
            action: .enable,
            policy: policy
        )
        #expect(command.executable.path == "/usr/bin/osascript")
        #expect(command.arguments.first == "-e")
        #expect(command.arguments[1].contains("with administrator privileges"))
        #expect(command.arguments[1].contains("/usr/bin/codesign --verify --deep --strict"))
        #expect(command.arguments[1].contains("io.darkbloom.provider"))
        #expect(command.arguments[1].contains("SLDQ2GJ6TL"))
        #expect(!command.arguments[1].contains("/Applications/Test CLI"))
        #expect(command.arguments.suffix(6) == [
            "/Applications/Test CLI/darkbloom", "enable",
            "--speed", "80.0", "--temperature", "45.0",
        ])

        let unsupportedInstalled = ProviderFanStatus(
            capability: ProviderFanStatus.controlCapability,
            installed: true,
            loaded: true,
            helper: nil,
            diagnostic: ProviderFanDiagnostic(
                chip: "Apple",
                supported: false,
                gpuTemperatures: [],
                fans: []
            ),
            helperErrorPresent: true,
            diagnosticErrorPresent: true
        )
        #expect(unsupportedInstalled.advertisesOfficialControl)
        #expect(!unsupportedInstalled.supportsOfficialControl)
    }

    @Test("fan mutations never elevate a PATH-discovered executable")
    func rejectsPathExecutableForFanMutation() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("dc-fan-path-\(UUID().uuidString)", isDirectory: true)
        let pathDirectory = directory.appendingPathComponent("bin", isDirectory: true)
        try FileManager.default.createDirectory(
            at: pathDirectory,
            withIntermediateDirectories: true
        )
        let pathExecutable = pathDirectory.appendingPathComponent("darkbloom")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: pathExecutable)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: pathExecutable.path
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let runner = ExtrasRunner(results: [:])
        let client = ProviderExtrasClient(
            policy: DarkbloomSourcePolicy(
                homeDirectory: directory,
                environmentPath: pathDirectory.path
            ),
            runner: runner
        )

        await #expect(throws: ProviderExtrasMutationError.executableUnavailable) {
            try await client.disableFan()
        }
        #expect(await runner.commands.isEmpty)
    }

    @Test("failed refresh retains the original source timestamp as stale")
    func retainsLastGoodSource() async {
        let client = StoreClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        let original = store.snapshot?.idlePolicy
        await client.failReads()
        await store.refresh()
        guard case .stale(let value, let capturedAt, _) = store.snapshot?.idlePolicy,
              case .available(let old, let oldTime) = original else {
            Issue.record("Failed read did not retain last-good idle policy as stale")
            return
        }
        #expect(value == old)
        #expect(capturedAt == oldTime)
        #expect(await client.saveCount == 0)
        await store.stop()
    }

    @Test("bounded parser rejects huge data and a fan index that would overflow the UI")
    func rejectsOversizeAndFanIndex() throws {
        #expect(throws: ProviderExtrasParseError.invalidPayload) {
            try ProviderExtrasParser.parseBeta(Data(repeating: 32, count: 256 * 1_024 + 1))
        }
        let overflow = String(decoding: fanJSON(updatedAt: 100), as: UTF8.self)
            .replacingOccurrences(of: "\"index\":0", with: "\"index\":9223372036854775807")
        #expect(throws: ProviderExtrasParseError.invalidValue) {
            try ProviderExtrasParser.parseFan(Data(overflow.utf8))
        }
    }

    @Test("store refresh is read-only and keeps a mutation error bounded")
    func storeReadOnlyAndBoundedMutation() async {
        let client = StoreClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        #expect(await client.refreshCount == 1)
        #expect(store.snapshot?.idlePolicy.value?.idleTimeoutMinutes == 0)
        #expect(await client.saveCount == 0)

        await #expect(throws: ProviderExtrasMutationError.commandFailed) {
            try await store.saveIdle(minutes: 60)
        }
        #expect(store.errorMessage == ProviderExtrasMutationError.commandFailed.userMessage)
    }
}

private func testPolicy() -> DarkbloomSourcePolicy {
    DarkbloomSourcePolicy(
        homeDirectory: URL(fileURLWithPath: "/tmp/dc-extras-tests"),
        environmentPath: "/usr/bin"
    )
}

private func fanJSON(updatedAt: Double) -> Data {
    Data(#"""
        {
          "capability":"darkbloom-fan-helper-v1",
          "installed":true,
          "loaded":true,
          "helper":{
            "helperVersion":"1",
            "protocolVersion":1,
            "enabled":true,
            "configuredUID":501,
            "providerActive":true,
            "mode":"waiting_for_temperature",
            "chip":"Apple M5",
            "gpuSensorKeys":["GPU0"],
            "gpuTemperatureC":65.0,
            "triggerTemperatureC":45.0,
            "releaseTemperatureC":40.0,
            "speedPercent":80.0,
            "fans":[{"index":0,"actualRPM":6250.0,"targetRPM":6000.0,"minimumRPM":1000.0,"maximumRPM":10000.0,"mode":"auto"}],
            "lastError":null,
            "updatedAt":\#(updatedAt)
          },
          "helperError":null,
          "diagnostic":{
            "chip":"Apple M5",
            "supported":true,
            "gpuTemperatures":[{"key":"GPU0","celsius":65.0}],
            "fans":[{"index":0,"actualRPM":6250.0,"targetRPM":6000.0,"minimumRPM":1000.0,"maximumRPM":10000.0,"mode":"auto"}],
            "error":null
          }
        }
        """#.utf8)
}

private actor ExtrasRunner: ProcessExecuting {
    enum Result {
        case success(Data)
        case failure
        case failureWithSecret
    }

    var results: [String: Result]
    let onFanRead: (@Sendable () -> Void)?
    private(set) var commands: [ProcessCommand] = []

    init(results: [String: Result], onFanRead: (@Sendable () -> Void)? = nil) {
        self.results = results
        self.onFanRead = onFanRead
    }

    func run(
        _ command: ProcessCommand,
        timeout: Duration,
        outputLimit: Int,
        onOutput: (@Sendable (ProcessOutputChunk) -> Void)?
    ) async throws -> CommandResult {
        commands.append(command)
        let key = command.arguments.prefix(2).joined(separator: " ")
        if key == "fan status" { onFanRead?() }
        switch results[key] {
        case .success(let data):
            return CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
        case .failure:
            throw ProcessRunnerError.nonzeroExit(code: 2, message: "private failure")
        case .failureWithSecret:
            throw ProcessRunnerError.nonzeroExit(code: 2, message: "secret=/Users/private/token")
        case nil:
            return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
        }
    }
}

private final class ExtrasTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) { self.date = date }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func set(_ date: Date) {
        lock.lock()
        defer { lock.unlock() }
        self.date = date
    }
}

private actor StoreClient: ProviderExtrasProviding {
    private var failing = false
    func failReads() { failing = true }
    private(set) var refreshCount = 0
    private(set) var saveCount = 0
    private(set) var fanRefreshCount = 0
    func refreshFan() async -> SourceAvailability<ProviderFanStatus> {
        fanRefreshCount += 1
        return .unavailable(reason: "fixture")
    }

    func refresh() async -> ProviderExtrasSnapshot {
        refreshCount += 1
        if failing {
            return ProviderExtrasSnapshot(capturedAt: Date(), idlePolicy: .unavailable(reason: "fixture"), betaFeatures: .unavailable(reason: "fixture"), fanStatus: .unavailable(reason: "fixture"))
        }
        return ProviderExtrasSnapshot(
            capturedAt: Date(),
            idlePolicy: .available(
                value: ProviderIdlePolicy(
                    idleTimeoutMinutes: 0,
                    policy: "always_ready",
                    summary: "always ready",
                    pinned: true
                ),
                capturedAt: Date()
            ),
            betaFeatures: .unavailable(reason: "fixture"),
            fanStatus: .unavailable(reason: "fixture")
        )
    }

    func saveIdle(minutes: Int) async throws {
        saveCount += 1
        throw ProviderExtrasMutationError.commandFailed
    }

    func setBeta(id: String, enabled: Bool) async throws {}
}
