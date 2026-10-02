import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Provider settings freshness", .serialized)
@MainActor
struct ProviderSettingsFreshnessTests {
    @Test("expired or future settings evidence cannot reach the mutation client", arguments: [46.0, -1.0], ["idle", "beta", "auto", "enable", "configure", "disable", "uninstall"])
    func expiredEvidence(age: Double, action: String) async throws {
        let clock = SettingsClock()
        let client = SettingsClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refresh()
        clock.advance(by: age)
        await #expect(throws: ProviderSettingsEvidenceError.refreshRequired) { try await mutate(action, store: store) }
        #expect(await client.mutations.isEmpty)
        #expect(store.errorMessage != nil)
        // Read-only refresh re-establishes evidence; no discarded write is retried.
        await store.refresh()
        #expect(await client.mutations.isEmpty)
        try await mutate(action, store: store)
        #expect(await client.mutations == [action])
        await store.stop()
    }

    @Test("source age is checked when a staged confirmation finally executes", arguments: ["idle", "beta", "auto", "configure", "disable"])
    func delayedConfirmation(action: String) async throws {
        let clock = SettingsClock()
        let client = SettingsClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refresh()
        // The parent may hold a confirmed operation while another operation finishes.
        let confirmedOperation: @Sendable () async throws -> Void = { try await mutate(action, store: store) }
        clock.advance(by: 45.001)
        await #expect(throws: ProviderSettingsEvidenceError.refreshRequired) { try await confirmedOperation() }
        #expect(await client.mutations.isEmpty)
        #expect(await client.reads == 1)
        await store.stop()
    }

    @Test("last-good and unavailable evidence cannot authorize settings writes", arguments: ["stale", "unavailable", "missing"], ["idle", "beta", "auto", "enable", "configure", "disable", "uninstall"])
    func unavailableEvidence(mode: String, action: String) async {
        let clock = SettingsClock()
        let client = SettingsClient(clock: clock, mode: mode)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        if mode != "missing" { await store.refresh() }
        await #expect(throws: ProviderSettingsEvidenceError.refreshRequired) { try await mutate(action, store: store) }
        #expect(await client.mutations.isEmpty)
        await store.stop()
    }

    @Test("the existing inclusive 45-second settings boundary remains usable", arguments: ["idle", "beta", "auto", "enable", "configure", "disable", "uninstall"])
    func boundary(action: String) async throws {
        let clock = SettingsClock()
        let client = SettingsClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refresh()
        clock.advance(by: 45)
        try await mutate(action, store: store)
        #expect(await client.mutations == [action])
        await store.stop()
    }

    @Test("idle and beta writes use only their matching source evidence", arguments: ["idle", "beta"], [false, true])
    func matchingEvidence(action: String, matchingSourceIsFresh: Bool) async throws {
        let clock = SettingsClock()
        let matchingMode = matchingSourceIsFresh ? "available" : "stale"
        let client = SettingsClient(clock: clock,
            mode: matchingSourceIsFresh ? "unavailable" : "available",
            idleMode: action == "idle" ? matchingMode : nil,
            betaMode: action == "beta" ? matchingMode : nil)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refresh()
        if matchingSourceIsFresh {
            try await mutate(action, store: store)
            #expect(await client.mutations == [action])
        } else {
            await #expect(throws: ProviderSettingsEvidenceError.refreshRequired) { try await mutate(action, store: store) }
            #expect(await client.mutations.isEmpty)
        }
        await store.stop()
    }

