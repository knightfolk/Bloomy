#if FIXTURE_SETTINGS_PREVIEW_PROOF
import DarkbloomTelemetry
import Foundation

/// Explicit reads only. No polling, CLI, sensors, files or fan mutations.
actor SettingsProofExtras: ProviderExtrasProviding {
    private var input: (temperature: Double, fanPercent: Double)?
    private(set) var readCount = 0
    func set(temperature: Double, fanPercent: Double) { input = (temperature, fanPercent) }
    func failRead() { input = nil }
    func refresh() async -> ProviderExtrasSnapshot {
        readCount += 1
        let now = Date()
        let fan: SourceAvailability<ProviderFanStatus>
        if let input {
            let reading = ProviderFanReading(index: 0, actualRPM: input.fanPercent * 60,
                targetRPM: nil, minimumRPM: 0, maximumRPM: 6_000, mode: "Synthetic measured input")
            let status = ProviderFanStatus(capability: ProviderFanStatus.controlCapability,
                installed: false, loaded: false, helper: nil,
                diagnostic: ProviderFanDiagnostic(chip: "Synthetic", supported: false,
                    gpuTemperatures: [ProviderFanTemperature(key: "Synthetic GPU", celsius: input.temperature)],
                    fans: [reading]), helperErrorPresent: false, diagnosticErrorPresent: false)
            fan = .available(value: status, capturedAt: now)
        } else { fan = .unavailable(reason: "Synthetic fan read failed") }
        return ProviderExtrasSnapshot(capturedAt: now,
            idlePolicy: .unavailable(reason: "Not used by this proof"),
            betaFeatures: .unavailable(reason: "Not used by this proof"), fanStatus: fan)
    }
    func saveIdle(minutes: Int) async throws { throw ProviderExtrasMutationError.commandFailed }
    func setBeta(id: String, enabled: Bool) async throws { throw ProviderExtrasMutationError.commandFailed }
}
#endif
