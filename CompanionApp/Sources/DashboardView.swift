import DarkbloomCompanionProtocol
import SwiftUI

struct DashboardView: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ConnectionBanner()
                    if let snapshot = store.snapshot {
                        RuntimeCard(states: snapshot.states)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 12) {
                            ForEach(snapshot.observations, id: \.metric) { observation in
                                MetricCard(observation: observation)
                            }
                        }
                    } else {
                        ContentUnavailableView("No host status yet", systemImage: "gauge.with.dots.needle.33percent", description: Text("Connect and refresh to load current telemetry."))
                    }
                }
                .padding()
            }
            .navigationTitle(store.host.map(store.displayName(for:)) ?? "Bloomy")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Refresh host status")
                }
            }
            .task(id: store.selectedHostID) {
                if store.connection != .connected { await store.connectAfterApproval() }
                else { await store.refresh() }
            }
            .refreshable { await store.refresh() }
        }
    }
}

private struct ConnectionBanner: View {
    @Environment(CompanionStore.self) private var store
    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(store.connection == .connected && !store.snapshotIsStale ? .green : .orange).frame(width: 10, height: 10)
            Text(status)
                .font(.headline)
            Spacer()
            if store.connection != .connected {
                Button("Reconnect") { Task { await store.connectAfterApproval() } }
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private var status: String {
        if store.connection != .connected { return "Host unavailable" }
        return store.snapshotIsStale ? "Connected · data is stale" : "Securely connected"
    }
}

private struct RuntimeCard: View {
    let states: RuntimeStates
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runtime").font(.headline)
            RuntimeRow(name: "Provider", state: states.provider)
            RuntimeRow(name: "Mac app", state: states.macApp)
            RuntimeRow(name: "Helper", state: states.helper)
        }
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct RuntimeRow: View {
    let name: String; let state: RuntimeStateObservation
    var body: some View {
        HStack { Text(name); Spacer(); Text(state.state.rawValue.replacingOccurrences(of: "_", with: " ").capitalized).foregroundStyle(.secondary) }
    }
}

private struct MetricCard: View {
    let observation: MetricObservation
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(observation.metric.label).font(.caption).foregroundStyle(.secondary)
            if let value = observation.value {
                Text(value.formatted(.number.precision(.fractionLength(0...2))) + observation.unit.suffix)
                    .font(.title2.bold()).monospacedDigit()
                Text(observation.provenance == .direct ? "Measured" : "Estimated").font(.caption2).foregroundStyle(.secondary)
            } else {
                Text("Unavailable").font(.headline).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }
}

private extension MetricID {
    var label: String {
        switch self {
        case .providerUptimeSeconds: "Provider uptime"
        case .requestsServed: "Requests served"
        case .tokensGenerated: "Tokens generated"
        case .tokenRate: "Token rate"
        case .systemCPUPercent: "Mac CPU"
        case .systemGPUPercent: "Mac GPU"
        case .memoryUsedBytes: "Memory used"
        case .powerWatts: "Power"
        case .accountEarnings: "Account earnings"
        case .accountEarningsRateEstimate: "Earnings rate"
        case .networkDemandPercent: "Network demand"
        }
    }
}
private extension MetricUnit {
    var suffix: String {
        switch self {
        case .percent: "%"
        case .watts: " W"
        case .tokensPerSecond: " tok/s"
        case .currency: ""
        case .currencyPerHour: "/hr"
        case .seconds: " s"
        case .bytes: " B"
        case .count: ""
        }
    }
}
