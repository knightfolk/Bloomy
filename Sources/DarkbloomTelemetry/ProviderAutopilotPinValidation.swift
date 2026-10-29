import Foundation

/// The desktop pin preflight for the qualified Darkbloom 0.10.4 release.
/// These errors deliberately contain no paths or provider diagnostics.
public enum ProviderAutopilotPinError: Error, Equatable, Sendable {
    case slotLimit, modelsUnavailable, memoryLimit, memoryUnavailable

    public var userMessage: String {
        switch self {
        case .slotLimit: "These pins exceed the configured model slot limit."
        case .modelsUnavailable: "Every pinned model must be downloaded and its memory estimate available."
        case .memoryLimit: "These pins exceed this Mac’s model memory allowance."
        case .memoryUnavailable: "This Mac’s model memory allowance could not be checked."
        }
    }
}

enum ProviderAutopilotPinValidation {
    static func validate(pins: [String], slots: Int, models: [LocalModel],
                         physicalBytes: UInt64, environment: [String: String]) throws {
        guard pins.count <= slots else { throw ProviderAutopilotPinError.slotLimit }
        let gib: UInt64 = 1_073_741_824
        let memoryGB = physicalBytes / gib // HardwareDetector truncates to whole GiB.
        guard memoryGB > 0, memoryGB <= 4096 else { throw ProviderAutopilotPinError.memoryUnavailable }
        let physical = memoryGB * gib
        var fraction = 0.9
        if let raw = environment["DARKBLOOM_MEM_CAP_FRACTION"], let value = Double(raw), value.isFinite, value > 0 {
            fraction = min(value, 1)
        }
        let cap = min(UInt64(Double(physical) * fraction), physical > 2 * gib ? physical - 2 * gib : 0)
        var activation = 11 * gib / 2
        if let raw = environment["DARKBLOOM_ACTIVATION_RESERVE_GB"], let value = Double(raw), value.isFinite, value > 0 {
            let scaled = value * Double(gib)
            activation = max(activation, scaled >= Double(UInt64.max) ? UInt64.max : UInt64(scaled))
        }
        let headroom = activation > UInt64.max - gib ? UInt64.max : activation + gib
        let budget = max(0, Double(cap) / Double(gib) - Double(headroom) / Double(gib))
        var total = 0.0
        for pin in pins {
            let matches = models.filter { $0.id == pin }
            guard matches.count == 1, let estimate = matches.first?.estimatedMemoryGB,
                  estimate.isFinite, estimate > 0 else { throw ProviderAutopilotPinError.modelsUnavailable }
            total += estimate
        }
        guard total.isFinite, total <= budget else { throw ProviderAutopilotPinError.memoryLimit }
    }
}
