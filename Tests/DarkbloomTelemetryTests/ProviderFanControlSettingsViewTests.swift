import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Provider fan control settings", .serialized)
@MainActor
struct ProviderFanControlSettingsViewTests {
    @Test("fan starting points are distinct policies accepted by the CLI")
    func presetPolicies() {
        let policies = FanPreset.allCases.map(\.policy)
        #expect(Set(policies.map(\.speedPercent)).count == FanPreset.allCases.count)
        for policy in policies {
            #expect(ProviderFanPolicy.speedRange.contains(policy.speedPercent))
            #expect(ProviderFanPolicy.triggerTemperatureRange.contains(policy.triggerTemperatureCelsius))
        }
    }

    @Test("fan controls render at settings and popup sizes", arguments: [false, true])
    func renders(compact: Bool) async throws {
        let now = Date()
        let status = ProviderFanStatus(
            capability: ProviderFanStatus.controlCapability,
            installed: true,
            loaded: true,
            helper: ProviderFanHelperStatus(
                enabled: true,
                providerActive: true,
                mode: "error",
                chip: "Apple M5",
                gpuTemperatureCelsius: 46,
                triggerTemperatureCelsius: 45,
                releaseTemperatureCelsius: 40,
                speedPercent: 80,
                fans: [
                    ProviderFanReading(index: 0, actualRPM: 7_800, targetRPM: 8_200, minimumRPM: 1_200, maximumRPM: 8_800, mode: "auto"),
                    ProviderFanReading(index: 1, actualRPM: 7_750, targetRPM: 8_200, minimumRPM: 1_200, maximumRPM: 8_800, mode: "auto"),
                ],
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
        #expect(ProviderFanControlSettingsView.toggleState(status) == true)
        #expect(ProviderFanControlSettingsView.toggleState(status.withoutHelper()) == nil)
        let stopped = ProviderFanStatus(
            capability: status.capability,
            installed: true,
            loaded: false,
            helper: nil,
            diagnostic: status.diagnostic,
            helperErrorPresent: false,
            diagnosticErrorPresent: false
        )
        #expect(ProviderFanControlSettingsView.toggleState(stopped) == false)
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
        let content = Group {
            if compact {
                PopupFanPanel(extras: store) { _, _ in false }
            } else {
                Form {
                    ProviderFanControlSettingsView(store: store) { _, _ in false }
                }.formStyle(.grouped)
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        let settingsSize = NSSize(width: compact ? 560 : 800, height: compact ? 520 : 560)
        window.setContentSize(settingsSize)
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        window.setContentSize(settingsSize)
        host.view.frame = NSRect(origin: .zero, size: settingsSize)
        host.view.layoutSubtreeIfNeeded()

        #expect(window.contentView?.frame.width == settingsSize.width)
        #expect(window.contentView?.frame.height == settingsSize.height)

        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else {
            return
        }
        let summary = NSHostingView(rootView: PopupFanSummary(store: store, now: now, open: {})
            .padding(12).frame(width: 365).background(Color(nsColor: .windowBackgroundColor)))
        summary.frame = NSRect(origin: .zero, size: summary.fittingSize)
        summary.layoutSubtreeIfNeeded()
        let bitmap = try #require(summary.bitmapImageRepForCachingDisplay(in: summary.bounds))
        summary.cacheDisplay(in: summary.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-popup-cooling.png"))

        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = [
            "-x", "-l", String(window.windowNumber),
            "/tmp/darkbloom-fan-control-\(compact ? "popup" : "settings").png",
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
