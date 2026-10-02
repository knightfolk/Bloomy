import DarkbloomTelemetry
import SwiftUI

enum PopupModelModePresentation: Equatable {
    case automatic
    case unavailable

    static func make(
        status: SourceAvailability<StatusSnapshot>,
        currentTime: Date = Date()
    ) -> Self {
        guard case .available(let status, let capturedAt) = status else {
            return .unavailable
        }
        let age = currentTime.timeIntervalSince(capturedAt)
        guard age.isFinite,
              age >= 0,
              age <= StatusSnapshot.maximumAge,
              status.configuredModel?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "auto-select"
        else { return .unavailable }
        return .automatic
    }
}

struct PopupModelStatusPresentation: Equatable {
    let statusName: String
    let supplementaryLabel: String?
    let systemImage: String?

    static func make(for state: DashboardModelState) -> Self {
        switch state {
        case .active:
            Self(statusName: "active", supplementaryLabel: nil, systemImage: nil)
        case .loadedIdle:
            Self(statusName: "loaded but idle", supplementaryLabel: nil, systemImage: nil)
        case .availableUnloaded:
            Self(
                statusName: "on demand",
                supplementaryLabel: "On demand",
                systemImage: "arrow.triangle.2.circlepath"
            )
        }
    }
}

enum PopupModelPresentation: Equatable {
    case models([DashboardModel])
    case unavailable

    static func make(input: PopupModelSourceInput, currentTime: Date = Date()) -> Self {
        let statusEnabledFilter = enabledFilter(from: input.status)
        let lifecycleInput = ProviderLifecycleSourceInput(
            daemonState: input.daemonState,
            status: input.status,
            controlDaemonState: input.controlSnapshot?.sources.daemon,
            currentTime: currentTime
        )

        if lifecycleInput.providerKnownRunning == false {
            return configuredModels(
                filter: controlEnabledFilter(
                    from: input.controlSnapshot,
                    fallback: statusEnabledFilter
                )
            )
        }

        // Provider-control residency is an independent local source. Prefer it
        // over telemetry whenever its two residency records are still fresh so
        // an old daemon snapshot cannot make a pill look authoritative.
        if let control = freshControlResidency(
            from: input.controlSnapshot,
            at: currentTime
        ) {
            return .models(DashboardModelDeriver.models(
                enabledFilter: controlEnabledFilter(
                    from: input.controlSnapshot,
                    fallback: statusEnabledFilter
                ),
                loadedModels: Array(control.residentModelIDs).sorted(),
                warmModels: [],
                slotModels: [],
                currentModel: control.daemonState?.currentModel,
                inferenceActive: control.daemonState?.inferenceActive ?? false
            ))
        }

        // Telemetry remains a valid fallback when both of its model records
        // are fresh. A stale or unavailable record is never promoted to a
        // loaded/active pill merely because the provider status says running.
        if let telemetry = freshTelemetryResidency(
            from: input,
            at: currentTime
        ) {
            return .models(DashboardModelDeriver.models(
                enabledFilter: statusEnabledFilter,
                loadedModels: telemetry.loadedModels,
                warmModels: telemetry.daemonState.warmModels,
                slotModels: telemetry.daemonState.slots.map(\.model),
                currentModel: telemetry.daemonState.currentModel,
                inferenceActive: telemetry.daemonState.inferenceActive
            ))
        }

        return .unavailable
    }

    private struct ControlResidency {
        let residentModelIDs: Set<String>
        let daemonState: DaemonState?
    }

    private struct TelemetryResidency {
        let daemonState: DaemonState
        let loadedModels: [String]
    }

    private static func freshControlResidency(
        from snapshot: ProviderControlSnapshot?,
        at currentTime: Date
    ) -> ControlResidency? {
        guard let snapshot else { return nil }
        let daemonSource = snapshot.sources.daemon.evaluated(
            at: currentTime,
            invalidReason: "Provider activity timestamp is invalid",
            staleReason: "Provider activity is stale",
            futureReason: "Provider activity timestamp is in the future"
        )
        let loadedSource = snapshot.sources.loadedModels.evaluated(
            at: currentTime,
            invalidReason: "Loaded model state timestamp is invalid",
            staleReason: "Loaded model state is stale",
            futureReason: "Loaded model state timestamp is in the future"
        )
        guard daemonSource.isMarkedFresh, loadedSource.isMarkedFresh else {
            return nil
        }
        return ControlResidency(
            residentModelIDs: snapshot.residentModelIDs,
            daemonState: snapshot.daemonState
        )
    }

    private static func freshTelemetryResidency(
        from input: PopupModelSourceInput,
        at currentTime: Date
    ) -> TelemetryResidency? {
        guard case .available(let daemon, let daemonCapturedAt) = input.daemonState,
              case .available(let loaded, let loadedCapturedAt) = input.loadedModels,
              fresh(capturedAt: daemonCapturedAt, at: currentTime),
              fresh(capturedAt: loadedCapturedAt, at: currentTime),
              fresh(timestamp: daemon.writtenAt, at: currentTime),
              loaded.updatedAt.isFinite,
              daemon.startedAt.isFinite,
              loaded.updatedAt >= daemon.startedAt,
              loaded.updatedAt <= currentTime.timeIntervalSince1970
        else { return nil }
        return TelemetryResidency(
            daemonState: daemon,
            loadedModels: loaded.models
        )
    }

