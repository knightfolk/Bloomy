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

    private struct BudgetedContent: View {
        @Environment(\.popupContentHeightBudget) private var heightBudget

        var body: some View {
            PopupScrollingViewport(width: 528, maximumHeight: heightBudget) {
                Content(height: 720, label: "Retained document")
            }
        }
    }

    @Test("Native placement caps oversized fitting input at the current budget while preserving natural smaller content")
    func oversizedPlacementInput() {
        let popover = NSPopover()
        let host = FittingPopoverHostingController(
            rootView: Color.clear.frame(width: 560, height: 720), popover: popover)
        popover.contentViewController = host
        for height: CGFloat in [580, 80, 360, 240, 360.9, 1_400] {
            host.prepareForPresentation(maximumContentHeight: height)
            #expect(popover.contentSize == NSSize(width: 560, height: min(720, floor(height))))
            let visibleSize = popover.contentSize
            NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: popover)
            host.preferredContentSize = NSSize(width: 560, height: 999)
            #expect(popover.contentSize == visibleSize)
        }
        host.prepareForPresentation()
        #expect(popover.contentSize == NSSize(width: 560, height: 720))
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: popover)
    }

    @Test("Retained popup height changes constrain stale preferred-size callbacks without replacing its document")
    func retainedHeightTransitions() async throws {
        let popover = NSPopover()
        let host = FittingPopoverHostingController(rootView: BudgetedContent(), popover: popover)
        popover.contentViewController = host
        host.prepareForPresentation(maximumContentHeight: 580)
        let scroll = try #require(findScroll(in: host.view))
        let document = try #require(scroll.documentView)
        defer {
            NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: popover)
            scroll.invalidate()
        }

        for height: CGFloat in [360, 80, 580, 240, 360] {
            NotificationCenter.default.post(name: NSPopover.willCloseNotification, object: popover)
            let closedSize = popover.contentSize
            host.preferredContentSize = NSSize(width: 528, height: 720)
            #expect(popover.contentSize == closedSize)
            host.prepareForPresentation(maximumContentHeight: height)
            #expect(popover.contentSize.height > 0)
            #expect(popover.contentSize.height <= height)

            // A retained SwiftUI document can deliver its previous preferred
            // size after the native screen budget has already changed.
            host.preferredContentSize = NSSize(width: 528, height: 720)
            #expect(popover.contentSize.height <= height)
            try await Task.sleep(for: .milliseconds(40))
            host.view.layoutSubtreeIfNeeded()
            #expect(scroll.documentView === document)
            #expect(scroll.intrinsicContentSize.height == height)
            #expect(popover.contentSize.height <= height)
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

    @Test("Hidden updates cancel pending fits and retain geometry, document and scroll position until reopening")
    func hiddenUpdatesAndReopening() async throws {
        let scroll = PopupScrollView(content: Content(height: 420, label: "Visible"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 80)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 528, height: 80),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = scroll
        window.orderBack(nil)
        defer { scroll.invalidate(); window.close() }
        try await waitForDocument(scroll, height: 420)
        let document = try #require(scroll.documentView)
        document.scroll(NSPoint(x: 0, y: 25))
        let origin = scroll.contentView.bounds.origin

        // Leave a fit queued, then close before its actor turn executes.
        scroll.update(content: Content(height: 600, label: "Queued"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 80)
        var hidden = EnvironmentValues()
        hidden.popupFittingActive = false
        scroll.update(content: Content(height: 700, label: "Hidden"),
            environment: hidden, width: 528, maximumHeight: 80)
        try await Task.sleep(for: .milliseconds(40))
        scroll.measureDocument()
        scroll.layoutSubtreeIfNeeded()
        #expect(scroll.documentView === document)
        #expect(document.frame.size == NSSize(width: 528, height: 420))
        #expect(scroll.intrinsicContentSize == NSSize(width: 528, height: 80))
        #expect(scroll.contentView.bounds.origin == origin)

        // Unchanged width also needs an immediate fit of the latest hidden data.
        scroll.update(content: Content(height: 700, label: "Same-width reopen"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 80)
        #expect(scroll.documentView === document)
        #expect(document.frame.size == NSSize(width: 528, height: 700))
        #expect(scroll.contentView.bounds.origin == origin)
        scroll.update(content: Content(height: 710, label: "Closed again"),
            environment: hidden, width: 528, maximumHeight: 80)

        // A changed screen budget is retained while hidden; it cannot force a fit.
        scroll.update(content: Content(height: 760, label: "Latest hidden"),
            environment: hidden, width: 400, maximumHeight: 360)
        try await Task.sleep(for: .milliseconds(40))
        scroll.measureDocument()
        #expect(document.frame.size == NSSize(width: 528, height: 700))
        #expect(scroll.intrinsicContentSize == NSSize(width: 528, height: 80))

        scroll.update(content: Content(height: 760, label: "Reopened"),
            environment: EnvironmentValues(), width: 400, maximumHeight: 360)
        #expect(scroll.documentView === document)
        #expect(document.frame.size == NSSize(width: 400, height: 760))
        #expect(scroll.intrinsicContentSize == NSSize(width: 400, height: 360))
        #expect(scroll.contentView.bounds.origin == origin)

        scroll.update(content: Content(height: 900, label: "Hidden before invalidation"),
            environment: hidden, width: 400, maximumHeight: 360)
        scroll.invalidate()
        scroll.update(content: Content(height: 1000, label: "Late reopen"),
            environment: EnvironmentValues(), width: 528, maximumHeight: 80)
        scroll.measureDocument()
        #expect(scroll.documentView == nil)
    }

    @Test("Native popup close suspends retained bridges synchronously, including stale environment updates")
    func controllerCloseAndReopening() async throws {
        let popover = NSPopover()
        let host = FittingPopoverHostingController(rootView: PopupScrollingViewport(width: 528, maximumHeight: 80) {
            Content(height: 420, label: "Visible")
        }, popover: popover)
        popover.contentViewController = host
        let initiallyLoaded = host.isViewLoaded
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: popover)
        #expect(host.isViewLoaded == initiallyLoaded)
        #expect(!host.isFittingActive)
        #expect(host.sizingOptions.isEmpty)

        host.prepareForPresentation(maximumContentHeight: 80)
        let scroll = try #require(findScroll(in: host.view))
        let document = try #require(scroll.documentView)
        #expect(document.frame.size == NSSize(width: 528, height: 420))
        let visibleSize = popover.contentSize
        var retainedLiveEnvironment = EnvironmentValues()
        retainedLiveEnvironment.popupFittingActive = true
        retainedLiveEnvironment.popupFittingPresentation = host.rootView.budget
        scroll.update(content: Content(height: 600, label: "Queued before close"),
            environment: retainedLiveEnvironment, width: 528, maximumHeight: 80)

        NotificationCenter.default.post(name: NSPopover.willCloseNotification, object: popover)
        #expect(!host.isFittingActive)
        #expect(host.sizingOptions.isEmpty)
        host.content = PopupScrollingViewport(width: 528, maximumHeight: 80) {
            Content(height: 720, label: "Latest hidden")
        }
        // The native shared state is authoritative before SwiftUI delivers false.
        scroll.update(content: Content(height: 720, label: "Old live environment"),
            environment: retainedLiveEnvironment, width: 528, maximumHeight: 80)
        host.preferredContentSize = NSSize(width: 560, height: 999)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(40))
        scroll.measureDocument()
        #expect(scroll.documentView === document)
        #expect(document.frame.size == NSSize(width: 528, height: 420))
        #expect(popover.contentSize == visibleSize)

        host.prepareForPresentation(maximumContentHeight: 80)
        #expect(host.isFittingActive)
        #expect(host.sizingOptions == .preferredContentSize)
        #expect(scroll.documentView === document)
        #expect(document.frame.size == NSSize(width: 528, height: 720))
        #expect(popover.contentSize == visibleSize)
        NotificationCenter.default.post(name: NSPopover.didCloseNotification, object: popover)
        scroll.invalidate()
    }

    private func findScroll(in view: NSView) -> PopupScrollView<Content>? {
        if let scroll = view as? PopupScrollView<Content> { return scroll }
        for subview in view.subviews {
            if let scroll = findScroll(in: subview) { return scroll }
        }
        return nil
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
