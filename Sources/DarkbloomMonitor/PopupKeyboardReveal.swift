import SwiftUI

private struct PopupKeyboardRevealEnabledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var popupKeyboardRevealEnabled: Bool {
        get { self[PopupKeyboardRevealEnabledKey.self] }
        set { self[PopupKeyboardRevealEnabledKey.self] = newValue }
    }
}

/// The popup has both a body viewport and a whole-popup fallback viewport.
/// Reveal through each native clip only when keyboard focus enters a control.
struct PopupKeyboardReveal: ViewModifier {
    @Environment(\.popupKeyboardRevealEnabled) private var isEnabled

    func body(content: Content) -> some View {
        if isEnabled {
            content.modifier(ScrollControlKeyboardReveal())
        } else {
            content
        }
    }
}
