import AppKit
import DarkbloomTelemetry
import Testing
@testable import DarkbloomMonitor

/// Exercises the delegates' transition guards without entering a macOS Space.
/// All windows use isolated preferences and disable frame autosaving.
@Suite("Full-screen window transitions", .serialized)
@MainActor
struct FullScreenWindowTests {
    @Test("Dashboard and Chat opt into native full screen", arguments: FullScreenWindowKind.allCases)
    func nativeFullScreenSupport(kind: FullScreenWindowKind) async throws {
        try await withWindow(kind: kind) { fixture in
            #expect(fixture.window.collectionBehavior.contains(.fullScreenPrimary))
            #expect(fixture.window.styleMask.contains(.resizable))
            #expect(fixture.window.frameAutosaveName.isEmpty)
            #expect(!fixture.window.styleMask.contains(.fullScreen))
        }
    }

    @Test("screen changes and presentation preserve the frame during entry and exit",
          arguments: FullScreenWindowKind.allCases, FullScreenTransition.allCases)
    func transitionPreservesFrame(kind: FullScreenWindowKind, transition: FullScreenTransition) async throws {
        try await withWindow(kind: kind) { fixture in
            let window = fixture.window
            // A real full-screen transition starts from a window that is
            // already visible. Complete AppKit's initial ordering first.
            fixture.present()
            try #require(window.isVisible)
            window.contentView?.layoutSubtreeIfNeeded()
            let desktopMaximum = window.contentMaxSize
            fixture.begin(transition)
            if kind == .dashboard, transition == .entering {
                #expect(window.contentMaxSize.width > desktopMaximum.width)
                #expect(window.contentMaxSize.height > desktopMaximum.height)
            }
            let transitionFrame = try moveOutsideVisibleFrame(window)
            fixture.screenChanged()
            #expect(window.frame == transitionFrame)
            fixture.present()
            #expect(window.frame == transitionFrame)

            // The successful exit notification releases the guard and restores
            // normal desktop fitting, including Dashboard's sizing limits.
            if transition == .entering {
                fixture.delegate.windowDidEnterFullScreen?(fixture.notification(NSWindow.didEnterFullScreenNotification))
                fixture.begin(.exiting)
            }
            fixture.delegate.windowDidExitFullScreen?(fixture.notification(NSWindow.didExitFullScreenNotification))
            try expectDesktopSizing(fixture)
            #expect(window.frame != transitionFrame)
        }
    }

    @Test("failed entry and exit restore normal screen fitting",
          arguments: FullScreenWindowKind.allCases, FullScreenTransition.allCases)
    func failedTransitionRestoresDesktop(kind: FullScreenWindowKind, transition: FullScreenTransition) async throws {
        try await withWindow(kind: kind) { fixture in
            // Failed entry and exit also begin from an already visible window.
            fixture.present()
            try #require(fixture.window.isVisible)
            fixture.window.contentView?.layoutSubtreeIfNeeded()
            fixture.begin(transition)
            let transitionFrame = try moveOutsideVisibleFrame(fixture.window)
            fixture.screenChanged()
            #expect(fixture.window.frame == transitionFrame)

            switch transition {
            case .entering:
                fixture.delegate.windowDidFailToEnterFullScreen?(fixture.window)
            case .exiting:
                fixture.delegate.windowDidFailToExitFullScreen?(fixture.window)
            }
            try expectDesktopSizing(fixture)
            #expect(fixture.window.frame != transitionFrame)

            // Recovery must also release the transition guard for later
            // ordinary desktop screen-change callbacks.
            let displacedDesktopFrame = try moveOutsideVisibleFrame(fixture.window)
            fixture.screenChanged()
            try expectDesktopSizing(fixture)
            #expect(fixture.window.frame != displacedDesktopFrame)
        }
    }

    private func moveOutsideVisibleFrame(_ window: NSWindow) throws -> NSRect {
        let screen = try #require(window.screen ?? NSScreen.main ?? NSScreen.screens.first)
        window.setFrameOrigin(NSPoint(
            x: screen.visibleFrame.midX - window.frame.width / 2,
            y: screen.visibleFrame.minY - 100
        ))
        let frame = window.frame
        let activeScreen = try #require(window.screen ?? NSScreen.main ?? NSScreen.screens.first)
        // Ensure the guard assertions exercise a frame the desktop clamp
        // would actually change, even on a machine with multiple screens.
        try #require(!activeScreen.visibleFrame.contains(frame))
        return frame
    }

