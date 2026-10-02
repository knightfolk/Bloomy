import DarkbloomTelemetry
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Read-only thermal evidence")
struct ProviderThermalPresentationTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test("current helper posture respects enabled before provider activity", arguments: [false, true], [false, true])
    func currentPosture(enabled: Bool, providerActive: Bool) throws {
        let presentation = try #require(make(status(helperAt: now, enabled: enabled, providerActive: providerActive)))
        #expect(presentation.cliFreshness == .current)
        #expect(presentation.helperFreshness == .current)
        #expect(!presentation.readingsAreStale)
        #expect(presentation.helperPosture == (!enabled ? .disabled : providerActive ? .active : .waiting))
        #expect(presentation.status.displayedTemperatureCelsius == 80)
    }

    @Test("both current evidence boundaries are inclusive")
    func inclusiveBoundaries() throws {
        let presentation = try #require(make(status(helperAt: now.addingTimeInterval(-15)), capturedAt: now.addingTimeInterval(-45)))
        #expect(presentation.helperPosture == .active)
        #expect(!presentation.readingsAreStale)
        let expiredCLI = try #require(make(status(helperAt: now), capturedAt: now.addingTimeInterval(-45.001)))
        #expect(expiredCLI.helperFreshness == .current)
        #expect(expiredCLI.cliFreshness == .stale)
        #expect(expiredCLI.helperPosture == .lastActive)
        #expect(expiredCLI.readingsAreStale)
    }

    @Test("a stale source never promotes its helper flag into a current activity claim", arguments: [0.0, 900.0])
    func markedStale(age: Double) throws {
        let original = status(helperAt: now.addingTimeInterval(-age))
        let presentation = try #require(ProviderThermalPresentation.make(from:
            .stale(value: original, capturedAt: now.addingTimeInterval(-age), reason: "Inert read failure"), at: now))
        #expect(presentation.helperPosture == .lastActive)
        #expect(presentation.helperPosture.message == "Last observed: fan helper was active while the provider was serving.")
        #expect(presentation.readingsAreStale)
        #expect(presentation.status == original)
        #expect(presentation.status.displayedFans.first?.actualRPM == 4_000)
    }

    @Test("current CLI diagnostics replace expired helper readings without claiming helper activity")
    func diagnosticFreshnessIsIndependent() throws {
        let presentation = try #require(make(status(helperAt: now.addingTimeInterval(-15.001), diagnosticTemperature: 42)))
        #expect(presentation.cliFreshness == .current)
        #expect(presentation.helperFreshness == .stale)
        #expect(presentation.helperPosture == .lastActive)
        #expect(!presentation.readingsAreStale)
        #expect(presentation.displayedTemperatureCelsius == 42)
        #expect(presentation.displayedFans.first?.actualRPM == 1_200)
        #expect(presentation.temperatureFreshness == .current)
        #expect(presentation.fanFreshness == .current)
    }

    @Test("expired helper readings remain last known when no current diagnostic can replace them", arguments: [false, true])
    func retainedReadings(diagnosticFailed: Bool) throws {
        let original = status(helperAt: now.addingTimeInterval(-900),
            diagnosticTemperature: diagnosticFailed ? 42 : nil, diagnosticFailed: diagnosticFailed)
        let presentation = try #require(make(original))
        #expect(presentation.status == original)
        #expect(presentation.status.displayedTemperatureCelsius == 80)
        #expect(presentation.status.displayedFans.first?.actualRPM == 4_000)
        #expect(presentation.readingsAreStale)
        #expect(presentation.helperPosture == .lastActive)
    }

    @Test("future and invalid timestamps do not assert current helper activity", arguments: [false, true], [false, true])
    func unverifiedTimestamps(invalid: Bool, helperTimestamp: Bool) throws {
        let timestamp = invalid ? Date(timeIntervalSince1970: .nan) : now.addingTimeInterval(1)
        let presentation = try #require(make(status(helperAt: helperTimestamp ? timestamp : now),
            capturedAt: helperTimestamp ? now : timestamp))
        #expect(presentation.helperPosture == .unverified)
        #expect(presentation.readingsAreStale)
        #expect(presentation.temperatureFreshness.readingQualifier == "Unverified")
        #expect(presentation.fanFreshness.readingQualifier == "Unverified")
        #expect(presentation.status.displayedTemperatureCelsius == 80)
    }

    @Test("disabled and unloaded last-known states also remain qualified")
    func staleNonactivePosture() throws {
        let disabled = try #require(make(status(helperAt: now.addingTimeInterval(-16), enabled: false)))
        #expect(disabled.helperPosture == .lastDisabled)
        let unloadedStatus = status(helperAt: now, loaded: false)
        let unloaded = try #require(make(unloadedStatus))
        #expect(unloaded.helperPosture == .notLoaded)
        let oldUnloaded = try #require(make(unloadedStatus, capturedAt: now.addingTimeInterval(-46)))
        #expect(oldUnloaded.helperPosture == .lastNotLoaded)
    }

    @Test("missing or failed helper activity is unavailable even if readings remain")
    func helperUnavailable() throws {
        let missing = try #require(make(status(helperAt: nil, diagnosticTemperature: 42)))
        #expect(missing.helperFreshness == .unavailable)
        #expect(missing.helperPosture == .unavailable)
        #expect(!missing.readingsAreStale)
        let failed = try #require(make(status(helperAt: now, diagnosticTemperature: 42, helperFailed: true)))
        #expect(failed.helperPosture == .unavailable)
        #expect(failed.displayedTemperatureCelsius == 42)
        #expect(!failed.readingsAreStale)
        #expect(ProviderThermalPresentation.make(from: .unavailable(reason: "Inert fixture"), at: now) == nil)
        #expect(ProviderThermalPresentation.make(from: nil, at: now) == nil)
    }

    @Test("partial current diagnostics retain the other last-known helper reading", arguments: [false, true])
    func partialDiagnostic(temperatureAvailable: Bool) throws {
        let original = status(helperAt: now.addingTimeInterval(-16),
            diagnosticTemperature: temperatureAvailable ? 42 : nil, diagnosticFans: !temperatureAvailable)
        let presentation = try #require(make(original))
        #expect(presentation.status == original)
        #expect(presentation.displayedTemperatureCelsius == (temperatureAvailable ? 42 : 80))
        #expect(presentation.displayedFans.first?.actualRPM == (temperatureAvailable ? 4_000 : 1_200))
        #expect(presentation.temperatureFreshness == (temperatureAvailable ? .current : .stale))
        #expect(presentation.fanFreshness == (temperatureAvailable ? .stale : .current))
        #expect(presentation.readingsAreStale)
        #expect(presentation.helperPosture == .lastActive)
        #expect((temperatureAvailable ? presentation.fanFreshness : presentation.temperatureFreshness).readingQualifier == "Last observed")
    }

    @Test("qualified temperature and two fans retain the compact dashboard width")
    @MainActor
    func twoFanReadingWidth() {
        let row = HStack(spacing: 14) {
            ProviderThermalView.readingLabel("80.0 °C", systemImage: "flame", accessibilityName: "Temperature", freshness: .stale)
            ProviderThermalView.readingLabel("Fan 1 4000 RPM", systemImage: "wind", freshness: .stale)
            ProviderThermalView.readingLabel("Fan 2 4000 RPM", systemImage: "wind", freshness: .stale)
        }.font(.callout)
        let host = NSHostingController(rootView: row)
        let fitted = host.sizeThatFits(in: NSSize(width: 500, height: 0))
        #expect(fitted.width <= 344)
        #expect(fitted.height <= 42)
    }

    @Test("a compressed measurement retains its full value and RPM unit", arguments: [false, true])
    @MainActor
    func measurementKeepsUnit(retained: Bool) {
        let label = ProviderThermalView.readingLabel("Fan 1 2200 RPM", systemImage: "wind",
            freshness: retained ? .stale : .current).font(.callout)
        let host = NSHostingController(rootView: label)
        let natural = host.sizeThatFits(in: NSSize(width: 500, height: 0))
        let compressed = host.sizeThatFits(in: NSSize(width: 60, height: 0))
        #expect(natural.width > 60)
        #expect(compressed.width >= natural.width)
        #expect(compressed.height <= natural.height)
        let mixed = HStack(spacing: 14) {
            ProviderThermalView.readingLabel("42.0 °C", systemImage: "flame", accessibilityName: "Temperature", freshness: .current)
            ProviderThermalView.readingLabel("Fan 1 2200 RPM", systemImage: "wind", freshness: .stale)
            ProviderThermalView.readingLabel("Fan 2 1200 RPM", systemImage: "wind", freshness: .current)
        }.font(.callout)
        let mixedHost = NSHostingController(rootView: mixed)
        let fitted = mixedHost.sizeThatFits(in: NSSize(width: 328, height: 0))
        #expect(fitted.width <= 328)
        #expect(fitted.height <= 42)
    }

    @Test("current fan metadata without RPM retains known readings per fan index", arguments: [false, true])
    func nilDiagnosticRPM(hasSecondFan: Bool) throws {
        let original = status(helperAt: now.addingTimeInterval(-16), diagnosticTemperature: 42,
            helperFans: [fan(0, rpm: 4_000), fan(1, rpm: 3_800)],
            diagnosticReadings: [fan(0, rpm: nil)] + (hasSecondFan ? [fan(1, rpm: 900)] : []))
        let presentation = try #require(make(original))
        #expect(presentation.displayedFans.map(\.index) == [0, 1])
        #expect(presentation.displayedFans.map(\.actualRPM) == [4_000, hasSecondFan ? 900 : 3_800])
        #expect(presentation.displayedFans.map(\.freshness) == [.stale, hasSecondFan ? .current : .stale])
        #expect(presentation.displayedFans.first?.freshness.readingQualifier == "Last observed")
        #expect(presentation.displayedFans.last?.freshness.readingQualifier == (hasSecondFan ? nil : "Last observed"))
        #expect(presentation.fanFreshness == .stale)
        #expect(presentation.readingsAreStale)
    }

    @Test("current helper metadata without RPM permits diagnostic or retained fallback", arguments: [false, true])
    func nilHelperRPM(diagnosticFailed: Bool) throws {
        let original = status(helperAt: now, diagnosticTemperature: 42, diagnosticFailed: diagnosticFailed,
            helperFans: [fan(0, rpm: nil)], diagnosticReadings: [fan(0, rpm: 1_200)])
        let presentation = try #require(make(original))
        #expect(presentation.displayedFans.first?.actualRPM == 1_200)
        #expect(presentation.fanFreshness == (diagnosticFailed ? .stale : .current))
        #expect(presentation.displayedFans.first?.freshness == (diagnosticFailed ? .stale : .current))
        #expect(presentation.readingsAreStale == diagnosticFailed)
    }

    @Test("metadata-only fans do not suppress missing readings and observed zero RPM remains usable")
    func usableRPM() throws {
        let missing = try #require(make(status(helperAt: now, helperTemperature: nil,
            helperFans: [fan(0, rpm: nil)], diagnosticReadings: [fan(0, rpm: nil)])))
        #expect(missing.displayedTemperatureCelsius == nil)
        #expect(missing.displayedFans.isEmpty)
        #expect(!missing.hasReadings)
        #expect(missing.fanFreshness == .unavailable)
        let stopped = try #require(make(status(helperAt: now, helperFans: [fan(0, rpm: 0)])))
        #expect(stopped.displayedFans.first?.actualRPM == 0)
        #expect(stopped.fanFreshness == .current)
    }

    private func fan(_ index: Int, rpm: Double?) -> ProviderFanReading {
        .init(index: index, actualRPM: rpm, targetRPM: nil, minimumRPM: 1_000, maximumRPM: 5_000, mode: "fixture")
    }

    private func make(_ status: ProviderFanStatus, capturedAt: Date? = nil) -> ProviderThermalPresentation? {
        ProviderThermalPresentation.make(from: .available(value: status, capturedAt: capturedAt ?? now), at: now)
    }

    private func status(helperAt: Date?, enabled: Bool = true, providerActive: Bool = true,
                        loaded: Bool = true, diagnosticTemperature: Double? = nil,
                        helperFailed: Bool = false, diagnosticFailed: Bool = false,
                        diagnosticFans: Bool? = nil, helperTemperature: Double? = 80,
                        helperFans: [ProviderFanReading]? = nil,
                        diagnosticReadings: [ProviderFanReading]? = nil) -> ProviderFanStatus {
        ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: loaded,
            helper: helperAt.map {
                ProviderFanHelperStatus(enabled: enabled, providerActive: providerActive, mode: "Inert fixture", chip: "fixture",
                    gpuTemperatureCelsius: helperTemperature, triggerTemperatureCelsius: 45, releaseTemperatureCelsius: 40, speedPercent: 80,
                    fans: helperFans ?? [.init(index: 0, actualRPM: 4_000, targetRPM: 4_000, minimumRPM: 1_000, maximumRPM: 5_000, mode: "auto")],
                    updatedAt: $0)
            }, diagnostic: .init(chip: "fixture", supported: true,
                gpuTemperatures: diagnosticTemperature.map { [.init(key: "GPU", celsius: $0)] } ?? [],
                fans: diagnosticReadings ?? ((diagnosticFans ?? (diagnosticTemperature != nil)) ? [.init(index: 0, actualRPM: 1_200, targetRPM: nil,
                    minimumRPM: 1_000, maximumRPM: 5_000, mode: "auto")] : [])),
            helperErrorPresent: helperFailed, diagnosticErrorPresent: diagnosticFailed)
    }
}
