import AppKit
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Application appearance", .serialized)
@MainActor
struct AppAppearanceTests {
    @Test("missing and unknown preferences follow the system")
    func invalidPreferencesUseSystem() throws {
        let suite = "AppAppearanceTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        #expect(ApplicationAppearance.storedMode(in: defaults) == .system)
        defaults.set("future-mode", forKey: ApplicationAppearance.defaultsKey)
        #expect(ApplicationAppearance.storedMode(in: defaults) == .system)
        #expect(AppAppearanceMode.system.appKitAppearanceName == nil)
    }

    @Test("light and dark preferences use native AppKit appearances")
    func explicitAppearances() {
        #expect(AppAppearanceMode(storedValue: "light").appKitAppearanceName == .aqua)
        #expect(AppAppearanceMode(storedValue: "dark").appKitAppearanceName == .darkAqua)
    }

    @Test("system mode removes an application override")
    func systemRemovesOverride() {
        let application = NSApplication.shared
        let original = application.appearance
        defer { application.appearance = original }

        ApplicationAppearance.apply(.dark, to: application)
        #expect(application.appearance?.name == .darkAqua)
        ApplicationAppearance.apply(.system, to: application)
        #expect(application.appearance == nil)
    }
}
