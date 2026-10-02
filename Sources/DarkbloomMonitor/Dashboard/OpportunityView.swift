import DarkbloomTelemetry
import SwiftUI

/// Presentation order is a demand comparison, never an earnings recommendation.
enum OpportunityPresentation {
    static func recommendationTitle(_ outcome: RecommendationOutcome) -> String {
        switch outcome {
        case .insufficientEvidence: "Evidence is incomplete"
        case .stay: "Stay with the current model"
        case .consider(let modelID): "Consider \(modelID)"
        }
    }

    static func factorTitle(_ kind: RecommendationFactorKind) -> String {
        switch kind {
        case .networkDemand: "Network requests"
        case .networkReadiness: "Network accepting"
        case .networkPressure: "Requests per loaded provider"
        case .inventory: "Local inventory"
        case .compatibility: "Runtime compatibility"
        case .readiness: "Locally ready"
        case .memory: "Memory admission"
        case .measuredThroughput: "Measured token rate"
        case .observedWork: "Observed account work"
        }
    }

    static func factorValue(_ factor: RecommendationFactor) -> String? {
        guard factor.freshness == .fresh, let value = factor.numericValue,
              value.isFinite else { return nil }
        switch factor.kind {
        case .networkDemand: return value.formatted(.number.precision(.fractionLength(0)))
        case .networkPressure: return value.formatted(.number.precision(.fractionLength(2)))
        case .networkReadiness, .inventory, .compatibility, .readiness, .memory:
            return value >= 0.5 ? "yes" : "no"
        case .measuredThroughput:
            return value.formatted(.number.precision(.fractionLength(1))) + " tok/s"
        case .observedWork:
            return "$" + (value / 1_000_000).formatted(.number.precision(.fractionLength(2))) + "/job observed"
        }
    }

    static func ordered(_ models: [NetworkModelCapacity]) -> [NetworkModelCapacity] {
        models.filter {
            ModelCatalogVisibility.includes(
                $0.id,
                inUse: $0.ready || $0.canAccept || $0.routableProviders > 0
                    || $0.warmProviders > 0 || $0.runningProviders > 0
                    || $0.activeRequests > 0 || $0.queuedRequests > 0
            )
        }.sorted {
            let left = $0.ready && $0.canAccept, right = $1.ready && $1.canAccept
            if left != right { return left }
            if $0.queuedRequests != $1.queuedRequests { return $0.queuedRequests > $1.queuedRequests }
            let a = $0.demandPerWarmProvider ?? ($0.activeRequests > 0 ? .infinity : 0)
            let b = $1.demandPerWarmProvider ?? ($1.activeRequests > 0 ? .infinity : 0)
            if a != b { return a > b }
            return $0.id < $1.id
        }
    }

    static func demand(_ model: NetworkModelCapacity) -> String {
        guard model.ready && model.canAccept else { return "Not accepting" }
        if model.queuedRequests > 0 { return "Work waiting" }
        switch model.demandBand {
        case .urgent, .high: return "Busy"
        case .moderate: return "Steady"
        case .low: return "Quiet"
        }
    }

    static func name(_ model: NetworkModelCapacity, metadata: CatalogModel?) -> String {
        guard let metadata, metadata.id == model.id, !metadata.displayName.isEmpty else { return model.id }
        return metadata.displayName
    }
}

