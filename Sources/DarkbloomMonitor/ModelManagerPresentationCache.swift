import DarkbloomTelemetry
import Foundation

/// Retains the original array's first match when catalog and local aliases
/// both occur in telemetry, without repeating a linear scan for each card.
private struct ModelTelemetryIndex<Value> {
    private var entries: [String: (offset: Int, value: Value)] = [:]

    init(_ values: [Value], model: (Value) -> String) {
        for (offset, value) in values.enumerated() where entries[model(value)] == nil {
            entries[model(value)] = (offset, value)
        }
    }

    func value(catalogID: String, localID: String? = nil) -> Value? {
        let catalog = entries[catalogID]
        let local = localID.flatMap { entries[$0] }
        if let catalog, let local { return catalog.offset < local.offset ? catalog.value : local.value }
        return catalog?.value ?? local?.value
    }
}

/// Inventory residency is a value, not evidence that it is still known.
/// A missing runtime read can leave `.unloaded` in the inventory as a default.
enum ModelCardResidencyPresentation: Equatable {
    case known(InventoryLiveState)
    case unavailable
    case notDownloaded

    var status: String {
        switch self {
        case .known(.active): "Serving now"
        case .known(.loadedIdle): "Ready in memory"
        case .known(.unloaded): "Not loaded"
        case .unavailable: "Status unavailable"
        case .notDownloaded: "Not downloaded"
        }
    }

    var badge: String {
        switch self {
        case .known(.active): "Active"
        case .known(.loadedIdle): "Loaded"
        case .known(.unloaded): "Unloaded"
        case .unavailable: "Unknown"
        case .notDownloaded: "Not downloaded"
        }
    }

    var accessibilityValue: String {
        self == .unavailable ? "Provider residency unavailable" : badge
    }
}

struct ModelManagerResidencyEvidence: Equatable {
    var providerKnownStopped = false
    var controlResidencyIsFresh = false

    func presentation(for item: ModelInventoryItem) -> ModelCardResidencyPresentation {
        guard item.isDownloaded else { return .notDownloaded }
        if providerKnownStopped { return .known(.unloaded) }
        return controlResidencyIsFresh ? .known(item.liveState) : .unavailable
    }

    static func make(
        control: ProviderControlSnapshot?,
        status: SourceAvailability<StatusSnapshot>,
        daemon: SourceAvailability<DaemonState>,
        at date: Date
    ) -> Self {
        let lifecycle = ProviderLifecycleSourceInput(
            daemonState: freshDaemon(daemon, at: date),
            status: freshAvailability(status, maximumAge: StatusSnapshot.maximumAge, at: date),
            controlDaemonState: control?.sources.daemon,
            currentTime: date
        )
        func fresh(_ source: ProviderControlSourceState?) -> Bool {
            source?.evaluated(at: date, invalidReason: "Invalid residency timestamp",
                staleReason: "Residency is stale", futureReason: "Residency timestamp is in the future")
                .isMarkedFresh == true
        }
        return Self(providerKnownStopped: lifecycle.providerKnownRunning == false,
            controlResidencyIsFresh: fresh(control?.sources.daemon) && fresh(control?.sources.loadedModels))
    }

    private static func freshAvailability<Value: Equatable & Sendable>(
        _ source: SourceAvailability<Value>, maximumAge: TimeInterval, at date: Date
    ) -> SourceAvailability<Value> {
        guard case .available(_, let capturedAt) = source,
              freshTimestamp(capturedAt.timeIntervalSince1970, maximumAge: maximumAge, at: date)
        else { return .unavailable(reason: "Provider state is unavailable") }
        return source
    }

    private static func freshDaemon(_ source: SourceAvailability<DaemonState>, at date: Date) -> SourceAvailability<DaemonState> {
        guard case .available(let daemon, _) = source,
              freshTimestamp(daemon.writtenAt, maximumAge: ProviderControlSourceState.maximumEvidenceAge, at: date)
        else { return .unavailable(reason: "Provider activity is unavailable") }
        return freshAvailability(source, maximumAge: ProviderControlSourceState.maximumEvidenceAge, at: date)
    }

