import Testing
@testable import DarkbloomTelemetry

@Suite("Darkbloom pin capacity")
struct ProviderAutopilotPinValidationTests {
    let gib: UInt64 = 1_073_741_824
    func model(_ id: String, _ memory: Double?) -> LocalModel {
        LocalModel(id: id, modelType: "mlx", sizeBytes: 1, estimatedMemoryGB: memory)
    }

    @Test("slot, downloaded model, and memory limits are all enforced")
    func limits() throws {
        let local = [model("a", 10), model("b", 11)]
        try ProviderAutopilotPinValidation.validate(pins: ["a", "b"], slots: 2, models: local, physicalBytes: 32 * gib, environment: [:])
        #expect(throws: ProviderAutopilotPinError.slotLimit) {
            try ProviderAutopilotPinValidation.validate(pins: ["a", "b"], slots: 1, models: local, physicalBytes: 32 * gib, environment: [:])
        }
        #expect(throws: ProviderAutopilotPinError.modelsUnavailable) {
            try ProviderAutopilotPinValidation.validate(pins: ["missing"], slots: 2, models: local, physicalBytes: 32 * gib, environment: [:])
        }
        #expect(throws: ProviderAutopilotPinError.modelsUnavailable) {
            try ProviderAutopilotPinValidation.validate(pins: ["a"], slots: 2, models: [model("a", nil)], physicalBytes: 32 * gib, environment: [:])
        }
        #expect(throws: ProviderAutopilotPinError.memoryLimit) {
            try ProviderAutopilotPinValidation.validate(pins: ["a", "b"], slots: 2, models: local, physicalBytes: 24 * gib, environment: [:])
        }
    }

    @Test("provider overrides affect the allowance and cannot lower activation floor")
    func overrides() throws {
        let local = [model("a", 20)]
        try ProviderAutopilotPinValidation.validate(pins: ["a"], slots: 1, models: local, physicalBytes: 32 * gib, environment: ["DARKBLOOM_ACTIVATION_RESERVE_GB": "1"])
        #expect(throws: ProviderAutopilotPinError.memoryLimit) {
            try ProviderAutopilotPinValidation.validate(pins: ["a"], slots: 1, models: local, physicalBytes: 32 * gib, environment: ["DARKBLOOM_MEM_CAP_FRACTION": "0.5"])
        }
        #expect(throws: ProviderAutopilotPinError.memoryLimit) {
            try ProviderAutopilotPinValidation.validate(pins: ["a"], slots: 1, models: local, physicalBytes: 32 * gib, environment: ["DARKBLOOM_ACTIVATION_RESERVE_GB": "10"])
        }
        #expect(throws: ProviderAutopilotPinError.memoryUnavailable) {
            try ProviderAutopilotPinValidation.validate(pins: ["a"], slots: 1, models: local, physicalBytes: 0, environment: [:])
        }
    }
}
