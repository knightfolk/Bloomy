import DarkbloomTelemetry
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Popup hosting connection truth")
@MainActor
struct PopupHostingPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("saved unified settings are unverified even after empty discovery")
    func unifiedIsNotLive() {
        let view = PopupHostingPresentation.make(
            options: HostingOptions(mode: .unified, port: 8123, bindAddress: "0.0.0.0"),
            discovery: .none("not rendered"), checkedAt: now, now: now)
        #expect(view.status == "Local API configured · unverified")
        #expect(view.address == "http://127.0.0.1:8123/v1")
        #expect(view.selection == "Selected: Fleet + local")
    }

    @Test("runtime discovery takes precedence over a different saved mode")
    func runtimeMismatch() {
        let record = LocalEndpointRecord(baseURL: "http://127.0.0.1:8123/v1", apiKey: "secret-do-not-render",
                                         host: "127.0.0.1", port: 8123, processID: 123)
        let view = PopupHostingPresentation.make(options: .default, discovery: .live(record), checkedAt: now, now: now)
        #expect(view.selection == "Selected: Fleet only")
        #expect(view.status == "Local-only listener reported")
        #expect(view.address == record.baseURL)
        #expect(view.detail.contains("API key required"))
        #expect(!String(describing: view).contains("secret-do-not-render"))
    }

    @Test("expired, future and undated discovery cannot claim a current listener")
    func expiredDiscovery() {
        let record = LocalEndpointRecord(baseURL: "http://127.0.0.1:8123/v1", apiKey: "",
                                         host: "127.0.0.1", port: 8123, processID: 123)
        for checkedAt in [now.addingTimeInterval(-31), now.addingTimeInterval(1)] {
            let view = PopupHostingPresentation.make(options: .default, discovery: .live(record), checkedAt: checkedAt, now: now)
            #expect(view.status == "Local-only report expired")
        }
        let unknown = PopupHostingPresentation.make(options: .default, discovery: .live(record), checkedAt: nil, now: now)
        #expect(unknown.status == "Local API status unknown")
        #expect(unknown.address == nil)
    }

    @Test("empty discovery is qualified and expires")
    func noListener() {
        let fresh = PopupHostingPresentation.make(options: .default, discovery: .none("private CLI prose"), checkedAt: now, now: now)
        #expect(fresh.status == "No local-only listener discovered")
        #expect(!fresh.detail.contains("private CLI prose"))
        let stale = PopupHostingPresentation.make(options: .default, discovery: .none("ignored"), checkedAt: now.addingTimeInterval(-31), now: now)
        #expect(stale.status == "Local API status unknown")
    }

    @Test("addresses never expose credentials or arbitrary payloads")
    func unsafeAddresses() {
        for address in ["http://user:secret@localhost:8123/v1", "http://localhost:8123/v1?api_key=secret",
                        "http://localhost:8123/v1#secret", "file:///secret", "http://localhost:8123/secret"] {
            let record = LocalEndpointRecord(baseURL: address, apiKey: "", host: "localhost", port: 8123, processID: 123)
            #expect(PopupHostingPresentation.make(options: .default, discovery: .live(record), checkedAt: now, now: now).address == nil)
        }
        #expect(PopupHostingPresentation.coordinatorHost("https://coordinator.example:443/path?token=secret") == "coordinator.example:443")
        #expect(PopupHostingPresentation.coordinatorHost("https://user:secret@coordinator.example") == nil)
    }

    @Test("hosting summary fits the popup in both appearances", arguments: [false, true])
    func popupFit(dark: Bool) async {
        let suite = "PopupHostingFit.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HostingSettingsStore(controlStore: nil, endpointClient: PopupHostingTestEndpoint(),
            tokenFile: LocalEndpointTokenFile(fileURL: URL(fileURLWithPath: "/tmp/bloomy-unused-test-token")),
            cliVersionProvider: { nil }, defaults: defaults, lanScanner: { [] }, now: { now })
        await store.fetchEndpointDetails()
        let view = PopupHostingSummary(store: store, isVisible: false, now: now,
            coordinator: "https://coordinator.example", openHosting: {})
            .frame(width: 526).environment(\.colorScheme, dark ? .dark : .light)
        let host = NSHostingController(rootView: view)
        let fitted = host.sizeThatFits(in: NSSize(width: 526, height: 0))
        #expect(fitted.width == 526)
        #expect(fitted.height > 60 && fitted.height < 140)
    }
}

private struct PopupHostingTestEndpoint: LocalEndpointFetching {
    func fetch() async -> LocalEndpointAvailability {
        .live(LocalEndpointRecord(baseURL: "http://127.0.0.1:8123/v1", apiKey: "",
                                  host: "127.0.0.1", port: 8123, processID: 123))
    }
}