    private static func freshTimestamp(_ timestamp: TimeInterval, maximumAge: TimeInterval, at date: Date) -> Bool {
        guard timestamp.isFinite, date.timeIntervalSince1970.isFinite else { return false }
        let age = date.timeIntervalSince1970 - timestamp
        return age.isFinite && (0...maximumAge).contains(age)
    }
}

struct ModelManagerPreparedPresentation {
    var grouping = ModelGrouping(enabled: [], available: [])
    fileprivate var rates = ModelTelemetryIndex<ModelTokenRateAverage>([], model: \.model)
    fileprivate var serving = ModelTelemetryIndex<ModelServingProfitAverage>([], model: \.model)
    fileprivate var network = ModelTelemetryIndex<NetworkModelCapacity>([], model: \.id)
    var grades: [String: String] = [:]
    var networkIsCurrent = false
    var residencyEvidence = ModelManagerResidencyEvidence()

    func tokenRate(for item: ModelInventoryItem) -> ModelTokenRateAverage? {
        rates.value(catalogID: item.catalogID, localID: item.localID)
    }
    func servingAverage(for item: ModelInventoryItem) -> ModelServingProfitAverage? {
        serving.value(catalogID: item.catalogID, localID: item.localID)
    }
    func capacity(for item: ModelInventoryItem) -> NetworkModelCapacity? {
        networkIsCurrent ? network.value(catalogID: item.catalogID) : nil
    }
    func demand(for item: ModelInventoryItem) -> ModelCardDemand {
        let model = network.value(catalogID: item.catalogID)
        return ModelCardDemand(model: model, isCurrent: networkIsCurrent && model != nil)
    }
}

@MainActor
final class ModelManagerPresentationCache {
    private struct CatalogInput: Equatable {
        let mine: [ModelInventoryItem]
        let available: [ModelInventoryItem]
        let enabled: Set<String>?
        let search: String
    }
    private struct GradeInput: Equatable {
        let mine: [ModelInventoryItem]
        let enabled: Set<String>?
        let telemetry: ModelManagerTelemetry
        let networkIsCurrent: Bool
    }
    private var catalogInput: CatalogInput?
    private var gradeInput: GradeInput?
    private struct TelemetryIndexInput: Equatable {
        let tokenRates: [ModelTokenRateAverage]
        let servingAverages: [ModelServingProfitAverage]
        let networkModels: [NetworkModelCapacity]
    }
    private var indexedTelemetry: TelemetryIndexInput?
    private var prepared = ModelManagerPreparedPresentation()
    private(set) var groupingBuildCount = 0
    private(set) var telemetryIndexBuildCount = 0
    private(set) var gradeBuildCount = 0

    func prepare(
        myCatalog: [ModelInventoryItem], available: [ModelInventoryItem],
        enabledSelectors: [String]?, search: String,
        telemetry: ModelManagerTelemetry, at date: Date,
        controlSnapshot: ProviderControlSnapshot? = nil,
        providerStatus: SourceAvailability<StatusSnapshot> = .unavailable(reason: "Provider status unavailable"),
        providerDaemonState: SourceAvailability<DaemonState> = .unavailable(reason: "Provider activity unavailable")
    ) -> ModelManagerPreparedPresentation {
        prepared.residencyEvidence = ModelManagerResidencyEvidence.make(control: controlSnapshot,
            status: providerStatus, daemon: providerDaemonState, at: date)
        let selectors = enabledSelectors.map(Set.init)
        func isEnabled(_ item: ModelInventoryItem) -> Bool {
            guard let selectors else { return item.isEnabled }
            return selectors.contains(item.catalogID)
                || item.enabledSelector.map(selectors.contains) == true
        }
        let catalog = CatalogInput(mine: myCatalog, available: available, enabled: selectors, search: search)
        if catalog != catalogInput {
            prepared.grouping = ModelGrouping.partition(myCatalog: myCatalog, available: available,
                search: search, isEnabled: isEnabled)
            catalogInput = catalog
            groupingBuildCount += 1
        }
        let indexInput = TelemetryIndexInput(tokenRates: telemetry.tokenRates,
            servingAverages: telemetry.servingAverages, networkModels: telemetry.networkCapacity?.models ?? [])
        if indexInput != indexedTelemetry {
            prepared.rates = ModelTelemetryIndex(telemetry.tokenRates, model: \.model)
            prepared.serving = ModelTelemetryIndex(telemetry.servingAverages, model: \.model)
            prepared.network = ModelTelemetryIndex(telemetry.networkCapacity?.models ?? [], model: \.id)
            indexedTelemetry = indexInput
            telemetryIndexBuildCount += 1
        }
        let current = telemetry.networkSourceAvailable && telemetry.networkCapacity?.isFresh(at: date) == true
        let grade = GradeInput(mine: myCatalog, enabled: selectors, telemetry: telemetry, networkIsCurrent: current)
        if grade != gradeInput {
            prepared.networkIsCurrent = current
            let peers = myCatalog.filter(isEnabled).map { item in
                ModelOpportunitySignal(modelID: item.catalogID,
                    tokensPerSecond: prepared.tokenRate(for: item)?.tokensPerSecond,
                    activeHours: prepared.servingAverage(for: item)?.activeHours ?? 0,
                    demand: prepared.capacity(for: item)?.demandBand,
                    netProfitUSDPerActiveHour: prepared.servingAverage(for: item)?.profitUSDPerActiveHour)
            }
            prepared.grades = ModelManagerPresentation.opportunityGrades(peers: peers)
            gradeInput = grade
            gradeBuildCount += 1
        }
        return prepared
    }
}

