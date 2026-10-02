import AppKit
import DarkbloomTelemetry
import Testing
@testable import DarkbloomMonitor

@Suite("Popover visibility", .serialized)
@MainActor
struct PopoverVisibilityTests {
    @Test("hidden popup schedules one initial update and visible popup keeps its one-second cadence")
    func timelineStopsWhenHidden() {
        let start = Date(timeIntervalSince1970: 1_000)
        var hidden = PopoverTimelineSchedule(isVisible: false).entries(from: start, mode: .normal)
        #expect(hidden.next() == start)
        #expect(hidden.next() == nil)
        var visible = PopoverTimelineSchedule(isVisible: true).entries(from: start, mode: .normal)
        #expect(visible.next() == start)
        #expect(visible.next() == start.addingTimeInterval(1))
        #expect(visible.next() == start.addingTimeInterval(2))
    }

    @Test("closing a retained popover stops fan reads and reopening resumes them")
    func retainedPopoverCancelsFanPolling() async throws {
        let client = PopoverFanClient()
        let extras = ProviderExtrasStore(client: client, visibleFanPollingInterval: .milliseconds(120))
        await extras.refresh()
        let monitor = MonitorStore(
            service: TelemetryService(source: PopoverInertTelemetry()),
            initial: .unavailable(now: Date()), providerExtras: extras
        )
        let control = ProviderControlStore(controller: PopoverInertControl())
        let status = StatusItemController(store: monitor, controlStore: control)
        var invalidated = false
        defer { if !invalidated { status.invalidate() } }
        // Keep other test windows from implicitly dismissing this transient
        // popover; the real show/close delegate callbacks remain in use.
        status.popover.behavior = .applicationDefined
        status.popover.animates = false
        // Status-bar item anchors can be temporarily absent while other suites
        // insert/remove their own items. Use a dedicated native window anchor
        // to exercise the actual popover and its delegate deterministically.
        let anchor = NSView(frame: NSRect(x: 0, y: 0, width: 120, height: 40))
        let anchorWindow = NSWindow(contentRect: anchor.frame, styleMask: [.titled], backing: .buffered, defer: false)
        anchorWindow.isReleasedWhenClosed = false
        anchorWindow.contentView = anchor
        anchorWindow.center()
        anchorWindow.orderBack(nil)
        defer { anchorWindow.close() }
        let retainedHost = try #require(status.popover.contentViewController)
        #expect(!status.popoverVisibility.isVisible)
        #expect(extras.visibleFanSubscriberCount == 0)
        try await Task.sleep(for: .milliseconds(180))
        #expect(await client.fanReads == 0)

        #expect(anchorWindow.isVisible)
        status.popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        #expect(status.popover.isShown)
        #expect(status.popoverVisibility.isVisible)
        #expect(extras.visibleFanSubscriberCount == 1)
        try await waitForReads(1, client: client)
        try await waitForReads(2, client: client)
        status.popover.performClose(nil)
        #expect(!status.popoverVisibility.isVisible)
        #expect(extras.visibleFanSubscriberCount == 0)
        // Native close removes the token synchronously. Wait for that exact
        // cancelled task to finish before measuring a quiescent hidden popup.
        await status.popoverFanCancellation?.value
        let readsAfterClose = await client.fanReads
        try await Task.sleep(for: .milliseconds(280))
        #expect(await client.fanReads == readsAfterClose)
        #expect(status.popover.contentViewController === retainedHost)

        status.popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        #expect(status.popover.isShown)
        #expect(status.popoverVisibility.isVisible)
        #expect(extras.visibleFanSubscriberCount == 1)
        try await waitForReads(readsAfterClose + 1, client: client)
        #expect(status.popover.contentViewController === retainedHost)
        status.invalidate()
        invalidated = true
        #expect(!status.popoverVisibility.isVisible)
        #expect(extras.visibleFanSubscriberCount == 0)
        await status.popoverFanCancellation?.value
        let readsAfterInvalidation = await client.fanReads
        try await Task.sleep(for: .milliseconds(280))
        #expect(await client.fanReads == readsAfterInvalidation)
        await extras.stop()
    }