struct OpportunityView: View {
    @ObservedObject var store: MonitorStore
    let controlStore: ProviderControlStore?
    @State private var showsHistory = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Opportunity").font(.largeTitle.bold())
            Picker("View", selection: $showsHistory) {
                Text("Models").tag(false)
                Text("Network activity").tag(true)
            }.pickerStyle(.segmented)
            if showsHistory {
                HStack {
                    Spacer()
                    Button {
                        Task { await store.manuallyRefreshNetworkSeries() }
                    } label: {
                        Label(store.networkSeriesRefreshing ? "Refreshing…" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(!store.canRefreshNetworkSeries)
                    .accessibilityLabel("Refresh network history")
                    .accessibilityIdentifier("opportunity.history.refresh")
                    .help("Read network activity now, without waiting for the next automatic attempt")
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NetworkHistoryView(source: store.networkSeries, isVisible: store.dashboardVisible)
                        DisclosureGroup("Network infrastructure") {
                            NetworkCacheView(isVisible: store.dashboardVisible)
                                .padding(.top, 8)
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                }
            } else {
                OpportunityModelListView(store: store, controlStore: controlStore)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct OpportunityModelListView: View {
    @ObservedObject var store: MonitorStore
    let controlStore: ProviderControlStore?
    @State private var search = ""
    @State private var refreshing = false

    var body: some View {
        TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 10), isVisible: store.dashboardVisible)) { _ in
            let now = Date()
            VStack(alignment: .leading, spacing: 14) {
                DisclosureGroup {
                    RecommendationEvidenceCard(
                        decision: store.recommendationDecision,
                        history: store.recommendationHistory,
                        historyAvailable: store.recommendationHistoryAvailable
                    )
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Model guidance", systemImage: "checklist").font(.subheadline.weight(.semibold))
                        Text(store.recommendationDecision.map { OpportunityPresentation.recommendationTitle($0.outcome) }
                             ?? "Waiting for evidence")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(12)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
                HStack {
                    TextField("Find a model", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Filter network models")
                    Button {
                        refreshing = true
                        Task {
                            await store.refreshNetworkCapacity()
                            await store.refreshPublicCatalog()
                            refreshing = false
                        }
                    } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(refreshing)
                }
                if let capacity = store.networkCapacity.value {
                    let current = PopupNetworkDemandPresentation.freshness(of: store.networkCapacity, at: now) == .current
                    HStack(spacing: 6) {
                        Circle().fill(current ? Color.green : Color.orange).frame(width: 6, height: 6)
                        Text(current ? "Live network" : "Last known demand")
                        Text("·")
                        Text(capacity.capturedAt, style: .relative)
                        Spacer()
                        Text("Demand first")
                    }.font(.callout).foregroundStyle(.secondary)
                    if !current {
                        Label("Data is out of date. Refresh before choosing a model.", systemImage: "clock")
                            .font(.callout).foregroundStyle(.orange)
                    }
                    if capacity.isDraining {
                        ContentUnavailableView(current ? "Network maintenance" : "Last reported: maintenance",
                            systemImage: "wrench.and.screwdriver", description: Text("Model capacity is temporarily withdrawn."))
                    } else {
                        let models = OpportunityPresentation.ordered(capacity.models).filter { model in
                            search.isEmpty || model.id.localizedCaseInsensitiveContains(search)
                                || OpportunityPresentation.name(model, metadata: metadata(model.id)).localizedCaseInsensitiveContains(search)
                        }
                        GeometryReader { geometry in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    if models.isEmpty {
                                        ContentUnavailableView(search.isEmpty ? "No models reported" : "No matching models",
                                            systemImage: "magnifyingglass", description: Text("Try a different search or refresh the network."))
                                    } else {
                                        LazyVGrid(
                                            columns: Array(repeating: GridItem(.flexible(), spacing: 12),
                                                           count: geometry.size.width >= 500 ? 2 : 1),
                                            alignment: .leading,
                                            spacing: 12
                                        ) {
                                            ForEach(models) { model in
                                                if let controlStore {
                                                    OpportunityLocalModelCard(model: model, controlStore: controlStore,
                                                        metadata: metadata(model.id), price: store.publicPricing.value?.price(for: model.id),
                                                        metadataIsCurrent: catalogCurrent(now), priceIsCurrent: pricingCurrent(now), networkIsCurrent: current)
                                                } else {
                                                    OpportunityModelCard(model: model, local: nil, metadata: metadata(model.id),
                                                        price: store.publicPricing.value?.price(for: model.id), metadataIsCurrent: catalogCurrent(now),
                                                        priceIsCurrent: pricingCurrent(now), networkIsCurrent: current)
                                                }
                                            }
                                        }
                                    }
                                    DisclosureGroup("How to read this") {
                                        VStack(alignment: .leading, spacing: 10) {
                                            Text("Work waiting comes first, then requests per loaded provider. These are network-wide signals, not a prediction of your earnings.")
                                            Text("RAM compares installed memory with the catalog minimum. It does not confirm free memory or runtime compatibility.")
                                            if let controlStore { OpportunityCatalogControls(store: store, controlStore: controlStore) }
                                            if let catalog = store.publicCatalog.value {
                                                Text("Model details last read \(catalog.capturedAt.formatted(date: .omitted, time: .shortened))\(catalogCurrent(now) ? "" : " · stale")")
                                            }
                                        }.font(.callout).foregroundStyle(.secondary).padding(.top, 8)
                                    }.padding(.top, 6)
                                }
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("Waiting for network demand", systemImage: "network",
                        description: Text("Your local provider continues independently. Try Refresh to check again."))
                }
            }
        }
        .task { await store.refreshRecommendation() }
    }

    private func metadata(_ id: String) -> CatalogModel? { store.publicCatalog.value?.models.first { $0.id == id } }
    private func catalogCurrent(_ date: Date) -> Bool {
        guard case .available(let value, _) = store.publicCatalog else { return false }
        return (0...1800).contains(date.timeIntervalSince(value.capturedAt))
    }
    private func pricingCurrent(_ date: Date) -> Bool {
        guard case .available(let value, _) = store.publicPricing else { return false }
        return (0...900).contains(date.timeIntervalSince(value.capturedAt))
    }
}

struct OpportunityCatalogControls: View {
    let store: MonitorStore?
    @ObservedObject var controlStore: ProviderControlStore
    init(store: MonitorStore? = nil, controlStore: ProviderControlStore) {
        self.store = store
        self.controlStore = controlStore
    }
    var body: some View {
        HStack {
            Text(controlStore.errorMessage == nil ? "Local model details" : "Local details need a refresh")
            Spacer()
            Button("Refresh local catalog") { Task { await refreshCatalog() } }
                .disabled(controlStore.operation != .idle || controlStore.pendingConfirmation != nil)
        }
    }
    func refreshCatalog() async {
        await controlStore.refreshPreservingDraft()
        await store?.refreshRecommendation()
    }
}

private struct RecommendationEvidenceCard: View {
    let decision: RecommendationDecision?
    let history: [RecommendationDecision]
    let historyAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Model evidence", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text("Observe only").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            if let decision {
                Text(OpportunityPresentation.recommendationTitle(decision.outcome))
                    .font(.title3.weight(.semibold))
                Text("Confidence: \(decision.confidence.rawValue). No model change is made from this decision.")
                    .font(.callout).foregroundStyle(.secondary)
                if !decision.blockers.isEmpty {
                    Text("Needs: " + decision.blockers.prefix(6).map(\.rawValue).joined(separator: ", "))
                        .font(.callout).foregroundStyle(.secondary)
                }
                let selectedID: String? = {
                    if case .consider(let id) = decision.outcome { return id }
                    return nil
                }()
                let assessments = decision.assessments.sorted { left, right in
                    if left.modelID == selectedID { return true }
                    if right.modelID == selectedID { return false }
                    return left.modelID < right.modelID
                }
                DisclosureGroup("Factors and source times") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(assessments.prefix(4).enumerated()), id: \.offset) { _, assessment in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(assessment.modelID)
                                    .font(.callout.weight(.semibold)).textSelection(.enabled)
                                if !assessment.blockers.isEmpty {
                                    Text("Blocked: " + assessment.blockers.prefix(5).map(\.rawValue).joined(separator: ", "))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(Array(assessment.factors.prefix(10).enumerated()), id: \.offset) { _, factor in
                                    HStack(alignment: .firstTextBaseline) {
                                        Text(OpportunityPresentation.factorTitle(factor.kind))
                                        Spacer(minLength: 8)
                                        Text(factor.freshness.rawValue)
                                            .foregroundStyle(factor.freshness == .fresh ? .primary : .secondary)
                                        if let value = OpportunityPresentation.factorValue(factor) {
                                            Text(value)
                                        }
                                        if let capturedAt = factor.sourceCapturedAt {
                                            Text(capturedAt, style: .relative).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text("Source: \(factor.provenance.rawValue)")
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }.font(.caption).padding(.top, 8)
                }.font(.callout)
            } else {
                Text("Waiting for a network and local inventory check.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup("Recent decisions") {
                if historyAvailable {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(history.suffix(10).reversed()), id: \.id) { entry in
                            HStack {
                                Text(OpportunityPresentation.recommendationTitle(entry.outcome))
                                Spacer()
                                Text(entry.evaluatedAt, style: .relative)
                            }
                        }
                    }.font(.caption).padding(.top, 8)
                } else {
                    Text("Recommendation history is unavailable.")
                        .font(.caption).foregroundStyle(.secondary).padding(.top, 8)
                }
            }.font(.callout)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct OpportunityLocalModelCard: View {
    let model: NetworkModelCapacity
    @ObservedObject var controlStore: ProviderControlStore
    let metadata: CatalogModel?
    let price: CustomerModelPrice?
    let metadataIsCurrent: Bool
    let priceIsCurrent: Bool
    let networkIsCurrent: Bool
    var body: some View {
        let inventory = controlStore.snapshot?.inventory
        let local = ((inventory?.myCatalog ?? []) + (inventory?.available ?? [])).first { $0.catalogID == model.id }
        OpportunityModelCard(model: model, local: local, metadata: metadata, price: price,
            metadataIsCurrent: metadataIsCurrent, priceIsCurrent: priceIsCurrent, networkIsCurrent: networkIsCurrent)
    }
}

struct OpportunityModelCard: View {
    let model: NetworkModelCapacity
    let local: ModelInventoryItem?
    var metadata: CatalogModel? = nil
    var price: CustomerModelPrice? = nil
    var metadataIsCurrent = false
    var priceIsCurrent = false
    var networkIsCurrent = true
    var installedMemoryBytes = ProcessInfo.processInfo.physicalMemory

    private var tint: Color {
        guard networkIsCurrent, model.ready, model.canAccept else { return .secondary }
        return model.queuedRequests > 0 ? .orange : (model.demandBand == .low ? .secondary : .green)
    }
    private var ramFit: CatalogRAMFit {
        CatalogRAMFit.evaluate(modelID: model.id, metadata: metadata, metadataIsCurrent: metadataIsCurrent,
            installedMemoryBytes: installedMemoryBytes)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.headline)
                    .foregroundStyle(tint)
                    .frame(width: 22)
                Text(ModelDisplayName.short(OpportunityPresentation.name(model, metadata: metadata)))
                    .font(.headline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(model.id)
                Spacer(minLength: 0)
            }
            HStack(spacing: 6) {
                Text(OpportunityPresentation.demand(model))
                    .font(.caption.weight(.semibold)).foregroundStyle(tint)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(tint.opacity(0.10), in: Capsule())
                if !networkIsCurrent {
                    Text("Last known").font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            fitLabel.font(.caption)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                metric("In progress", model.activeRequests)
                metric("Waiting", model.queuedRequests)
                metric("Loaded", model.warmProviders)
                metric("Network tok/s", model.aggregateTokensPerSecond)
            }
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.id).font(.callout).textSelection(.enabled)
                    if let metadata {
                        Text("\(metadata.sizeGB.formatted(.number.precision(.fractionLength(1)))) GB download · \(metadata.minimumRAMGB) GB minimum RAM\(metadataIsCurrent ? "" : " · last known")")
                        if let requirements = metadata.requiredProviderCapabilities, !requirements.isEmpty {
                            Text("Requires " + requirements.map {
                                $0 == "apple_m5" ? "Apple M5" : ($0 == "mlx_nax" ? "MLX NAX" : $0)
                            }.joined(separator: ", ") + ". Runtime support is not verified.")
                        }
                    }
                    if let local {
                        Text("Last catalog check: \(local.isDownloaded ? "downloaded" : "not downloaded") · \(local.isEnabled ? "enabled" : "not enabled")")
                    }
                    Text("\(model.routableProviders) routable providers · \(model.canAccept && model.ready ? "accepting requests" : "not accepting requests")")
                    if let pressure = model.demandPerWarmProvider {
                        Text("\(pressure.formatted(.number.precision(.fractionLength(2)))) active or waiting requests per loaded provider")
                    }
                    if let price {
                        Text("Customer price per million tokens\(priceIsCurrent ? "" : " · last known")")
                            .fontWeight(.medium)
                        Text("$\(price.inputUSDPerMillion.formatted()) input · $\(price.outputUSDPerMillion.formatted()) output")
                        Text("Customer prices are not your provider payout.")
                    }
                    Text("RAM minimum is one check, not a guarantee that this model can run alongside your current models.")
                }.font(.callout).foregroundStyle(.secondary).padding(.top, 8)
            }.font(.callout).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
    }

    @ViewBuilder private var fitLabel: some View {
        switch ramFit {
        case .minimumMet:
            if metadata?.requiredProviderCapabilities?.isEmpty == false {
                Label("RAM meets minimum · check runtime", systemImage: "memorychip").foregroundStyle(.secondary)
            } else {
                Label("RAM meets minimum", systemImage: "memorychip").foregroundStyle(.secondary)
            }
        case .belowMinimum:
            Label("Needs more RAM", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        case .unavailable:
            Label("RAM check unavailable", systemImage: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number).font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func metric(_ title: String, _ value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value, format: .number.precision(.fractionLength(0...1)))
                .font(.headline).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("Aggregate network throughput across providers, not the speed of this Mac")
        .accessibilityElement(children: .combine)
    }
}
