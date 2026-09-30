import SwiftUI

enum DashboardDestination: String, CaseIterable, Identifiable {
    case overview = "Overview", chat = "Chat", activity = "Activity", opportunity = "Opportunity"
    case history = "Action History"
    case models = "Models", hosting = "Hosting", health = "Health & Logs", settings = "Settings"
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .chat: "bubble.left.and.bubble.right"
        case .activity: "chart.bar"
        case .opportunity: "network"
        case .models: "cpu"
        case .hosting: "antenna.radiowaves.left.and.right"
        case .health: "waveform.path.ecg"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

@MainActor
final class DashboardNavigation: ObservableObject {
    private let defaults: UserDefaults
    @Published var selected: DashboardDestination {
        didSet { defaults.set(selected.rawValue, forKey: "dashboard.selectedSection") }
    }
    @Published var settingsPage: SettingsPage {
        didSet { defaults.set(settingsPage.rawValue, forKey: "dashboard.settingsPage") }
    }
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        settingsPage = defaults.string(forKey: "dashboard.settingsPage").flatMap(SettingsPage.init(rawValue:)) ?? .appearance
        selected = defaults.string(forKey: "dashboard.selectedSection").flatMap(DashboardDestination.init(rawValue:)) ?? .overview
    }
}

struct DashboardRootView: View {
    @ObservedObject var store: MonitorStore
    let controlStore: ProviderControlStore?
    var hostingStore: HostingSettingsStore? = nil
    var chatStore: ChatStore? = nil
    var openChatWindow: (() -> Void)? = nil
    @ObservedObject var navigation: DashboardNavigation
    @AppStorage("sidebar.monitor.expanded") private var monitorExpanded = true
    @AppStorage("sidebar.workspace.expanded") private var workspaceExpanded = true
    @AppStorage("sidebar.diagnostics.expanded") private var diagnosticsExpanded = true
    @AppStorage("sidebar.settings.expanded") private var settingsExpanded = true
    private var selectedRaw: String { navigation.selected.rawValue }

    var body: some View {
        NavigationSplitView {
            List {
                DisclosureGroup("Monitor", isExpanded: $monitorExpanded) {
                    destinationRows([.overview, .activity, .opportunity])
                }
                DisclosureGroup("Workspace", isExpanded: $workspaceExpanded) {
                    destinationRows([.chat, .models, .hosting])
                }
                DisclosureGroup("Diagnostics", isExpanded: $diagnosticsExpanded) {
                    destinationRows([.history, .health])
                }
                DisclosureGroup("Settings", isExpanded: $settingsExpanded) {
                    ForEach(SettingsPage.allCases) { page in
                        sidebarRow(
                            title: page.rawValue,
                            symbol: page.symbol,
                            selected: navigation.selected == .settings && navigation.settingsPage == page
                        ) {
                            navigation.settingsPage = page
                            navigation.selected = .settings
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            if selectedRaw == DashboardDestination.overview.rawValue || DashboardDestination(rawValue: selectedRaw) == nil {
                DashboardOverviewView(store: store, controlStore: controlStore)
            } else if navigation.selected == .chat {
                if let chatStore {
                    ChatView(store: chatStore, openPopOut: openChatWindow)
                } else {
                    ContentUnavailableView(
                        "Chat unavailable",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("Chat is not available in this session.")
                    )
                }
            } else if selectedRaw == DashboardDestination.activity.rawValue {
                ActivityView(store: store)
            } else if selectedRaw == DashboardDestination.opportunity.rawValue {
                OpportunityView(store: store, controlStore: controlStore)
            } else if selectedRaw == DashboardDestination.models.rawValue {
                ModelsView(controlStore: controlStore, monitorStore: store) { modelID, date in
                    let network = ModelNetworkContext.labels(modelID: modelID, capacity: store.networkCapacity, pricing: store.publicPricing, now: date)
                    let performance = ModelNetworkContext.performanceLabel(modelID: modelID, averages: store.modelTokenRateAverages, now: date)
                    let work = ModelNetworkContext.workLabel(modelID: modelID, values: store.modelWorkEarnings, now: date)
                    return network + [performance, work].compactMap { $0 }
                }
            } else if navigation.selected == .hosting {
                if let hostingStore {
                    HostingSettingsView(store: hostingStore)
                } else {
                    ContentUnavailableView(
                        "Hosting unavailable",
                        systemImage: "antenna.radiowaves.left.and.right",
                        description: Text("Provider hosting controls are not available in this session.")
                    )
                }
            } else if navigation.selected == .history {
                if let history = store.actionHistory {
                    ActionHistoryView(store: history)
                } else {
                    Text("Action history is unavailable in this session.")
                }
            } else if navigation.selected == .settings {
                MonitorSettingsView(
                    extrasStore: store.providerExtras,
                    controlStore: controlStore,
                    monitorStore: store,
                    selection: navigation.settingsPage
                )
            } else {
                HealthView(store: store)
            }
        }
        .toolbar {
            if let nudge = store.inactivityNudge {
                PopupNudgeControl(store: nudge)
                    .labelStyle(.titleAndIcon)
            }
            Button { settingsExpanded = true; navigation.selected = .settings } label: { Label("Settings", systemImage: "gearshape") }
                .help("Open Settings")
        }
        .onChange(of: navigation.selected) { _, destination in
            switch destination {
            case .overview, .activity, .opportunity: monitorExpanded = true
            case .chat, .models, .hosting: workspaceExpanded = true
            case .health, .history: diagnosticsExpanded = true
            case .settings: settingsExpanded = true
            }
        }
        .onChange(of: store.snapshot.status.value?.version) { _, _ in
            hostingStore?.refreshEnvironment()
        }
    }

    private func destinationRows(_ destinations: [DashboardDestination]) -> some View {
        ForEach(destinations) { destination in
            sidebarRow(
                title: destination.rawValue,
                symbol: destination.symbol,
                selected: navigation.selected == destination
            ) {
                navigation.selected = destination
            }
        }
    }

    private func sidebarRow(
        title: String,
        symbol: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    selected ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 7)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .listRowInsets(EdgeInsets(top: 1, leading: 4, bottom: 1, trailing: 4))
    }

}
