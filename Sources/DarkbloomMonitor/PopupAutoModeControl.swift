import DarkbloomTelemetry
import SwiftUI

/// Auto is a saved provider plan, not a switch inferred from CLI defaults.
struct PopupAutoModeControl: View {
    @ObservedObject var store: ProviderControlStore
    let openModels: () -> Void
    @State private var showsSetup = false

    var body: some View {
        Button {
            showsSetup = true
        } label: {
            Label("Auto…", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Advertise selected models with one slot and a chosen startup model")
        .accessibilityIdentifier("popover.auto")
        .sheet(isPresented: $showsSetup) {
            PopupAutoModeSetup(store: store, openModels: openModels)
        }
    }
}

private struct PopupAutoModeSetup: View {
    @ObservedObject var store: ProviderControlStore
    let openModels: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var preferredModelID = ""
    @State private var saved = false

    private var candidates: [ModelInventoryItem] {
        store.snapshot?.inventory.myCatalog.filter {
            $0.isEnabled && $0.isDownloaded && $0.issue == nil
        } ?? []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Auto", systemImage: "arrow.triangle.2.circlepath").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Advertise all selected models. Keep one model loaded at a time.")
                .font(.headline)
            Form {
                Section("Startup plan") {
                    LabeledContent("Model slots", value: "1 · Recommended")
                    LabeledContent("Selected models", value: (store.draft?.original.enabled.count ?? 0).formatted())
                    Picker("Preload at startup", selection: $preferredModelID) {
                        Text("Choose a model").tag("")
                        ForEach(candidates, id: \.catalogID) { model in
                            Text(model.displayName).tag(model.catalogID)
                        }
                    }
                    .accessibilityIdentifier("popover.auto.preload")
                    .onChange(of: preferredModelID) { _, _ in saved = false }
                    Text("The coordinator can send work to any selected model. Bloomy enables startup preload for the model you choose; other models load on demand.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Choose selected models…") {
                        dismiss()
                        openModels()
                    }
                    .accessibilityIdentifier("popover.auto.models")
                }
                Section {
                    Button("Save Auto plan") {
                        Task {
                            await store.configureAutomaticMode(preferredModelID: preferredModelID)
                            saved = store.errorMessage == nil && store.draft?.hasChanges == false
                                && store.savedAutomaticStartupModelID == preferredModelID
                        }
                    }
                    .disabled(store.automaticModeUnavailableReason(preferredModelID: preferredModelID) != nil)
                    .accessibilityIdentifier("popover.auto.save")
                    if let reason = store.automaticModeUnavailableReason(preferredModelID: preferredModelID) {
                        Text(reason).font(.callout).foregroundStyle(.secondary)
                    }
                    if saved {
                        Label("Auto plan saved", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    Text("Saving does not interrupt serving. The one-slot limit and startup preload take effect on the next provider start. Apply Live updates which selected models are advertised now.")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("Apply selected models live") {
                        Task { await store.applyLive() }
                    }
                    .disabled(!store.canApplyLive)
                    .accessibilityIdentifier("popover.auto.applyLive")
                    if let reason = store.applyLiveUnavailableReason {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = store.errorMessage {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            Button("Refresh model controls") {
                Task { await store.refreshPreservingDraft() }
            }
            .disabled(store.operation != .idle)
            .accessibilityIdentifier("popover.auto.refresh")
        }
        .padding(20)
        .frame(width: 540, height: 560)
        .task {
            await store.refreshPreservingDraft()
            preferredModelID = candidates.first(where: \.isPreloaded)?.catalogID
                ?? candidates.first?.catalogID ?? ""
        }
    }
}
