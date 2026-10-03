import SwiftUI

/// IDs are local to the Fans settings reader, never the popup's nested scroll.
enum FanSettingsFocusTarget: Hashable, Sendable {
    case settingsRefresh, readingsRefresh, enabled, policy, preset(FanPreset)
    case speed, temperature, save, advanced, disable, uninstall, discard
}

private struct FanSettingsFocusRevealKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (FanSettingsFocusTarget) -> Void)? = nil
}

extension EnvironmentValues {
    var fanSettingsFocusReveal: (@MainActor @Sendable (FanSettingsFocusTarget) -> Void)? {
        get { self[FanSettingsFocusRevealKey.self] }
        set { self[FanSettingsFocusRevealKey.self] = newValue }
    }
}

/// Native Tab, arrows and Space still belong to the control. Only focus entering
/// a control asks its settings Form to reveal it; source updates do not scroll.
struct FanSettingsKeyboardReveal: ViewModifier {
    let target: FanSettingsFocusTarget
    @Environment(\.fanSettingsFocusReveal) private var reveal
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if let reveal {
            content
                .background {
                    // Native focus rings extend beyond control bounds. Give
                    // the scroll target breathing room without adding layout
                    // padding or an extra accessibility/key-loop element.
                    Color.clear.id(target).padding(-6).accessibilityHidden(true)
                }
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused { reveal(target) }
                }
        } else {
            content
        }
    }
}