    private func expectDesktopSizing(_ fixture: FullScreenWindowFixture) throws {
        let window = fixture.window
        let screen = try #require(window.screen ?? NSScreen.main ?? NSScreen.screens.first)
        let visible = screen.visibleFrame
        #expect(window.frame.minX >= visible.minX - 1)
        #expect(window.frame.minY >= visible.minY - 1)
        #expect(window.frame.maxX <= visible.maxX + 1)
        #expect(window.frame.maxY <= visible.maxY + 1)
        if fixture.kind == .dashboard {
            let maximum = window.contentRect(forFrameRect: NSRect(origin: .zero, size: visible.size)).size
            #expect(window.contentMaxSize == maximum)
            #expect(window.contentMinSize == NSSize(width: min(800, maximum.width), height: min(560, maximum.height)))
        } else {
            #expect(window.contentMinSize == NSSize(width: 460, height: 520))
        }
    }

    private func withWindow(
        kind: FullScreenWindowKind,
        _ body: (FullScreenWindowFixture) throws -> Void
    ) async throws {
        let suite = "FullScreenWindowTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let monitor = MonitorStore(
            service: TelemetryService(source: FullScreenUnusedSource()),
            initial: .unavailable(now: Date()),
            earningsClient: FullScreenUnusedEarnings(),
            energyPreferences: defaults,
            energyRecorder: EnergyRecorder(
                file: FileManager.default.temporaryDirectory.appendingPathComponent(suite + "-energy.json"),
                readPower: { _ in nil }
            ),
            menuAttentionPreferences: defaults
        )
        let controller: NSWindowController
        let delegate: any NSWindowDelegate
        let present: () -> Void
        switch kind {
        case .dashboard:
            let dashboard = DashboardWindowController(
                store: monitor, controlStore: nil, frameAutosaveName: nil, defaults: defaults
            )
            controller = dashboard
            delegate = dashboard
            present = { dashboard.present(activate: false) }
        case .chat:
            let chat = ChatStore(
                localClient: FakeChatRouteClient(), networkClient: FakeChatRouteClient(),
                balanceClient: FakeBalanceClient(), pricingClient: FakePricingClient(),
                keyStore: FakeConsumerKeyStore()
            )
            await chat.refreshKeyStatus()
            let chatWindow = ChatWindowController(store: chat, frameAutosaveName: nil, defaults: defaults)
            controller = chatWindow
            delegate = chatWindow
            present = { chatWindow.present(activate: false) }
        }
        defer { controller.close() }
        do {
            let window = try #require(controller.window)
            try body(FullScreenWindowFixture(kind: kind, window: window, delegate: delegate, present: present))
            await monitor.stop()
        } catch {
            await monitor.stop()
            throw error
        }
    }
}

enum FullScreenWindowKind: CaseIterable, Sendable {
    case dashboard, chat
}

enum FullScreenTransition: CaseIterable, Sendable {
    case entering, exiting
}

@MainActor
private struct FullScreenWindowFixture {
    let kind: FullScreenWindowKind
    let window: NSWindow
    let delegate: any NSWindowDelegate
    let present: () -> Void

    func notification(_ name: Notification.Name) -> Notification {
        Notification(name: name, object: window)
    }

    func begin(_ transition: FullScreenTransition) {
        switch transition {
        case .entering:
            delegate.windowWillEnterFullScreen?(notification(NSWindow.willEnterFullScreenNotification))
        case .exiting:
            delegate.windowWillExitFullScreen?(notification(NSWindow.willExitFullScreenNotification))
        }
    }

    func screenChanged() {
        delegate.windowDidChangeScreen?(notification(NSWindow.didChangeScreenNotification))
    }
}

private struct FullScreenUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw FullScreenUnexpectedAcquisition() }
    func readLoadedModels() async throws -> LoadedModelsState { throw FullScreenUnexpectedAcquisition() }
    func readStatus() async throws -> StatusSnapshot { throw FullScreenUnexpectedAcquisition() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw FullScreenUnexpectedAcquisition() }
}

private struct FullScreenUnexpectedAcquisition: Error {}

private struct FullScreenUnusedEarnings: AccountEarningsFetching {
    func fetch(now: Date) async throws -> EarningsPresentationValue {
        throw FullScreenUnexpectedAcquisition()
    }
}
