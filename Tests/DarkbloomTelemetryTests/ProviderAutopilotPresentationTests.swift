import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Autopilot consent and observed mode presentation")
@MainActor
struct ProviderAutopilotPresentationTests {
    private let date = Date(timeIntervalSince1970: 1_000)

    @Test("a previously constructed action view reads later idle and fan edits immediately")
    func liveDraftGate() {
        let draft = ProviderSettingsDraftState()
        let view = ProviderAutopilotSettingsView(store: ProviderExtrasStore(client: PresentationExtras()),
            control: ProviderControlStore(controller: PresentationController(), hostingOptions: { .default }),
            performMutation: { _, _ in false }, isVisible: true, draft: draft)
        #expect(view.enrollmentReason == nil)
        draft.syncIdle(from: .available(value: ProviderIdlePolicy(idleTimeoutMinutes: 30,
            policy: "idle_timeout", summary: "Fixture", pinned: false), capturedAt: date))
        draft.editIdle("30")
        #expect(!view.hasUnsavedSettings)
        #expect(view.enrollmentReason == nil)
        draft.editIdle("45")
        #expect(view.hasUnsavedSettings)
        #expect(view.enrollmentReason == "Save or discard your provider settings edits first.")
        draft.discardIdle(from: nil)
        #expect(!view.hasUnsavedSettings)
        #expect(view.enrollmentReason == nil)
        draft.editFanSpeed(85)
        #expect(view.hasUnsavedSettings)
        #expect(view.enrollmentReason != nil)
    }

    private func status(enabled: Bool = true, consent: Bool = true, paused: Bool = false,
                        livePaused: Bool = false, active: Bool = false, observeOnly: Bool = true,
                        matches: Bool = true, phase: ProviderAutopilotPhase? = .shadow,
                        livePresent: Bool = true) -> ProviderAutopilotStatus {
        .init(configuredEnabled: enabled, consentRecorded: consent, configuredPaused: paused,
              selectedModels: enabled ? ["EigenLabs/Qwen3.8-27B-4bit-mtp"] : [], pinnedModels: [],
              configuredRevision: "fixture",
              live: livePresent ? .init(protocolVersion: 3, enabled: enabled, active: active,
                  observeOnly: observeOnly, paused: livePaused, cachedOnly: true,
                  revision: matches ? "fixture" : "old") : nil,
              phase: phase)
    }
    private func presentation(_ value: ProviderAutopilotStatus, age: TimeInterval = 0) -> ProviderAutopilotPresentation {
        .init(source: .available(value: value, capturedAt: date), at: date.addingTimeInterval(age))
    }

    @Test("Enrollment and shadow observation never promise automatic model changes")
    func shadow() {
        let observed = presentation(status())
        #expect(observed.stateTitle == "Observing · shadow mode")
        #expect(observed.compactStateTitle == "Shadow")
        #expect(observed.explanation.contains("recorded only"))
        #expect(!observed.canEnroll)
        #expect(observed.canPerform(.pause))
        #expect(!observed.canPerform(.resume))
        #expect(observed.canPerform(.disable))
    }

    @Test("Active requires consistent fresh matching live flags and known active phase",
          arguments: ["valid", "oldRevision", "observeOnly", "unknownPhase", "noLive"])
    func active(mode: String) {
        let observed = presentation(status(active: true, observeOnly: mode == "observeOnly",
            matches: mode != "oldRevision", phase: mode == "unknownPhase" ? nil : .active,
            livePresent: mode != "noLive"))
        #expect((observed.stateTitle == "Actively managing") == (mode == "valid"))
        #expect((observed.compactStateTitle == "Live") == (mode == "valid"))
    }

    @Test("Configured pause or resume is distinguishable from observed control")
    func policyReadback() {
        #expect(presentation(status(paused: true)).stateTitle == "Pause requested")
        let paused = presentation(status(paused: true, livePaused: true, phase: .paused))
        #expect(paused.stateTitle == "Paused")
        #expect(paused.compactStateTitle == "Paused")
        #expect(paused.canPerform(.resume))
        #expect(!paused.canPerform(.pause))
        let resume = presentation(status(livePaused: true))
        #expect(resume.stateTitle == "Resume requested")
        #expect(resume.explanation.contains("Resume is saved"))
        #expect(paused.explanation.contains("may still finish"))
    }

    @Test("Fresh off or incomplete consent allows the native opt-in")
    func optIn() {
        #expect(presentation(status(enabled: false)).canEnroll)
        #expect(presentation(status(consent: false)).canEnroll)
        #expect(presentation(status(consent: false)).stateTitle == "Setup incomplete")
        #expect(!presentation(status(enabled: false)).canPerform(.resume))
    }

    @Test("Leaving keeps accepted transitions visible even after active becomes false",
          arguments: [ProviderAutopilotPhase.recovering, .transitioning])
    func finishingAfterLeave(phase: ProviderAutopilotPhase) {
        let observed = presentation(status(enabled: false, active: false, phase: phase))
        #expect(observed.stateTitle == "Leaving Autopilot")
        #expect(observed.explanation.contains("may still finish"))
        #expect(!observed.canEnroll)
    }

    @Test("Successful evidence expires without a new read", arguments: [45.0, 45.001, -1.0])
    func expiry(age: TimeInterval) {
        let observed = presentation(status(), age: age)
        let fresh = age >= 0 && age <= 45
        #expect(observed.isFresh == fresh)
        #expect(observed.canPerform(.pause) == fresh)
        #expect(observed.canPerform(.disable) == fresh)
        #expect(observed.stateTitle.hasPrefix("Last known:") == !fresh)
        #expect(observed.compactStateTitle == (fresh ? "Shadow" : "Stale"))
        #expect(presentation(status(enabled: false), age: age).canEnroll == fresh)
    }

    @Test("Retained evidence and absent status cannot authorize consent or policy changes")
    func missing() {
        let sources: [SourceAvailability<ProviderAutopilotStatus>?] = [nil,
            .unavailable(reason: "fixture"), .stale(value: status(), capturedAt: date, reason: "fixture")]
        for source in sources {
            let observed = ProviderAutopilotPresentation(source: source, at: date)
            #expect(!observed.canEnroll)
            #expect(!observed.canPerform(.pause))
            #expect(!observed.canPerform(.resume))
            #expect(!observed.canPerform(.disable))
            #expect(observed.explanation.contains("Refresh"))
        }
    }
}

private struct PresentationExtras: ProviderExtrasProviding {
    func refresh() async -> ProviderExtrasSnapshot {
        .init(capturedAt: Date(), idlePolicy: .unavailable(reason: "fixture"),
            betaFeatures: .unavailable(reason: "fixture"), fanStatus: .unavailable(reason: "fixture"))
    }
    func saveIdle(minutes: Int) async throws { throw ProviderExtrasMutationError.commandFailed }
    func setBeta(id: String, enabled: Bool) async throws { throw ProviderExtrasMutationError.commandFailed }
}
private struct PresentationController: ProviderControlling {
    func refresh() async throws -> ProviderControlSnapshot { throw ProviderControlError.noEnabledModels }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw ProviderControlError.noEnabledModels }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws { throw ProviderControlError.noEnabledModels }
    func delete(_ localModelID: String) async throws { throw ProviderControlError.noEnabledModels }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { throw ProviderControlError.noEnabledModels }
}
