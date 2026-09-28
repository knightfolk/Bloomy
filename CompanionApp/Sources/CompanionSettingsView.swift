import DarkbloomCompanionProtocol
import SwiftUI

struct CompanionSettingsView: View {
    @Environment(CompanionStore.self) private var store
    @State private var concurrency = 1
    @State private var slots = 1
    @State private var startupPreload = false
    @State private var enabledModels: Set<String> = []
    @State private var preloadModels: Set<String> = []
    @State private var confirmForget = false
    @State private var confirmRevoke = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Provider") {
                    if let settings = store.settings {
                        Stepper("Concurrent requests: \(concurrency)", value: $concurrency, in: settings.concurrentRequestRange.minimum...settings.concurrentRequestRange.maximum)
                        Stepper("Resident model slots: \(slots)", value: $slots, in: settings.residentSlotRange.minimum...settings.residentSlotRange.maximum)
                        Toggle("Preload selected models at startup", isOn: $startupPreload)
                        if let models = store.snapshot?.models, !models.isEmpty {
                            ForEach(models, id: \.id) { model in
                                VStack(alignment: .leading) {
                                    Toggle(model.name, isOn: Binding(
                                        get: { enabledModels.contains(model.id) },
                                        set: { enabled in
                                            if enabled { enabledModels.insert(model.id) }
                                            else { enabledModels.remove(model.id); preloadModels.remove(model.id) }
                                        }
                                    ))
                                    Toggle("Preload", isOn: Binding(
                                        get: { preloadModels.contains(model.id) },
                                        set: { preload in
                                            if preload { enabledModels.insert(model.id); preloadModels.insert(model.id) }
                                            else { preloadModels.remove(model.id) }
                                        }
                                    ))
                                    .font(.subheadline)
                                    .disabled(!enabledModels.contains(model.id))
                                }
                            }
                        }
                        Button("Stage changes") {
                            Task {
                                await store.saveSettings(.init(
                                    enabledModels: enabledModels.sorted(),
                                    preloadModels: preloadModels.sorted(),
                                    maximumConcurrentRequests: concurrency,
                                    residentModelSlots: slots,
                                    startupPreload: startupPreload
                                ))
                            }
                        }
                        .disabled(!(store.snapshot?.capabilities.contains(.settingsWrite) ?? false))
                        Button("Save staged settings") {
                            Task {
                                await store.prepare(
                                    .saveSettings(draftID: settings.draftID),
                                    expectedRevision: settings.revision
                                )
                            }
                        }
                        .disabled(!(store.snapshot?.capabilities.contains(.settingsWrite) ?? false))
                    } else {
                        Button("Load settings") { Task { await load() } }
                    }
                    Text("Staging and saving are separate signed commands. Saving does not restart the provider.")
                        .font(.footnote).foregroundStyle(.secondary)
                }

                Section("Hosts") {
                    if !store.hosts.isEmpty {
                        Picker("Active Mac", selection: Binding(
                            get: { store.selectedHostID },
                            set: { if let hostID = $0 { store.selectHost(hostID) } }
                        )) {
                            ForEach(store.hosts) { host in
                                Text(store.displayName(for: host)).tag(Optional(host.hostID))
                            }
                        }
                        LabeledContent("Status", value: statusLabel)
                        Button("Reconnect") { Task { await store.connectAfterApproval() } }
                        Button("Forget this Mac locally", role: .destructive) { confirmForget = true }
                        Button("Revoke this iPhone on Mac", role: .destructive) { confirmRevoke = true }
                            .disabled(store.host == nil)
                        Text("Forgetting removes this Mac’s saved route and pin from this iPhone. Revoking also removes this iPhone’s pairing from the selected Mac.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        Text("No paired Macs")
                    }
                }

                Section("Selected host access") {
                    if let host = store.host {
                        LabeledContent("Host ID", value: host.hostID.uuidString.lowercased())
                    }
                }

                Section("Remote access") {
                    Label("Use Tailscale on the Mac and iPhone for remote routes in this release.", systemImage: "network.badge.shield.half.filled")
                    Text("An embedded Tailscale route remains under evaluation and is not shipped in this build.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { if store.settings == nil { await load() } }
            .onChange(of: store.selectedHostID) { _, _ in
                Task { if store.settings == nil { await load() } }
            }
            .confirmationDialog("Forget this Mac from this iPhone?", isPresented: $confirmForget, titleVisibility: .visible) {
                Button("Forget locally", role: .destructive) { Task { await store.forgetHost() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The Mac will still remember this iPhone until you revoke it there.")
            }
            .confirmationDialog("Revoke this iPhone on the selected Mac?", isPresented: $confirmRevoke, titleVisibility: .visible) {
                Button("Revoke pairing", role: .destructive) { Task { await store.revokeSelectedPhone() } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The selected Mac will remove this iPhone’s pairing. Only that Mac is affected.")
            }
        }
    }

    private func load() async {
        await store.loadSettings()
        if let saved = store.settings?.saved {
            concurrency = saved.maximumConcurrentRequests
            slots = saved.residentModelSlots
            startupPreload = saved.startupPreload
            enabledModels = Set(saved.enabledModels)
            preloadModels = Set(saved.preloadModels)
        }
    }

    private var statusLabel: String {
        switch store.connection {
        case .unpaired: "Not paired"
        case .pairing: "Pairing"
        case .awaitingApproval: "Awaiting Mac approval"
        case .connecting: "Connecting"
        case .connected: store.snapshotIsStale ? "Connected · stale data" : "Connected"
        case .disconnected: "Disconnected"
        }
    }
}
