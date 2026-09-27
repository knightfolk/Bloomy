import DarkbloomCompanionProtocol
import SwiftUI

struct ModelsView: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        NavigationStack {
            Group {
                if let models = store.snapshot?.models, !models.isEmpty {
                    List(models, id: \.id) { model in
                        HStack(spacing: 12) {
                            Image(systemName: model.active ? "bolt.fill" : model.resident ? "memorychip.fill" : "shippingbox")
                                .foregroundStyle(model.active ? .green : model.resident ? .mint : .secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.name).font(.headline)
                                Text(status(model)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let rate = model.tokenRate {
                                Text("\(rate.formatted(.number.precision(.fractionLength(1)))) tok/s")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } else {
                    ContentUnavailableView("No models reported", systemImage: "shippingbox", description: Text("Refresh the host when its provider is available."))
                }
            }
            .navigationTitle("Models")
            .refreshable { await store.refresh() }
        }
    }

    private func status(_ model: ModelSummary) -> String {
        [model.enabled ? "Enabled" : nil, model.advertised ? "Advertised" : nil,
         model.resident ? "Resident" : nil, model.active ? "Active" : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
