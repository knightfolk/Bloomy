import AppKit
import SwiftUI

@MainActor
final class DashboardWindowController: NSWindowController, NSWindowDelegate {
    private let store: MonitorStore
    private let frameAutosaveName: String?
    private let unconstrainedContentMaxSize: NSSize
    private var isTransitioningFullScreen = false
    let navigation: DashboardNavigation
    let settingsDraft = ProviderSettingsDraftState()
    var hasUnsavedSettingsEdits: Bool { settingsDraft.hasChanges }
    init(
        store: MonitorStore,
        controlStore: ProviderControlStore?,
        hostingStore: HostingSettingsStore? = nil,
        chatStore: ChatStore? = nil,
        openChatWindow: (() -> Void)? = nil,
        frameAutosaveName: String? = "DarkbloomDashboard",
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.frameAutosaveName = frameAutosaveName
        navigation = DashboardNavigation(defaults: defaults)
        let content = NSHostingController(rootView: DashboardRootView(
            store: store, controlStore: controlStore, hostingStore: hostingStore,
            chatStore: chatStore, openChatWindow: openChatWindow, navigation: navigation,
            settingsDraft: settingsDraft
        ).defaultAppStorage(defaults))
        let window = NSWindow(contentViewController: content)
        window.title = MonitorApplicationIdentity.displayName
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenPrimary)
        unconstrainedContentMaxSize = window.contentMaxSize
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1280, height: 900))
        window.contentMinSize = NSSize(width: 800, height: 560)
        window.center()
        if let frameAutosaveName { window.setFrameAutosaveName(frameAutosaveName) }
        super.init(window: window)
        window.delegate = self
        constrainToVisibleScreen()
    }

    required init?(coder: NSCoder) { nil }

    func present(section: DashboardDestination? = nil, settingsPage: SettingsPage? = nil, activate: Bool = true) {
        let hasExplicitRoute = section != nil || settingsPage != nil
        if let settingsPage { navigation.settingsPage = settingsPage }
        if let section { navigation.selected = section }
        if hasExplicitRoute { navigation.revealSelectedSection() }
        if activate { showWindow(nil) } else { window?.orderBack(nil) }
        window?.deminiaturize(nil)
        constrainToVisibleScreen()
        store.setDashboardVisible(true)
        if activate {
            NSApplication.shared.activate()
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) { store.setDashboardVisible(false) }
    func windowDidMiniaturize(_ notification: Notification) { store.setDashboardVisible(false) }
    func windowDidDeminiaturize(_ notification: Notification) { store.setDashboardVisible(true) }

    func windowDidChangeScreen(_ notification: Notification) {
        constrainToVisibleScreen()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = true
        window?.contentMaxSize = unconstrainedContentMaxSize
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        finishFullScreenTransition()
    }

    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        finishFullScreenTransition()
    }

    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        finishFullScreenTransition()
    }

    private func finishFullScreenTransition() {
        isTransitioningFullScreen = false
        constrainToVisibleScreen()
    }

    private func constrainToVisibleScreen() {
        guard !isTransitioningFullScreen,
              let window, !window.styleMask.contains(.fullScreen),
              let screen = window.screen ?? NSScreen.main ?? NSScreen.screens.first
        else { return }

        let visibleFrame = screen.visibleFrame
        let maximumContentRect = window.contentRect(
            forFrameRect: NSRect(origin: .zero, size: visibleFrame.size)
        )
        window.contentMaxSize = maximumContentRect.size
        window.contentMinSize = NSSize(
            width: min(800, maximumContentRect.width),
            height: min(560, maximumContentRect.height)
        )

        let fittedFrame = DashboardWindowSizing.fitted(window.frame, within: visibleFrame)
        if fittedFrame != window.frame {
            window.setFrame(fittedFrame, display: true)
        }
        if let frameAutosaveName {
            window.saveFrame(usingName: frameAutosaveName)
        }
    }
}

enum DashboardWindowSizing {
    static func fitted(_ frame: NSRect, within visibleFrame: NSRect) -> NSRect {
        let width = min(frame.width, visibleFrame.width)
        let height = min(frame.height, visibleFrame.height)
        let x = min(max(frame.minX, visibleFrame.minX), visibleFrame.maxX - width)
        let y = min(max(frame.minY, visibleFrame.minY), visibleFrame.maxY - height)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}