    private static func fresh(capturedAt: Date, at currentTime: Date) -> Bool {
        fresh(timestamp: capturedAt.timeIntervalSince1970, at: currentTime)
    }

    private static func fresh(timestamp: TimeInterval, at currentTime: Date) -> Bool {
        guard timestamp.isFinite,
              currentTime.timeIntervalSince1970.isFinite
        else { return false }
        let age = currentTime.timeIntervalSince1970 - timestamp
        return age.isFinite && age >= 0 && age <= ProviderControlSourceState.maximumEvidenceAge
    }

    private static func configuredModels(filter: String?) -> Self {
        guard filter?.split(separator: ",").contains(where: {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) == true else { return .unavailable }
        return .models(DashboardModelDeriver.models(
            enabledFilter: filter,
            loadedModels: [],
            warmModels: [],
            slotModels: [],
            currentModel: nil,
            inferenceActive: false
        ))
    }

    private static func enabledFilter(
        from availability: SourceAvailability<StatusSnapshot>
    ) -> String? {
        guard case .available(let status, _) = availability else { return nil }
        return status.enabledModelFilter
    }

    private static func controlEnabledFilter(
        from snapshot: ProviderControlSnapshot?,
        fallback: String?
    ) -> String? {
        guard let snapshot else { return fallback }
        // The popup represents this provider's saved local selection. The
        // available section is the broader catalog and must not expand the
        // provider filter with models the user did not enable locally.
        let catalogModels = snapshot.inventory.myCatalog
            .filter(\.isEnabled)
            .map(\.catalogID)
        if !catalogModels.isEmpty {
            return catalogModels.joined(separator: ",")
        }
        let savedModels = snapshot.draft.original.enabled
        return savedModels.isEmpty ? fallback : savedModels.joined(separator: ",")
    }

}

struct PopupModelSourceInput: Equatable {
    let daemonState: SourceAvailability<DaemonState>
    let loadedModels: SourceAvailability<LoadedModelsState>
    let status: SourceAvailability<StatusSnapshot>
    let controlSnapshot: ProviderControlSnapshot?

    init(
        snapshot: TelemetrySnapshot,
        controlSnapshot: ProviderControlSnapshot? = nil
    ) {
        daemonState = snapshot.state
        loadedModels = snapshot.loadedModels
        status = snapshot.status
        self.controlSnapshot = controlSnapshot
    }

    init(
        daemonState: SourceAvailability<DaemonState>,
        loadedModels: SourceAvailability<LoadedModelsState>,
        status: SourceAvailability<StatusSnapshot>,
        controlSnapshot: ProviderControlSnapshot? = nil
    ) {
        self.daemonState = daemonState
        self.loadedModels = loadedModels
        self.status = status
        self.controlSnapshot = controlSnapshot
    }
}

struct PopupEarningsMetrics: Equatable {
    let totalUSD: Double
    let perHourUSD: Double

    static func make(from summary: ObservedEarningsWindow?) -> Self? {
        guard let summary,
              summary.microUSD >= 0,
              let perHour = EarningsHourlyRate.derive(
                  microUSD: summary.microUSD,
                  observedSeconds: summary.observedSeconds
              )
        else { return nil }
        return Self(
            totalUSD: Double(summary.microUSD) / 1_000_000,
            perHourUSD: perHour
        )
    }
}

struct PopupWeekEarningsMetric: Equatable {
    let title: String
    let totalUSD: Double

    static func make(from summary: CalendarWeekEarningsSummary?) -> Self? {
        guard let summary, summary.microUSD >= 0 else { return nil }
        return Self(
            title: summary.isComplete ? "This week" : "Observed this week",
            totalUSD: Double(summary.microUSD) / 1_000_000
        )
    }
}

struct PopupNetworkDemandRow: Equatable, Identifiable {
    let id: String
    let band: NetworkDemandBand
    let activeRequests: Int
    let queuedRequests: Int
    let warmProviders: Int
}

enum PopupNetworkDemandPresentation {
    enum Freshness: Equatable {
        case current
        case stale
    }

    static func freshness(
        of availability: SourceAvailability<NetworkCapacitySnapshot>,
        at now: Date
    ) -> Freshness? {
        switch availability {
        case .available(let capacity, _):
            return capacity.isFresh(at: now) ? .current : .stale
        case .stale:
            return .stale
        case .unavailable:
            return nil
        }
    }

