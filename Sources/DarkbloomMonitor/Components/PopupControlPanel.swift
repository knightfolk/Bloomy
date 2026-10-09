import AppKit
import DarkbloomTelemetry
import SwiftUI

/// One route owns the popup's operational panels. These panels use the same
/// stores and retained drafts as the popup's quick controls.
enum PopupControlDestination: Hashable, Identifiable {
    case models, hosting, cooling, protection, profitSwitch, nudge, health
    case settings(SettingsPage)

    var id: String {
        switch self {
        case .models: "models"
        case .hosting: "hosting"
        case .cooling: "cooling"
        case .protection: "protection"
        case .profitSwitch: "profitSwitch"
        case .nudge: "nudge"
        case .health: "health"
        case .settings(let page): "settings.\(page.id)"
        }
    }

    var title: String {
        switch self {
        case .models: "Manage models"
        case .hosting: "Hosting"
        case .cooling: "Cooling"
        case .protection: "GPU protection"
        case .profitSwitch: "Profit switching"
        case .nudge: "Inactivity nudge"
        case .health: "Health & Logs"
        case .settings(let page): page == .electricity ? "Energy & electricity" : page.rawValue
        }
    }

    var symbol: String {
        switch self {
        case .models: "cpu"
        case .hosting: "network"
        case .cooling: "fan"
        case .protection: "shield"
        case .profitSwitch: "arrow.triangle.2.circlepath"
        case .nudge: "hand.tap"
        case .health: "waveform.path.ecg"
        case .settings(let page): page.symbol
        }
    }

    static let controlMenu: [Self] = [
        .models, .hosting, .settings(.provider), .protection, .settings(.electricity),
        .cooling, .nudge, .profitSwitch, .health
    ]
    static let settingsMenu: [Self] = [
        .settings(.appearance), .settings(.menuBar), .settings(.updates), .settings(.support)
    ]

    static func readiness(_ destination: ProviderReadinessPresentation.Destination) -> Self {
        switch destination {
        case .health: .health
        case .models: .models
        case .hosting: .hosting
        }
    }
}

/// AppKit dismisses its menu before presenting a SwiftUI panel, keeping the
/// transient parent popup available for the user's next command.
struct PopupControlMoreMenu: NSViewRepresentable {
    let openPanel: (PopupControlDestination) -> Void
    let openDashboard: () -> Void
    let quit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(actions: self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "More", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        button.symbolConfiguration = .init(pointSize: 17, weight: .medium)
        button.imagePosition = .imageAbove
        button.imageHugsTitle = true
        button.contentTintColor = .labelColor
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.setAccessibilityLabel("More controls")
        button.setAccessibilityIdentifier("popup.more")
        button.toolTip = "Models, hosting, energy, protection and app settings"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.actions = self }

    @MainActor final class Coordinator: NSObject {
        var actions: PopupControlMoreMenu
        private var selectedAction: (() -> Void)?
        init(actions: PopupControlMoreMenu) { self.actions = actions }

