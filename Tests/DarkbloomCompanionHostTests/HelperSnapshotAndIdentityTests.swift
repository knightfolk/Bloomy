import DarkbloomCompanionHelper
import DarkbloomCompanionProtocol
import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Companion helper adapters")
struct HelperSnapshotAndIdentityTests {
    @Test("live snapshot reads only allowlisted fields")
    func snapshotAllowlist() async throws {
        let canary = "SECRET_CANARY_\(UUID().uuidString)"
        let now = Date(timeIntervalSince1970: 1_000_000)
        var rawStatus = StatusSnapshot()
        rawStatus.configPath = "/private/\(canary)/config.toml"
        rawStatus.trustReason = canary
        let rawLog = LogEvent(
            timestamp: now, severity: .error, category: "provider", message: canary,
            source: .unified, processID: 123, processImage: canary
        )
        let source = TelemetrySnapshot(
            state: .unavailable(reason: canary),
            loadedModels: .unavailable(reason: canary),
            status: .available(value: rawStatus, capturedAt: now),
            eventFeed: .available(value: .init(events: [rawLog], legacyReadAt: now, unifiedActivityAt: now), capturedAt: now),
            tokenRate: .unavailable(reason: canary),
            diagnostics: [], capturedAt: now, menuStatus: .unavailable
        )
        let adapter = LiveCompanionSnapshotProvider(
            hostID: UUID(), runtimeEpoch: UUID(),
            telemetry: RefreshingTelemetrySource { source }, now: { now }
        )
        let snapshot = try await adapter.snapshot(for: UUID(), capabilities: [.monitor])
        let encoded = try JSONEncoder().encode(snapshot)
        #expect(!String(decoding: encoded, as: UTF8.self).contains(canary))
        #expect(snapshot.observations.isEmpty)
        #expect(snapshot.models.isEmpty)
        #expect(snapshot.states.provider.state == .unavailable)
        #expect(snapshot.capabilities == [.monitor])
    }

    @Test("app lifecycle uses the registered bundle only and refuses a mismatched running app")
    func exactAppIdentity() async throws {
        let url = URL(fileURLWithPath: "/Applications/Darkbloom.app")
        let registration = try RegisteredAppIdentity(
            bundleIdentifier: "com.darkbloom.control", bundleURL: url,
            designatedRequirement: "identifier com.darkbloom.control"
        )
        let system = FakeRegisteredAppSystem(bundleID: "com.darkbloom.control", signed: true)
        let dispatcher = RegisteredAppLifecycleDispatcher(registration: registration, system: system, canQuit: { true })
        try await dispatcher.perform(.open)
        #expect(await system.openedURLs == [url])
        await system.setRunning([.init(processID: 123, bundleURL: URL(fileURLWithPath: "/tmp/Darkbloom.app"))])
        await #expect(throws: RegisteredAppError.identityMismatch) { try await dispatcher.perform(.quit) }
        #expect(await system.terminatedIDs.isEmpty)
        await system.setRunning([.init(processID: 123, bundleURL: url)])
        await system.setRunningSignatureValid(false)
        await #expect(throws: RegisteredAppError.identityMismatch) { try await dispatcher.perform(.quit) }
        #expect(await system.terminatedIDs.isEmpty)
        await system.setRunningSignatureValid(true)
        try await dispatcher.perform(.quit)
        #expect(await system.terminatedIDs == [123])
    }

    @Test("dirty local draft refuses app quit")
    func dirtyDraftRefusal() async throws {
        let url = URL(fileURLWithPath: "/Applications/Darkbloom.app")
        let registration = try RegisteredAppIdentity(
            bundleIdentifier: "com.darkbloom.control", bundleURL: url,
            designatedRequirement: "identifier com.darkbloom.control"
        )
        let system = FakeRegisteredAppSystem(bundleID: "com.darkbloom.control", signed: true)
        let dispatcher = RegisteredAppLifecycleDispatcher(registration: registration, system: system, canQuit: { false })
        await #expect(throws: RegisteredAppError.dirtyDraft) { try await dispatcher.perform(.quit) }
    }
}

private actor FakeRegisteredAppSystem: RegisteredAppSystem {
    let bundleID: String
    let signed: Bool
    private(set) var openedURLs: [URL] = []
    private(set) var terminatedIDs: [Int32] = []
    private var running: [RegisteredRunningApp] = []
    private var runningSignatureValid = true

    init(bundleID: String, signed: Bool) {
        self.bundleID = bundleID
        self.signed = signed
    }

    func setRunning(_ apps: [RegisteredRunningApp]) { running = apps }
    func setRunningSignatureValid(_ value: Bool) { runningSignatureValid = value }
    func bundleIdentifier(at url: URL) -> String? { bundleID }
    func signatureMatches(at url: URL, requirement: String) -> Bool { signed }
    func signatureMatchesRunning(processID: Int32, requirement: String) -> Bool { signed && runningSignatureValid }
    func runningApps(bundleIdentifier: String) -> [RegisteredRunningApp] { running }
    func open(_ url: URL) { openedURLs.append(url) }
    func terminate(processID: Int32) -> Bool {
        terminatedIDs.append(processID)
        running.removeAll { $0.processID == processID }
        return true
    }
    func isRunning(processID: Int32) -> Bool { running.contains { $0.processID == processID } }
}
