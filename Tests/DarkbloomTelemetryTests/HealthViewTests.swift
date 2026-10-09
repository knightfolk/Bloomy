import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Health rendering", .serialized)
@MainActor
struct HealthViewTests {
    @Test("popup freshness clocks follow their own visibility, while dashboard clocks retain their lifecycle",
          arguments: [false, true])
    func independentlyOwnedClock(dashboardVisible: Bool) {
        let store = MonitorStore(service: TelemetryService(source: HealthUnusedSource()),
            initial: .unavailable(now: Date()))
        store.setDashboardVisible(dashboardVisible)
        for override in [nil, false, true] as [Bool?] {
            let view = HealthView(store: store, visibilityOverride: override)
            let dates = Array(view.displaySchedule.entries(from: Date(), mode: .normal).prefix(3))
            #expect(dates.count == ((override ?? dashboardVisible) ? 3 : 1))
            if dates.count == 3 {
                #expect(abs(dates[2].timeIntervalSince(dates[1]) - 5) < 0.001)
            }
        }
    }

    @Test("long unavailable diagnostics remain compact until expanded", arguments: [300.0, 540.0])
    func diagnosticDisclosure(width: Double) async throws {
        let reason = String(repeating: "The source could not complete its read; retry when it is available. ", count: 12)
        let source: SourceAvailability<String> = .unavailable(reason: reason)
        let collapsed = NSHostingView(rootView: HealthSourceFreshnessRow(title: "Loaded models", source: source)
            .frame(width: width))
        let expanded = NSHostingView(rootView: HealthSourceFreshnessRow(title: "Loaded models", source: source, isExpanded: true)
            .frame(width: width))
        collapsed.setFrameSize(NSSize(width: width, height: 1_200))
        expanded.setFrameSize(NSSize(width: width, height: 1_200))
        collapsed.layoutSubtreeIfNeeded()
        expanded.layoutSubtreeIfNeeded()
        #expect(collapsed.fittingSize.height < 90)
        #expect(expanded.fittingSize.height > collapsed.fittingSize.height + 100)
        #expect(collapsed.fittingSize.width <= width)
        #expect(expanded.fittingSize.width <= width)
    }

    @Test("thermal and retained slot diagnostics render without acquiring CLI data", arguments: [false, true])
    func render(hasDaemon: Bool) async throws {
        let now = Date()
        let url = try #require(Bundle.module.url(forResource: "daemon-state-online", withExtension: "json", subdirectory: "Fixtures"))
        let state = try DaemonStateParser.parse(Data(contentsOf: url))
        let initial = TelemetrySnapshot(
            state: hasDaemon ? .stale(value: state, capturedAt: now, reason: "Fixture read timeout") : .unavailable(reason: "Fixture permission denied"),
            loadedModels: .unavailable(reason: "Not acquired"), status: .unavailable(reason: "Not acquired"),
            eventFeed: .unavailable(reason: "Not acquired"), tokenRate: .unavailable(reason: "No interval"),
            diagnostics: [], capturedAt: now, menuStatus: hasDaemon ? .stale : .unavailable
        )
        let store = MonitorStore(service: TelemetryService(source: HealthUnusedSource()), initial: initial)
        let host = NSHostingController(rootView: HealthView(store: store))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 1050))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()
        #expect(store.snapshot == initial)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-health-\(hasDaemon ? "slots" : "missing").png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}

private struct HealthUnusedSource: TelemetrySource {
    struct UnexpectedRead: Error {}
    func readDaemonState() async throws -> DaemonState { Issue.record("Health view started acquisition"); throw UnexpectedRead() }
    func readLoadedModels() async throws -> LoadedModelsState { Issue.record("Health view started acquisition"); throw UnexpectedRead() }
    func readStatus() async throws -> StatusSnapshot { Issue.record("Health view started acquisition"); throw UnexpectedRead() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { Issue.record("Health view started acquisition"); throw UnexpectedRead() }
}
