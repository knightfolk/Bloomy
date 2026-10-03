import AppKit
import Testing
@testable import DarkbloomMonitor

@Suite("Native dashboard visibility", .serialized)
@MainActor
struct DashboardVisibilityObserverTests {
    @Test("an unordered native window starts hidden and repeated refreshes are deduplicated")
    func initialNativeState() {
        let window = makeWindow()
        var publications: [Bool] = []
        let observer = DashboardVisibilityObserver(window: window) { publications.append($0) }
        #expect(publications == [false])
        observer.refreshVisibility()
        observer.refreshVisibility()
        #expect(publications == [false])
    }

    @Test("each native visibility condition is required", arguments: [0, 1, 2, 3])
    func visibilityConditions(condition: Int) {
        let window = makeWindow()
        let probe = VisibilityProbe()
        let observer = probe.observer(window: window)
        switch condition {
        case 0: probe.state.isVisible = false
        case 1: probe.state.isMiniaturized = true
        case 2: probe.state.isApplicationHidden = true
        default: probe.state.occlusionState = []
        }
        observer.refreshVisibility()
        #expect(probe.publications == [true, false])
        probe.state = .visible
        observer.refreshVisibility()
        #expect(probe.publications == [true, false, true])
    }

    @Test("Hide stops visibility and Unhide waits for native exposure before restoring it")
    func hideAndRestore() {
        let window = makeWindow()
        let center = NotificationCenter()
        let probe = VisibilityProbe()
        let observer = probe.observer(window: window, center: center)
        probe.state.isApplicationHidden = true
        center.post(name: NSApplication.didHideNotification, object: NSApplication.shared)
        center.post(name: NSApplication.didHideNotification, object: NSApplication.shared)
        #expect(probe.publications == [true, false])
        probe.state.isApplicationHidden = false
        probe.state.occlusionState = []
        center.post(name: NSApplication.didUnhideNotification, object: NSApplication.shared)
        #expect(probe.publications == [true, false])
        probe.state.occlusionState = .visible
        center.post(name: NSWindow.didExposeNotification, object: window)
        #expect(probe.publications == [true, false, true])
        withExtendedLifetime(observer) {}
    }

    @Test("minimize, restore and occlusion notifications reread native state without duplicate publications")
    func windowNotifications() {
        let window = makeWindow()
        let center = NotificationCenter()
        let probe = VisibilityProbe()
        let observer = probe.observer(window: window, center: center)
        probe.state.isMiniaturized = true
        center.post(name: NSWindow.didMiniaturizeNotification, object: window)
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        probe.state.isMiniaturized = false
        probe.state.occlusionState = []
        center.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        #expect(probe.publications == [true, false])
        probe.state.occlusionState = .visible
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        center.post(name: NSWindow.didExposeNotification, object: window)
        #expect(probe.publications == [true, false, true])
        #expect(probe.reads == 6)
        withExtendedLifetime(observer) {}
    }

    @Test("willClose latches hidden while the native window still reports visible, until explicit presentation")
    func closeAndReopen() {
        let window = makeWindow()
        let center = NotificationCenter()
        let probe = VisibilityProbe()
        let observer = probe.observer(window: window, center: center)
        center.post(name: NSWindow.willCloseNotification, object: window)
        center.post(name: NSWindow.didChangeOcclusionStateNotification, object: window)
        center.post(name: NSWindow.didExposeNotification, object: window)
        center.post(name: NSWindow.didDeminiaturizeNotification, object: window)
        center.post(name: NSApplication.didUnhideNotification, object: NSApplication.shared)
        observer.refreshVisibility()
        #expect(probe.publications == [true, false])
        #expect(probe.reads == 1)
        observer.resetForPresentation()
        #expect(probe.publications == [true, false])
        probe.state.occlusionState = []
        observer.refreshVisibility()
        #expect(probe.publications == [true, false])
        probe.state.occlusionState = .visible
        observer.refreshVisibility()
        #expect(probe.publications == [true, false, true])
    }

    @Test("notifications from another window do not refresh or close the dashboard")
    func unrelatedWindow() {
        let window = makeWindow()
        let otherWindow = makeWindow()
        let center = NotificationCenter()
        let probe = VisibilityProbe()
        let observer = probe.observer(window: window, center: center)
        probe.state.isVisible = false
        for name in [NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                     NSWindow.didChangeOcclusionStateNotification, NSWindow.didExposeNotification,
                     NSWindow.willCloseNotification] {
            center.post(name: name, object: otherWindow)
        }
        #expect(probe.reads == 1)
        #expect(probe.publications == [true])
        probe.state.isVisible = true
        observer.refreshVisibility()
        #expect(probe.publications == [true])
    }

    @Test("notification registrations do not retain the observer and are removed at release")
    func observerLifetime() {
        let window = makeWindow()
        let center = NotificationCenter()
        let probe = VisibilityProbe()
        var observer: DashboardVisibilityObserver? = probe.observer(window: window, center: center)
        weak let releasedObserver = observer
        #expect(releasedObserver != nil)
        observer = nil
        #expect(releasedObserver == nil)
        probe.state.isApplicationHidden = true
        center.post(name: NSApplication.didHideNotification, object: NSApplication.shared)
        center.post(name: NSWindow.willCloseNotification, object: window)
        #expect(probe.reads == 1)
        #expect(probe.publications == [true])
    }

    @Test("the observer holds its native window weakly and becomes hidden when it is released")
    func windowLifetime() {
        let probe = VisibilityProbe()
        var observer: DashboardVisibilityObserver?
        weak var releasedWindow: NSWindow?
        // AppKit autoreleases a newly created NSWindow. Drain that ownership
        // before checking whether the observer or its registrations retain it.
        autoreleasepool {
            let window = makeWindow()
            releasedWindow = window
            observer = probe.observer(window: window)
        }
        #expect(releasedWindow == nil)
        observer?.refreshVisibility()
        #expect(probe.publications == [true, false])
        #expect(probe.reads == 1)
    }

    private func makeWindow() -> NSWindow {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        return window
    }
}

@MainActor
private final class VisibilityProbe {
    var state = DashboardVisibilityObserver.State.visible
    var publications: [Bool] = []
    var reads = 0

    func observer(window: NSWindow, center: NotificationCenter = NotificationCenter()) -> DashboardVisibilityObserver {
        DashboardVisibilityObserver(window: window, notificationCenter: center, readState: { _ in
            self.reads += 1
            return self.state
        }) { self.publications.append($0) }
    }
}

private extension DashboardVisibilityObserver.State {
    static var visible: Self {
        Self(isVisible: true, isMiniaturized: false, isApplicationHidden: false, occlusionState: .visible)
    }
}
