import DarkbloomCompanionProtocol
import SwiftUI

struct AlertHistoryView: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Alerts")
                .toolbar {
                    if let host = store.host {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { Task { await store.loadAlertHistory(hostID: host.hostID) } } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .accessibilityLabel("Refresh alert history")
                        }
                    }
                }
                .task(id: store.selectedHostID) {
                    if let hostID = store.selectedHostID, !store.alertHistoryLoaded {
                        await store.loadAlertHistory(hostID: hostID)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let host = store.host {
                if store.selectedAlertRecords.isEmpty && !store.alertHistoryLoaded {
                    ContentUnavailableView(
                        "Alert history not loaded",
                        systemImage: "bell.badge",
                        description: Text("Connect to \(store.displayName(for: host)) to load its sanitized alert history.")
                    )
                } else if store.selectedAlertRecords.isEmpty {
                    ContentUnavailableView("No retained alerts", systemImage: "bell.slash")
                } else {
                    List {
                        Section {
                            ForEach(store.selectedAlertRecords) { record in
                                AlertHistoryRow(record: record, hostName: store.displayName(for: host))
                            }
                            if let cursor = store.alertNextCursor {
                                Button("Load older alerts") {
                                    Task { await store.loadAlertHistory(hostID: host.hostID, cursor: cursor) }
                                }
                                .frame(maxWidth: .infinity, alignment: .center)
                            }
                        } header: {
                            Text("\(store.displayName(for: host)) · \(host.hostID.uuidString.lowercased())")
                        } footer: {
                            Text("History contains fixed alert codes and bounded timing evidence. It does not include logs or diagnostic prose.")
                        }
                    }
                    .listStyle(.insetGrouped)
                    .refreshable { await store.loadAlertHistory(hostID: host.hostID) }
                }
        } else {
            ContentUnavailableView("No Mac selected", systemImage: "macbook.and.iphone")
        }
    }
}

private struct AlertHistoryRow: View {
    let record: CompanionAlertRecord
    let hostName: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(record.code.safeTitle).font(.headline)
                Spacer()
                Text(record.transition.rawValue.capitalized)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(record.transition == .raised ? .orange : .secondary)
            }
            Text(hostName).font(.caption).foregroundStyle(.secondary)
            Text("Mac-reported · \(record.occurredAt.formatted(date: .abbreviated, time: .standard))")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            HStack(spacing: 14) {
                if let duration = record.observedDurationSeconds {
                    Label("\(duration)s observed", systemImage: "timer")
                }
                Label("\(record.observationCount) observations", systemImage: "waveform.path")
            }
            .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
    }
}
