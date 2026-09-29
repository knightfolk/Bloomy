import AppKit
import SwiftUI
import Testing
import DarkbloomTelemetry
@testable import DarkbloomMonitor

@MainActor
struct InactivityNudgeSettingsViewTests {
    @Test("automatic nudge settings render without contacting the provider")
    func render() async throws {
        let suite = "NudgeRender-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = InactivityNudgeStore(
            keyStore: RenderNudgeKey(), defaults: defaults,
            evidence: { _ in .unavailable }, canAct: { false }, send: { _, _ in nil }
        )
        let host = NSHostingController(rootView: Form {
            InactivityNudgeSettingsView(store: store)
        }.formStyle(.grouped))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        let size = NSSize(width: 700, height: 850)
        window.setContentSize(size)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.frame = NSRect(origin: .zero, size: size)
        host.view.layoutSubtreeIfNeeded()
        #expect(!store.enabled)
        #expect(host.view.bounds.width == 700)
        if ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" {
            let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
            host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/bloomy-nudge-settings.png"))
        }
    }
}

private struct RenderNudgeKey: ConsumerKeyManaging {
    var hasKey: Bool { false }
    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? { nil }
    func store(_ key: String) throws {}
    func remove() {}
}
