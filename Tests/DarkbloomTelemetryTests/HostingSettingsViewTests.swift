import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Hosting settings view", .serialized)
@MainActor
struct HostingSettingsViewTests {
    @Test("bind preset selection follows reachability scope, not the fallback address")
    func bindPresetSelection() {
        let defaults = HostingOptions.default
        #expect(HostingBindPreset.loopback.isSelected(for: defaults))
        #expect(!HostingBindPreset.specificInterface.isSelected(for: defaults))
        #expect(!HostingBindPreset.allInterfaces.isSelected(for: defaults))

        let lan = HostingOptions(mode: .unified, bindAddress: "192.168.1.20")
        #expect(!HostingBindPreset.loopback.isSelected(for: lan))
        #expect(HostingBindPreset.specificInterface.isSelected(for: lan))
        #expect(!HostingBindPreset.allInterfaces.isSelected(for: lan))
    }

    @Test("specific bind preset chooses an active address without inventing one")
    func specificPresetAddress() {
        let loopback = HostingOptions.default
        #expect(HostingBindPreset.specificInterface.address(for: loopback, activeAddresses: []) == nil)
        #expect(HostingBindPreset.specificInterface.address(for: loopback, activeAddresses: ["192.168.1.20"]) == "192.168.1.20")

        let selected = HostingOptions(mode: .unified, bindAddress: "100.90.10.2")
        #expect(HostingBindPreset.specificInterface.address(for: selected, activeAddresses: ["192.168.1.20"]) == "100.90.10.2")
    }

    @Test("empty LAN selection opens the editor without saving a bind, and refresh permits recovery", arguments: [HostingOptions.loopbackBindAddress, HostingOptions.allInterfacesBindAddress])
    func emptyAddressSelectionRecovers(savedAddress: String) throws {
        let suite = "HostingEmptyAddresses-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let scanner = HostingViewAddressScanner()
        let store = HostingSettingsStore(
            controlStore: nil,
            endpointClient: HostingNoEndpoint(),
            tokenFile: HostingViewTokenFileFake(),
            cliVersionProvider: { "0.9.7" },
            defaults: defaults,
            lanScanner: { scanner.addresses() }
        )
        store.setMode(.unified)
        #expect(store.setBindAddress(savedAddress))
        store.refreshEnvironment()
        let savedOptions = store.options
        let savedPreferences = defaults.persistentDomain(forName: suite) as NSDictionary?
        let draft = HostingSettingsDraftState(options: savedOptions)
        draft.portText = "65536"
        draft.customAddressText = "192.168.1."
        var selection = HostingBindSelectionState()
        #expect(!selection.showsAddressEditor(for: store.options))

        selection.choose(.specificInterface, store: store, draft: draft)

        #expect(selection.showsAddressEditor(for: store.options))
        #expect(store.lanAddresses.isEmpty)
        #expect(store.options == savedOptions)
        #expect((defaults.persistentDomain(forName: suite) as NSDictionary?) == savedPreferences)
        #expect(store.pendingExposureConfirmation == nil)
        #expect(draft.customAddressText == "192.168.1.")
        #expect(draft.portText == "65536")
        #expect(draft.hasUnsavedEdits(comparedTo: store.options))

        scanner.setAddresses(["192.168.1.20"])
        store.refreshEnvironment()
        draft.synchronize(to: store.options)

        #expect(selection.showsAddressEditor(for: store.options))
        #expect(store.lanAddresses == ["192.168.1.20"])
        #expect(store.options == savedOptions)
        #expect((defaults.persistentDomain(forName: suite) as NSDictionary?) == savedPreferences)
        #expect(draft.customAddressText == "192.168.1.")
        #expect(draft.portText == "65536")

        selection.choose(.specificInterface, store: store, draft: draft)

        #expect(store.options.bindAddress == "192.168.1.20")
        #expect(store.options.bindScope == .specificInterface)
        #expect(draft.customAddressText == "192.168.1.20")
        #expect(draft.portText == "65536")
        #expect(store.pendingExposureConfirmation == nil)
        #expect(store.errorMessage == nil)
    }

    @Test("leaving the unsaved LAN choice hides the editor and preserves partial input")
    func cancelsEmptyAddressChoice() throws {
        let suite = "HostingCancelEmptyAddresses-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HostingSettingsStore(
            controlStore: nil,
            endpointClient: HostingNoEndpoint(),
            tokenFile: HostingViewTokenFileFake(),
            cliVersionProvider: { "0.9.7" },
            defaults: defaults,
            lanScanner: { [] }
        )
        let savedOptions = store.options
        let draft = HostingSettingsDraftState(options: savedOptions)
        draft.customAddressText = "100.90."
        var selection = HostingBindSelectionState()
        selection.choose(.specificInterface, store: store, draft: draft)
        #expect(selection.showsAddressEditor(for: store.options))

        selection.choose(.loopback, store: store, draft: draft)
        draft.synchronize(to: store.options)

        #expect(!selection.showsAddressEditor(for: store.options))
        #expect(store.options == savedOptions)
        #expect(draft.customAddressText == "100.90.")
        #expect(draft.hasUnsavedEdits(comparedTo: store.options))
        // A saved specific bind still renders its editor when the transient
        // choice is absent, including when its interface is no longer active.
        #expect(store.setBindAddress("100.90.10.2"))
        #expect(selection.showsAddressEditor(for: store.options))
    }

    @Test("hosting settings render at compact and readable window sizes", arguments: ["light", "dark"])
    func renders(appearance: String) async throws {
        let suite = "HostingSettingsView-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = HostingSettingsStore(
            controlStore: nil,
            endpointClient: HostingNoEndpoint(),
            tokenFile: HostingViewTokenFileFake(),
            cliVersionProvider: { "0.9.7" },
            defaults: defaults,
            lanScanner: { ["192.168.1.20"] }
        )
        store.setMode(.unified)
        let content = NSHostingController(rootView: HostingSettingsView(store: store))
        let window = NSWindow(contentViewController: content)
        defer { window.close() }
        window.setContentSize(NSSize(width: 800, height: 620))
        window.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        window.orderBack(nil)
        try await Task.sleep(for: .milliseconds(150))
        content.view.layoutSubtreeIfNeeded()

        #expect(content.view.frame.width == 800)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-hosting-settings-\(appearance).png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}

private struct HostingNoEndpoint: LocalEndpointFetching {
    func fetch() async -> LocalEndpointAvailability {
        .none(LocalEndpointClient.noLiveEndpointReason)
    }
}

private struct HostingViewTokenFileFake: LocalEndpointTokenManaging {
    func withBearerToken(_ action: (String) -> Void) -> Bool { false }
    func saveBearerToken(_ token: String) throws {}
}

private final class HostingViewAddressScanner: @unchecked Sendable {
    private let lock = NSLock()
    private var currentAddresses: [String] = []

    func addresses() -> [String] {
        lock.withLock { currentAddresses }
    }

    func setAddresses(_ addresses: [String]) {
        lock.withLock { currentAddresses = addresses }
    }
}
