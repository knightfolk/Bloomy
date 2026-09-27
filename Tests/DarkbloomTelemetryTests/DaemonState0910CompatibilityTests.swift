import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Darkbloom 0.9.10 daemon state")
struct DaemonState0910CompatibilityTests {
    @Test("scheduled idle preserves process and lifecycle evidence without trust or capacity")
    func scheduledIdleSparseState() throws {
        let state = try parse("daemon-state-0910-scheduled-idle")

        #expect(state.processIdentity == .init(pid: 12001, startTimeMicros: 1_800_000_000_000_000))
        #expect(state.trust == nil)
        #expect(state.capacity == nil)
        #expect(state.slots.isEmpty)
        #expect(state.lifecycle?.outcome == .drained)
        #expect(state.availability == .init(phase: .waitingForSchedule, nextWindowAt: 1_800_003_600))
        #expect(ProviderRuntimePresentation.make(state).title == "Waiting for schedule")
        #expect(ProviderRequestActivityPresentation.make(daemonState: state).status == "Scheduled idle")
    }

    @Test("startup preload and on-demand models remain distinct")
    func preloadAndOnDemand() throws {
        let state = try parse("daemon-state-0910-preload")

        #expect(state.startupPreloadPendingModels == ["model-b"])
        #expect(state.runtimeCapabilities == ["apple_m5", "mlx_nax"])
        #expect(state.configPath == "/Users/example/.config/darkbloom/provider.toml")
        #expect(ProviderModelRuntimePresentation.make(modelID: "model-b", state: state).status == "Preloading")
        #expect(ProviderModelRuntimePresentation.make(modelID: "model-a", state: state).status == "Loaded")
        #expect(ProviderModelRuntimePresentation.make(modelID: "model-c", state: state).status == "On demand")
        #expect(ProviderRequestActivityPresentation.make(daemonState: state).status == "Preloading")
    }

    @Test("model switch exposes only typed bounded state")
    func switchingState() throws {
        let state = try parse("daemon-state-0910-switching")

        #expect(state.modelSwitch == .init(outcome: .switching, models: ["model-c"], remainingRequests: 1))
        let presentation = ProviderRuntimePresentation.make(state)
        #expect(presentation.title == "Switching models")
        #expect(ProviderRequestActivityPresentation.make(daemonState: state).status == "Switching")
        #expect(!presentation.detail.contains("private provider prose"))
        #expect(!presentation.detail.contains("private-request-id"))
    }

    @Test(arguments: [
        ("daemon-state-0910-busy", ProviderLifecycleOutcome.busy, "Lifecycle busy", "Busy"),
        ("daemon-state-0910-forced", ProviderLifecycleOutcome.forced, "Forced stop", "Forced stop"),
        ("daemon-state-0910-timeout", ProviderLifecycleOutcome.timedOut, "Drain timed out", "Timed out"),
    ])
    func terminalLifecycleStates(
        fixture: String,
        outcome: ProviderLifecycleOutcome,
        title: String,
        activityStatus: String
    ) throws {
        let state = try parse(fixture)

        #expect(state.lifecycle?.outcome == outcome)
        #expect(ProviderRuntimePresentation.make(state).title == title)
        #expect(ProviderRequestActivityPresentation.make(daemonState: state).status == activityStatus)
    }

    private func parse(_ name: String) throws -> DaemonState {
        let url = try #require(Bundle.module.url(
            forResource: name,
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        return try DaemonStateParser.parse(Data(contentsOf: url))
    }
}
