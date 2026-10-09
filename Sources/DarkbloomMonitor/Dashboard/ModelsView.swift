import SwiftUI

/// Hosts the model editor and its staged draft; opening this route does
/// not acquire data, reset edits, or create a second control service.
struct ModelsView: View {
    let controlStore: ProviderControlStore?
    var monitorStore: MonitorStore? = nil
    var networkContext: (String, Date) -> [String] = { _, _ in [] }
    @State private var showsSelectionDetails = false

    var body: some View {
        ModelDemandHistoryScope(store: monitorStore?.networkDemandHistory,
            isVisible: monitorStore?.dashboardVisible ?? true) { history in
            modelContent(history: history)
        }
    }

    private func modelContent(history: ModelDemandHistoryPresentation?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if let controlStore {
                if let monitorStore {
                    DisclosureGroup(isExpanded: $showsSelectionDetails) {
                        ProviderSelectionView(store: monitorStore, controlStore: controlStore)
                    } label: {
                        Text("Running and saved selection")
                            .font(.callout.weight(.medium))
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
                ModelManagerView(
                    store: controlStore,
                    networkContext: networkContext,
                    telemetry: ModelManagerTelemetry(
                        tokenRates: monitorStore?.currentModelTokenRateAverages ?? [],
                        servingAverages: monitorStore?.modelServingProfitAverages ?? [],
                        networkCapacity: monitorStore?.networkCapacity.value,
                        networkSourceAvailable: monitorStore.map { if case .available = $0.networkCapacity { true } else { false } } ?? false
                    ),
                    refreshDemand: monitorStore.map { store in { await store.refreshNetworkCapacity() } },
                    demandHistory: history,
                    liveSnapshot: monitorStore?.snapshot,
                    providerThroughputPeak: monitorStore?.providerThroughputPeak.value,
                    isVisible: monitorStore?.dashboardVisible ?? true,
                    providerStatus: monitorStore?.snapshot.status ?? .unavailable(reason: "Provider status unavailable"),
                    providerDaemonState: monitorStore?.snapshot.state ?? .unavailable(reason: "Provider activity unavailable")
                )
            } else {
                ContentUnavailableView("Model controls unavailable", systemImage: "cpu",
                                       description: Text("The provider control service is not available. Monitoring continues independently."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await monitorStore?.refreshModelServingProfitability()
        }
    }
}
