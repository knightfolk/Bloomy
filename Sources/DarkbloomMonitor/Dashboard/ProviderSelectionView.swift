import DarkbloomTelemetry
import SwiftUI

struct ProviderSelectionView: View {
    @ObservedObject var store: MonitorStore
    @ObservedObject var controlStore: ProviderControlStore

    var body: some View {
        TimelineView(.periodic(from: .now, by: 2)) { context in
            VStack(alignment: .leading, spacing: 10) {
                Text("Selections").font(.headline)
                if let control = controlStore.snapshot {
                    let saved = control.inventory.myCatalog.filter(\.isEnabled).map(\.catalogID)
                    row("Saved selection", ids: saved)
                    Text("Settings last read " + control.capturedAt.formatted(date: .omitted, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if case .available(let state, _) = store.snapshot.state,
                       (0...10).contains(context.date.timeIntervalSince1970 - state.writtenAt) {
                        let runtime = ProviderRuntimePresentation.make(state)
                        Label(runtime.title, systemImage: runtimeSymbol(for: state))
                            .font(.callout.weight(.semibold))
                        Text(runtime.detail)
                            .font(.caption).foregroundStyle(.secondary)
                        if let advertised = state.advertisedModels {
                            row("Advertised now", ids: advertised)
                            row("Loaded now", ids: state.warmModels)
                        } else {
                            Text("Running selection is not reported in this provider phase.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        if let pending = state.startupPreloadPendingModels, !pending.isEmpty {
                            row("Preloading", ids: pending)
                        }
                        if let switching = state.modelSwitch,
                           [.validating, .draining, .switching].contains(switching.outcome),
                           !switching.models.isEmpty {
                            row("Switching", ids: switching.models)
                        }
                        if let advertised = state.advertisedModels {
                            if Set(saved) != Set(advertised) {
                                Label("Restart applies a different saved selection", systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.orange).font(.callout)
                            }
                            let onDemand = Set(advertised).subtracting(state.warmModels).sorted()
                            if !onDemand.isEmpty {
                                Text("On demand: " + onDemand.joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary)
                                Text("These advertised models will load when requested.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text("Running selection is not currently verified").foregroundStyle(.secondary)
                    }
                    if controlStore.draft?.hasChanges == true {
                        Text("Unsaved model edits are separate from the saved selection above.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Text("Refresh model controls to compare selections").foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func row(_ title: String, ids: [String]) -> some View {
        LabeledContent(title) {
            Text(ids.isEmpty ? "None" : ids.sorted().map { id in controlStore.snapshot?.inventory.myCatalog.first(where: { $0.catalogID == id })?.displayName ?? id }.joined(separator: ", "))
                .multilineTextAlignment(.trailing).textSelection(.enabled)
        }
        .font(.callout)
    }

    private func runtimeSymbol(for state: DaemonState) -> String {
        if state.availability?.phase == .waitingForSchedule { return "calendar.badge.clock" }
        if state.modelSwitch.map({ [.validating, .draining, .switching].contains($0.outcome) }) == true {
            return "arrow.triangle.2.circlepath"
        }
        if state.startupPreloadPendingModels?.isEmpty == false { return "arrow.down.circle" }
        if state.lifecycle?.outcome == .draining { return "hourglass" }
        return "checkmark.circle"
    }
}
