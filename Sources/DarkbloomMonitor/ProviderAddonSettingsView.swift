import DarkbloomTelemetry
import SwiftUI

/// The CLI is an operator override: its release acts on every add-on hold.
struct ProviderAddonSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    @ObservedObject var control: ProviderControlStore
    @ObservedObject var draft: ProviderSettingsDraftState
    let performMutation: ProviderExtrasMutationExecutor
    let isVisible: Bool
    @State private var leaseSeconds = 600
    @State private var confirmation: Confirmation?
    @State private var submitting = false
    @State private var feedback: String?

    private enum Confirmation: String, Identifiable, Sendable {
        case hold, release, forceRelease
        var id: String { rawValue }
    }
    private var busy: Bool { submitting || store.mutationInFlight || store.addonRefreshing || control.operation != .idle }
    private func fresh(at date: Date) -> Bool {
        guard let checked = store.addonCheckedAt else { return false }
        let age = date.timeIntervalSince(checked)
        return age.isFinite && (0...ProviderExtrasSnapshot.maximumSourceAge).contains(age)
    }
    private var transitions: [Date] {
        guard let checked = store.addonCheckedAt else { return [] }
        return ProviderSettingsFreshnessPolicy.transitions(capturedAt: checked,
            maximumAge: ProviderExtrasSnapshot.maximumSourceAge, at: store.currentDate)
    }

    var body: some View {
        Section("Add-on hold · Operator controls") {
            TimelineView(VisibilityTimelineSchedule(base: .explicit(transitions), isVisible: isVisible)) { context in
                content(at: context.date)
            }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
        }
        .task { await store.refreshAddon() }
        .alert(item: $confirmation) { action in
            switch action {
            case .hold:
                Alert(title: Text("Place operator hold?"),
                    message: Text("New inference stops immediately. Accepted requests have up to two minutes to finish; remaining work may be cancelled, and the provider then attempts to unload models. This renews the shared operator hold. The lease can outlast its duration while an add-on holds the machine lock."),
                    primaryButton: .default(Text("Place hold")) { submit(action) }, secondaryButton: .cancel())
            case .release:
                Alert(title: Text("Release all add-on holds?"),
                    message: Text("This releases every hold, including holds placed by other apps and any added since the last refresh. Darkbloom refuses while the machine lock is held."),
                    primaryButton: .destructive(Text("Release all holds")) { submit(action) }, secondaryButton: .cancel())
            case .forceRelease:
                Alert(title: Text("Force release all holds?"),
                    message: Text("This releases every hold even while another add-on holds the machine lock. Its virtual machines may still be using memory, and the provider can resume inference immediately."),
                    primaryButton: .destructive(Text("Force release all")) { submit(action) }, secondaryButton: .cancel())
            }
        }
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        let current = fresh(at: date)
        VStack(alignment: .leading, spacing: 8) {
            Text("These debugging controls affect the running provider and may affect other apps.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if case .available(let status) = store.addonStatus {
                let title: String = switch status.hold {
                case .none: "No active holds"
                case .draining: "Draining accepted work"
                case .held: "Held"
                case .unrecognized: "Hold status unconfirmed"
                }
                Text((current ? "" : "Last checked: ") + title)
                    .font(.callout.weight(.semibold)).accessibilityIdentifier("settings.addon.status")
                Text(status.machineLockHeld ? "Machine lock held · an add-on may still be using memory." : "Machine lock free")
                    .font(.caption).foregroundStyle(.secondary)
                if status.operatorHoldPresent { Text("The shared operator hold is present.").font(.caption).foregroundStyle(.secondary) }
                Stepper("Operator hold lease: \(leaseSeconds) seconds", value: $leaseSeconds, in: 30...600, step: 30)
                    .disabled(busy || draft.hasChanges)
                HStack {
                    Button(status.operatorHoldPresent ? "Renew operator hold…" : "Place operator hold…") { feedback = nil; confirmation = .hold }
                        .disabled(!current || busy || draft.hasChanges)
                    Button("Release all holds…") { feedback = nil; confirmation = .release }
                        .disabled(!current || busy || draft.hasChanges || status.hold == .none || status.machineLockHeld)
                    if status.machineLockHeld && status.hold != .none {
                        Button("Force release all…") { feedback = nil; confirmation = .forceRelease }
                            .disabled(!current || busy || draft.hasChanges)
                    }
                }
            } else if case .unavailable(let reason) = store.addonStatus {
                Text(reason == .unsupportedVersion
                     ? "This Darkbloom version is not yet verified for add-on controls."
                     : "Add-on hold status unavailable. Refresh to check the running provider.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Button("Refresh add-on status") { Task { await store.refreshAddon() } }
                .disabled(busy).accessibilityIdentifier("settings.addon.refresh")
        }
    }

    private func submit(_ action: Confirmation) {
        guard !busy, !draft.hasChanges else { return }
        submitting = true
        let duration = leaseSeconds
        Task { @MainActor in
            let success = await performMutation("Add-on hold") {
                switch action {
                case .hold: try await store.changeAddonHold(leaseSeconds: duration)
                case .release: try await store.changeAddonHold()
                case .forceRelease: try await store.changeAddonHold(force: true)
                }
            }
            submitting = false
            feedback = success ? "Change accepted. Check the current hold status above."
                : (store.errorMessage ?? "The change could not be confirmed. Refresh before trying again.")
        }
    }
}
