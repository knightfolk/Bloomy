import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Fan settings state", .serialized)
@MainActor
struct FanSettingsStateTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let submitted = ProviderFanPolicy(speedPercent: 83, triggerTemperatureCelsius: 43)!

    @Test("unconfirmed fan commands retain submitted values until matching fresh readback", arguments: [
        "missing", "unavailable", "stale", "aged", "future", "expiredHelper", "futureHelper",
        "missingHelper", "helperError", "mismatch", "notLoaded", "notEnabled"
    ])
    func unconfirmedReadback(mode: String) {
        let draft = ProviderSettingsDraftState()
        draft.editFanSpeed(submitted.speedPercent)
        draft.editFanTemperature(submitted.triggerTemperatureCelsius)
        let revision = draft.fanRevision
        var source: SourceAvailability<ProviderFanStatus>? = .available(value: status(), capturedAt: now)
        switch mode {
        case "missing": source = nil
        case "unavailable": source = .unavailable(reason: "fixture")
        case "stale": source = .stale(value: status(), capturedAt: now, reason: "fixture")
        case "aged": source = .available(value: status(), capturedAt: now.addingTimeInterval(-45.001))
        case "future": source = .available(value: status(), capturedAt: now.addingTimeInterval(1))
        case "expiredHelper": source = .available(value: status(helperAt: now.addingTimeInterval(-15.001)), capturedAt: now)
        case "futureHelper": source = .available(value: status(helperAt: now.addingTimeInterval(1)), capturedAt: now)
        case "missingHelper": source = .available(value: status().withoutHelper(), capturedAt: now)
        case "helperError": source = .available(value: status(helperError: true), capturedAt: now)
        case "mismatch": source = .available(value: status(policy: .default), capturedAt: now)
        case "notLoaded": source = .available(value: status(loaded: false), capturedAt: now)
        default: source = .available(value: status(enabled: false), capturedAt: now)
        }
        #expect(!draft.didSaveFan(revision: revision, source: source, submittedPolicy: submitted,
                                 requiresEnabled: true, at: now))
        #expect(draft.fanPolicy == submitted)
        #expect(draft.fanDirty)
        #expect(draft.fanSaveAwaitingConfirmation)
        #expect(draft.hasChanges)
        draft.syncFan(from: source, at: now)
        #expect(draft.fanPolicy == submitted)
        #expect(draft.fanDirty)
        // A later observed policy, rather than a second write, releases the guard.
        draft.syncFan(from: .available(value: status(), capturedAt: now), at: now)
        #expect(draft.fanPolicy == submitted)
        #expect(!draft.fanDirty)
        #expect(!draft.fanSaveAwaitingConfirmation)
        #expect(!draft.hasChanges)
        #expect(draft.fanRevision == revision)
    }

    @Test("late or pending confirmation cannot clear a newer edit")
    func newerEdit() {
        let draft = ProviderSettingsDraftState()
        draft.selectFanPreset(.cooling)
        let revision = draft.fanRevision
        #expect(!draft.didSaveFan(revision: revision, source: nil, submittedPolicy: FanPreset.cooling.policy, at: now))
        draft.editFanSpeed(83)
        #expect(!draft.fanSaveAwaitingConfirmation)
        let oldReadback: SourceAvailability<ProviderFanStatus> = .available(value: status(policy: FanPreset.cooling.policy), capturedAt: now)
        #expect(ProviderSettingsDraftState.fanPolicyIsConfirmed(FanPreset.cooling.policy, source: oldReadback, at: now))
        #expect(!draft.didSaveFan(revision: revision, source: oldReadback, submittedPolicy: FanPreset.cooling.policy, at: now))
        draft.syncFan(from: oldReadback, at: now)
        #expect(draft.fanSpeedPercent == 83)
        #expect(draft.fanDirty)
        #expect(!draft.fanSaveAwaitingConfirmation)
        draft.discardFan(from: oldReadback)
        #expect(!draft.fanDirty)
        #expect(!draft.fanSaveAwaitingConfirmation)
        #expect(draft.fanPolicy == FanPreset.cooling.policy)
    }

    @Test("a clean enable command with unknown readback still protects its submitted policy")
    func cleanEnable() {
        let draft = ProviderSettingsDraftState()
        draft.syncFan(from: .available(value: status(), capturedAt: now), at: now)
        #expect(!draft.hasChanges)
        #expect(!draft.didSaveFan(revision: draft.fanRevision, source: nil, submittedPolicy: submitted,
                                 requiresEnabled: true, at: now))
        #expect(draft.fanPolicy == submitted)
        #expect(draft.hasChanges)
        #expect(draft.fanSaveAwaitingConfirmation)
    }

    @Test("expired or invalid helper evidence cannot supply an actionable toggle", arguments: [0.0, 15.0, 15.001, -1.0, Double.infinity, Double.nan])
    func toggleFreshness(age: Double) {
        let value = status(helperAt: now.addingTimeInterval(-age))
        let expected: Bool? = age.isFinite && age >= 0 && age <= 15 ? true : nil
        #expect(ProviderFanControlSettingsView.toggleState(value, at: now) == expected)
        #expect(ProviderFanControlSettingsView.toggleState(status(helperError: true), at: now) == nil)
        #expect(ProviderFanControlSettingsView.toggleState(status().withoutHelper(), at: now) == nil)
        #expect(ProviderFanControlSettingsView.toggleState(status(loaded: false), at: now) == false)
    }

    @Test("current and retained readings remain independent and spoken", arguments: [false, true])
    func partialDiagnostics(temperatureIsCurrent: Bool) throws {
        let value = status(helperAt: now.addingTimeInterval(-16),
            diagnosticTemperature: temperatureIsCurrent ? 42 : nil,
            diagnosticFans: temperatureIsCurrent ? [] : [fan(rpm: 1_200)])
        let presentation = try #require(ProviderThermalPresentation.make(from: .available(value: value, capturedAt: now), at: now))
        let first = try #require(presentation.displayedFans.first)
        #expect(presentation.displayedTemperatureCelsius == (temperatureIsCurrent ? 42 : 80))
        #expect(first.actualRPM == (temperatureIsCurrent ? 4_000 : 1_200))
        #expect(first.reading.targetRPM == 4_500)
        #expect(presentation.temperatureFreshness == (temperatureIsCurrent ? .current : .stale))
        #expect(first.freshness == (temperatureIsCurrent ? .stale : .current))
        let temperatureAX = ProviderFanControlSettingsView.measurementAccessibilityLabel("GPU temperature", value: "80.0 °C", freshness: presentation.temperatureFreshness)
        let fanAX = ProviderFanControlSettingsView.measurementAccessibilityLabel("Fan 1 speed", value: "4000 RPM", freshness: first.freshness)
        #expect(temperatureAX.contains("Last observed") == !temperatureIsCurrent)
        #expect(fanAX.contains("Last observed") == temperatureIsCurrent)
        #expect(fanAX.contains("Fan 1 speed"))
        #expect(fanAX.contains("RPM"))
        #expect(ProviderFanControlSettingsView.measurementAccessibilityLabel("GPU temperature", value: "80.0 °C", freshness: .invalid).contains("Unverified"))
    }

    @Test("empty evidence does not fabricate a zero measurement")
    func emptyReadings() throws {
        let value = ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: false,
            loaded: false, helper: nil,
            diagnostic: .init(chip: "fixture", supported: true, gpuTemperatures: [], fans: []),
            helperErrorPresent: false, diagnosticErrorPresent: false)
        let presentation = try #require(ProviderThermalPresentation.make(from: .available(value: value, capturedAt: now), at: now))
        #expect(presentation.displayedTemperatureCelsius == nil)
        #expect(presentation.displayedFans.isEmpty)
        #expect(!presentation.hasReadings)
        #expect(ProviderThermalPresentation.make(from: .unavailable(reason: "fixture"), at: now) == nil)
    }

    @Test("completed writes distinguish fan and provider confirmation", arguments: [false, true], [false, true])
    func completionFeedback(fanConfirmed: Bool, providerConfirmed: Bool) {
        let message = ProviderFanControlSettingsView.completedCommandFeedback(fanConfirmed: fanConfirmed,
            providerConfirmed: providerConfirmed, successMessage: "Fan policy updated.")
        if !fanConfirmed {
            #expect(message.contains("command completed"))
            #expect(message.contains("has not been confirmed"))
            #expect(message != "Fan policy updated.")
        } else if !providerConfirmed {
            #expect(message.contains("Fan state confirmed"))
            #expect(message.contains("Provider settings confirmation is unavailable"))
        } else {
            #expect(message == "Fan policy updated.")
        }
    }

    private func status(policy: ProviderFanPolicy? = nil, helperAt: Date? = nil,
                        loaded: Bool = true, enabled: Bool = true, helperError: Bool = false,
                        diagnosticTemperature: Double? = nil, diagnosticFans: [ProviderFanReading] = []) -> ProviderFanStatus {
        let policy = policy ?? submitted
        return ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: loaded,
            helper: .init(enabled: enabled, providerActive: true, mode: "active", chip: "fixture",
                gpuTemperatureCelsius: 80, triggerTemperatureCelsius: policy.triggerTemperatureCelsius,
                releaseTemperatureCelsius: 40, speedPercent: policy.speedPercent,
                fans: [fan(rpm: 4_000)], updatedAt: helperAt ?? now),
            diagnostic: .init(chip: "fixture", supported: true,
                gpuTemperatures: diagnosticTemperature.map { [.init(key: "GPU0", celsius: $0)] } ?? [],
                fans: diagnosticFans), helperErrorPresent: helperError, diagnosticErrorPresent: false)
    }

    private func fan(rpm: Double) -> ProviderFanReading {
        .init(index: 0, actualRPM: rpm, targetRPM: 4_500, minimumRPM: 1_000, maximumRPM: 9_000, mode: "auto")
    }
}
