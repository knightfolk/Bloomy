import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Provider request activity")
struct ProviderRequestActivityPresentationTests {
    @Test("active inference is shown as a lower bound because the daemon exposes no exact count")
    func activeIsLowerBound() throws {
        let state = try daemon(inferenceActive: true, lifecycle: ["outcome": "serving"])
        let value = ProviderRequestActivityPresentation.make(daemonState: state)

        #expect(value.mode == .active)
        #expect(value.value == "1+")
        #expect(value.status == "Active")
        #expect(value.detail.contains("exact live count is not reported"))
    }

    @Test("accepted work and loading are not presented as idle")
    func queuedWork() throws {
        let pending = ProviderRequestActivityPresentation.make(daemonState: try daemon(inferenceActive: false, lifecycle: nil, pending: true))
        #expect(pending.mode == .active && pending.value == "1+" && pending.status == "Work pending")
        let loading = ProviderRequestActivityPresentation.make(daemonState: try daemon(inferenceActive: false, lifecycle: nil, loading: true))
        #expect(loading.status == "Loading" && loading.value == "—")
        let idle = ProviderRequestActivityPresentation.make(daemonState: try daemon(inferenceActive: false, lifecycle: nil, pending: false))
        #expect(idle.detail.contains("No active inference or accepted or queued work"))
    }

    @Test("stopped lifecycle cannot conceal a pending work report")
    func conflictingStoppedWork() throws {
        let state = try daemon(inferenceActive: false, lifecycle: ["outcome": "stopped"], pending: true)
        let presentation = ProviderRequestActivityPresentation.make(daemonState: state)
        #expect(presentation.mode == .unavailable)
        #expect(presentation.status == "Unconfirmed")
        #expect(presentation.value == "—")
    }

    @Test("validation does not assert that new work is paused")
    func validating() throws {
        let state = try daemon(inferenceActive: true, lifecycle: nil, modelSwitch: ["outcome": "validating", "models": []])
        let value = ProviderRequestActivityPresentation.make(daemonState: state)
        #expect(value.status == "Validating")
        #expect(value.detail.contains("does not establish"))
    }

    @Test("native drain presents the exact remaining accepted request count")
    func drainingShowsExactRemaining() throws {
        let state = try daemon(
            inferenceActive: true,
            lifecycle: ["outcome": "draining", "remaining": 7, "coordinator_acknowledged": false]
        )
        let value = ProviderRequestActivityPresentation.make(daemonState: state)

        #expect(value.mode == .draining)
        #expect(value.value == "7")
        #expect(value.status == "Draining")
        #expect(value.detail.contains("new requests are paused"))
    }

    @Test("zero remaining requests stays in finishing while usage acknowledgement is pending")
    func waitsForUsageAcknowledgement() throws {
        let state = try daemon(
            inferenceActive: false,
            lifecycle: ["outcome": "draining", "remaining": 0, "coordinator_acknowledged": false]
        )
        let value = ProviderRequestActivityPresentation.make(daemonState: state)

        #expect(value.mode == .draining)
        #expect(value.value == "0")
        #expect(value.status == "Finishing")
        #expect(value.detail.contains("confirming usage"))
    }

    @Test("malformed lifecycle counts are omitted and arbitrary outcome text is reduced to unknown")
    func sanitizesLifecycleFields() throws {
        let state = try daemon(
            inferenceActive: true,
            lifecycle: ["outcome": "private-token=never-display", "remaining": -4]
        )

        #expect(state.lifecycle?.outcome == .unknown)
        #expect(state.lifecycle?.remainingRequests == nil)
        let value = ProviderRequestActivityPresentation.make(daemonState: state)
        #expect(value.value == "1+")
        #expect(!value.status.contains("private-token"))
        #expect(!value.detail.contains("private-token"))
    }

    @Test("old schema-one states remain usable without lifecycle telemetry")
    func legacyStateUsesInferenceSignal() throws {
        let state = try daemon(inferenceActive: false, lifecycle: nil)

        #expect(state.lifecycle == nil)
        #expect(ProviderRequestActivityPresentation.make(daemonState: state).mode == .idle)
    }

    private func daemon(inferenceActive: Bool, lifecycle: [String: Any]?, pending: Bool? = nil, loading: Bool? = nil, modelSwitch: [String: Any]? = nil) throws -> DaemonState {
        let url = try #require(Bundle.module.url(
            forResource: "daemon-state-online",
            withExtension: "json",
            subdirectory: "Fixtures"
        ))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["inference_active"] = inferenceActive
        json["request_work_pending"] = pending
        json["load_transition_active"] = loading
        json["model_switch"] = modelSwitch
        if let lifecycle {
            json["lifecycle"] = lifecycle
        } else {
            json.removeValue(forKey: "lifecycle")
        }
        return try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: json))
    }
}
