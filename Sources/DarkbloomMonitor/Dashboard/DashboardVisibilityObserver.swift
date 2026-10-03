import AppKit

/// Owns display visibility only; background monitoring and actions keep their
/// separate lifetimes. Native notifications supply changes without a timer.
@MainActor
final class DashboardVisibilityObserver: NSObject {
    struct State {
        var isVisible: Bool
        var isMiniaturized: Bool
        var isApplicationHidden: Bool
        var occlusionState: NSWindow.OcclusionState

        var isDisplayVisible: Bool {
            isVisible && !isMiniaturized && !isApplicationHidden && occlusionState.contains(.visible)
        }
    }

    private weak var window: NSWindow?
    private let notificationCenter: NotificationCenter
    private let readState: @MainActor (NSWindow) -> State
    private let onVisibilityChange: @MainActor (Bool) -> Void
    private var isClosed = false
    private var lastPublishedVisibility: Bool?

    init(
        window: NSWindow,
        application: NSApplication = .shared,
        notificationCenter: NotificationCenter = .default,
        readState: (@MainActor (NSWindow) -> State)? = nil,
        onVisibilityChange: @escaping @MainActor (Bool) -> Void
    ) {
        self.window = window
        self.notificationCenter = notificationCenter
        self.readState = readState ?? { [weak application] window in
            State(isVisible: window.isVisible, isMiniaturized: window.isMiniaturized,
                  isApplicationHidden: application?.isHidden ?? true, occlusionState: window.occlusionState)
        }
        self.onVisibilityChange = onVisibilityChange
        super.init()
        for name in [NSWindow.didChangeOcclusionStateNotification, NSWindow.didExposeNotification,
                     NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification] {
            notificationCenter.addObserver(self, selector: #selector(visibilityChanged), name: name, object: window)
        }
        notificationCenter.addObserver(self, selector: #selector(windowWillClose),
                                       name: NSWindow.willCloseNotification, object: window)
        for name in [NSApplication.didHideNotification, NSApplication.didUnhideNotification] {
            notificationCenter.addObserver(self, selector: #selector(visibilityChanged), name: name, object: application)
        }
        refreshVisibility()
    }

    deinit { notificationCenter.removeObserver(self) }

    /// Call before explicitly presenting a retained window. Do not publish yet:
    /// its native ordering and activation must determine whether it is exposed.
    func resetForPresentation() { isClosed = false }

    /// Call after native ordering as well as in response to visibility changes.
    func refreshVisibility() {
        guard !isClosed, let window else {
            publish(false)
            return
        }
        publish(readState(window).isDisplayVisible)
    }

    @objc private func visibilityChanged(_ notification: Notification) { refreshVisibility() }

    @objc private func windowWillClose(_ notification: Notification) {
        // willClose precedes the native visibility update. Later expose/occlusion
        // notifications must not restart display work on this retained window.
        isClosed = true
        publish(false)
    }

    private func publish(_ visible: Bool) {
        guard lastPublishedVisibility != visible else { return }
        lastPublishedVisibility = visible
        onVisibilityChange(visible)
    }
}
