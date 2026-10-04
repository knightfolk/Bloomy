import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Popup document sizing follows native content notifications", .serialized)
@MainActor
struct PopupScrollSizingTests {
    private struct Content: View {
        let height: CGFloat
        let label: String
        var body: some View {
            Text(label).frame(maxWidth: .infinity).frame(height: height)
        }
    }

    @Test("Live height changes grow and shrink the document under a retained viewport", arguments: [80.0, 360.0])
    func contentChanges(maximumHeight: Double) async throws {
        let scroll = PopupScrollView(content: Content(height: 120, label: "Initial"),
            environment: EnvironmentValues(), width: 528, maximumHeight: maximumHeight)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: maximumHeight),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderBack(nil)
        defer { scroll.invalidate(); window.close() }
        let document = try #require(scroll.documentView)
        for height: CGFloat in [220, 460, 96, 380, 120] {
            scroll.update(content: Content(height: height, label: "Height \(height)"),
                environment: EnvironmentValues(), width: 528, maximumHeight: maximumHeight)
            try await waitForDocument(scroll, height: height)
            #expect(scroll.documentView === document)
            #expect(scroll.intrinsicContentSize == NSSize(width: 528, height: min(height, maximumHeight)))
        }
        // Text and evidence updates must preserve the native scroll position.
        document.scroll(NSPoint(x: 0, y: 15))
        let origin = scroll.contentView.bounds.origin
        scroll.update(content: Content(height: 120, label: "Fresh reading"),
            environment: EnvironmentValues(), width: 528, maximumHeight: maximumHeight)
        try await Task.sleep(for: .milliseconds(40))
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.contentView.bounds.origin == origin)
    }

    @Test("Width and viewport-only changes remain immediate, and dismantling releases the document")
    func geometryChanges() async throws {
        let scroll = PopupScrollView(content: Content(height: 240, label: "Reading"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 360)
        scroll.update(content: Content(height: 240, label: "Reading"),
            environment: EnvironmentValues(), width: 400, maximumHeight: 80)
        #expect(scroll.intrinsicContentSize == NSSize(width: 400, height: 80))
        #expect(scroll.documentView?.frame.size == NSSize(width: 400, height: 240))
        scroll.invalidate()
        #expect(scroll.documentView == nil)
    }

    @Test("A burst uses the latest content, immediate layout wins, and pending fits cannot survive dismantling")
    func burstAndCancellation() async throws {
        let scroll = PopupScrollView(content: Content(height: 120, label: "Initial"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 360)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 360),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderBack(nil)
        defer { scroll.invalidate(); window.close() }
        for height in 121...420 {
            scroll.update(content: Content(height: CGFloat(height), label: "Burst \(height)"),
                environment: EnvironmentValues(), width: 528, maximumHeight: 360)
        }
        try await waitForDocument(scroll, height: 420)
        #expect(scroll.intrinsicContentSize.height == 360)
        scroll.update(content: Content(height: 90, label: "Layout request"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 360)
        scroll.measureDocument()
        #expect(scroll.documentView?.frame.height == 90)
        scroll.update(content: Content(height: 240, label: "Cancelled"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 360)
        scroll.invalidate()
        try await Task.sleep(for: .milliseconds(40))
        scroll.update(content: Content(height: 500, label: "Late callback"),
            environment: EnvironmentValues(), width: 400, maximumHeight: 80)
        scroll.measureDocument()
        #expect(scroll.documentView == nil)
        #expect(scroll.intrinsicContentSize == NSSize(width: 528, height: 90))
    }

    private func waitForDocument(_ scroll: PopupScrollView<Content>, height: CGFloat) async throws {
        for _ in 0..<100 {
            scroll.layoutSubtreeIfNeeded()
            if scroll.documentView?.frame.height == height { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Native popup document failed to reach \(height) points")
    }
}
