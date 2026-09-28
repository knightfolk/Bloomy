import DarkbloomCompanionProtocol
import SwiftUI

struct RootView: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.hosts.isEmpty {
                PairingView()
            } else {
                TabView {
                    DashboardView()
                        .tabItem { Label("Status", systemImage: "gauge.with.dots.needle.67percent") }
                    ModelsView()
                        .tabItem { Label("Models", systemImage: "shippingbox") }
                    ControlsView()
                        .tabItem { Label("Control", systemImage: "switch.2") }
                    FleetOverview()
                        .tabItem { Label("Fleet", systemImage: "server.rack") }
                    AlertHistoryView()
                        .tabItem { Label("Alerts", systemImage: "bell.badge") }
                    CompanionSettingsView()
                        .tabItem { Label("Settings", systemImage: "slider.horizontal.3") }
                    PairingView()
                        .tabItem { Label("Add Mac", systemImage: "plus.circle") }
                }
            }
        }
        .tint(.mint)
        .alert("Darkbloom", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sheet(item: Binding(
            get: { store.pendingCommand.map(IdentifiedCommand.init) },
            set: { if $0 == nil { store.cancelPendingCommand() } }
        )) { item in
            CommandApprovalView(command: item.value)
        }
        .task {
            if store.autoPairFixture, store.host == nil, !store.qrText.isEmpty {
                await store.pair(scannedCode: store.qrText)
            }
        }
    }
}

private struct IdentifiedCommand: Identifiable {
    let value: PreparedCommand
    var id: UUID { value.commandID }
}

private struct CommandApprovalView: View {
    @Environment(CompanionStore.self) private var store
    let command: PreparedCommand

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: command.risk.icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(command.risk == .stopsProvider || command.risk == .quitsMacApp ? .orange : .mint)
                Text(command.risk.title).font(.largeTitle.bold())
                Text(command.action.summary)
                    .font(.title3)
                LabeledContent("Mac", value: store.host?.name ?? "Paired host")
                LabeledContent("Expires", value: command.expiresAt.formatted(date: .omitted, time: .standard))
                Spacer()
                Button {
                    Task { await store.approvePendingCommand(for: command) }
                } label: {
                    Label("Approve with Face ID or Passcode", systemImage: "faceid")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Cancel", role: .cancel) { store.cancelPendingCommand(command) }
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
            .navigationTitle("Confirm Command")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.large])
    }
}

private extension CommandRisk {
    var title: String {
        switch self {
        case .configurationChange: "Change configuration?"
        case .restartsProvider: "Restart provider?"
        case .interruptsActiveWork: "Apply models live?"
        case .stopsProvider: "Stop provider?"
        case .quitsMacApp: "Quit Mac app?"
        }
    }
    var icon: String {
        switch self {
        case .configurationChange: "slider.horizontal.3"
        case .restartsProvider: "arrow.clockwise.circle"
        case .interruptsActiveWork: "bolt.horizontal.circle"
        case .stopsProvider: "stop.circle"
        case .quitsMacApp: "macwindow.badge.xmark"
        }
    }
}

private extension ControlAction {
    var summary: String {
        switch self {
        case let .providerLifecycle(action): "\(action.rawValue.capitalized) the Darkbloom CLI/provider using its graceful lifecycle path."
        case .applySavedModelsLive: "Apply the saved model selection to the running provider. Active work may drain first."
        case .applySettings: "Update the staged provider settings on the paired Mac."
        case .saveSettings: "Save the staged provider settings. This does not restart the provider."
        case let .appLifecycle(action): "\(action.rawValue.capitalized) Darkbloom Control on the paired Mac. The helper stays online."
        }
    }
}
