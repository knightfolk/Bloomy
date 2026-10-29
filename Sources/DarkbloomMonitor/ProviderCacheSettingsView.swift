import DarkbloomTelemetry
import SwiftUI

/// Saved cache settings are separate from the provider's running configuration.
struct ProviderCacheSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    @ObservedObject var draft: ProviderSettingsDraftState
    let performMutation: ProviderExtrasMutationExecutor
    @State private var feedback: String?
    @State private var submitting = false

    var body: some View {
        Section("Encrypted inference cache") {
            if let source = store.cacheStatus, let value = source.value {
                let fresh = ProviderSettingsFreshnessPolicy.isFresh(source, at: store.currentDate)
                Text(fresh ? "Saved settings" : "Last known settings · refresh before changing")
                    .font(.caption).foregroundStyle(.secondary)
                if let selected = value.selectedDirectory {
                    Text("Selected folder: \(selected)").font(.callout).textSelection(.enabled)
                }
                Text("Cache files: \(value.directory)").font(.callout).textSelection(.enabled)
                Text(limitDescription(value.dailyWriteBytes)).font(.callout)
                if value.hasProblem {
                    Label("The selected storage could not be verified. Check the directory and volume.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                } else if !value.hasVolume {
                    Text("Built-in storage is checked when the cache opens.").font(.caption).foregroundStyle(.secondary)
                }
                HStack {
                    Button("Manage cache…") {
                        draft.cacheExpected = value
                        draft.cacheDirectory = value.selectedDirectory ?? ""
                        draft.cacheDaily = value.dailyWriteBytes.map { String(Double($0) / 1_000_000_000) } ?? ""
                        feedback = nil
                    }
                    .disabled(!fresh || store.cacheRefreshing || store.mutationInFlight || submitting || draft.hasChanges)
                    Button("Refresh") { Task { await store.refreshCache() } }
                        .disabled(store.cacheRefreshing || submitting)
                }
            } else {
                Text("Cache settings unavailable").foregroundStyle(.secondary)
                Button("Refresh") { Task { await store.refreshCache() } }.disabled(store.cacheRefreshing || submitting)
            }
            Text("Saved settings apply after a provider restart. Changing directories leaves old cache files in place.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
        }
        .task { await store.refreshCache() }
        .sheet(isPresented: Binding(get: { draft.cacheExpected != nil }, set: { if !$0 { draft.cacheExpected = nil; draft.setCacheDirty(false) } })) {
            cacheSheet
        }
    }

    private func limitDescription(_ bytes: Int64?) -> String {
        guard let bytes else { return "Daily writes: provider startup setting or default" }
        guard bytes > 0 else { return "Daily writes: unlimited" }
        return "Daily writes: \(Double(bytes) / 1_000_000_000) GB per rolling day"
    }
    private var numericLimit: Double? {
        guard let value = Double(draft.cacheDaily.trimmingCharacters(in: .whitespacesAndNewlines)),
              ProviderCacheParser.validDailyWriteGB(value) else { return nil }
        return value
    }
    private var dailyHasEdits: Bool {
        guard let expected = draft.cacheExpected else { return false }
        return draft.cacheDaily != (expected.dailyWriteBytes.map { String(Double($0) / 1_000_000_000) } ?? "")
    }
    private var directoryHasEdits: Bool { draft.cacheExpected.map { draft.cacheDirectory != ($0.selectedDirectory ?? "") } ?? false }
    private var cacheSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Encrypted inference cache").font(.title2.bold())
            Text("Daily write limit (decimal GB)").font(.callout)
            TextField("0 means unlimited", text: $draft.cacheDaily).accessibilityLabel("Daily write limit in decimal GB").disabled(submitting)
            Text("Use 0 for unlimited. An unset limit uses the provider's startup setting or default.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Save write limit") { if let value = numericLimit { submit(.dailyWriteGB(value)) } }
                .disabled(numericLimit == nil || submitting || draft.hasOtherChangesForCache || directoryHasEdits)
            Divider()
            Text("Cache directory").font(.callout)
            TextField("Absolute directory path", text: $draft.cacheDirectory).accessibilityLabel("Cache directory path").disabled(submitting)
            Text("Choose an existing private directory on APFS. External volumes must be encrypted. Existing cache files are not moved.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Use directory") { submit(.directory(draft.cacheDirectory)) }
                    .disabled(!draft.cacheDirectory.hasPrefix("/") || submitting || draft.hasOtherChangesForCache || dailyHasEdits)
                Button("Use built-in directory") { submit(.resetDirectory) }.disabled(submitting || draft.hasOtherChangesForCache || dailyHasEdits || directoryHasEdits)
            }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            if dailyHasEdits && directoryHasEdits {
                Text("Save one change at a time; restore the other field first.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            HStack { Spacer(); Button("Cancel") { draft.cacheExpected = nil; draft.setCacheDirty(false) }.keyboardShortcut(.cancelAction).disabled(submitting) }
        }
        .padding(24).frame(width: 520, height: 460)
        .onChange(of: draft.cacheDaily) { _, _ in draft.setCacheDirty(dailyHasEdits || directoryHasEdits) }
        .onChange(of: draft.cacheDirectory) { _, _ in draft.setCacheDirty(dailyHasEdits || directoryHasEdits) }
    }
    private func submit(_ change: ProviderCacheChange) {
        guard let expected = draft.cacheExpected, !submitting, !draft.hasOtherChangesForCache else { return }
        draft.setCacheDirty(false)
        submitting = true; feedback = nil
        Task { @MainActor in
            let success = await performMutation("inference cache") { try await store.setCache(expected: expected, change: change) }
            submitting = false
            if success { draft.cacheExpected = nil } else { draft.setCacheDirty(dailyHasEdits || directoryHasEdits) }
            feedback = success ? "Cache settings saved. Restart the provider to apply them."
                : "Cache settings could not be confirmed. Refresh before trying again."
        }
    }
}
