import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Popup keyboard reveal")
@MainActor
struct PopupKeyboardRevealTests {
    @Test("shared controls register native reveal anchors only in the popup", arguments: [false, true])
    func scopedRegistration(enabled: Bool) async {
        let root = Button("Shared control") {}.modifier(PopupKeyboardReveal())
            .environment(\.popupKeyboardRevealEnabled, enabled)
            .frame(width: 200, height: 50)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: 200, height: 50))
        host.view.layoutSubtreeIfNeeded()
        await Task.yield()
        host.view.layoutSubtreeIfNeeded()
        #expect(anchors(in: host.view).count == (enabled ? 1 : 0))
    }

    @Test("nested viewports reveal the same control with its focus-ring margin")
    func nestedClips() {
        let outer = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        let outerDocument = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        outer.documentView = outerDocument
        let inner = NSScrollView(frame: NSRect(x: 0, y: 300, width: 400, height: 120))
        outerDocument.addSubview(inner)
        let innerDocument = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        inner.documentView = innerDocument
        let anchor = PopupFocusAnchorView(frame: NSRect(x: 40, y: 450, width: 100, height: 20))
        innerDocument.addSubview(anchor)
        outer.layoutSubtreeIfNeeded()
        anchor.revealInEnclosingViewports()
        let expanded = anchor.bounds.insetBy(dx: -6, dy: -6)
        #expect(inner.documentVisibleRect.contains(innerDocument.convert(expanded, from: anchor)))
        #expect(outer.documentVisibleRect.contains(outerDocument.convert(expanded, from: anchor)))
    }

    @Test("unchanged focused publications do not repeatedly scroll")
    func sourceUpdatesKeepPosition() async throws {
        let (window, scroll, anchor) = fixture()
        defer { window.close() }
        anchor.setFocused(true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(scroll.documentVisibleRect.minY > 0)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        anchor.setFocused(true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(scroll.documentVisibleRect.minY == 0)
        anchor.setFocused(false)
        anchor.setFocused(true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(scroll.documentVisibleRect.minY > 0)
    }

    @Test("focus loss cancels a queued reveal")
    func cancelledFocus() async throws {
        let (window, scroll, anchor) = fixture()
        defer { window.close() }
        anchor.setFocused(true)
        anchor.setFocused(false)
        try await Task.sleep(for: .milliseconds(30))
        #expect(scroll.documentVisibleRect.minY == 0)
    }

    private func fixture() -> (NSWindow, NSScrollView, PopupFocusAnchorView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        window.contentView = scroll
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scroll.documentView = document
        let anchor = PopupFocusAnchorView(frame: NSRect(x: 40, y: 450, width: 100, height: 20))
        document.addSubview(anchor)
        scroll.layoutSubtreeIfNeeded()
        return (window, scroll, anchor)
    }

    private func anchors(in view: NSView) -> [PopupFocusAnchorView] {
        (view as? PopupFocusAnchorView).map { [$0] } ?? view.subviews.flatMap { anchors(in: $0) }
    }
}
