import AppKit
import SwiftUI

@MainActor
private final class ChatWindowVisibility: ObservableObject {
    @Published var isVisible = false
}

private struct VisibleWindowChat: View {
    let store: ChatStore
    let draft: ChatDraftState
    let updateProtection: AppUpdateEditorProtection?
    @ObservedObject var visibility: ChatWindowVisibility
    var body: some View {
        ChatView(store: store, draft: draft, isVisible: visibility.isVisible, updateProtection: updateProtection)
    }
}

/// Retained, resizable pop-out chat window. It hosts the same `ChatStore` as
/// the dashboard's Chat tab, so both windows show the identical in-memory
/// conversation and either can send on it.
@MainActor
final class ChatWindowController: NSWindowController, NSWindowDelegate {
    private let store: ChatStore
    let chatDraft: ChatDraftState
    private let frameAutosaveName: String?
    private var isTransitioningFullScreen = false
    private let visibility = ChatWindowVisibility()

    init(
        store: ChatStore,
        frameAutosaveName: String? = "DarkbloomChatPopOut",
        defaults: UserDefaults = .standard,
        updateProtection: AppUpdateEditorProtection? = nil
    ) {
        self.store = store
        let draft = ChatDraftState()
        self.chatDraft = draft
        self.frameAutosaveName = frameAutosaveName
        let content = NSHostingController(rootView: VisibleWindowChat(
            store: store, draft: draft, updateProtection: updateProtection, visibility: visibility
        ))
        let window = NSWindow(contentViewController: content)
        window.title = "\(MonitorApplicationIdentity.displayName) — Chat"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 560, height: 680))
        window.contentMinSize = NSSize(width: 460, height: 520)
        window.center()
        if let frameAutosaveName {
            window.setFrameAutosaveName(frameAutosaveName)
        }
        super.init(window: window)
        window.delegate = self
        constrainToVisibleScreen()
    }

    required init?(coder: NSCoder) { nil }

    var hasUnsavedChatEdits: Bool {
        chatDraft.hasUnsentText(in: store.conversation?.id)
    }

    func present(activate: Bool = true) {
        if window?.isMiniaturized == true { window?.deminiaturize(nil) }
        visibility.isVisible = true
        if activate {
            showWindow(nil)
            NSApplication.shared.activate()
            window?.makeKeyAndOrderFront(nil)
        } else {
            window?.orderBack(nil)
        }
        constrainToVisibleScreen()
    }

    func windowWillClose(_ notification: Notification) { visibility.isVisible = false }
    func windowDidMiniaturize(_ notification: Notification) { visibility.isVisible = false }
    func windowDidDeminiaturize(_ notification: Notification) { visibility.isVisible = true }

    func windowDidChangeScreen(_ notification: Notification) {
        constrainToVisibleScreen()
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isTransitioningFullScreen = true
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
        let fitted = DashboardWindowSizing.fitted(window.frame, within: visibleFrame)
        if fitted != window.frame {
            window.setFrame(fitted, display: true)
        }
        if let frameAutosaveName {
            window.saveFrame(usingName: frameAutosaveName)
        }
    }
}
