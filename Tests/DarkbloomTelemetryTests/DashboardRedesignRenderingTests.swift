import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Dashboard redesign rendering", .serialized)
@MainActor
struct DashboardRedesignRenderingTests {
    @Test("overview and logs fit narrow and wide layouts", arguments: [570.0, 1100.0])
    func render(width: Double) async throws {
        let now = Date()
        let events = [
            LogEvent(timestamp: now, severity: .info, category: "provider", message: "Model is ready to serve requests.", source: .unified, processID: 42, processImage: "darkbloom"),
            LogEvent(timestamp: now, severity: .warning, category: "network", message: "Network sample could not be refreshed. Last-known measurements are retained.", source: .legacy, processID: 42, processImage: "darkbloom"),
        ]
        let feed = EventFeed(events: events, legacyReadAt: now, unifiedActivityAt: now)
        try await capture(LogsView(feed: .available(value: feed, capturedAt: now)), width: width, name: "logs")
        let store = MonitorStore(service: TelemetryService(source: RedesignUnusedSource()), initial: .unavailable(now: now))
        try await capture(DashboardOverviewView(store: store, controlStore: nil), width: width, name: "overview")
    }

    private func capture(_ view: some View, width: Double, name: String) async throws {
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: 740))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width <= width)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-redesign-\(name)-\(Int(width)).png"))
    }
}

private struct RedesignUnusedSource: TelemetrySource {
    struct Unused: Error {}
    func readDaemonState() async throws -> DaemonState { throw Unused() }
    func readLoadedModels() async throws -> LoadedModelsState { throw Unused() }
    func readStatus() async throws -> StatusSnapshot { throw Unused() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw Unused() }
}
