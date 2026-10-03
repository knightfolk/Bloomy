import AppKit
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
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            content.focused($isFocused)
                .background {
                    PopupFocusAnchor(isFocused: isFocused)
                        .accessibilityHidden(true)
                }
        } else {
            content
        }
    }
}

private struct PopupFocusAnchor: NSViewRepresentable {
    let isFocused: Bool
    func makeNSView(context: Context) -> PopupFocusAnchorView { PopupFocusAnchorView() }
    func updateNSView(_ view: PopupFocusAnchorView, context: Context) { view.setFocused(isFocused) }
    static func dismantleNSView(_ view: PopupFocusAnchorView, coordinator: ()) { view.setFocused(false) }
}

@MainActor
final class PopupFocusAnchorView: NSView {
    private var isFocused = false
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setFocused(_ focused: Bool) {
        guard focused != isFocused else { return }
        isFocused = focused
        if focused { requestReveal() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, isFocused { requestReveal() }
    }

    private func requestReveal() {
        // Layout must have assigned the background anchor's actual control
        // bounds. A lost focus or dismantled view cancels this queued reveal.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFocused, self.window != nil else { return }
            self.window?.contentView?.layoutSubtreeIfNeeded()
            self.revealInEnclosingViewports()
        }
    }

    func revealInEnclosingViewports() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        var scroll = enclosingScrollView
        while let viewport = scroll {
            if let document = viewport.documentView {
                let target = document.convert(bounds.insetBy(dx: -6, dy: -6), from: self)
                _ = document.scrollToVisible(target)
                viewport.reflectScrolledClipView(viewport.contentView)
            }
            scroll = viewport.enclosingScrollView
        }
    }
}
