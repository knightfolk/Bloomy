import AppKit
import DarkbloomTelemetry
import SwiftUI

@MainActor
final class PopoverVisibility: ObservableObject {
    @Published private(set) var isVisible = false

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
    }
}

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    static let itemWidth: CGFloat = 80

    private let statusItem: NSStatusItem
    let popover = NSPopover()
    let popoverVisibility = PopoverVisibility()
    private var popoverFanToken: UUID?
    private(set) var popoverFanCancellation: Task<Void, Never>?
    private(set) var dashboardWindowController: DashboardWindowController?
    private(set) var chatWindowController: ChatWindowController?
    private let store: MonitorStore
    private let defaults: UserDefaults
    private(set) var controlStore: ProviderControlStore?
    private let hostingStore: HostingSettingsStore?
    private let chatStore: ChatStore?
    let updateProtection = AppUpdateEditorProtection()
    let popupSettingsDraft = ProviderSettingsDraftState()

    var statusItemLength: CGFloat { statusItem.length }
    var popoverContentSize: NSSize { popover.contentSize }
    var hasUnsavedSettingsEdits: Bool { dashboardWindowController?.hasUnsavedSettingsEdits == true }
    /// Read retained drafts as well as mounted editors at the updater's actual
    /// relaunch decision. Closing a window does not discard its nonsecret input.
    var hasBlockingUpdateWork: Bool {
        hasUnsavedSettingsEdits
            || dashboardWindowController?.hasUnsavedChatEdits == true
            || dashboardWindowController?.hasUnsavedHostingEdits == true
            || chatWindowController?.hasUnsavedChatEdits == true
            || popupSettingsDraft.hasChanges
            || updateProtection.hasBlockingEditors
            || chatStore?.isSending == true
            || hostingStore?.pendingExposureConfirmation != nil
    }

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
        popover.delegate = self
        let contentController = FittingPopoverHostingController(
            rootView: PopoverRootView(
                store: store,
                visibility: popoverVisibility,
                controlStore: controlStore,
                openSettings: { [weak self] page in self?.showSettings(page: page) },
                openDashboard: { [weak self] in self?.showDashboard() },
                openModels: { [weak self] in self?.showDashboard(section: .models) },
                openHosting: { [weak self] in self?.showDashboard(section: .hosting) },
                updateProtection: updateProtection,
                popupSettingsDraft: popupSettingsDraft
            ),
            popover: popover
        )
        popover.contentViewController = contentController
        contentController.prepareForPresentation()
    }

    func invalidate() {
        endPopoverFanObservation()
        popoverVisibility.setVisible(false)
        popover.performClose(nil)
        chatWindowController?.close()
        dashboardWindowController?.close()
        NSStatusBar.system.removeStatusItem(statusItem)
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            showPopover()
        }
    }

    func showPopover() {
        guard !popover.isShown, let button = statusItem.button else { return }
        let controlStore = self.controlStore
        Task { @MainActor [weak controlStore] in
            await controlStore?.refreshPreservingDraft()
        }
        (popover.contentViewController as? FittingPopoverHostingController<PopoverRootView>)?
            .prepareForPresentation(anchorView: button)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    func popoverWillShow(_ notification: Notification) {
        if popoverFanToken == nil {
            popoverFanToken = store.providerExtras?.beginVisibleFanObservation()
        }
        popoverVisibility.setVisible(true)
    }

    func popoverWillClose(_ notification: Notification) {
        endPopoverFanObservation()
        popoverVisibility.setVisible(false)
    }

    func popoverDidClose(_ notification: Notification) {
        endPopoverFanObservation()
        popoverVisibility.setVisible(false)
    }

    private func endPopoverFanObservation() {
        guard let token = popoverFanToken else { return }
        popoverFanToken = nil
        popoverFanCancellation = store.providerExtras?.endVisibleFanObservation(token)
    }

    func showDashboard(section: DashboardDestination? = nil, settingsPage: SettingsPage? = nil, activate: Bool = true) {
        popover.performClose(nil)
        if dashboardWindowController == nil {
            dashboardWindowController = DashboardWindowController(
                store: store, controlStore: controlStore, hostingStore: hostingStore,
                chatStore: chatStore,
                openChatWindow: { [weak self] in self?.showChatWindow() },
                defaults: defaults,
                updateProtection: updateProtection
            )
        }
        dashboardWindowController?.present(section: section, settingsPage: settingsPage, activate: activate)
    }

    /// Opens the resizable pop-out chat window. It shares the dashboard
    /// Chat tab's `ChatStore`, so both views show the same conversation.
    func showChatWindow(activate: Bool = true) {
        popover.performClose(nil)
        if chatWindowController == nil, let chatStore {
            chatWindowController = ChatWindowController(store: chatStore, updateProtection: updateProtection)
        }
        chatWindowController?.present(activate: activate)
    }

    func showSettings(page: SettingsPage? = nil, activate: Bool = true) {
        showDashboard(section: .settings, settingsPage: page, activate: activate)
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
    @ObservedObject var visibility: PopoverVisibility
    let controlStore: ProviderControlStore?
    let openSettings: (SettingsPage?) -> Void
    let openDashboard: () -> Void
    let openModels: () -> Void
    let openHosting: () -> Void
    let updateProtection: AppUpdateEditorProtection
    let popupSettingsDraft: ProviderSettingsDraftState

    @ViewBuilder
    var body: some View {
        if let controlStore {
            MonitorPopover(store: store, isVisible: visibility.isVisible, ownsVisibleFanPolling: false, openSettings: openSettings, openDashboard: openDashboard, openModels: openModels, openHosting: openHosting, updateProtection: updateProtection, popupSettingsDraft: popupSettingsDraft)
                .environmentObject(controlStore)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Label("Model controls unavailable", systemImage: "exclamationmark.circle")
                    .font(.headline)
                Button("Open dashboard", action: openDashboard)
            }
            .padding(16)
            .frame(width: 560, alignment: .leading)
        }
    }
}