    @Test("closing the popup keeps an independent Settings fan observer active")
    func closeKeepsSettingsObserver() async throws {
        let client = PopoverFanClient()
        let extras = ProviderExtrasStore(client: client, visibleFanPollingInterval: .milliseconds(120))
        await extras.refresh()
        let monitor = MonitorStore(service: TelemetryService(source: PopoverInertTelemetry()), initial: .unavailable(now: Date()), providerExtras: extras)
        let status = StatusItemController(store: monitor, controlStore: ProviderControlStore(controller: PopoverInertControl()))
        defer { status.invalidate() }
        let settings = Task { await extras.observeVisibleFan() }
        defer { settings.cancel() }
        try await waitForReads(1, client: client)
        #expect(extras.visibleFanSubscriberCount == 1)
        // Delegate callbacks are synchronous even when SwiftUI is busy.
        status.popoverWillShow(Notification(name: NSPopover.willShowNotification))
        #expect(extras.visibleFanSubscriberCount == 2)
        status.popoverWillClose(Notification(name: NSPopover.willCloseNotification))
        #expect(extras.visibleFanSubscriberCount == 1)
        #expect(status.popoverFanCancellation == nil)
        let afterPopupClose = await client.fanReads
        try await waitForReads(afterPopupClose + 2, client: client)
        settings.cancel()
        await settings.value
        #expect(extras.visibleFanSubscriberCount == 0)
        let afterSettingsClose = await client.fanReads
        try await Task.sleep(for: .milliseconds(280))
        #expect(await client.fanReads == afterSettingsClose)
        await extras.stop()
    }

    private func waitForReads(_ count: Int, client: PopoverFanClient) async throws {
        for _ in 0..<200 {
            if await client.fanReads >= count { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Visible popover did not start its fan subscription")
    }
}

private actor PopoverFanClient: ProviderExtrasProviding {
    private(set) var fanReads = 0
    func refresh() async -> ProviderExtrasSnapshot {
        ProviderExtrasSnapshot(
            capturedAt: Date(), idlePolicy: .unavailable(reason: "Fixture"),
            betaFeatures: .unavailable(reason: "Fixture"), fanStatus: fanStatus(),
            autoUpdateStatus: .unavailable(reason: "Fixture")
        )
    }
    func refreshFan() async -> SourceAvailability<ProviderFanStatus> {
        fanReads += 1
        return fanStatus()
    }
    private func fanStatus() -> SourceAvailability<ProviderFanStatus> {
        .available(value: ProviderFanStatus(
            capability: ProviderFanStatus.controlCapability,
            installed: false, loaded: false, helper: nil,
            diagnostic: ProviderFanDiagnostic(chip: "Fixture", supported: true, gpuTemperatures: [], fans: []),
            helperErrorPresent: false, diagnosticErrorPresent: false
        ), capturedAt: Date())
    }
    func saveIdle(minutes: Int) async throws { throw PopoverUnexpectedAcquisition() }
    func setBeta(id: String, enabled: Bool) async throws { throw PopoverUnexpectedAcquisition() }
}

private struct PopoverInertControl: ProviderControlling {
    func refresh() async throws -> ProviderControlSnapshot { throw PopoverUnexpectedAcquisition() }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw PopoverUnexpectedAcquisition() }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws { throw PopoverUnexpectedAcquisition() }
    func delete(_ localModelID: String) async throws { throw PopoverUnexpectedAcquisition() }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { throw PopoverUnexpectedAcquisition() }
}

private struct PopoverInertTelemetry: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw PopoverUnexpectedAcquisition() }
    func readLoadedModels() async throws -> LoadedModelsState { throw PopoverUnexpectedAcquisition() }
    func readStatus() async throws -> StatusSnapshot { throw PopoverUnexpectedAcquisition() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw PopoverUnexpectedAcquisition() }
}

private struct PopoverUnexpectedAcquisition: Error {}
