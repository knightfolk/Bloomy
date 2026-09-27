import DarkbloomCompanionProtocol
import SwiftUI

struct CompanionSettingsView: View {
    @Environment(CompanionStore.self) private var store
    @State private var concurrency = 1
    @State private var slots = 1
    @State private var startupPreload = false
    @State private var enabledModels: Set<String> = []
    @State private var preloadModels: Set<String> = []

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

                Section("Connection") {
                    LabeledContent("Host", value: store.host?.name ?? "None")
                    LabeledContent("Status", value: String(describing: store.connection))
                    Button("Reconnect") { Task { await store.connectAfterApproval() } }
                    Button("Forget this Mac", role: .destructive) { Task { await store.forgetHost() } }
                }

                Section("Remote access") {
                    Label("Use Tailscale on the Mac and iPhone for remote routes in this release.", systemImage: "network.badge.shield.half.filled")
                    Text("An embedded Tailscale route remains under evaluation and is not shipped in this build.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .task { if store.settings == nil { await load() } }
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
}
