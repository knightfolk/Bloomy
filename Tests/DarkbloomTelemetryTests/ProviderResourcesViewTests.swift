import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Provider resource panel", .serialized)
@MainActor
struct ProviderResourcesViewTests {
    @Test("resource panel renders system CPU/GPU use, request activity, provider GPU memory, and temperature")
    func rendersMeasuredAndProviderReportedResources() async throws {
        let now = Date()
        let fixtureURL = try #require(
            Bundle.module.url(forResource: "daemon-state-online", withExtension: "json", subdirectory: "Fixtures")
        )
        var daemonJSON = try #require(
            JSONSerialization.jsonObject(with: Data(contentsOf: fixtureURL)) as? [String: Any]
        )
        daemonJSON["inference_active"] = true
        daemonJSON["lifecycle"] = [
            "outcome": "draining",
            "remaining": 6,
            "coordinator_acknowledged": false,
        ]
        let daemon = try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: daemonJSON))
        let snapshot = TelemetrySnapshot(
            state: .available(value: daemon, capturedAt: now),
            loadedModels: .unavailable(reason: "Not acquired"),
            status: .unavailable(reason: "Not acquired"),
            eventFeed: .unavailable(reason: "Not acquired"),
            tokenRate: .unavailable(reason: "No interval"),
            diagnostics: [],
            capturedAt: now,
            menuStatus: .online
        )
        let fanStatus = ProviderFanStatus(
            capability: "fixture",
            installed: true,
            loaded: true,
            helper: nil,
            diagnostic: ProviderFanDiagnostic(
                chip: "Apple silicon fixture",
                supported: true,
                gpuTemperatures: [ProviderFanTemperature(key: "GPU Die", celsius: 62.0)],
                fans: []
            ),
            helperErrorPresent: false,
            diagnosticErrorPresent: false
        )
        let extras = ProviderExtrasStore(client: ResourcePanelFixtureClient(
            snapshot: ProviderExtrasSnapshot(
                capturedAt: now,
                idlePolicy: .unavailable(reason: "Not needed"),
                betaFeatures: .unavailable(reason: "Not needed"),
                fanStatus: .available(value: fanStatus, capturedAt: now)
            )
        ))
        await extras.refresh()

        let store = MonitorStore(
            service: TelemetryService(source: ResourcePanelUnusedSource()),
            initial: snapshot,
            providerExtras: extras
        )
        store.setDashboardVisible(true)
        let overviewContent = ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ProviderResourcesView(store: store)
                Spacer(minLength: 0)
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingController(rootView: overviewContent)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 370))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(3_200))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width == 570)
        #expect(host.view.frame.height >= 340)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-provider-resources.png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }

    @Test("a retained resource panel stops CPU sampling while hidden and restarts with a new interval")
    func samplingFollowsWindowVisibility() async throws {
        var readCount = 0
        let cpu = SystemCPUUsageStore(interval: .milliseconds(25), read: {
            readCount += 1
            return SystemCPUTimes(user: UInt64(readCount * 10), system: 0, nice: 0,
                                  idle: UInt64(readCount * 10))
        })
        let store = MonitorStore(service: TelemetryService(source: ResourcePanelUnusedSource()),
                                 initial: .unavailable(now: Date()), gpuUsage: SystemGPUUsageStore(read: { nil }))
        var appeared = false
        var disappeared = false
        let host = NSHostingController(rootView: AnyView(
            ProviderResourcesView(store: store, cpuUsage: cpu)
                .onAppear { appeared = true }
                .onDisappear { disappeared = true }
        ))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 370))
        window.orderBack(nil)
        defer { store.setDashboardVisible(false); cpu.stop(); window.close() }

        let state: @MainActor () -> String = {
            "reads=\(readCount), percentage=\(cpu.percentage.map(String.init(describing:)) ?? "nil"), sampled=\(cpu.sampledAt != nil), dashboardVisible=\(store.dashboardVisible), windowVisible=\(window.isVisible), windowUnoccluded=\(window.occlusionState.contains(.visible)), appeared=\(appeared), disappeared=\(disappeared), hostAttached=\(host.view.window === window), viewSize=\(host.view.frame.size)"
        }

        // Background windows can be fully occluded by other parallel suites.
        // A window alone does not prove its SwiftUI graph has appeared.
        try await waitUntil("initial panel appearance", window: window, state: state) { appeared }
        #expect(readCount == 0)
        store.setDashboardVisible(true)
        try await waitUntil("first visible sampling", window: window, state: state) { cpu.percentage != nil && readCount >= 2 }

        store.setDashboardVisible(false)
        try await waitUntil("hidden clears sampling", window: window, state: state) { cpu.percentage == nil && cpu.sampledAt == nil }
        let hiddenCount = readCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(readCount == hiddenCount)

        store.setDashboardVisible(true)
        try await waitUntil("visible restarts interval", window: window, state: state) { readCount >= hiddenCount + 2 && cpu.percentage != nil }
        #expect(cpu.percentage == 50)
        host.rootView = AnyView(EmptyView())
        try await waitUntil("removed panel stops sampling", window: window, state: state) { disappeared && cpu.percentage == nil }
        let removedCount = readCount
        try await Task.sleep(for: .milliseconds(100))
        #expect(readCount == removedCount)
    }

    private func waitUntil(_ stage: String, window: NSWindow, state: @MainActor () -> String,
                           _ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            // Drive only this test's hosted layout. NSApp retains ownership of
            // event dispatch, and sampling still starts through the real view.
            window.contentView?.needsLayout = true
            window.contentView?.layoutSubtreeIfNeeded()
            window.contentView?.displayIfNeeded()
            window.displayIfNeeded()
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        } while Date() < deadline
        // Stop here on a missing transition so later assertions do not
        // confuse its cause with a second visibility or sampling failure.
        try #require(condition(), "Stage \(stage) did not complete: \(state())")
    }
}

private struct ResourcePanelFixtureClient: ProviderExtrasProviding {
    let snapshot: ProviderExtrasSnapshot

    func refresh() async -> ProviderExtrasSnapshot { snapshot }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}

private struct ResourcePanelUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw CancellationError() }
    func readLoadedModels() async throws -> LoadedModelsState { throw CancellationError() }
    func readStatus() async throws -> StatusSnapshot { throw CancellationError() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw CancellationError() }
}
