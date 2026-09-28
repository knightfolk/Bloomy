import DarkbloomCompanionProtocol
import SwiftUI

struct FleetOverview: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if store.fleetHostStatuses.isEmpty {
                    ContentUnavailableView(
                        "No Macs paired",
                        systemImage: "macbook.and.iphone",
                        description: Text("Add a Mac from the Pair tab to see its status here.")
                    )
                } else {
                    List(store.fleetHostStatuses) { status in
                        Button {
                            store.selectHost(status.host.hostID)
                            Task { await store.connect(hostID: status.host.hostID) }
                        } label: {
                            FleetHostCard(
                                status: status,
                                title: store.displayName(for: status.host),
                                selected: store.selectedHostID == status.host.hostID
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("fleet-host-\(status.host.hostID.uuidString.lowercased())")
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await store.refreshFleet() }
                }
            }
            .navigationTitle("Fleet")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refreshFleet() } } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh all Macs")
                }
            }
            .task { await store.refreshFleet() }
        }
    }
}

private struct FleetHostCard: View {
    let status: FleetHostStatus
    let title: String
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline)
                    Text("Host ID · \(status.host.hostID.uuidString.lowercased())")
                        .font(.caption2.monospaced()).foregroundStyle(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint) }
            }

            LabeledContent("Connection", value: connectionLabel)
            LabeledContent("Provider", value: providerLabel)
            LabeledContent("Active model", value: activeModelLabel)
            LabeledContent("Jobs", value: "Not shared by this host")
            LabeledContent("Account earnings", value: earningsLabel)
            LabeledContent("Temperature", value: "Not shared by this host")
            LabeledContent("Latest alert", value: alertLabel)
            LabeledContent("Freshness", value: freshnessLabel)

            if let error = status.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
                    .lineLimit(3)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var connectionLabel: String {
        switch status.connection {
        case .connected: "Online"
        case .connecting: "Connecting"
        case .pairing, .awaitingApproval: "Pairing"
        case .disconnected: "Offline"
        case .unpaired: "Not paired"
        }
    }

    private var providerLabel: String {
        guard let snapshot = status.snapshot else { return "Unavailable" }
        return snapshot.states.provider.state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var activeModelLabel: String {
        guard let models = status.snapshot?.models else { return "Unavailable" }
        return models.first(where: \.active)?.name ?? "None reported"
    }

    private var earningsLabel: String {
        guard let value = status.snapshot?.observations.first(where: { $0.metric == .accountEarnings }),
              let amount = value.value else { return "Unavailable" }
        let number = amount.formatted(.number.precision(.fractionLength(2)))
        return "\(value.currencyCode ?? "") \(number)"
    }

    private var alertLabel: String {
        guard let alert = status.latestAlert else { return "No retained alerts" }
        return "\(alert.code.safeTitle) · \(alert.transition.rawValue.capitalized)"
    }

    private var freshnessLabel: String {
        guard status.snapshot != nil else { return "No snapshot received" }
        return status.isStale ? "Stale" : "Fresh · received on this iPhone"
    }
}

extension CompanionAlertCode {
    var safeTitle: String {
        switch self {
        case .providerOffline: "Provider unavailable"
        case .lifecycleTimedOut: "Provider operation timed out"
        case .lifecycleForced: "Provider required a forced stop"
        case .modelInsufficientMemory: "Model memory unavailable"
        case .modelUnavailable: "Model unavailable"
        case .modelUnsupported: "Model unsupported"
        case .modelIntegrityFailure: "Model integrity check failed"
        case .modelTimedOut: "Model load timed out"
        case .modelBackendUnavailable: "Model backend unavailable"
        case .modelUnknown: "Model load failed"
        }
    }
}