    static func rows(
        capacity: NetworkCapacitySnapshot,
        enabledModelIDs: [String]
    ) -> [PopupNetworkDemandRow] {
        let enabled = Set(enabledModelIDs)
        return capacity.models
            .filter { enabled.contains($0.id) }
            .map {
                PopupNetworkDemandRow(
                    id: $0.id,
                    band: $0.demandBand,
                    activeRequests: $0.activeRequests,
                    queuedRequests: $0.queuedRequests,
                    warmProviders: $0.warmProviders
                )
            }
            .sorted {
                let left = rank($0.band)
                let right = rank($1.band)
                if left != right { return left < right }
                let leftWork = Double($0.activeRequests) + Double($0.queuedRequests)
                let rightWork = Double($1.activeRequests) + Double($1.queuedRequests)
                if leftWork != rightWork { return leftWork > rightWork }
                return $0.id.localizedStandardCompare($1.id) == .orderedAscending
            }
    }

    static func row(
        for modelID: String,
        in capacity: NetworkCapacitySnapshot
    ) -> PopupNetworkDemandRow? {
        guard let model = capacity.models.first(where: { $0.id == modelID }) else {
            return nil
        }
        return PopupNetworkDemandRow(
            id: model.id,
            band: model.demandBand,
            activeRequests: model.activeRequests,
            queuedRequests: model.queuedRequests,
            warmProviders: model.warmProviders
        )
    }

    private static func rank(_ band: NetworkDemandBand) -> Int {
        switch band {
        case .urgent: 0
        case .high: 1
        case .moderate: 2
        case .low: 3
        }
    }
}

private struct PopupAvailableDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                    configuration.label
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityValue(configuration.isExpanded ? "Expanded" : "Collapsed")
            if configuration.isExpanded {
                configuration.content
            }
        }
    }
}

/// A hidden popup retains its view state, but schedules no recurring updates.
struct PopoverTimelineSchedule: TimelineSchedule {
    let isVisible: Bool

    func entries(from startDate: Date, mode: TimelineScheduleMode) -> Entries {
        Entries(nextDate: startDate, repeats: isVisible)
    }

    struct Entries: Sequence, IteratorProtocol {
        var nextDate: Date?
        let repeats: Bool

        mutating func next() -> Date? {
            guard let date = nextDate else { return nil }
            nextDate = repeats ? date.addingTimeInterval(1) : nil
            return date
        }
    }
}

struct MonitorPopover: View {
    private static let popupWidth: CGFloat = 560
    private static let modelCardWidth: CGFloat = (popupWidth - 32 - 2 - 16) / 3
    @ObservedObject var cliUpdates = CLIUpdateStatusStore.shared
    @ObservedObject var store: MonitorStore
    @EnvironmentObject private var controlStore: ProviderControlStore
    let isVisible: Bool
    let openSettings: (SettingsPage?) -> Void
    let openDashboard: () -> Void
    let openModels: () -> Void
    let openHosting: () -> Void
    @State private var showsFans = false
    @State private var pendingSingleModelID: String?
    @State private var pendingSwapModelID: String?
    @AppStorage("popover.availableExpanded") private var availableExpanded = false
    private static let machineName = Host.current().localizedName ?? "This Mac"

    init(
        store: MonitorStore,
        isVisible: Bool = true,
        openSettings: @escaping (SettingsPage?) -> Void = { _ in },
        openDashboard: @escaping () -> Void = {},
        openModels: @escaping () -> Void = {},
        openHosting: @escaping () -> Void = {}
    ) {
        self.store = store
        self.isVisible = isVisible
        self.openSettings = openSettings
        self.openDashboard = openDashboard
        self.openModels = openModels
        self.openHosting = openHosting
    }

    var body: some View {
        TimelineView(PopoverTimelineSchedule(isVisible: isVisible)) { _ in
            // Published samples can arrive between timeline ticks. Evaluate
            // freshness at render time, not against the previous tick.
            content(currentTime: Date())
        }
    }