/// Only freshness transitions invalidate the grid's time-dependent demand.
/// The age label owns its separate one-second display schedule.
enum ModelDemandFreshnessSchedule {
    static func nextTransition(capacity: NetworkCapacitySnapshot?, at date: Date) -> Date? {
        guard let capacity else { return nil }
        let age = date.timeIntervalSince(capacity.capturedAt)
        guard age.isFinite else { return nil }
        if age < -NetworkCapacitySnapshot.maximumFutureSkew {
            return capacity.capturedAt.addingTimeInterval(-NetworkCapacitySnapshot.maximumFutureSkew)
        }
        if age <= NetworkCapacitySnapshot.maximumAge {
            return capacity.capturedAt.addingTimeInterval(NetworkCapacitySnapshot.maximumAge + 0.001)
        }
        return nil
    }
}

struct ModelDemandFreshnessTaskInput: Equatable {
    let capturedAt: Date?
    let sourceAvailable: Bool
    let isVisible: Bool
}

/// Schedule only evidence transitions rather than redrawing every card each second.
struct ModelResidencyFreshnessTaskInput: Equatable {
    let sources: ProviderControlSourceStates?
    let status: SourceAvailability<StatusSnapshot>
    let daemon: SourceAvailability<DaemonState>
    let isVisible: Bool
}

enum ModelResidencyFreshnessSchedule {
    static func nextTransition(input: ModelResidencyFreshnessTaskInput, at date: Date) -> Date? {
        guard date.timeIntervalSince1970.isFinite else { return nil }
        var transitions: [Date] = []
        func include(_ timestamp: TimeInterval, maximumAge: TimeInterval) {
            guard timestamp.isFinite else { return }
            let evidenceAt = Date(timeIntervalSince1970: timestamp)
            if evidenceAt > date { transitions.append(evidenceAt) }
            let expiry = evidenceAt.addingTimeInterval(maximumAge + 0.001)
            if expiry > date { transitions.append(expiry) }
        }
        for source in [input.sources?.daemon, input.sources?.loadedModels] {
            if case .fresh(let evidenceAt) = source {
                include(evidenceAt.timeIntervalSince1970, maximumAge: ProviderControlSourceState.maximumEvidenceAge)
            }
        }
        if case .available(_, let capturedAt) = input.status {
            include(capturedAt.timeIntervalSince1970, maximumAge: StatusSnapshot.maximumAge)
        }
        if case .available(let daemon, let capturedAt) = input.daemon {
            include(capturedAt.timeIntervalSince1970, maximumAge: ProviderControlSourceState.maximumEvidenceAge)
            include(daemon.writtenAt, maximumAge: ProviderControlSourceState.maximumEvidenceAge)
        }
        return transitions.min()
    }
}
