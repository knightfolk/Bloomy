import AppKit
import SwiftUI

/// Adds no input handling: native controls own Tab, arrows, typing and Space.
/// Reveal their six-point focus-ring margin through enclosing native clips only
/// when focus enters or its document position changes. Repeated source
/// publications and manual scrolling do not move the control's document frame.
struct ScrollControlKeyboardReveal: ViewModifier {
    var documentSpace: String? = nil
    /// Let an editor own focus restoration while using the same reveal anchor.
    /// One binding owns each control; do not stack competing focused modifiers.
    var focus: FocusState<Bool>.Binding? = nil
    @FocusState private var isFocused: Bool

    private var controlFocus: FocusState<Bool>.Binding { focus ?? $isFocused }

    func body(content: Content) -> some View {
        content.focused(controlFocus)
            .background {
                if let documentSpace {
                    GeometryReader { geometry in
                        KeyboardFocusRevealAnchor(isFocused: controlFocus.wrappedValue,
                            documentFrame: geometry.frame(in: .named(documentSpace)))
                            .accessibilityHidden(true)
                    }
                    .accessibilityHidden(true)
                } else {
                    KeyboardFocusRevealAnchor(isFocused: controlFocus.wrappedValue, documentFrame: nil)
                        .accessibilityHidden(true)
                }
            }
    }
}

private struct KeyboardFocusRevealAnchor: NSViewRepresentable {
    let isFocused: Bool
    let documentFrame: CGRect?
    func makeNSView(context: Context) -> KeyboardFocusRevealAnchorView { KeyboardFocusRevealAnchorView() }
    func updateNSView(_ view: KeyboardFocusRevealAnchorView, context: Context) {
        view.setFocused(isFocused, documentFrame: documentFrame)
    }
    static func dismantleNSView(_ view: KeyboardFocusRevealAnchorView, coordinator: ()) { view.setFocused(false) }
}

@MainActor
final class KeyboardFocusRevealAnchorView: NSView {
    private var isFocused = false
    private var lastFocusedDocument: ObjectIdentifier?
    private var lastFocusedFrame: NSRect?
    private var lastPublishedDocumentFrame: CGRect?
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func setFocused(_ focused: Bool, documentFrame: CGRect? = nil) {
        let moved = documentFrame != nil && documentFrame != lastPublishedDocumentFrame
        lastPublishedDocumentFrame = documentFrame
        if focused == isFocused {
            if focused { requestReveal(onlyIfLayoutChanged: !moved) }
            return
        }
        isFocused = focused
        lastFocusedDocument = nil
        lastFocusedFrame = nil
        if focused { requestReveal() }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil, isFocused { requestReveal() }
    }

    private func requestReveal(onlyIfLayoutChanged: Bool = false) {
        // Layout must have assigned the background anchor's actual control
        // bounds. A lost focus or dismantled view cancels this queued reveal.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isFocused, self.window != nil else { return }
            self.window?.contentView?.layoutSubtreeIfNeeded()
            if onlyIfLayoutChanged, let document = self.enclosingScrollView?.documentView {
                let frame = document.convert(self.bounds, from: self)
                guard self.lastFocusedDocument != ObjectIdentifier(document) || self.lastFocusedFrame != frame else { return }
            }
            self.revealInEnclosingViewports()
            // Compare in the nearest document, not screen coordinates. Manual
            // scrolling changes screen position and must remain under user control.
            if let document = self.enclosingScrollView?.documentView {
                self.lastFocusedDocument = ObjectIdentifier(document)
                self.lastFocusedFrame = document.convert(self.bounds, from: self)
            }
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
