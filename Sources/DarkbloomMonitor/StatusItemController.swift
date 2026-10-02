import AppKit
import DarkbloomTelemetry
import SwiftUI

@MainActor
final class StatusItemController: NSObject {
    static let itemWidth: CGFloat = 80

    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private(set) var dashboardWindowController: DashboardWindowController?
    private(set) var chatWindowController: ChatWindowController?
    private let store: MonitorStore
    private let defaults: UserDefaults
    private(set) var controlStore: ProviderControlStore?
    private let hostingStore: HostingSettingsStore?
    private let chatStore: ChatStore?

    var statusItemLength: CGFloat { statusItem.length }
    var popoverContentSize: NSSize { popover.contentSize }

    init(
        store: MonitorStore,
        controlStore: ProviderControlStore? = nil,
        hostingStore: HostingSettingsStore? = nil,
        chatStore: ChatStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.store = store
        self.defaults = defaults
        self.hostingStore = hostingStore
        self.chatStore = chatStore
        statusItem = NSStatusBar.system.statusItem(withLength: Self.itemWidth)
        self.controlStore = controlStore
        super.init()

        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp])

        let hostingView = PassthroughHostingView(rootView: StatusItemRootView(store: store))
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: button.leadingAnchor, constant: 4),
            hostingView.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -4),
            hostingView.topAnchor.constraint(equalTo: button.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])

        popover.behavior = .transient
        popover.contentSize = NSSize(width: 560, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView(
                store: store,
                controlStore: controlStore,
                openSettings: { [weak self] in self?.showSettings() },
                openDashboard: { [weak self] in self?.showDashboard() },
                openModels: { [weak self] in self?.showDashboard(section: .models) },
                openHosting: { [weak self] in self?.showDashboard(section: .hosting) }
            )
        )
    }

    func invalidate() {
        popover.performClose(nil)
        chatWindowController?.close()
        dashboardWindowController?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            let controlStore = self.controlStore
            Task { @MainActor [weak controlStore] in
                await controlStore?.refreshPreservingDraft()
            }
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
        }
    }

    func showDashboard(section: DashboardDestination? = nil, activate: Bool = true) {
        popover.performClose(nil)
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(
                store: store, controlStore: controlStore, hostingStore: hostingStore,
                chatStore: chatStore,
                openChatWindow: { [weak self] in self?.showChatWindow() },
                defaults: defaults
            )
        }
        dashboardWindowController?.present(section: section, activate: activate)
    }

    /// Opens the resizable pop-out chat window. It shares the dashboard
    /// Chat tab's `ChatStore`, so both views show the same conversation.
    func showChatWindow(activate: Bool = true) {
        popover.performClose(nil)
        if chatWindowController == nil, let chatStore {
            chatWindowController = ChatWindowController(store: chatStore)
        }
        chatWindowController?.present(activate: activate)
    }

    func showSettings(activate: Bool = true) {
        showDashboard(section: .settings, activate: activate)
    }
}

private final class PassthroughHostingView<Content: View>: NSHostingView<Content> {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

private struct StatusItemRootView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject private var gpuUsage: SystemGPUUsageStore

    init(store: MonitorStore) {
        self.store = store
        self.gpuUsage = store.gpuUsage
    }

    var body: some View {
        if let extras = store.providerExtras {
            ProviderExtrasStatusItemView(store: store, extras: extras)
        } else {
            MenuBarStatusContent(store: store, fanStatus: nil)
        }
    }
}

/// Fan measurements publish independently of daemon/GPU telemetry. The store's
/// existing lifecycle polls the read-only extras client every 30 seconds.
private struct ProviderExtrasStatusItemView: View {
    let store: MonitorStore
    @ObservedObject var extras: ProviderExtrasStore

    var body: some View {
        MenuBarStatusContent(store: store, fanStatus: extras.snapshot?.fanStatus)
    }
}

private struct MenuBarStatusContent: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject private var gpuUsage: SystemGPUUsageStore
    let fanStatus: SourceAvailability<ProviderFanStatus>?
    @State private var freshnessCheckedAt = Date()

    init(store: MonitorStore, fanStatus: SourceAvailability<ProviderFanStatus>?) {
        self.store = store
        self.gpuUsage = store.gpuUsage
        self.fanStatus = fanStatus
    }

    var body: some View {
        let now = max(Date(), freshnessCheckedAt)
        let gpu = store.gpuUsage.reading(at: now)
        let values = MenuBarIndicators.make(
            snapshot: store.snapshot,
            utilization: gpu.percentage,
            sampledAt: store.gpuUsage.lastGoodSampledAt,
            utilizationIsCurrent: !gpu.isStale,
            fanStatus: fanStatus,
            now: now
        )
        MenuBarLabel(
            presentation: store.menuPresentation(mode: .statusOnly),
            uptime: store.observedUptime,
            family: MenuBarIndicators.modelFamily(snapshot: store.snapshot, now: now),
            attention: store.menuAttention,
            indicators: values
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: values.nextFreshnessChange) {
            guard let deadline = values.nextFreshnessChange else { return }
            do { try await Task.sleep(for: .seconds(max(0.01, deadline.timeIntervalSinceNow))) }
            catch { return }
            freshnessCheckedAt = Date()
        }
    }
}

private struct PopoverRootView: View {
    @ObservedObject var store: MonitorStore
    let controlStore: ProviderControlStore?
    let openSettings: () -> Void
    let openDashboard: () -> Void
    let openModels: () -> Void
    let openHosting: () -> Void

    @ViewBuilder
    var body: some View {
        if let controlStore {
            MonitorPopover(store: store, openSettings: openSettings, openDashboard: openDashboard, openModels: openModels, openHosting: openHosting)
                .environmentObject(controlStore)
        } else {
            MonitorPopover(store: store, openSettings: openSettings, openDashboard: openDashboard, openModels: openModels, openHosting: openHosting)
        }
    }
}
