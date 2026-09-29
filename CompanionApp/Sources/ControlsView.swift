import DarkbloomCompanionProtocol
import SwiftUI

struct ControlsView: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        NavigationStack {
            List {
                Section("CLI / provider") {
                    ControlButton("Start provider", icon: "play.fill", enabled: has(.providerLifecycle)) {
                        await store.prepare(.providerLifecycle(.start))
                    }
                    ControlButton("Stop provider", icon: "stop.fill", role: .destructive, enabled: has(.providerLifecycle)) {
                        await store.prepare(.providerLifecycle(.stop))
                    }
                    ControlButton("Restart provider", icon: "arrow.clockwise", enabled: has(.providerLifecycle)) {
                        await store.prepare(.providerLifecycle(.restart))
                    }
                    ControlButton("Apply saved models live", icon: "bolt.horizontal.fill", enabled: has(.providerLiveSwitch)) {
                        await store.prepare(.applySavedModelsLive)
                    }
                }
                Section("Bloomy on Mac") {
                    ControlButton("Open app", icon: "macwindow", enabled: has(.appLifecycle)) {
                        await store.prepare(.appLifecycle(.open))
                    }
                    ControlButton("Quit app", icon: "macwindow.badge.xmark", role: .destructive, enabled: has(.appLifecycle)) {
                        await store.prepare(.appLifecycle(.quit))
                    }
                    ControlButton("Relaunch app", icon: "arrow.clockwise.square", enabled: has(.appLifecycle)) {
                        await store.prepare(.appLifecycle(.relaunch))
                    }
                }
                if let operation = store.lastOperation {
                    Section("Last operation") {
                        LabeledContent("State", value: operation.state.rawValue.capitalized)
                        LabeledContent("Updated", value: operation.updatedAt.formatted(date: .omitted, time: .standard))
                    }
                }
                Section {
                    Text("Commands are prepared by the Mac, show the exact action here, and require Face ID or your passcode before the phone signs them.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Control")
        }
    }

    private func has(_ capability: Capability) -> Bool {
        store.connection == .connected && (store.snapshot?.capabilities.contains(capability) ?? false)
    }
}

private struct ControlButton: View {
    let title: String; let icon: String; let role: ButtonRole?; let enabled: Bool
    let action: @MainActor () async -> Void
    init(_ title: String, icon: String, role: ButtonRole? = nil, enabled: Bool, action: @escaping @MainActor () async -> Void) {
        self.title = title; self.icon = icon; self.role = role; self.enabled = enabled; self.action = action
    }
    var body: some View {
        Button(role: role) { Task { await action() } } label: { Label(title, systemImage: icon) }
            .disabled(!enabled)
    }
}