    private func content(currentTime: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            providerHeader(currentTime: currentTime)
            HStack(spacing: 14) {
                CompactGPUGauge(usage: store.gpuUsage, now: currentTime)
                Divider().frame(height: 38)
                if let extras = store.providerExtras {
                    PopupFanSummary(store: extras, now: currentTime, isVisible: isVisible) { showsFans = true }
                } else {
                    Label("Fan readings unavailable", systemImage: "fan")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            HStack(spacing: 10) {
                PopupAutoModeControl(store: controlStore, openModels: openModels)
                if let nudge = store.inactivityNudge {
                    PopupNudgeControl(store: nudge)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
            }
            if case .available(.updateAvailable(_, let latest), let checkedAt) = cliUpdates.status,
               currentTime.timeIntervalSince(checkedAt) < 6 * 60 * 60 {
                Button("CLI \(latest) available") { openSettings(.updates) }.font(.caption)
            }
            if let error = controlStore.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let swap = controlStore.swapStatus {
                ModelSwapFeedback(status: swap, nudgeStatus: controlStore.swapNudgeStatus, openHosting: openHosting)
            }
            if let warmup = controlStore.switchWarmupStatus {
                SwitchWarmupFeedback(status: warmup)
            }
            if let attention = store.menuAttention {
                Label(attention.detail, systemImage: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("popover.attention")
            }
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    compactModels(currentTime: currentTime)
                    financePanel(currentTime: currentTime)
                    compactJobs
                    if case .available(let capacity, _) = store.networkCapacity,
                       capacity.isDraining, capacity.isFresh(at: currentTime) {
                        Label("Network maintenance", systemImage: "wrench.and.screwdriver")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }.padding(.trailing, 2)
            }
            .frame(height: popupBodyHeight(currentTime: currentTime))
        }
        .tint(isOffline(at: currentTime) ? .gray : .accentColor)
        .compositingGroup()
        .saturation(isOffline(at: currentTime) ? 0 : 1)
        .padding(16)
        .frame(width: Self.popupWidth, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: $showsFans) {
            if let extras = store.providerExtras {
                PopupFanPanel(extras: extras, isVisible: isVisible) { label, mutation in
                    await controlStore.performSettingsMutation(label, mutation: mutation)
                }
            }
        }
        .confirmationDialog(
            "Use \(ModelDisplayName.short(pendingSingleModelID ?? "model")) alone?",
            isPresented: Binding(
                get: { pendingSingleModelID != nil },
                set: { if !$0 { pendingSingleModelID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let modelID = pendingSingleModelID {
                Button("Use only this model") {
                    pendingSingleModelID = nil
                    Task { await controlStore.switchToSingleModel(modelID) }
                }
            }
            Button("Cancel", role: .cancel) { pendingSingleModelID = nil }
        } message: {
            Text("Other advertised models stop receiving new work. Accepted work finishes before switching. If a Chat API key is saved, one free test request will try to load this model on an owned provider. You can restore the saved selection in Models.")
        }
        .confirmationDialog(
            "Swap to \(ModelDisplayName.short(pendingSwapModelID ?? "model"))?",
            isPresented: Binding(
                get: { pendingSwapModelID != nil },
                set: { if !$0 { pendingSwapModelID = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let modelID = pendingSwapModelID {
                Button("Request swap") {
                    pendingSwapModelID = nil
                    Task { await controlStore.swapToModel(modelID) }
                }
            }
            Button("Cancel", role: .cancel) { pendingSwapModelID = nil }
        } message: {
            Text("Keep all advertised models available. Bloomy loads this model through this Mac’s local API, verifies it is ready, then sends one network self-route nudge using your saved Nudge key. If work arrives, the nudge is skipped. Incoming work can change the loaded model again. The local swap still works without a Nudge key.")
        }
        .task { await store.refreshModelServingProfitability() }
    }

    private func providerRunning(at now: Date) -> Bool? {
        guard case .available(_, let capturedAt) = store.snapshot.status,
              (0...10).contains(now.timeIntervalSince(capturedAt)) else { return nil }
        return ProviderLifecycleSourceInput(daemonState: store.snapshot.state, status: store.snapshot.status,
            controlDaemonState: controlStore.snapshot?.sources.daemon,
            currentTime: now).providerKnownRunning
    }

    private func isOffline(at now: Date) -> Bool { providerRunning(at: now) == false }

    private func displayedSelection(at now: Date) -> [String]? {
        if !isOffline(at: now), let advertised = advertisedIDs(at: now) { return advertised }
        if let control = controlStore.snapshot {
            return control.inventory.myCatalog.filter { $0.isEnabled }.map(\.catalogID).sorted()
        }
        return nil
    }

    private func popupBodyHeight(currentTime: Date) -> CGFloat {
        let advertised = displayedSelection(at: currentTime) ?? []
        let available = availableIDs(excluding: advertised)
        let rows = (advertised.count + 2) / 3
            + (availableExpanded ? (available.count + 2) / 3 : 0)
        return min(470, CGFloat(rows) * (CompactModelCard.popupHeight + 8) + 190)
    }

    private func advertisedIDs(at now: Date) -> [String]? {
        PopupModelGroups.advertised(snapshot: store.snapshot, control: controlStore.snapshot, now: now)
    }

    private func availableIDs(excluding advertised: [String]) -> [String] {
        let currentModelIDs = Set(models.map(\.name))
        let local = controlStore.snapshot?.inventory.myCatalog.filter { item in
            ModelCatalogVisibility.includes(
                item.catalogID,
                inUse: item.isEnabled || item.isPreloaded || item.enabledSelector != nil
                    || item.preloadSelector != nil || item.liveState != .unloaded
                    || currentModelIDs.contains(item.catalogID)
            )
        }.map(\.catalogID) ?? Array(currentModelIDs)
        return Array(Set(local).subtracting(advertised)).sorted()
    }

    private func compactModels(currentTime: Date) -> some View {
        let advertised = displayedSelection(at: currentTime)
        let available = availableIDs(excluding: advertised ?? [])
        let liveSelectionUnknown = advertisedIDs(at: currentTime) == nil
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(isOffline(at: currentTime) ? "Selected · Offline"
                      : liveSelectionUnknown ? "Saved models · Live status unavailable" : "Advertised",
                      systemImage: "antenna.radiowaves.left.and.right")
                    .font(.subheadline.weight(.semibold))
                if controlStore.draft?.originalMaxModelSlots == 1 {
                    Label("1 slot saved", systemImage: "1.circle")
                        .font(.caption).foregroundStyle(.secondary)
                        .help("Saved capacity is one resident model. A restart is needed after changing the limit.")
                }
                Spacer()
                if let advertised { Text(advertised.count.formatted()).foregroundStyle(.secondary) }
                Button {
                    Task { await controlStore.refreshPreservingDraft() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(controlStore.operation != .idle)
                .help("Refresh model controls")
                .accessibilityLabel("Refresh model controls")
                .accessibilityIdentifier("popover.models.refresh")
            }
            if let advertised {
                if advertised.isEmpty {
                    Text(isOffline(at: currentTime) ? "No saved models selected" : "No models advertised")
                        .font(.caption).foregroundStyle(.secondary)
                } else { modelGrid(advertised, now: currentTime) }
            } else {
                Label("Advertising state unavailable", systemImage: "clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup(isExpanded: $availableExpanded) {
                if available.isEmpty {
                    Text("No other downloaded models").font(.caption).foregroundStyle(.secondary)
                } else {
                    modelGrid(available, now: currentTime, offersActivation: true)
                }
            } label: {
                HStack {
                    Label("Available on this Mac", systemImage: "internaldrive")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(available.count.formatted()).foregroundStyle(.secondary)
                }
            }
            .disclosureGroupStyle(PopupAvailableDisclosureStyle())
            .accessibilityIdentifier("popover.availableModels")
        }
    }

    private func modelGrid(_ ids: [String], now: Date, offersActivation: Bool = false) -> some View {
        let liveSelectionUnknown = isOffline(at: now) || advertisedIDs(at: now) == nil
        return LazyVGrid(columns: Array(repeating: GridItem(.fixed(Self.modelCardWidth), spacing: 8), count: 3),
                         alignment: .leading, spacing: 8) {
            ForEach(ids, id: \.self) { id in
                let state = models.first(where: { $0.name == id })?.state
                let downloaded = controlStore.snapshot?.inventory.myCatalog.first(where: { $0.catalogID == id })?.isDownloaded == true
                let status = liveSelectionUnknown
                    ? (offersActivation ? (downloaded ? "Downloaded" : "Live state unknown")
                       : isOffline(at: now) ? "Ready when online" : "Saved selection")
                    : (offersActivation && state == nil && downloaded ? "Downloaded" : modelStateLabel(state))
                CompactModelCard(modelID: id, status: status,
                                 tint: liveSelectionUnknown ? .secondary : state == .active ? .green : state == .loadedIdle ? .orange : .secondary,
                                 metrics: modelMetrics(id), selected: !liveSelectionUnknown && state == .active,
                                 compact: true, compactWidth: Self.modelCardWidth,
                                 activate: offersActivation ? { _ = Task<Void, Never> { await controlStore.activateModel(id, providerKnownRunning: providerRunning(at: now)) } } : nil,
                                 activationUnavailableReason: controlStore.activationUnavailableReason(for: id, providerKnownRunning: providerRunning(at: now)),
                                 activationHelp: isOffline(at: now) ? "Save for the next provider start" : "Advertise this model alongside the others",
                                 swapModel: !liveSelectionUnknown && !offersActivation && state != .active && state != .loadedIdle
                                    ? { pendingSwapModelID = id } : nil,
                                 swapUnavailableReason: controlStore.swapModelUnavailableReason(for: id),
                                 switchModel: !liveSelectionUnknown && displayedSelection(at: now) != [id]
                                    ? { pendingSingleModelID = id } : nil,
                                 switchUnavailableReason: controlStore.singleModelSwitchUnavailableReason(for: id))
            }
        }
    }

    private func modelStateLabel(_ state: DashboardModelState?) -> String {
        switch state {
        case .active: "Serving now"
        case .loadedIdle: "In memory"
        case .availableUnloaded: "Loads on request"
        case nil: "State unavailable"
        }
    }

    private func modelMetrics(_ id: String) -> [ModelCardMetric] {
        var metrics: [ModelCardMetric] = []
        if let rate = store.currentModelTokenRateAverages.first(where: { $0.model == id }) {
            metrics.append(ModelCardMetric(id: "speed", symbol: "speedometer",
                value: String(format: "%.1f", rate.tokensPerSecond), caption: "avg tok/s today"))
        }
        if let average = store.modelServingProfitAverages.first(where: { $0.model == id }) {
            let value = average.profitUSDPerActiveHour ?? average.grossUSDPerActiveHour
            metrics.append(ModelCardMetric(id: "earnings", symbol: "dollarsign.circle",
                value: value.formatted(.currency(code: "USD").precision(.fractionLength(2...4))),
                caption: average.profitUSDPerActiveHour == nil ? "derived gross / active h" : "est. net / active h"))
        }
        if metrics.isEmpty {
            metrics.append(ModelCardMetric(id: "unknown", symbol: "clock", value: "Learning", caption: "No measured averages"))
        }
        return metrics
    }

    private func financePanel(currentTime: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Earnings", systemImage: "chart.line.uptrend.xyaxis")
                .font(.subheadline.weight(.semibold))
            if earningsMetrics != nil || weekEarningsMetric != nil {
                compactEarnings
            } else {
                Text("Waiting for earnings history").font(.caption).foregroundStyle(.secondary)
            }
            if UserDefaults.standard.bool(forKey: "electricity.enabled") {
                Divider()
                EnergySummaryView(reading: store.currentEnergyReading,
                                  earnings: store.currentEnergyEarnings, now: currentTime,
                                  waitingMessage: store.energy?.issue ?? "Collecting matched earnings data")
            } else {
                Button { openSettings(.electricity) } label: {
                    Label("Set up electricity estimate", systemImage: "bolt")
                }.font(.caption).buttonStyle(.plain).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
    }

    private var compactEarnings: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            if let metrics = earningsMetrics {
                compactAmount("Observed today", value: metrics.totalUSD)
                compactAmount("Per observed h", value: metrics.perHourUSD)
            }
            if let week = weekEarningsMetric {
                compactAmount(week.title, value: week.totalUSD)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func demandColor(_ band: NetworkDemandBand) -> Color {
        switch band {
        case .urgent: .red
        case .high: .orange
        case .moderate: .blue
        case .low: .secondary
        }
    }

    private func compactAmount(_ label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value, format: .currency(code: "USD").precision(.fractionLength(2...4)))
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var compactJobs: some View {
        if let summary = jobSummary {
            HStack {
                Text("\(summary.completedToday) jobs today")
                Spacer()
                if let averageJobsPerDay {
                    Text("\(averageJobsPerDay, specifier: "%.1f") / day avg")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            DarkbloomLogo(
                image: DarkbloomLogoAsset.sourceImage,
                tint: logoColor
            )
            .frame(width: 22, height: 25)

            Text(MonitorApplicationIdentity.displayName)
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Spacer()

            Button(action: openDashboard) { Image(systemName: "rectangle.grid.2x2") }
                .help("Open dashboard").accessibilityLabel("Open dashboard")
            Button { openSettings(nil) } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Settings")
            .accessibilityLabel("Settings")
            .accessibilityIdentifier("dashboard.settings")

            Button(role: .destructive) {
                Task { await store.quit() }
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .help("Quit \(MonitorApplicationIdentity.displayName)")
            .accessibilityLabel("Quit \(MonitorApplicationIdentity.displayName)")
            .accessibilityIdentifier("dashboard.quit")
        }
    }

    private func providerHeader(currentTime: Date) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Label(Self.machineName, systemImage: "desktopcomputer")
                    .font(.headline).lineLimit(1).help(Self.machineName)
                Text(isOffline(at: currentTime) ? "Offline · selections ready for next start" : store.snapshot.menuStatus.accessibilityLabel)
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                ProviderLifecycleControls(
                    store: controlStore,
                    snapshot: store.snapshot,
                    currentTime: currentTime
                )
                if let feedback = ProviderLifecycleFeedbackPresentation.make(
                    operation: controlStore.operation,
                    errorMessage: controlStore.errorMessage
                ), feedback.isError {
                    Text(feedback.message)
                        .font(.caption)
                        .foregroundStyle(feedback.isError ? Color.red : Color.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }

    private var throughputSection: some View {
        DashboardSection(title: "Throughput", systemImage: "speedometer") {
            let breakdown = ModelTokenRatePresentation.breakdown(
                store.currentModelTokenRateAverages
            )
            if breakdown.isEmpty {
                HStack(spacing: 12) {
                    currentRateCard
                    if let averageTokenRate {
                        InfographicMetricCard(
                            title: "Today's average",
                            unit: "tok/sec",
                            accessibilityValue: "\(averageTokenRate) tokens per second today"
                        ) {
                            Text(
                                averageTokenRate,
                                format: .number.precision(.fractionLength(1))
                            )
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    currentRateCard
                    ModelTokenRatePanel(averages: breakdown)
                }
            }
        }
    }

    private var currentRateCard: some View {
        InfographicMetricCard(
            title: "Activity",
            unit: nil,
            accessibilityValue: currentActivityLabel
        ) {
            Text(currentActivityLabel)
        }
    }

    private var currentActivityLabel: String {
        guard let state = store.snapshot.state.value else { return "Unavailable" }
        return state.inferenceActive ? "Working" : "Idle"
    }

    private func earningsSection(
        _ metrics: PopupEarningsMetrics?,
        week: PopupWeekEarningsMetric?
    ) -> some View {
        DashboardSection(title: "Earnings", systemImage: "dollarsign.circle.fill") {
            VStack(alignment: .leading, spacing: 12) {
                if let metrics {
                    HStack(spacing: 12) {
                        InfographicMetricCard(
                            title: "Today",
                            unit: nil,
                            accessibilityValue: "\(metrics.totalUSD) dollars earned today"
                        ) {
                            Text(
                                metrics.totalUSD,
                                format: .currency(code: "USD").precision(.fractionLength(2))
                            )
                        }

                        InfographicMetricCard(
                            title: "Average",
                            unit: "per hour",
                            accessibilityValue: "\(metrics.perHourUSD) dollars per observed hour today"
                        ) {
                            Text(
                                metrics.perHourUSD,
                                format: .currency(code: "USD").precision(.fractionLength(2))
                            )
                        }
                    }
                }

                if let week {
                    InfographicMetricCard(
                        title: week.title,
                        unit: nil,
                        accessibilityValue: "\(week.totalUSD) dollars earned \(week.title.lowercased())"
                    ) {
                        Text(
                            week.totalUSD,
                            format: .currency(code: "USD").precision(.fractionLength(2))
                        )
                    }
                }
            }
        }
    }

    private var jobsSection: some View {
        DashboardSection(title: "Completed jobs", systemImage: "checkmark.circle.fill") {
            HStack(spacing: 12) {
                InfographicMetricCard(
                    title: "Today",
                    unit: nil,
                    accessibilityValue: jobSummary.map { "\($0.completedToday) jobs" }
                        ?? "Not available"
                ) {
                    if let summary = jobSummary {
                        Text(summary.completedToday, format: .number.grouping(.automatic))
                    } else {
                        Text("—")
                    }
                }

                InfographicMetricCard(
                    title: "7-day average",
                    unit: averageJobsPerDay == nil ? nil : "per day",
                    accessibilityValue: averageJobsPerDay.map { "\($0) jobs per day" }
                        ?? "Not available"
                ) {
                    if let averageJobsPerDay {
                        Text(
                            averageJobsPerDay,
                            format: .number.precision(.fractionLength(1))
                        )
                    } else {
                        Text("—")
                    }
                }
            }
        }
    }

    private func modelsSection(currentTime: Date) -> some View {
        DashboardSection(title: "Models", systemImage: "cpu") {
            switch modelPresentation(at: currentTime) {
            case .unavailable:
                Text("Model state unavailable")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            case .models(let models) where models.isEmpty:
                Text("No models reported")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            case .models(let models):
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(models) { model in
                        HStack(spacing: 8) {
                            ModelStatusPill(model: model)
                            Spacer(minLength: 6)
                        }
                    }
                }
            }
        }
    }

    private func networkDemandSection(currentTime: Date) -> some View {
        DashboardSection(title: "Network demand", systemImage: "network") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(networkDemandRows(at: currentTime)) { row in
                    NetworkDemandRow(
                        row: row,
                        isRecommended: opportunityRecommendation(at: currentTime)?.modelID == row.id
                    )
                }
                if PopupNetworkDemandPresentation.freshness(
                    of: store.networkCapacity,
                    at: currentTime
                ) == .stale {
                    Text("Last known network sample · stale")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func networkDemandRows(at _: Date) -> [PopupNetworkDemandRow] {
        guard let capacity = store.networkCapacity.value else { return [] }
        return PopupNetworkDemandPresentation.rows(
            capacity: capacity,
            enabledModelIDs: enabledNetworkModelIDs
        )
    }

    private func opportunityRecommendation(at currentTime: Date) -> ModelOpportunityRecommendation? {
        guard case .available(let capacity, _) = store.networkCapacity,
              capacity.isFresh(at: currentTime)
        else { return nil }
        return ModelOpportunityRanker.recommend(
            capacity: capacity,
            enabledModelIDs: enabledNetworkModelIDs,
            observedWork: store.modelWorkEarnings,
            tokenRates: store.modelTokenRateAverages,
            now: currentTime,
            calendar: .current
        )
    }

    private var enabledNetworkModelIDs: [String] {
        if let inventory = controlStore.snapshot?.inventory.myCatalog {
            let downloaded = Set(inventory.filter(\.isEnabled).map(\.catalogID))
            let configured = Set(controlStore.snapshot?.draft.original.enabled ?? [])
            return Array(downloaded.union(configured)).sorted()
        }
        return models.map(\.name)
    }

    private func inlineNetworkDemand(for modelID: String) -> PopupNetworkDemandRow? {
        guard let capacity = store.networkCapacity.value else { return nil }
        return PopupNetworkDemandPresentation.row(for: modelID, in: capacity)
    }

    private var averageTokenRate: Double? {
        store.currentDayAverageTokenRate
    }

    private var jobSummary: JobCompletionSummary? {
        store.currentJobSummary
    }

    private var averageJobsPerDay: Double? {
        jobSummary?.averagePerDay
    }

    private var earningsMetrics: PopupEarningsMetrics? {
        PopupEarningsMetrics.make(from: store.currentTodayEarnings)
    }

    private var weekEarningsMetric: PopupWeekEarningsMetric? {
        PopupWeekEarningsMetric.make(from: store.currentWeekEarnings)
    }

    private func modelPresentation(at currentTime: Date = Date()) -> PopupModelPresentation {
        .make(
            input: PopupModelSourceInput(
                snapshot: store.snapshot,
                controlSnapshot: controlStore.snapshot
            ),
            currentTime: currentTime
        )
    }

    private func modelModePresentation(at currentTime: Date) -> PopupModelModePresentation {
        .make(status: store.snapshot.status, currentTime: currentTime)
    }

    private var models: [DashboardModel] {
        guard case .models(let models) = modelPresentation() else { return [] }
        return models
    }

    private var logoColor: Color {
        switch models.first?.state {
        case .active: .green
        case .loadedIdle: .yellow
        case .availableUnloaded, nil: .secondary
        }
    }

}

private struct DashboardSection<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct InfographicMetricCard<Value: View>: View {
    let title: String
    let unit: String?
    let accessibilityValue: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                value()
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                if let unit {
                    Text(unit)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
        .padding(12)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityValue)
    }
}

private struct ModelTokenRatePanel: View {
    let averages: [ModelTokenRateAverage]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today's average by model")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)

            ForEach(averages, id: \.model) { average in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(average.model)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Text(average.tokensPerSecond, format: .number.precision(.fractionLength(1)))
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("tok/sec")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(average.model)
                .accessibilityValue("\(average.tokensPerSecond) tokens per second today")
            }
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct NetworkDemandRow: View {
    let row: PopupNetworkDemandRow
    let isRecommended: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(row.id)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .truncationMode(.middle)
            if isRecommended {
                Image(systemName: "star.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                    .help("Demand-first suggestion; ties use fresh observed work per job and throughput when available. Partial observations are not a profitability or hardware-fit guarantee.")
                    .accessibilityLabel("Demand-first suggestion, not a profitability guarantee")
            }
            Spacer(minLength: 6)
            Text(row.band.rawValue.capitalized)
                .font(.caption2.weight(.bold))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(bandColor.opacity(0.16), in: Capsule())
                .foregroundStyle(bandColor)
            Text("\(row.activeRequests) active")
                .font(.caption.monospacedDigit())
            if row.queuedRequests > 0 {
                Text("\(row.queuedRequests) queued")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text("\(row.warmProviders) warm")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.id)
        .accessibilityValue(
            "\(row.band.rawValue) demand, \(row.activeRequests) active requests, "
                + "\(row.queuedRequests) queued requests, \(row.warmProviders) warm providers"
        )
    }

    private var bandColor: Color {
        switch row.band {
        case .low: .secondary
        case .moderate: .blue
        case .high: .orange
        case .urgent: .red
        }
    }
}

private struct InlineNetworkDemandBadge: View {
    let row: PopupNetworkDemandRow
    let isStale: Bool

    var body: some View {
        Text("\(row.band.rawValue.capitalized) demand")
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
            .foregroundStyle(color)
            .help(isStale ? "Last known network demand; sample is stale" : "Current network demand")
            .accessibilityLabel("\(row.band.rawValue) network demand for \(row.id)\(isStale ? ", stale sample" : "")")
    }

    private var color: Color {
        if isStale { return .secondary }
        switch row.band {
        case .low: return .secondary
        case .moderate: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

private struct ModelStatusPill: View {
    let model: DashboardModel

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(PopupModelName.short(model.name))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)

            if let label = status.supplementaryLabel,
               let systemImage = status.systemImage {
                Label(label, systemImage: systemImage)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(color.opacity(backgroundOpacity), in: Capsule())
        .help(helpText)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(model.name), \(status.statusName)")
    }

    private var status: PopupModelStatusPresentation {
        .make(for: model.state)
    }

    private var color: Color {
        switch model.state {
        case .active: .green
        case .loadedIdle: .yellow
        case .availableUnloaded: .gray
        }
    }

    private var backgroundOpacity: Double {
        model.state == .availableUnloaded ? 0.12 : 0.18
    }

    private var helpText: String {
        if model.state == .availableUnloaded {
            return "\(model.name) — on demand. Loads automatically when requested."
        }
        return "\(model.name) — \(status.statusName)"
    }
}

private struct AutoModelModeBadge: View {
    var monochrome = false
    var body: some View {
        Label("Auto", systemImage: "arrow.triangle.2.circlepath")
            .font(.system(size: 10, weight: .semibold, design: .rounded))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(monochrome ? Color.secondary : .blue)
            .background((monochrome ? Color.secondary : .blue).opacity(0.12), in: Capsule())
            .help("Darkbloom selects and loads enabled models for incoming requests. Switch pins one advertised model until you change it.")
            .accessibilityLabel("Automatic model selection")
            .accessibilityHint("Enabled models load automatically when requested")
    }
}

enum PopupModelName {
    static func short(_ id: String) -> String { ModelDisplayName.short(id) }
}

struct PopupFanPanel: View {
    @ObservedObject var extras: ProviderExtrasStore
    var isVisible: Bool = true
    let performMutation: ProviderExtrasMutationExecutor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Cooling", systemImage: "fan").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding()
            Form {
                ProviderFanControlSettingsView(store: extras, performMutation: performMutation, isVisible: isVisible, compactPresentation: true)
            }.formStyle(.grouped)
        }
        .frame(width: 560, height: 520)
    }
}
