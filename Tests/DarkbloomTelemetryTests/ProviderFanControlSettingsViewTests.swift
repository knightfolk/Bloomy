import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Provider fan control settings", .serialized)
@MainActor
struct ProviderFanControlSettingsViewTests {
    @Test("official fan and automatic-update controls render at settings width")
    func renders() async throws {
        let now = Date()
        let status = ProviderFanStatus(
            capability: ProviderFanStatus.controlCapability,
            installed: true,
            loaded: true,
            helper: ProviderFanHelperStatus(
                enabled: true,
                providerActive: true,
                mode: "controlling",
                chip: "Apple M5",
                gpuTemperatureCelsius: 46,
                triggerTemperatureCelsius: 45,
                releaseTemperatureCelsius: 40,
                speedPercent: 80,
                fans: [],
                updatedAt: now
            ),
            diagnostic: ProviderFanDiagnostic(
                chip: "Apple M5",
                supported: true,
                gpuTemperatures: [ProviderFanTemperature(key: "GPU0", celsius: 46)],
                fans: []
            ),
            helperErrorPresent: false,
            diagnosticErrorPresent: false
        )
        let snapshot = ProviderExtrasSnapshot(
            capturedAt: now,
            idlePolicy: .unavailable(reason: "Not needed"),
            betaFeatures: .unavailable(reason: "Not needed"),
            fanStatus: .available(value: status, capturedAt: now),
            autoUpdateStatus: .available(
                value: ProviderAutoUpdateStatus(enabled: true),
                capturedAt: now
            )
        )
        let store = ProviderExtrasStore(client: FanSettingsFixtureClient(snapshot: snapshot))
        await store.refresh()
        let content = Form {
            ProviderAutoUpdateSettingsView(store: store) { _, _ in false }
            ProviderFanControlSettingsView(store: store) { _, _ in false }
        }
        .formStyle(.grouped)
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 760, height: 580))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutSubtreeIfNeeded()

        #expect(host.view.frame.width == 760)
        #expect(host.view.frame.height >= 560)

        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else {
            return
        }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = [
            "-x", "-l", String(window.windowNumber),
            "/tmp/darkbloom-fan-control-settings.png",
        ]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}

private struct FanSettingsFixtureClient: ProviderExtrasProviding {
    let snapshot: ProviderExtrasSnapshot

    func refresh() async -> ProviderExtrasSnapshot { snapshot }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}
