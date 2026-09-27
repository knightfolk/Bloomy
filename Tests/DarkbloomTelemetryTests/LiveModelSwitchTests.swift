import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Live model switch capability")
struct LiveModelSwitchTests {
    private let config = URL(fileURLWithPath: "/Users/example/.config/darkbloom/provider.toml")
    private let now = Date(timeIntervalSince1970: 1_800_000_110)

    @Test("fresh matching v0.9.10 state enables live apply")
    func freshMatchingState() {
        let availability = ProviderLiveSwitchAvailability.evaluate(
            daemon: daemon(),
            daemonSource: .fresh(evidenceAt: now),
            providerConfig: config,
            at: now
        )

        #expect(availability == .available)
        #expect(availability.isAvailable)
    }

    @Test("older stale mismatched and in-progress providers fail closed")
    func unavailableStates() {
        let older = daemon(modelSwitch: nil, configPath: nil, runtimeCapabilities: nil)
        #expect(ProviderLiveSwitchAvailability.evaluate(
            daemon: older,
            daemonSource: .fresh(evidenceAt: now),
            providerConfig: config,
            at: now
        ) == .unavailable("Upgrade the running provider to use Apply Live"))

        #expect(ProviderLiveSwitchAvailability.evaluate(
            daemon: daemon(),
            daemonSource: .stale("private stale detail"),
            providerConfig: config,
            at: now
        ) == .unavailable("Refresh current provider state before applying live"))

        #expect(ProviderLiveSwitchAvailability.evaluate(
            daemon: daemon(configPath: "/different/provider.toml"),
            daemonSource: .fresh(evidenceAt: now),
            providerConfig: config,
            at: now
        ) == .unavailable("The running provider uses a different configuration"))

        #expect(ProviderLiveSwitchAvailability.evaluate(
            daemon: daemon(modelSwitch: .init(outcome: .switching, models: ["model-b"])),
            daemonSource: .fresh(evidenceAt: now),
            providerConfig: config,
            at: now
        ) == .inProgress)
    }

    private func daemon(
        modelSwitch: ProviderModelSwitchState? = .init(outcome: .serving, models: []),
        configPath: String? = "/Users/example/.config/darkbloom/provider.toml",
        runtimeCapabilities: [String]? = []
    ) -> DaemonState {
        DaemonState(
            schema: 1,
            version: "0.9.10",
            currentModel: "model-a",
            warmModels: ["model-a"],
            stats: .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: nil,
            capacity: nil,
            slots: [],
            inferenceActive: false,
            startedAt: 1_800_000_000,
            writtenAt: 1_800_000_110,
            pid: 42,
            processIdentity: .init(pid: 42, startTimeMicros: 1_800_000_000_000_000),
            advertisedModels: ["model-a"],
            coordinatorURL: "https://api.darkbloom.dev",
            modelSwitch: modelSwitch,
            configPath: configPath,
            runtimeCapabilities: runtimeCapabilities
        )
    }
}
