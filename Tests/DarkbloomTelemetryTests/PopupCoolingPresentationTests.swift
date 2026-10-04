import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Compact popup cooling distinguishes helper state and sensors")
@MainActor
struct PopupCoolingPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_000)

    private func status(enabled: Bool = true, mode: String = "automatic", helperAge: Double = 0,
                        helperError: Bool = false, diagnosticError: Bool = false,
                        diagnosticTemperature: Double? = 42, diagnosticRPM: Double? = 1_200) -> ProviderFanStatus {
        let helperFan = ProviderFanReading(index: 0, actualRPM: 2_200, targetRPM: 2_200,
            minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic")
        let diagnosticFans = diagnosticRPM.map { rpm in [ProviderFanReading(index: 0, actualRPM: rpm,
            targetRPM: nil, minimumRPM: 1_200, maximumRPM: 5_200, mode: "automatic")] } ?? []
        return ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
            helper: ProviderFanHelperStatus(enabled: enabled, providerActive: true, mode: mode, chip: "Synthetic",
                gpuTemperatureCelsius: 54, triggerTemperatureCelsius: 45, releaseTemperatureCelsius: 40,
                speedPercent: 80, fans: [helperFan], updatedAt: now.addingTimeInterval(-helperAge)),
            diagnostic: ProviderFanDiagnostic(chip: "Synthetic", supported: true,
                gpuTemperatures: diagnosticTemperature.map { [ProviderFanTemperature(key: "GPU", celsius: $0)] } ?? [],
                fans: diagnosticFans), helperErrorPresent: helperError, diagnosticErrorPresent: diagnosticError)
    }

    @Test("RPM cannot hide a disabled helper")
    func disabled() {
        let value = PopupCoolingPresentation(source: .available(value: status(enabled: false), capturedAt: now), at: now)
        #expect(value.state == .off)
        #expect(value.compactDetail == "Helper off")
        #expect(value.temperatureLabel == "54°C")
        #expect(value.accessibilityReadings.contains("2200 RPM"))
    }

    @Test("Current RPM remains compact when the helper is confirmed healthy")
    func healthy() {
        let value = PopupCoolingPresentation(source: .available(value: status(), capturedAt: now), at: now)
        #expect(value.state == .on && value.readingsAreFresh)
        #expect(value.compactDetail == "2200 RPM")
        #expect(!value.accessibilityReadings.contains("Last observed"))
    }

    @Test("Fresh helper and diagnostic errors remain visible despite readings", arguments: ["helper", "diagnostic", "mode"])
    func attention(_ kind: String) {
        let value = PopupCoolingPresentation(source: .available(value: status(mode: kind == "mode" ? "error" : "automatic",
            helperError: kind == "helper", diagnosticError: kind == "diagnostic"), capturedAt: now), at: now)
        #expect(value.state == .attention && value.compactDetail == "Needs attention")
        #expect(value.maximumFan != nil)
    }

    @Test("Expired helper control stays unknown while each sensor keeps its own freshness")
    func partialReadings() {
        let value = PopupCoolingPresentation(source: .available(value: status(helperAge: 16, diagnosticRPM: nil), capturedAt: now), at: now)
        #expect(value.state == .checkHelper)
        #expect(value.compactDetail == "Check helper")
        #expect(value.temperatureLabel == "42°C")
        #expect(value.accessibilityReadings.contains("Last observed highest fan speed 2200 RPM"))
        let missingDiagnostic = PopupCoolingPresentation(source: .available(value: status(helperAge: 16,
            diagnosticTemperature: nil, diagnosticRPM: nil), capturedAt: now), at: now)
        #expect(missingDiagnostic.temperatureLabel == "Last 54°C")
        #expect(missingDiagnostic.accessibilityReadings.contains("Last observed 54 degrees Celsius"))
    }

    @Test("Retained data is not announced as healthy current control", arguments: [0.0, 45.001, -1.0])
    func retainedAndInvalid(age: Double) {
        let source: SourceAvailability<ProviderFanStatus> = age == 0
            ? .stale(value: status(), capturedAt: now, reason: "Synthetic retained data")
            : .available(value: status(), capturedAt: now.addingTimeInterval(-age))
        let value = PopupCoolingPresentation(source: source, at: now)
        #expect(!value.readingsAreFresh)
        #expect(value.state == (age < 0 ? .unverified : .retained))
        #expect(value.compactDetail == (age < 0 ? "Unverified" : "Last readings"))
        #expect(value.temperatureLabel == (age < 0 ? "Unverified 54°C" : "Last 54°C"))
    }

    @Test("Missing sources preserve unknown instead of manufacturing zero RPM")
    func missing() {
        for source: SourceAvailability<ProviderFanStatus>? in [nil, .unavailable(reason: "Synthetic failure")] {
            let value = PopupCoolingPresentation(source: source, at: now)
            #expect(value.state == .unavailable && value.maximumFan == nil)
            #expect(value.temperatureLabel == "Cooling —" && value.compactDetail == "Unavailable")
            #expect(value.accessibilityReadings == "Temperature unavailable, Fan speed unavailable")
        }
    }
}
