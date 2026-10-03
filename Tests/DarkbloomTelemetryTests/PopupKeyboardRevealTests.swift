import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Popup keyboard reveal")
@MainActor
struct PopupKeyboardRevealTests {
    // There is one native keyboard focus owner. Run this explicitly in an
    // isolated process; parallel AppKit window tests can legitimately take it.
    @Test("editor-owned focus reveals its input through the shared anchor",
          .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_ISOLATED_FOCUS_PROOF"] == "1"))
    func editorOwnedFocus() async throws {
        let probe = EditorFocusRevealProbe()
        let host = NSHostingController(rootView: EditorFocusRevealFixture(probe: probe))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: 300, height: 80))
        window.orderBack(nil)
        host.view.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        let anchor = try #require(anchors(in: host.view).first)
        let scroll = try #require(anchor.enclosingScrollView)
        let document = try #require(scroll.documentView)
        #expect(!scroll.documentVisibleRect.contains(document.convert(anchor.bounds, from: anchor)))

        probe.requestsFocus = true
        // Focus, SwiftUI layout and the native scroll reveal are separate main
        // queue turns. Await their result rather than sampling a fixed delay
        // while the full suite is also mounting native windows.
        for _ in 0..<30 {
            if probe.hasFocus,
               scroll.documentVisibleRect.contains(document.convert(anchor.bounds.insetBy(dx: -6, dy: -6), from: anchor)) { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(probe.hasFocus)
        #expect(scroll.documentVisibleRect.contains(document.convert(anchor.bounds.insetBy(dx: -6, dy: -6), from: anchor)))
    }

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
        let anchor = KeyboardFocusRevealAnchorView(frame: NSRect(x: 40, y: 450, width: 100, height: 20))
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

    @Test("a focused control moving after validation stays visible without a focus change")
    func changedFocusedLayout() async throws {
        let (window, scroll, anchor) = fixture()
        defer { window.close() }
        anchor.setFocused(true)
        try await Task.sleep(for: .milliseconds(30))
        let previousOffset = scroll.documentVisibleRect.minY
        anchor.setFrameOrigin(NSPoint(x: anchor.frame.minX, y: anchor.frame.minY + 50))
        anchor.setFocused(true)
        try await Task.sleep(for: .milliseconds(30))
        #expect(scroll.documentVisibleRect.minY > previousOffset)
        let frame = scroll.documentView!.convert(anchor.bounds.insetBy(dx: -6, dy: -6), from: anchor)
        #expect(scroll.documentVisibleRect.contains(frame))
    }

    private func fixture() -> (NSWindow, NSScrollView, KeyboardFocusRevealAnchorView) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 80),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 80))
        window.contentView = scroll
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 600))
        scroll.documentView = document
        let anchor = KeyboardFocusRevealAnchorView(frame: NSRect(x: 40, y: 450, width: 100, height: 20))
        document.addSubview(anchor)
        scroll.layoutSubtreeIfNeeded()
        return (window, scroll, anchor)
    }

    private func anchors(in view: NSView) -> [KeyboardFocusRevealAnchorView] {
        (view as? KeyboardFocusRevealAnchorView).map { [$0] } ?? view.subviews.flatMap { anchors(in: $0) }
    }
}

@MainActor
private final class EditorFocusRevealProbe: ObservableObject {
    @Published var requestsFocus = false
    var hasFocus = false
}

private struct EditorFocusRevealFixture: View {
    @ObservedObject var probe: EditorFocusRevealProbe
    @FocusState private var inputFocused: Bool
    @State private var text = "Address"

    var body: some View {
        ScrollView {
            VStack {
                Color.clear.frame(height: 500)
                TextField("Address", text: $text)
                    .modifier(ScrollControlKeyboardReveal(documentSpace: "editor.proof", focus: $inputFocused))
                    .padding(12)
                Color.clear.frame(height: 100)
            }
            .coordinateSpace(name: "editor.proof")
        }
        .onChange(of: probe.requestsFocus) { _, value in inputFocused = value }
        .onChange(of: inputFocused) { _, value in probe.hasFocus = value }
    }
}