        @objc func showMenu(_ sender: NSButton) {
            selectedAction = nil
            let menu = NSMenu(title: "More controls")
            for destination in PopupControlDestination.controlMenu { menu.addItem(panelItem(destination)) }
            menu.addItem(.separator())
            for destination in PopupControlDestination.settingsMenu { menu.addItem(panelItem(destination)) }
            menu.addItem(.separator())
            menu.addItem(item("Dashboard & history", symbol: "rectangle.grid.2x2", action: #selector(dashboard)))
            menu.addItem(item("Quit Bloomy", symbol: "rectangle.portrait.and.arrow.right", action: #selector(quitApp)))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
            let action = selectedAction
            selectedAction = nil
            action?()
        }

        private func panelItem(_ destination: PopupControlDestination) -> NSMenuItem {
            let menuItem = item(destination.title, symbol: destination.symbol, action: #selector(panel(_:)))
            menuItem.representedObject = destination
            menuItem.setAccessibilityIdentifier("popup.more.\(destination.id)")
            return menuItem
        }

        private func item(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
            let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: "")
            menuItem.target = self
            menuItem.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return menuItem
        }

        @objc private func panel(_ sender: NSMenuItem) {
            guard let destination = sender.representedObject as? PopupControlDestination else { return }
            selectedAction = { [actions] in actions.openPanel(destination) }
        }
        @objc private func dashboard() { selectedAction = actions.openDashboard }
        @objc private func quitApp() { selectedAction = actions.quit }
    }
}

struct PopupControlPanel: View {
    let destination: PopupControlDestination
    @ObservedObject var store: MonitorStore
    @ObservedObject var controlStore: ProviderControlStore
    let hostingStore: HostingSettingsStore?
    let settingsDraft: ProviderSettingsDraftState
    let hostingDraft: HostingSettingsDraftState
    let updateProtection: AppUpdateEditorProtection?
    let isVisible: Bool
    let ownsVisibleFanPolling: Bool
    let maximumHeight: CGFloat?
    let openPanel: (PopupControlDestination) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var modelVisibilityOwner = UUID()

    var body: some View {
        Group {
            if destination == .cooling, let extras = store.providerExtras {
                PopupFanPanel(extras: extras, isVisible: isVisible,
                    ownsVisibleFanPolling: ownsVisibleFanPolling, draft: settingsDraft,
                    providerActionBusy: controlStore.operation != .idle || !controlStore.canEditProviderSettings) { label, mutation in
                    await controlStore.performSettingsMutation(label, mutation: mutation)
                }
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Label(destination.title, systemImage: destination.symbol)
                            .font(.headline)
                        Spacer()
                        Button("Done") { dismiss() }
                            .keyboardShortcut(.cancelAction)
                            .accessibilityIdentifier("popup.panel.done")
                    }
                    .padding(.horizontal, 16).padding(.vertical, 12)
                    Divider()
                    panelContent
                }
                .frame(width: 560, height: min(620, max(300, maximumHeight ?? 620)))
            }
        }
        .labelStyle(.titleAndIcon)
        .buttonStyle(.bordered)
        .environment(\.popupKeyboardRevealEnabled, false)
        .accessibilityIdentifier("popup.panel.\(destination.id)")
    }

    @ViewBuilder private var panelContent: some View {
        switch destination {
        case .models:
            ModelDemandHistoryScope(store: store.networkDemandHistory, isVisible: isVisible) { history in
                ModelManagerView(store: controlStore, telemetry: ModelManagerTelemetry(
                    tokenRates: store.currentModelTokenRateAverages,
                    servingAverages: store.modelServingProfitAverages,
                    networkCapacity: store.networkCapacity.value,
                    networkSourceAvailable: { if case .available = store.networkCapacity { true } else { false } }()
                ), refreshDemand: { await store.refreshNetworkCapacity() }, demandHistory: history,
                    liveSnapshot: store.snapshot, providerThroughputPeak: store.providerThroughputPeak.value,
                    isVisible: isVisible, providerStatus: store.snapshot.status, providerDaemonState: store.snapshot.state)
            }
            .task(id: isVisible) {
                guard isVisible else { return }
                await controlStore.refreshPreservingDraft()
            }
            .onAppear { store.setModelControlsVisible(isVisible, owner: modelVisibilityOwner) }
            .onChange(of: isVisible) { _, visible in
                store.setModelControlsVisible(visible, owner: modelVisibilityOwner)
            }
            .onDisappear { store.setModelControlsVisible(false, owner: modelVisibilityOwner) }
        case .hosting:
            if let hostingStore {
                HostingSettingsView(store: hostingStore, draft: hostingDraft,
                    updateProtection: updateProtection, presentation: .popup)
            } else { unavailable("Hosting controls are not available in this session.") }
        case .settings(let page):
            if page == .provider {
                VStack(spacing: 0) {
                    TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 1), isVisible: isVisible)) { context in
                        HStack {
                            Label("Provider", systemImage: "server.rack").font(.subheadline.weight(.semibold))
                            Spacer(minLength: 8)
                            ProviderLifecycleControls(store: controlStore, snapshot: store.snapshot,
                                currentTime: context.date, isConfirmationOwner: isVisible)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                    }
                    Divider()
                    settings(page)
                }
                .task(id: isVisible) {
                    guard isVisible else { return }
                    await controlStore.refreshPreservingDraft()
                }
            } else {
                settings(page)
            }
        case .cooling:
            settings(.fans)
        case .protection:
            Form {
                if let protection = store.hostGPUProtection {
                    HostGPUProtectionSettingsView(store: protection, slowdownWarning: store.servingSlowdownWarning)
                } else { unavailable("GPU protection is not available in this session.") }
            }.formStyle(.grouped)
        case .profitSwitch:
            Form {
                if let profitSwitch = store.profitSwitch { ProfitSwitchSettingsView(store: profitSwitch) }
                else { unavailable("Profit switching is not available in this session.") }
            }.formStyle(.grouped)
        case .nudge:
            Form {
                if let nudge = store.inactivityNudge {
                    InactivityNudgeSettingsView(store: nudge, updateProtection: updateProtection)
                } else { unavailable("Inactivity nudge is not available in this session.") }
            }.formStyle(.grouped)
        case .health:
            HealthView(store: store,
                openReadinessDestination: { openPanel(.readiness($0)) },
                visibilityOverride: isVisible, showsTitle: false)
        }
    }

    private func settings(_ page: SettingsPage) -> some View {
        MonitorSettingsView(extrasStore: store.providerExtras, controlStore: controlStore,
            monitorStore: store, selection: page, isVisible: isVisible, draft: settingsDraft,
            updateProtection: updateProtection, showsTitle: false)
    }

    private func unavailable(_ message: String) -> some View {
        ContentUnavailableView(destination.title + " unavailable", systemImage: destination.symbol,
            description: Text(message))
    }
}