    @Test("settings schedule contains only the next evidence transitions")
    func freshnessDeadlines() {
        let capturedAt = Date(timeIntervalSince1970: 1_000)
        let source: SourceAvailability<ProviderAutoUpdateStatus> = .available(value: .init(enabled: true), capturedAt: capturedAt)
        #expect(ProviderSettingsFreshnessPolicy.transitions(for: source, at: capturedAt.addingTimeInterval(10))
            == [Date(timeIntervalSince1970: 1_045.001)])
        #expect(ProviderSettingsFreshnessPolicy.transitions(for: source, at: capturedAt.addingTimeInterval(-1))
            == [capturedAt, Date(timeIntervalSince1970: 1_045.001)])
        #expect(ProviderSettingsFreshnessPolicy.transitions(for: source, at: capturedAt.addingTimeInterval(46)).isEmpty)
        let stale: SourceAvailability<ProviderAutoUpdateStatus> = .stale(value: .init(enabled: true), capturedAt: capturedAt, reason: "fixture")
        #expect(ProviderSettingsFreshnessPolicy.transitions(for: stale, at: capturedAt).isEmpty)
    }

    @Test("expired helper readings yield to current diagnostics", arguments: [false, true])
    func helperReadings(hasDiagnostic: Bool) {
        let now = Date(timeIntervalSince1970: 1_000)
        let helper = ProviderFanHelperStatus(enabled: true, providerActive: true, mode: "active", chip: "fixture",
            gpuTemperatureCelsius: 80, triggerTemperatureCelsius: 45, releaseTemperatureCelsius: 40,
            speedPercent: 80, fans: [.init(index: 0, actualRPM: 8_000, targetRPM: 8_000, minimumRPM: 1_000, maximumRPM: 9_000, mode: "auto")],
            updatedAt: now.addingTimeInterval(-90))
        let status = ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
            helper: helper, diagnostic: .init(chip: "fixture", supported: true,
                gpuTemperatures: hasDiagnostic ? [.init(key: "GPU0", celsius: 42)] : [], fans: []),
            helperErrorPresent: false, diagnosticErrorPresent: false)
        let displayed = ProviderFanControlSettingsView.readingStatus(status, at: now)
        #expect(displayed.displayedTemperatureCelsius == (hasDiagnostic ? 42 : 80))
        #expect((displayed.helper == nil) == hasDiagnostic)
    }
}

@MainActor
private func mutate(_ action: String, store: ProviderExtrasStore) async throws {
    switch action {
    case "idle": try await store.saveIdle(minutes: 10)
    case "beta": try await store.setBeta(id: "mtp", enabled: false)
    case "auto": try await store.setAutoUpdate(enabled: false)
    case "enable": try await store.enableFan(policy: .default)
    case "configure": try await store.configureFan(policy: .default)
    case "disable": try await store.disableFan()
    default: try await store.uninstallFan()
    }
}

private final class SettingsClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_000)
    func advance(by interval: TimeInterval) { lock.withLock { date = date.addingTimeInterval(interval) } }
    func now() -> Date { lock.withLock { date } }
}

private actor SettingsClient: ProviderExtrasProviding {
    let clock: SettingsClock
    let mode: String
    let idleMode: String?
    let betaMode: String?
    private(set) var mutations: [String] = []
    private(set) var reads = 0
    init(clock: SettingsClock, mode: String = "available", idleMode: String? = nil, betaMode: String? = nil) {
        self.clock = clock
        self.mode = mode
        self.idleMode = idleMode
        self.betaMode = betaMode
    }
    func refresh() async -> ProviderExtrasSnapshot {
        reads += 1
        let date = clock.now()
        return ProviderExtrasSnapshot(capturedAt: date,
            idlePolicy: availability(ProviderIdlePolicy(idleTimeoutMinutes: 5,
                policy: "fixture", summary: "fixture", pinned: false), at: date, mode: idleMode),
            betaFeatures: availability([ProviderBetaFeature(id: "mtp", title: "Fixture feature",
                state: .on, enabled: true, requiresRestart: true, summary: "fixture")], at: date, mode: betaMode),
            fanStatus: availability(ProviderFanStatus(capability: ProviderFanStatus.controlCapability,
                installed: true, loaded: true, helper: nil,
                diagnostic: ProviderFanDiagnostic(chip: "fixture", supported: true, gpuTemperatures: [], fans: []),
                helperErrorPresent: false, diagnosticErrorPresent: false), at: date),
            autoUpdateStatus: availability(ProviderAutoUpdateStatus(enabled: true), at: date))
    }
    private func availability<Value>(_ value: Value, at date: Date, mode: String? = nil) -> SourceAvailability<Value> where Value: Equatable & Sendable {
        switch mode ?? self.mode {
        case "stale": .stale(value: value, capturedAt: date, reason: "fixture")
        case "unavailable": .unavailable(reason: "fixture")
        default: .available(value: value, capturedAt: date)
        }
    }
    func saveIdle(minutes: Int) async throws { mutations.append("idle") }
    func setBeta(id: String, enabled: Bool) async throws { mutations.append("beta") }
    func setAutoUpdate(enabled: Bool) async throws { mutations.append("auto") }
    func enableFan(policy: ProviderFanPolicy) async throws { mutations.append("enable") }
    func configureFan(policy: ProviderFanPolicy) async throws { mutations.append("configure") }
    func disableFan() async throws { mutations.append("disable") }
    func uninstallFan() async throws { mutations.append("uninstall") }
}
