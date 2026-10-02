import AppKit
import DarkbloomTelemetry
import Testing
@testable import DarkbloomMonitor

@Suite("Native application menus", .serialized)
@MainActor
struct SettingsNavigationTests {
    @Test("application menu routes Settings, Dashboard and Chat to the shared delegate")
    func applicationRoutesAndShortcuts() throws {
        let delegate = DarkbloomMonitorAppDelegate()
        let menu = delegate.makeMainMenu()
        let appMenu = try #require(menu.items.first?.submenu)
        for (title, selector, key, modifiers) in [
            ("Settings…", #selector(DarkbloomMonitorAppDelegate.showSettings), ",", NSEvent.ModifierFlags.command),
            ("Open Dashboard", #selector(DarkbloomMonitorAppDelegate.showDashboard), "d", [.command, .shift]),
            ("Open Chat Window", #selector(DarkbloomMonitorAppDelegate.showChat), "c", [.command, .shift]),
        ] {
            let item = try #require(appMenu.items.first { $0.title == title })
            #expect(item.target === delegate)
            #expect(item.action == selector)
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == modifiers)
        }
        let updates = try #require(appMenu.items.first { $0.title == "Check for Updates…" })
        #expect(updates.target === delegate)
        #expect(updates.action == #selector(DarkbloomMonitorAppDelegate.checkForAppUpdates))
        #expect(delegate.validateMenuItem(updates) == ControlAppUpdater.shared.canCheck)
    }

    @Test("editing and window shortcuts use the native responder chain")
    func responderCommands() throws {
        let menu = DarkbloomMonitorAppDelegate().makeMainMenu()
        let edit = try #require(menu.items.first { $0.title == "Edit" }?.submenu)
        for (title, selector, key) in [
            ("Undo", NSSelectorFromString("undo:"), "z"),
            ("Redo", NSSelectorFromString("redo:"), "z"),
            ("Cut", #selector(NSText.cut(_:)), "x"),
            ("Copy", #selector(NSText.copy(_:)), "c"),
            ("Paste", #selector(NSText.paste(_:)), "v"),
            ("Select All", #selector(NSText.selectAll(_:)), "a"),
        ] {
            let item = try #require(edit.items.first { $0.title == title })
            #expect(item.target == nil)
            #expect(item.action == selector)
            #expect(item.keyEquivalent == key)
            #expect(item.keyEquivalentModifierMask == (title == "Redo" ? [.command, .shift] : .command))
        }
        let window = try #require(menu.items.first { $0.title == "Window" }?.submenu)
        for (title, selector, key) in [
            ("Close", #selector(NSWindow.performClose(_:)), "w"),
            ("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"),
            ("Zoom", #selector(NSWindow.performZoom(_:)), ""),
        ] {
            let item = try #require(window.items.first { $0.title == title })
            #expect(item.target == nil)
            #expect(item.action == selector)
            #expect(item.keyEquivalent == key)
        }
    }

    @Test("native Edit selectors perform Undo, Redo and Select All in a native editor")
    func nativeTextEditing() throws {
        let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
        editor.allowsUndo = true
        let window = NSWindow(contentRect: editor.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = editor
        defer { window.close() }
        #expect(window.makeFirstResponder(editor))
        let responder = try #require(window.firstResponder)
        let undoManager = try #require(editor.undoManager)
        undoManager.beginUndoGrouping()
        editor.insertText("Bloomy", replacementRange: NSRange(location: NSNotFound, length: 0))
        undoManager.endUndoGrouping()
        #expect(editor.string == "Bloomy")
        let menu = DarkbloomMonitorAppDelegate().makeMainMenu()
        let edit = try #require(menu.items.first { $0.title == "Edit" }?.submenu)
        let undo = try #require(edit.items.first { $0.title == "Undo" })
        // SwiftPM's test helper does not supply a key window for nil-target dispatch.
        // Start at its real first responder; menu-target nil is checked above.
        #expect(responder.tryToPerform(try #require(undo.action), with: undo))
        #expect(editor.string.isEmpty)
        let redo = try #require(edit.items.first { $0.title == "Redo" })
        #expect(responder.tryToPerform(try #require(redo.action), with: redo))
        #expect(editor.string == "Bloomy")
        let selectAll = try #require(edit.items.first { $0.title == "Select All" })
        #expect(responder.tryToPerform(try #require(selectAll.action), with: selectAll))
        #expect(editor.selectedRange() == NSRange(location: 0, length: 6))
    }

    @Test("native Services and Window menus are registered with the application")
    func registersApplicationMenus() throws {
        let application = NSApplication.shared
        let original = (application.mainMenu, application.servicesMenu, application.windowsMenu)
        defer {
            application.mainMenu = original.0
            application.servicesMenu = original.1
            application.windowsMenu = original.2
        }
        let delegate = DarkbloomMonitorAppDelegate()
        delegate.installApplicationMenus()
        let main = try #require(application.mainMenu)
        #expect(main.items.map(\.title) == [MonitorApplicationIdentity.displayName, "Edit", "Window"])
        #expect(application.servicesMenu === main.items.first?.submenu?.items.first { $0.title == "Services" }?.submenu)
        #expect(application.windowsMenu === main.items.first { $0.title == "Window" }?.submenu)
    }

    @Test("the menu Settings action reuses the existing dashboard and selected Settings page")
    func settingsMenuReusesDashboard() throws {
        let suite = "MenuSettingsRouting-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(SettingsPage.electricity.rawValue, forKey: "dashboard.settingsPage")
        let monitor = MonitorStore(service: TelemetryService(source: NavigationUnusedSource()), initial: .unavailable(now: Date()))
        let status = StatusItemController(store: monitor, defaults: defaults)
        defer { status.invalidate() }
        status.showDashboard(section: .models, activate: false)
        let dashboard = try #require(status.dashboardWindowController)
        let window = try #require(dashboard.window)
        let frame = window.frame
        let delegate = DarkbloomMonitorAppDelegate(instanceGuard: SingleInstanceGuard(), statusItemController: status)
        let item = try #require(delegate.makeMainMenu().items.first?.submenu?.items.first { $0.title == "Settings…" })
        #expect(NSApplication.shared.sendAction(try #require(item.action), to: item.target, from: item))
        #expect(status.dashboardWindowController === dashboard)
        #expect(dashboard.window === window)
        #expect(dashboard.navigation.selected == .settings)
        #expect(dashboard.navigation.settingsPage == .electricity)
        #expect(window.frame == frame)
        dashboard.close()
        #expect(!window.isVisible)
        #expect(!delegate.applicationShouldHandleReopen(.shared, hasVisibleWindows: false))
        #expect(status.dashboardWindowController === dashboard)
        #expect(dashboard.window === window)
        #expect(window.isVisible)
        #expect(dashboard.navigation.selected == .settings)
        #expect(dashboard.navigation.settingsPage == .electricity)
    }
}

private struct NavigationUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw NavigationUnexpectedAcquisition() }
    func readLoadedModels() async throws -> LoadedModelsState { throw NavigationUnexpectedAcquisition() }
    func readStatus() async throws -> StatusSnapshot { throw NavigationUnexpectedAcquisition() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw NavigationUnexpectedAcquisition() }
}

private struct NavigationUnexpectedAcquisition: Error {}
