import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Electricity settings recording readiness")
struct ElectricitySettingsRecordingTests {
    struct PriceCase: Sendable {
        let text: String
        let expected: ElectricitySettingsRecordingState
    }

    static let cases: [PriceCase] = [
        .init(text: "", expected: .waitingForPrice),
        .init(text: " \n\t ", expected: .waitingForPrice),
        .init(text: "-0.15", expected: .invalidPrice),
        .init(text: "unknown", expected: .invalidPrice),
        .init(text: "nan", expected: .invalidPrice),
        .init(text: "inf", expected: .invalidPrice),
        .init(text: "-inf", expected: .invalidPrice),
        .init(text: "0", expected: .ready),
        .init(text: " 0 ", expected: .ready),
        .init(text: "0.15", expected: .ready),
        .init(text: " 0.15 ", expected: .ready),
    ]

    @Test("enabled readiness agrees with the recorder's actual sampling gate", arguments: cases)
    func enabledPrice(_ price: PriceCase) async throws {
        let state = ElectricitySettingsRecordingState(enabled: true, price: price.text)
        #expect(state == price.expected)
        #expect((state.validation == nil) == (price.expected == .ready))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let recorder = EnergyRecorder(file: directory.appendingPathComponent("energy.json")) { date in
            // A missing/invalid price must return before asking the sensor.
            #expect(price.expected == .ready)
            return EnergyReading(date: date, watts: 40, source: "synthetic", estimated: true)
        }
        let sample = await recorder.sample(enabled: true, rate: ElectricityCost.rate(price.text),
            now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect((sample.reading != nil) == (price.expected == .ready))
        #expect((sample.issue == nil) == (price.expected == .ready))
    }

    @Test("disabled remains off and never samples regardless of retained price", arguments: cases)
    func disabledPrice(_ price: PriceCase) async {
        let state = ElectricitySettingsRecordingState(enabled: false, price: price.text)
        #expect(state == .disabled)
        #expect(state.validation == nil)
        let recorder = EnergyRecorder(file: FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).appendingPathComponent("unused.json")) { date in
                Issue.record("Disabled settings must not read the power sensor")
                return EnergyReading(date: date, watts: 40, source: "synthetic", estimated: true)
            }
        let sample = await recorder.sample(enabled: false, rate: ElectricityCost.rate(price.text),
            now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(sample.reading == nil)
        #expect(sample.intervals.isEmpty)
        #expect(sample.issue == nil)
    }
}
