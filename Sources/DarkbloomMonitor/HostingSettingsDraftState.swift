import DarkbloomTelemetry
import SwiftUI

/// Retains only nonsecret text that has not yet become a hosting preference.
/// The caller supplies current options when checking protection; a stale
/// synchronization snapshot must never decide whether an update is safe.
@MainActor
final class HostingSettingsDraftState: ObservableObject {
    @Published var portText: String
    @Published var customAddressText: String

    private var synchronizedOptions: HostingOptions

    init(options: HostingOptions = .default) {
        portText = String(options.port)
        customAddressText = Self.customAddress(for: options)
        synchronizedOptions = options
    }

    func hasUnsavedEdits(comparedTo options: HostingOptions) -> Bool {
        hasUnsavedPort(comparedTo: options) || hasUnsavedAddress(comparedTo: options)
    }

    /// Refresh saved values independently, leaving partial input untouched.
    func synchronize(to options: HostingOptions) {
        if !hasUnsavedPort(comparedTo: synchronizedOptions) {
            portText = String(options.port)
        }
        if !hasUnsavedAddress(comparedTo: synchronizedOptions) {
            customAddressText = Self.customAddress(for: options)
        }
        synchronizedOptions = options
    }

    /// Discard text buffers only. This does not mutate saved preferences.
    func discardInputEdits(comparedTo options: HostingOptions) {
        portText = String(options.port)
        customAddressText = Self.customAddress(for: options)
        synchronizedOptions = options
    }

    private func hasUnsavedPort(comparedTo options: HostingOptions) -> Bool {
        UInt16(portText) != options.port
    }

    private func hasUnsavedAddress(comparedTo options: HostingOptions) -> Bool {
        customAddressText != Self.customAddress(for: options)
    }

    private static func customAddress(for options: HostingOptions) -> String {
        options.bindScope == .specificInterface ? options.bindAddress : ""
    }
}
