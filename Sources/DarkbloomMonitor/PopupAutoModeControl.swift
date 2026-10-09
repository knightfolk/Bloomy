import DarkbloomTelemetry
import SwiftUI

/// Auto is a saved provider plan, not a switch inferred from CLI defaults.
struct PopupAutoModeControl: View {
    @ObservedObject var store: ProviderControlStore
    let openModels: () -> Void
    var updateProtection: AppUpdateEditorProtection? = nil
    var commandTile = false
    @State private var showsSetup = false
    @State private var opensModelsAfterDismissal = false

    var body: some View {
        Button {
            showsSetup = true
        } label: {
            Label("Auto…", systemImage: "arrow.triangle.2.circlepath")
        }
        .buttonStyle(PopupAdaptiveCommandButtonStyle(commandTile: commandTile))
        .controlSize(.small)
        .help("Advertise selected models with one slot and a chosen startup model")
        .accessibilityIdentifier("popover.auto")
        .modifier(PopupKeyboardReveal())
        .sheet(isPresented: $showsSetup, onDismiss: {
            guard opensModelsAfterDismissal else { return }
            opensModelsAfterDismissal = false
            openModels()
        }) {
            PopupAutoModeSetup(store: store, openModels: { opensModelsAfterDismissal = true },
                updateProtection: updateProtection)
                .labelStyle(.titleAndIcon).buttonStyle(.bordered)
        }
    }
}

private struct PopupAutoModeSetup: View {
    @ObservedObject var store: ProviderControlStore
    let openModels: () -> Void
    var updateProtection: AppUpdateEditorProtection? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var planDraft = PopupAutoPlanDraft()
    @State private var editorOwner = UUID()
    @State private var isMounted = false
    @State private var saved = false

    private var preferredModelID: String { planDraft.preferredModelID }

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
                    Picker("Preload at startup", selection: protectedPlanBinding) {
                        Text("Choose a model").tag("")
                        ForEach(candidates, id: \.catalogID) { model in
                            Text(model.displayName).tag(model.catalogID)
                        }
                    }
                    .accessibilityIdentifier("popover.auto.preload")
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
                        let requestedModelID = preferredModelID
                        let revision = planDraft.revision
                        Task {
                            await store.configureAutomaticMode(preferredModelID: requestedModelID)
                            let verified = store.errorMessage == nil && store.draft?.hasChanges == false
                                && store.savedAutomaticStartupModelID == requestedModelID
                            guard isMounted else { return }
                            saved = verified && planDraft.didSave(modelID: requestedModelID, revision: revision)
                            updateProtection?.setBlocked(planDraft.hasChanges, owner: editorOwner)
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
        .onAppear { isMounted = true }
        .onDisappear {
            isMounted = false
            updateProtection?.endEditing(owner: editorOwner)
        }
        .task {
            await store.refreshPreservingDraft()
            guard !Task.isCancelled, isMounted else { return }
            planDraft.initialize(modelID: candidates.first(where: \.isPreloaded)?.catalogID
                ?? candidates.first?.catalogID ?? "")
        }
    }

    private var protectedPlanBinding: Binding<String> {
        Binding(get: { preferredModelID }, set: {
            planDraft.edit(modelID: $0)
            saved = false
            updateProtection?.setBlocked(planDraft.hasChanges, owner: editorOwner)
        })
    }
}

/// The suggested startup choice is clean. Only a deliberate changed selection
/// blocks an update, and older save completions cannot consume newer choices.
struct PopupAutoPlanDraft {
    private(set) var preferredModelID = ""
    private var baselineModelID = ""
    private(set) var revision: UInt64 = 0

    var hasChanges: Bool { preferredModelID != baselineModelID }

    mutating func initialize(modelID: String) {
        guard revision == 0 else { return }
        preferredModelID = modelID
        baselineModelID = modelID
    }

    mutating func edit(modelID: String) {
        preferredModelID = modelID
        revision &+= 1
    }

    @discardableResult
    mutating func didSave(modelID: String, revision: UInt64) -> Bool {
        guard self.revision == revision, preferredModelID == modelID else { return false }
        baselineModelID = modelID
        return true
    }
}
