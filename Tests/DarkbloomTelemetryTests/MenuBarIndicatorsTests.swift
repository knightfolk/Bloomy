import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Three menu-bar indicator policy")
struct MenuBarIndicatorsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("only fresh online inference enables activity")
    func activityRequiresCurrentEvidence() {
        #expect(make(snapshot: snapshot(active: true)).modelIsActive)
        #expect(!make(snapshot: snapshot(active: false)).modelIsActive)
        for state in [MenuPresentationStatus.offline, .stale, .unavailable] {
            #expect(!make(snapshot: snapshot(active: true, status: state)).modelIsActive)
        }
        #expect(!make(snapshot: snapshot(active: true, age: 10.01)).modelIsActive)
        #expect(!make(snapshot: snapshot(active: true, age: -1)).modelIsActive)
        #expect(make(snapshot: snapshot(active: true, age: 10)).modelIsActive)
    }

    @Test("idle resident model keeps its family without implying work")
    func idleModelFamily() {
        let idle = snapshot(active: false)
        #expect(MenuBarIndicators.modelFamily(snapshot: idle, now: now) == .qwen)
        #expect(!make(snapshot: idle).modelIsActive)
        #expect(MenuBarIndicators.modelFamily(snapshot: snapshot(active: true, age: 11), now: now) == .darkbloom)
        #expect(MenuBarIndicators.modelFamily(snapshot: snapshot(active: false, status: .offline), now: now) == .darkbloom)
        let newlyResident = snapshot(active: false, model: "Qwen3.8-27B", residents: ["openai/gpt-oss-20b"])
        #expect(MenuBarIndicators.modelFamily(snapshot: newlyResident, now: now) == .openai)
        #expect(!make(snapshot: newlyResident).modelIsActive)
    }

    @Test("GPU valid samples cover zero half and full without invented data")
    func gpuValues() {
        for (value, progress) in [(0.0, 0.0), (50.0, 0.5), (100.0, 1.0)] {
            let indicators = make(gpu: value)
            #expect(indicators.gpu.progress == progress)
            #expect(indicators.gpu.freshness == .current)
        }
        for value in [-1.0, 101, Double.nan, .infinity] {
            #expect(make(gpu: value).gpu.freshness == .unavailable)
        }
        #expect(make(gpu: nil).gpu.value == nil)
    }

    @Test("expired and skipped GPU readings stay faded last samples")
    func staleGPU() {
        let expired = make(gpu: 45, gpuAge: 10.01)
        #expect(expired.gpu.value == 45)
        #expect(expired.gpu.freshness == .stale)
        #expect(expired.accessibilityDetail.contains("last sample 45"))
        #expect(make(gpu: 45, gpuCurrent: false).gpu.freshness == .stale)
        #expect(make(gpu: 45, gpuAge: -1).gpu.freshness == .unavailable)
    }

    @Test("highest actual RPM fraction wins; targets and configured percent never count")
    func measuredFanSpeed() {
        let status = fanStatus(fans: [fan(1000, max: 5000), fan(2400, max: 3000)], configuredPercent: 99)
        #expect(make(fan: .available(value: status, capturedAt: now)).fanSpeed.value == 80)
        #expect(MenuBarIndicators.highestFanPercentage([fan(0, max: 5000)]) == 0)
        #expect(MenuBarIndicators.highestFanPercentage([fan(7000, max: 5000)]) == 100)
        #expect(MenuBarIndicators.highestFanPercentage([fan(nil, max: 5000, target: 5000)]) == nil)
        #expect(MenuBarIndicators.highestFanPercentage([fan(4000, max: nil)]) == nil)
        #expect(MenuBarIndicators.highestFanPercentage([fan(4000, max: 0)]) == nil)
        #expect(MenuBarIndicators.highestFanPercentage([fan(-1, max: 5000)]) == nil)
        #expect(MenuBarIndicators.highestFanPercentage([fan(.infinity, max: 5000)]) == nil)
        #expect(MenuBarIndicators.highestFanPercentage([fan(4000, max: .nan)]) == nil)
        #expect(make(fan: .available(value: fanStatus(fans: [fan(nil, max: nil)]), capturedAt: now)).fanSpeed.value == nil)
    }

    @Test("a stale helper uses fresh diagnostic RPM instead")
    func helperFallback() {
        let status = fanStatus(fans: [fan(4500, max: 5000)], helperAge: 16,
                               diagnosticFans: [fan(1000, max: 5000)], temperature: 95, sensors: [65])
        let indicators = make(fan: .available(value: status, capturedAt: now))
        #expect(indicators.fanSpeed.value == 20)
        #expect(indicators.fanSpeed.freshness == .current)
        #expect(indicators.temperature.value == 65)
        #expect(indicators.temperatureTint == .green)
        // Missing actual RPM in the helper cannot replace measured diagnostics.
        let missingActual = fanStatus(fans: [fan(nil, max: 5000, target: 4900)],
                                      diagnosticFans: [fan(3000, max: 5000)])
        #expect(make(fan: .available(value: missingActual, capturedAt: now)).fanSpeed.value == 60)
    }

    @Test("old fan readings remain explicit last samples with neutral temperature tint")
    func staleFan() {
        let status = fanStatus(fans: [fan(2500, max: 5000)], temperature: 90, sensors: [90])
        for availability in [SourceAvailability.available(value: status, capturedAt: now.addingTimeInterval(-46)),
                             .stale(value: status, capturedAt: now, reason: "fixture")] {
            let indicators = make(fan: availability)
            #expect(indicators.fanSpeed.value == 50)
            #expect(indicators.fanSpeed.freshness == .stale)
            #expect(indicators.temperatureTint == .neutral)
            #expect(!indicators.modelIsActive)
        }
        #expect(make(fan: .unavailable(reason: "fixture")).fanSpeed.value == nil)
        #expect(make(fan: .available(value: status, capturedAt: now.addingTimeInterval(1))).temperature.value == nil)
    }

    @Test("temperature keeps established 70 and 85 degree display boundaries")
    func thermalStates() {
        for (temperature, tint) in [(69.9, MenuBarGPURing.Tint.green), (70, .yellow), (84.9, .yellow), (85, .red)] {
            let indicators = make(fan: .available(value: fanStatus(temperature: temperature), capturedAt: now))
            #expect(indicators.temperature.value == temperature)
            #expect(indicators.temperatureTint == tint)
            #expect(indicators.accessibilityDetail.contains("degrees Celsius"))
        }
        for value in [Double.nan, .infinity, 9.9, 125.1] {
            #expect(make(fan: .available(value: fanStatus(temperature: value), capturedAt: now)).temperature.value == nil)
        }
        let diagnostic = fanStatus(temperature: nil, sensors: [61, 74, 130])
        #expect(make(fan: .available(value: diagnostic, capturedAt: now)).temperature.value == 74)
    }

    @Test("idle unavailable input schedules no periodic display updates")
    func freshnessDeadlines() {
        let missing = MenuBarIndicators.make(snapshot: .unavailable(now: now), utilization: nil,
                                            sampledAt: nil, fanStatus: nil, now: now)
        #expect(missing.nextFreshnessChange == nil)
        let active = make(snapshot: snapshot(active: true, age: 9), gpu: nil)
        #expect(active.nextFreshnessChange == now.addingTimeInterval(1.01))
        let expired = make(snapshot: snapshot(active: true, age: 11), gpu: 50, gpuAge: 11)
        #expect(expired.nextFreshnessChange == nil)
    }

    private func make(snapshot: TelemetrySnapshot? = nil, gpu: Double? = 50, gpuAge: Double = 1,
                      gpuCurrent: Bool = true, fan: SourceAvailability<ProviderFanStatus>? = nil) -> MenuBarIndicators {
        MenuBarIndicators.make(snapshot: snapshot ?? .unavailable(now: now), utilization: gpu,
                               sampledAt: now.addingTimeInterval(-gpuAge), utilizationIsCurrent: gpuCurrent,
                               fanStatus: fan, now: now)
    }

    private func snapshot(active: Bool, status: MenuPresentationStatus = .online, age: Double = 1,
                          model: String = "Qwen3.8-27B", residents: [String] = ["Qwen3.8-27B"]) -> TelemetrySnapshot {
        let state = DaemonState(schema: 1, version: "fixture", currentModel: model,
            warmModels: residents, stats: .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: .init(level: "full", status: "online", reason: "fixture", receivedAt: now.timeIntervalSince1970),
            capacity: nil, slots: [], inferenceActive: active, startedAt: now.timeIntervalSince1970 - 600,
            writtenAt: now.timeIntervalSince1970 - age, pid: 1, processIdentity: .init(pid: 1, startTimeMicros: 1))
        return TelemetrySnapshot(state: .available(value: state, capturedAt: now), loadedModels: .unavailable(reason: "fixture"),
            status: .unavailable(reason: "fixture"), eventFeed: .unavailable(reason: "fixture"),
            tokenRate: .unavailable(reason: "fixture"), diagnostics: [], capturedAt: now, menuStatus: status)
    }

    private func fan(_ actual: Double?, max: Double?, target: Double? = 4900) -> ProviderFanReading {
        .init(index: 0, actualRPM: actual, targetRPM: target, minimumRPM: 1000, maximumRPM: max, mode: "auto")
    }

    private func fanStatus(fans: [ProviderFanReading] = [], helperAge: Double = 1,
                           diagnosticFans: [ProviderFanReading] = [], temperature: Double? = nil,
                           sensors: [Double] = [], configuredPercent: Double = 80) -> ProviderFanStatus {
        .init(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
            helper: .init(enabled: true, providerActive: false, mode: "standby", chip: "fixture",
                gpuTemperatureCelsius: temperature, triggerTemperatureCelsius: 45, releaseTemperatureCelsius: 40,
                speedPercent: configuredPercent, fans: fans, updatedAt: now.addingTimeInterval(-helperAge)),
            diagnostic: .init(chip: "fixture", supported: true,
                gpuTemperatures: sensors.enumerated().map { .init(key: "G\($0.offset)", celsius: $0.element) }, fans: diagnosticFans),
            helperErrorPresent: false, diagnosticErrorPresent: false)
    }
}
