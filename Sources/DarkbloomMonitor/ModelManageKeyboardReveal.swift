import AppKit
import SwiftUI

/// One model is presented per Manage sheet; these IDs belong only to its reader.
enum ModelManageFocusTarget: Hashable, Sendable {
    case header, runtime, enabled, preload, delete, details, forecast, download, refresh
}

private struct ModelManageFocusRevealKey: EnvironmentKey {
    static let defaultValue: (@MainActor @Sendable (ModelManageFocusTarget) -> Void)? = nil
}

extension EnvironmentValues {
    var modelManageFocusReveal: (@MainActor @Sendable (ModelManageFocusTarget) -> Void)? {
        get { self[ModelManageFocusRevealKey.self] }
        set { self[ModelManageFocusRevealKey.self] = newValue }
    }
}

/// Keep native controls and their normal key loop. Only a visible Manage sheet
/// installs the reader callback; compact cards register no additional focus.
struct ModelManageKeyboardReveal: ViewModifier {
    let target: ModelManageFocusTarget
    @Environment(\.modelManageFocusReveal) private var reveal
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        if let reveal {
            content
                .id(target)
                .focused($isFocused)
                .onChange(of: isFocused) { _, focused in
                    if focused { reveal(target) }
                }
        } else {
            content
        }
    }
}

/// Selectable SwiftUI text consumes Escape before the button shortcut or
/// onExitCommand sees it. Own only the presented model sheet's plain Escape;
/// composition, modified keys, other windows and nested dialogs retain theirs.
struct ModelManageEscapeHandler: NSViewRepresentable {
    let dismiss: @MainActor () -> Void

    func makeNSView(context: Context) -> ModelManageEscapeView {
        ModelManageEscapeView(dismiss: dismiss)
    }
    func updateNSView(_ view: ModelManageEscapeView, context: Context) { view.dismiss = dismiss }
    static func dismantleNSView(_ view: ModelManageEscapeView, coordinator: ()) { view.invalidate() }
}

@MainActor
final class ModelManageEscapeView: NSView {
    var dismiss: @MainActor () -> Void
    private var monitor: Any?

    init(dismiss: @escaping @MainActor () -> Void) {
        self.dismiss = dismiss
        super.init(frame: .zero)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(dismiss:)") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateMonitor()
        guard window != nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let handled = MainActor.assumeIsolated {
                guard let self, let window = self.window,
                      event.window === window, NSApplication.shared.keyWindow === window,
                      window.attachedSheet == nil,
                      event.keyCode == 53,
                      event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
                      (window.firstResponder as? NSTextView)?.hasMarkedText() != true else { return false }
                self.dismiss()
                return true
            }
            return handled ? nil : event
        }
    }

    func invalidate() {
        invalidateMonitor()
        dismiss = {}
    }
    private func invalidateMonitor() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }
}
