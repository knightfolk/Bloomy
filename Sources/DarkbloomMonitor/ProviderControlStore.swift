import DarkbloomTelemetry
import Foundation
import SwiftUI

enum ProviderOperation: Equatable {
    case idle
    case refreshing
    case nudging
    case saving
    case liveSwitch
    case downloading(String)
    case deleting(String)
    case lifecycle(ProviderLifecycleAction)
}

enum SwitchWarmupStatus: Equatable {
    case checking(modelID: String)
    case result(modelID: String, SelfRouteWarmupResult, at: Date)
}

enum ModelSwapStatus: Equatable {
    case checking(modelID: String)
    case confirmed(modelID: String, at: Date)
    case unconfirmed(modelID: String, at: Date)
    case failed(modelID: String, LocalModelSwapResult, at: Date)
}

typealias SwapNudgeRequest = @Sendable (
    String,
    @escaping @Sendable () async -> Bool
) async -> SelfRouteWarmupResult

enum LifecycleConfirmation: Equatable {
    case stop(ProviderActivityRisk)
    case restart(ProviderActivityRisk)
    case restartSelection(ProviderActivityRisk, ProviderSelectionComparison)

    var action: ProviderLifecycleAction {
        switch self {
        case .stop: .stop
        case .restart, .restartSelection: .restart
        }
    }

    var risk: ProviderActivityRisk {
        switch self {
        case .stop(let risk), .restart(let risk), .restartSelection(let risk, _): risk
        }
    }
}

@MainActor
final class ProviderControlStore: ObservableObject {
    var actionHistory: ActionHistoryStore?
    var onManualProviderIntent: (@MainActor () -> Void)?
    private var hostGPUResumeRevision: String?
    private var hostGPUResumeHosting: HostingOptions?
    private var hostGPUStoppedIdentity: ProcessIdentity?
    private var manualProviderIntentGeneration: UInt64 = 0

    var ownsHostGPUPause: Bool { hostGPUResumeRevision != nil }

    func relinquishHostGPUPause() {
        hostGPUResumeRevision = nil
        hostGPUResumeHosting = nil
        hostGPUStoppedIdentity = nil
    }
    private var historyOperationID: UUID?
    private var historySwapID: UUID?
    private var historyNudgeID: UUID?
    private var historyWarmupID: UUID?
    private var historyCancelled = false
    @Published private(set) var snapshot: ProviderControlSnapshot?
    @Published private(set) var draft: ProviderConfigDraft?
    @Published private(set) var savedCapacity: SourceAvailability<ProviderSavedCapacity> =
        .unavailable(reason: "Refresh to read saved capacity settings.")
    @Published private(set) var operation: ProviderOperation = .idle
    @Published private(set) var operationPhase: ProviderMutationPhase?
    @Published private(set) var pendingConfirmation: LifecycleConfirmation?
    @Published private(set) var autopilotEnrollmentMessage: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var latestDownloadProgressLine: String?
    @Published private(set) var switchWarmupStatus: SwitchWarmupStatus? { didSet { recordSelectionWarmup() } }
    @Published private(set) var swapStatus: ModelSwapStatus? { didSet { recordSwapStatus() } }
    @Published private(set) var swapNudgeStatus: SwitchWarmupStatus? { didSet { recordSwapNudgeStatus() } }

    private let controller: any ProviderControlling
    private let warmupProbe: (any SelfRouteWarmupProbing)?
    private let swapProbe: (any LocalModelSwapRequesting)?
    private let swapNudge: SwapNudgeRequest?
    private let diagnosticSanitizer: UserDiagnosticSanitizer
    private let refreshTelemetry: @MainActor @Sendable () async -> Void
    private let awaitStartup: @MainActor @Sendable (Date) async throws -> Void
    private let now: @Sendable () -> Date
    private let swapConfirmationSleep: @Sendable () async -> Void
    /// Saved hosting start flags, re-applied by every monitor-initiated start
    /// or restart so a later popup restart cannot silently drop the endpoint
    /// from the new provider registration.
    private let hostingOptions: @MainActor () -> HostingOptions
    private var currentTask: Task<Void, Never>?
    private var operationGeneration: UInt64 = 0

    init(
        controller: any ProviderControlling,
        warmupProbe: (any SelfRouteWarmupProbing)? = nil,
        swapProbe: (any LocalModelSwapRequesting)? = nil,
        swapNudge: SwapNudgeRequest? = nil,
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        refreshTelemetry: @escaping @MainActor @Sendable () async -> Void = {},
        now: @escaping @Sendable () -> Date = { Date() },
        swapConfirmationSleep: @escaping @Sendable () async -> Void = {
            try? await Task.sleep(for: .seconds(1))
        },
        awaitStartup: @escaping @MainActor @Sendable (Date) async throws -> Void = { _ in },
        hostingOptions: @escaping @MainActor () -> HostingOptions = {
            HostingSettingsStore.loadOptions(from: .standard)
        }
    ) {
        self.awaitStartup = awaitStartup
        self.controller = controller
        self.warmupProbe = warmupProbe
        self.swapProbe = swapProbe
        self.swapNudge = swapNudge
        diagnosticSanitizer = UserDiagnosticSanitizer(homeDirectory: homeDirectory)
        self.refreshTelemetry = refreshTelemetry
        self.now = now
        self.swapConfirmationSleep = swapConfirmationSleep
        self.hostingOptions = hostingOptions
    }

    var canSave: Bool {
        guard operation == .idle, let draft, draft.hasChanges else { return false }
        return draftValidationMessage == nil
    }

    var canApplyLive: Bool { applyLiveUnavailableReason == nil }

    /// Automatic traffic may run only while provider controls have no user
    /// mutation, pending confirmation, or unsaved model edits.
    var canAutomaticNudge: Bool {
        operation == .idle && pendingConfirmation == nil && draft?.hasChanges != true
    }

    /// Local settings buffers need no command ownership. A provider mutation,
    /// unresolved operation or model-selection draft still blocks editing.
    var canEditProviderSettings: Bool {
        (operation == .idle || operation == .refreshing)
            && pendingConfirmation == nil && draft?.hasChanges != true
    }

    /// Own the same operation gate used by model switches and lifecycle work
    /// for the entire self-route request. The watcher owns cancellation.
    func performAutomaticNudge(
        modelID: String,
        family: String,
        probe: any SelfRouteWarmupProbing
    ) async -> SelfRouteWarmupResult? {
        guard canAutomaticNudge, let generation = begin(.nudging) else { return nil }
        defer { finish(generation) }
        return await probe.warm(modelID: modelID, family: family)
    }

    /// A request for an already advertised model can cause the provider to
    /// load it on demand. No provider configuration or advertised set changes.
    /// Completion is confirmed only by fresh telemetry from this same Mac.
    func swapModelUnavailableReason(for modelID: String) -> String? {
        guard operation == .idle else { return "Another provider action is in progress" }
        guard pendingConfirmation == nil else { return "Finish the pending provider action first" }
        guard swapProbe != nil else { return "Swap is unavailable in this build" }
        guard let snapshot, let draft else { return "Provider configuration is unavailable" }
        guard !draft.hasChanges else { return "Save or discard pending changes before swapping" }
        guard draft.sourceRevision == snapshot.draft.sourceRevision,
              draft.original == snapshot.draft.original,
              freshModelSources(in: snapshot) else {
            return "Refresh model controls before swapping"
        }
        guard let item = snapshot.inventory.myCatalog.first(where: { $0.catalogID == modelID }),
              item.isDownloaded, item.localID != nil, item.issue == nil else {
            return "This downloaded model is unavailable"
        }
        return modelSwapStateReason(modelID: modelID, snapshot: snapshot, at: now())
    }

    func swapToModel(_ modelID: String) async {
        guard swapModelUnavailableReason(for: modelID) == nil,
              let initial = snapshot?.daemonState,
              let advertised = initial.advertisedModels,
              let swapProbe,
              let generation = begin(.nudging) else { return }
        let controller = self.controller
        let initialIdentity = initial.processIdentity
        let now = self.now
        let expectedAdvertised = Set(advertised)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                if case .checking = swapStatus {
                    swapStatus = .unconfirmed(modelID: modelID, at: now())
                }
                finish(generation)
            }
            do {
                let latest = try await controller.refresh()
                guard modelSwapStateReason(
                    modelID: modelID, snapshot: latest, at: now(),
                    expectedIdentity: initialIdentity,
                    expectedAdvertised: expectedAdvertised
                ) == nil,
                    await controller.activityRisk() == .idle else {
                    errorMessage = "Provider activity changed. Refresh before swapping."
                    return
                }
                accept(latest, preserving: draft)
                swapStatus = .checking(modelID: modelID)
                let result = await swapProbe.request(
                    modelID: modelID,
                    expectedProcessIdentity: initialIdentity
                ) {
                    guard !Task.isCancelled,
                          let fresh = try? await controller.refresh() else { return false }
                    guard modelSwapStateReason(
                        modelID: modelID, snapshot: fresh, at: now(),
                        expectedIdentity: initialIdentity,
                        expectedAdvertised: expectedAdvertised
                    ) == nil else { return false }
                    return await controller.activityRisk() == .idle
                }
                guard result == .sent || result == .failed else {
                    swapStatus = .failed(modelID: modelID, result, at: now())
                    return
                }
                for attempt in 0..<5 {
                    let fresh: ProviderControlSnapshot?
                    if Task.isCancelled {
                        fresh = await Task.detached {
                            try? await controller.refresh()
                        }.value
                    } else {
                        fresh = try? await controller.refresh()
                    }
                    if let fresh {
                        accept(fresh, preserving: draft)
                        if modelSwapConfirmed(
                            modelID: modelID, snapshot: fresh, at: now(),
                            expectedIdentity: initialIdentity,
                            expectedAdvertised: expectedAdvertised
                        ) {
                            swapStatus = .confirmed(modelID: modelID, at: now())
                            await refreshTelemetry()
                            if result == .sent, !Task.isCancelled, let swapNudge {
                                // A local load may finish while a real job or a
                                // restart begins. Revalidate before starting the
                                // optional network self-route model lookup.
                                guard !Task.isCancelled,
                                      let beforeNudge = try? await controller.refresh(),
                                      modelSwapConfirmed(
                                        modelID: modelID, snapshot: beforeNudge, at: now(),
                                        expectedIdentity: initialIdentity,
                                        expectedAdvertised: expectedAdvertised
                                      ),
                                      await controller.activityRisk() == .idle else {
                                    swapNudgeStatus = .result(modelID: modelID, .failed, at: now())
                                    return
                                }
                                swapNudgeStatus = .checking(modelID: modelID)
                                let nudgeResult = await swapNudge(modelID) {
                                    guard !Task.isCancelled,
                                          let current = try? await controller.refresh(),
                                          modelSwapConfirmed(
                                            modelID: modelID, snapshot: current, at: now(),
                                            expectedIdentity: initialIdentity,
                                            expectedAdvertised: expectedAdvertised
                                          ) else { return false }
                                    return await controller.activityRisk() == .idle
                                }
                                swapNudgeStatus = .result(
                                    modelID: modelID,
                                    Task.isCancelled ? .failed : nudgeResult,
                                    at: now()
                                )
                            }
                            return
                        }
                        if fresh.daemonState?.processIdentity != initialIdentity ||
                            Set(fresh.daemonState?.advertisedModels ?? []) != expectedAdvertised {
                            break
                        }
                    }
                    if Task.isCancelled { break }
                    if attempt < 4 { await swapConfirmationSleep() }
                }
                swapStatus = result == .sent
                    ? .unconfirmed(modelID: modelID, at: now())
                    : .failed(modelID: modelID, result, at: now())
                await refreshTelemetry()
            } catch is CancellationError {
                swapStatus = .unconfirmed(modelID: modelID, at: now())
            } catch {
                errorMessage = "Current provider state could not be checked. Refresh before swapping."
            }
        }
        currentTask = task
        await awaitTask(task)
    }

    func singleModelSwitchUnavailableReason(for modelID: String) -> String? {
        guard operation == .idle else { return "Another provider action is in progress" }
        guard pendingConfirmation == nil else { return "Finish the pending provider action first" }
        guard let draft, let snapshot else { return "Provider configuration is unavailable" }
        guard !draft.hasChanges else { return "Save or discard pending changes before switching" }
        guard draft.sourceRevision == snapshot.draft.sourceRevision,
              draft.original == snapshot.draft.original,
              freshModelSources(in: snapshot) else {
            return "Refresh model controls before switching"
        }
        guard let item = snapshot.inventory.myCatalog.first(where: { $0.catalogID == modelID }),
              item.isDownloaded, item.localID != nil, item.issue == nil else {
            return "This downloaded model is unavailable"
        }
        guard let daemon = snapshot.daemonState,
              snapshot.sources.daemon.evaluated(
                at: now(),
                invalidReason: "Provider state is unavailable",
                staleReason: "Provider state is stale",
                futureReason: "Provider state timestamp is in the future"
              ).isMarkedFresh,
              let advertised = daemon.advertisedModels else {
            return "Refresh current provider state before switching"
        }
        if advertised == [modelID] { return "This is already the selected model" }
        return liveActivationUnavailableReason(in: snapshot)
    }

    /// The CLI switch command replaces and persists the entire advertised set.
    /// Keep this explicit rather than changing Apply Live's full-set behavior.
    func switchToSingleModel(_ modelID: String, sendWarmup: Bool = true, trigger: ActionHistoryTrigger = .manual) async {
        guard singleModelSwitchUnavailableReason(for: modelID) == nil,
              let generation = begin(.liveSwitch, trigger: trigger, model: modelID) else { return }
        let controller = self.controller
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await controller.performSingleModelSwitch(
                    modelID: modelID,
                    onPhase: { [weak self] phase in
                        await self?.advanceMutationPhase(phase, generation: generation)
                    }
                )
                await reconcileCompletedMutation(
                    completion,
                    preserving: nil,
                    failureMessage: "The model switched, but controls could not refresh.",
                    uncertainFailureMessage: "The switch outcome could not be confirmed. Refresh model controls."
                )
                if sendWarmup, !completion.isOutcomeUncertain,
                   let refreshed = snapshot,
                   refreshed.daemonState?.advertisedModels == [modelID],
                   refreshed.sources.daemon.evaluated(
                    at: now(),
                    invalidReason: "Provider state unavailable",
                    staleReason: "Provider state stale",
                    futureReason: "Provider state timestamp invalid"
                   ).isMarkedFresh,
                   let family = refreshed.inventory.myCatalog.first(where: { $0.catalogID == modelID })?.family,
                   let warmupProbe {
                    switchWarmupStatus = .checking(modelID: modelID)
                    let result = await warmupProbe.warm(modelID: modelID, family: family)
                    switchWarmupStatus = .result(modelID: modelID, result, at: now())
                }
            } catch is CancellationError {
                // The service owns dispatch and cancellation boundaries.
            } catch let error as ProviderControlError {
                errorMessage = controlErrorMessage(error, action: "switch models")
            } catch {
                errorMessage = "Could not switch models."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    /// The popup action only changes one downloaded model. A staged settings
    /// draft must be resolved separately so this action cannot publish it.
    func activationUnavailableReason(
        for modelID: String,
        providerKnownRunning: Bool? = nil
    ) -> String? {
        guard operation == .idle else { return "Another provider action is in progress" }
        guard pendingConfirmation == nil else {
            return "Finish the pending provider action before activating a model"
        }
        guard let draft, let snapshot else { return "Provider configuration is unavailable" }
        guard !draft.hasChanges else {
            return "Save or discard pending changes before activating a model"
        }
        guard draft.sourceRevision == snapshot.draft.sourceRevision,
              draft.original == snapshot.draft.original else {
            return "Refresh model controls before activating a model"
        }
        guard freshModelSources(in: snapshot) else {
            return "Refresh model controls before activating a model"
        }
        guard let item = snapshot.inventory.myCatalog.first(where: { $0.catalogID == modelID }),
              item.isDownloaded, item.localID != nil, item.issue == nil else {
            return "This downloaded model is unavailable"
        }
        if let validation = draftValidationMessage { return validation }
        let saved = draft.original.enabled.contains {
            Self.resolvedCatalogID(for: $0, in: snapshot.inventory) == modelID
        }
        guard let daemon = snapshot.daemonState else {
            guard providerKnownRunning == false else {
                return "Refresh current provider state before activating a model"
            }
            return saved ? "This model is already saved for the next start" : nil
        }
        guard snapshot.sources.daemon.evaluated(
            at: now(),
            invalidReason: "Provider state is unavailable",
            staleReason: "Provider state is stale",
            futureReason: "Provider state timestamp is in the future"
        ).isMarkedFresh else {
            return "Refresh current provider state before activating a model"
        }
        guard let advertised = daemon.advertisedModels else {
            return "Refresh advertised models before activating a model"
        }
        guard !hasUnexpectedAdvertisedModels(advertised, in: snapshot) else {
            return "The running model selection differs from saved settings. Use Models to review it."
        }
        if advertised.contains(modelID) {
            return "This model is already active"
        }
        return liveActivationUnavailableReason(in: snapshot)
    }

    private func hasUnexpectedAdvertisedModels(
        _ advertised: [String],
        in snapshot: ProviderControlSnapshot
    ) -> Bool {
        let saved = Set(snapshot.draft.original.enabled.compactMap {
            Self.resolvedCatalogID(for: $0, in: snapshot.inventory)
        })
        return !Set(advertised).isSubset(of: saved)
    }

    private func freshModelSources(in snapshot: ProviderControlSnapshot) -> Bool {
        let currentTime = now()
        return snapshot.sources.catalog.evaluated(
            at: currentTime,
            invalidReason: "Model catalog is unavailable",
            staleReason: "Model catalog is stale",
            futureReason: "Model catalog timestamp is in the future"
        ).isMarkedFresh && snapshot.sources.localModels.evaluated(
            at: currentTime,
            invalidReason: "Local models are unavailable",
            staleReason: "Local models are stale",
            futureReason: "Local models timestamp is in the future"
        ).isMarkedFresh
    }

    private func liveActivationUnavailableReason(in snapshot: ProviderControlSnapshot) -> String? {
        switch snapshot.liveSwitchAvailability {
        case .available: nil
        case .inProgress: "A live model switch is already in progress"
        case .unavailable(let reason):
            Self.safeLiveSwitchDiagnostics.contains(reason)
                ? diagnosticSanitizer.sanitize(reason)
                : "Apply Live is unavailable"
        }
    }

    var applyLiveUnavailableReason: String? {
        guard operation == .idle else { return "Another provider action is in progress" }
        guard let draft, let snapshot else {
            return savedCapacity.value == nil ? "Provider configuration is unavailable"
                : "Refresh model controls before applying live"
        }
        guard !draft.hasChanges else {
            return "Save or discard pending changes before applying live"
        }
        guard !draft.original.enabled.isEmpty else {
            return "Apply Live requires at least one saved enabled model"
        }
        guard snapshot.sources.catalog.isMarkedFresh,
              snapshot.sources.localModels.isMarkedFresh else {
            return "Refresh model controls before applying live"
        }
        switch snapshot.liveSwitchAvailability {
        case .available:
            break
        case .inProgress:
            return "A live model switch is already in progress"
        case .unavailable(let reason):
            return Self.safeLiveSwitchDiagnostics.contains(reason)
                ? diagnosticSanitizer.sanitize(reason)
                : "Apply Live is unavailable"
        }
        if let advertised = snapshot.daemonState?.advertisedModels {
            let saved = Set(draft.original.enabled.compactMap {
                Self.resolvedCatalogID(for: $0, in: snapshot.inventory)
            })
            if !saved.isEmpty, saved == Set(advertised) {
                return "The saved model selection is already active"
            }
        }
        return nil
    }

    func canDownload(_ modelID: String) -> Bool {
        guard operation == .idle, hasFreshModelSources, let snapshot else { return false }
        return snapshot.inventory.available.contains {
            $0.catalogID == modelID && $0.issue == nil
        }
    }

    func sanitizedDiagnostic(_ value: String) -> String {
        diagnosticSanitizer.sanitize(value)
    }

    var canCancelCurrentOperation: Bool {
        guard case .downloading = operation else { return false }
        return operationPhase == .mutating
    }

    var draftValidationMessage: String? {
        guard let draft else {
            return savedCapacity.value == nil ? "Provider configuration is unavailable"
                : "Refresh the model catalog before changing provider settings"
        }
        guard let snapshot else { return "Model inventory is unavailable" }
        guard snapshot.sources.catalog.isMarkedFresh else {
            return "Refresh the model catalog before changing provider settings"
        }
        guard snapshot.sources.localModels.isMarkedFresh else {
            return "Refresh local models before changing provider settings"
        }

        let enabledIDs = Set(draft.selection.enabled.compactMap {
            Self.resolvedCatalogID(for: $0, in: snapshot.inventory)
        })
        if let selector = draft.selection.preloaded.first(where: {
            guard let modelID = Self.resolvedCatalogID(
                for: $0,
                in: snapshot.inventory
            ) else { return false }
            return !enabledIDs.contains(modelID)
        }) {
            return "Enable '\(Self.safeIdentifier(selector))' or remove it from preload"
        }

        let validSelectors = Set(snapshot.inventory.myCatalog.flatMap { item in
            [item.catalogID, item.enabledSelector, item.preloadSelector]
                .compactMap { $0 }
        })
        if let modelID = (draft.selection.enabled + draft.selection.preloaded).first(where: {
            !validSelectors.contains($0)
        }) {
            return "Downloaded model '\(Self.safeIdentifier(modelID))' is unavailable"
        }
        return nil
    }

    private var hasFreshModelSources: Bool {
        guard let sources = snapshot?.sources else { return false }
        return sources.catalog.isMarkedFresh && sources.localModels.isMarkedFresh
    }

    func refresh() async {
        await refresh(preservingEdits: false)
    }

    /// Refresh authoritative controls without discarding a staged draft. This
    /// is used by read-only surfaces that need fresh safety evidence while a
    /// user may still be editing settings.
    func refreshPreservingDraft() async {
        await refresh(preservingEdits: true)
    }

    private func refresh(preservingEdits: Bool) async {
        guard let generation = begin(.refreshing) else { return }
        let controller = self.controller
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let reader = controller as? any ProviderSavedCapacityReading {
                    try await refreshSavedCapacity(using: reader)
                }
                let refreshed = try await controller.refresh()
                try Task.checkCancellation()
                // Read the latest draft after the suspended read so edits made
                // during refresh survive. Clean drafts follow saved changes.
                let stagedDraft = preservingEdits && draft?.hasChanges == true ? draft : nil
                accept(refreshed, preserving: stagedDraft)
            } catch is CancellationError {
                // Cancellation is an intentional state transition, not a user-facing failure.
            } catch ProviderControlError.inventoryUnavailable(let reason) {
                errorMessage = Self.safeRefreshInventoryDiagnostic(reason)
                    .map { diagnosticSanitizer.sanitize($0) }
                    ?? "Could not refresh model controls."
            } catch {
                errorMessage = "Could not refresh model controls."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    private func refreshSavedCapacity(using reader: any ProviderSavedCapacityReading) async throws {
        do {
            let value = try await reader.readSavedCapacity()
            try Task.checkCancellation()
            savedCapacity = .available(value: value, capturedAt: now())
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let reason = "Saved capacity settings could not be read."
            switch savedCapacity {
            case .available(let value, let capturedAt), .stale(let value, let capturedAt, _):
                savedCapacity = .stale(value: value, capturedAt: capturedAt, reason: reason)
            case .unavailable:
                savedCapacity = .unavailable(reason: reason)
            }
        }
    }

    func setEnabled(_ enabled: Bool, modelID: String) {
        guard var draft else { return }
        Self.setMembership(enabled, modelID: modelID, in: &draft.selection.enabled)
        self.draft = draft
    }

    func setPreloaded(_ preloaded: Bool, modelID: String) {
        guard var draft else { return }
        Self.setMembership(preloaded, modelID: modelID, in: &draft.selection.preloaded)
        self.draft = draft
    }

    func setMaxModelSlots(_ maxModelSlots: Int) {
        guard var draft, maxModelSlots > 0 else { return }
        draft.maxModelSlots = maxModelSlots
        self.draft = draft
    }

    /// A single preload is the start-up preference for the one-slot setup.
    /// Runtime request routing remains the provider's responsibility.
    func setPreferredStartupModel(_ modelID: String?) {
        guard var draft else { return }
        if let modelID {
            guard draft.selection.enabled.contains(modelID) else { return }
            draft.selection.preloaded = [modelID]
        } else {
            draft.selection.preloaded = []
        }
        self.draft = draft
    }

    /// The saved Auto choice is a configuration fact, not proof that the
    /// running provider has applied its slot limit or loaded the model.
    var savedAutomaticStartupModelID: String? {
        guard let draft, let snapshot,
              draft.originalMaxModelSlots == 1,
              draft.originalStartupPreload == true,
              draft.original.preloaded.count == 1 else { return nil }
        return Self.resolvedCatalogID(for: draft.original.preloaded[0], in: snapshot.inventory)
    }

    func automaticModeUnavailableReason(preferredModelID: String) -> String? {
        guard operation == .idle else { return "Another provider action is in progress" }
        guard pendingConfirmation == nil else { return "Finish the pending provider action first" }
        guard let draft, let snapshot else { return "Provider configuration is unavailable" }
        guard !draft.hasChanges else { return "Save or discard pending changes before changing Auto" }
        guard draft == snapshot.draft, freshModelSources(in: snapshot) else {
            return "Refresh model controls before changing Auto"
        }
        if let validation = draftValidationMessage { return validation }
        guard !draft.original.enabled.isEmpty else { return "Enable a model before choosing Auto" }
        var resolvedIDs = Set<String>()
        var preferredSelector: String?
        for selector in draft.original.enabled {
            guard let id = Self.resolvedCatalogID(for: selector, in: snapshot.inventory),
                  resolvedIDs.insert(id).inserted,
                  let item = snapshot.inventory.myCatalog.first(where: { $0.catalogID == id }),
                  item.isDownloaded, item.localID != nil, item.issue == nil else {
                return "Refresh downloaded model selection before changing Auto"
            }
            if id == preferredModelID { preferredSelector = selector }
        }
        guard let preferredSelector else { return "Choose an enabled downloaded model" }
        if draft.originalMaxModelSlots == 1,
           draft.originalStartupPreload == true,
           draft.original.preloaded == [preferredSelector] {
            return "Auto is already saved with this startup model"
        }
        return nil
    }

    /// Save the existing enabled set with one startup preload and one resident
    /// slot. Running capacity and preload change on the next provider start;
    /// live advertisement remains a separate, explicitly gated action.
    func configureAutomaticMode(preferredModelID: String) async {
        guard automaticModeUnavailableReason(preferredModelID: preferredModelID) == nil,
              var candidate = draft, let snapshot else { return }
        guard let selector = candidate.original.enabled.first(where: {
            Self.resolvedCatalogID(for: $0, in: snapshot.inventory) == preferredModelID
        }) else { return }
        candidate.selection.preloaded = [selector]
        candidate.maxModelSlots = 1
        candidate.startupPreload = true
        self.draft = candidate
        await save()
    }

    /// Stage the provider-wide CBv2 concurrent-request cap. Per-model TOML
    /// overrides remain untouched and continue to take precedence at runtime.
    func setEngineV2MaxConcurrent(_ engineV2MaxConcurrent: Int) {
        guard var draft, (1...24).contains(engineV2MaxConcurrent) else { return }
        draft.engineV2MaxConcurrent = engineV2MaxConcurrent
        self.draft = draft
    }

    func save() async {
        guard canSave, let draftToSave = draft,
              let generation = begin(.saving)
        else { return }
        let controller = self.controller
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await controller.performSave(
                    draftToSave,
                    onPhase: { [weak self] phase in
                        await self?.advanceMutationPhase(phase, generation: generation)
                    }
                )
                let result = completion.result
                draft = result.draft
                if let snapshot {
                    self.snapshot = ProviderControlSnapshot(
                        inventory: snapshot.inventory,
                        draft: result.draft,
                        daemonState: snapshot.daemonState,
                        residentModelIDs: snapshot.residentModelIDs,
                        capturedAt: snapshot.capturedAt,
                        sources: snapshot.sources,
                        effectiveCacheDirectory: snapshot.effectiveCacheDirectory,
                        liveSwitchAvailability: snapshot.liveSwitchAvailability
                    )
                }
                await reconcileCompletedMutation(
                    completion.controls,
                    preserving: nil,
                    failureMessage: "Settings were saved, but model controls could not refresh.",
                    uncertainFailureMessage: "Settings were saved, but model controls could not refresh."
                )
            } catch is CancellationError {
                // The service owns rollback and publication boundaries.
            } catch let error as ProviderControlError {
                errorMessage = controlErrorMessage(error, action: "save")
            } catch let error as ProviderConfigError {
                errorMessage = configErrorMessage(error)
            } catch {
                errorMessage = "Could not save provider settings."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    func applyLive() async {
        guard canApplyLive, let savedEnabledModels = draft?.original.enabled,
              let generation = begin(.liveSwitch)
        else { return }
        let controller = self.controller
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await controller.performLiveSwitch(
                    enabledModels: savedEnabledModels,
                    onPhase: { [weak self] phase in
                        await self?.advanceMutationPhase(phase, generation: generation)
                    }
                )
                await reconcileCompletedMutation(
                    completion,
                    preserving: draft,
                    failureMessage: "The live switch completed, but model controls could not refresh.",
                    uncertainFailureMessage:
                        "The live switch outcome could not be confirmed; model controls could not refresh."
                )
            } catch is CancellationError {
                // Cancellation is authoritative until the service reports dispatch.
            } catch let error as ProviderControlError {
                errorMessage = controlErrorMessage(error, action: "apply models live")
            } catch {
                errorMessage = "Could not apply the saved model selection live."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    /// Enable and save this model, then apply the saved selection to a running
    /// provider without a lifecycle restart. An offline provider picks it up
    /// on its next start.
    func activateModel(_ modelID: String, providerKnownRunning: Bool? = nil) async {
        guard activationUnavailableReason(
            for: modelID,
            providerKnownRunning: providerKnownRunning
        ) == nil,
              let initialDraft = draft,
              let initialSnapshot = snapshot,
              let generation = begin(.saving, model: modelID, historyAction: .modelSelection) else { return }
        let alreadySaved = initialDraft.original.enabled.contains {
            Self.resolvedCatalogID(for: $0, in: initialSnapshot.inventory) == modelID
        }
        let controller = self.controller
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var saved = false
            var applyingLive = false
            do {
                var current = initialSnapshot
                var savedDraft = initialDraft
                if !alreadySaved {
                    var selection = initialDraft.selection
                    Self.setMembership(true, modelID: modelID, in: &selection.enabled)
                    let completion = try await controller.performSave(
                        initialDraft.withSelection(selection),
                        onPhase: { [weak self] phase in
                            await self?.advanceMutationPhase(phase, generation: generation)
                        }
                    )
                    saved = true
                    savedDraft = completion.result.draft
                    draft = savedDraft
                    // The save is published even if its follow-up refresh is
                    // uncertain. Never dispatch Apply Live from old evidence.
                    do {
                        current = try await refreshControlsAfterCompletedMutation()
                        accept(current)
                    } catch {
                        invalidateActionableSnapshot()
                        errorMessage = "Model was saved, but current provider state could not refresh. Apply Live was not attempted."
                        finish(generation)
                        return
                    }
                }
                if initialSnapshot.daemonState != nil, current.daemonState == nil {
                    errorMessage = "Model was saved, but current provider state could not be confirmed. Apply Live was not attempted."
                    finish(generation)
                    return
                }
                if current.daemonState != nil {
                    guard current.draft.original == savedDraft.original,
                          current.draft.original.enabled.contains(where: {
                            Self.resolvedCatalogID(for: $0, in: current.inventory) == modelID
                          }),
                          freshModelSources(in: current),
                          current.sources.daemon.evaluated(
                            at: now(),
                            invalidReason: "Provider state is unavailable",
                            staleReason: "Provider state is stale",
                            futureReason: "Provider state timestamp is in the future"
                          ).isMarkedFresh,
                          let advertised = current.daemonState?.advertisedModels,
                          !hasUnexpectedAdvertisedModels(advertised, in: current),
                          liveActivationUnavailableReason(in: current) == nil else {
                        errorMessage = "Model was saved, but Apply Live is unavailable. Refresh model controls before trying again."
                        finish(generation)
                        return
                    }
                    if !advertised.contains(modelID) {
                        applyingLive = true
                        let completion = try await controller.performLiveSwitch(
                            enabledModels: savedDraft.original.enabled,
                            onPhase: { [weak self] phase in
                                await self?.advanceMutationPhase(phase, generation: generation)
                            }
                        )
                        await reconcileCompletedMutation(
                            completion,
                            preserving: draft,
                            failureMessage: "The live switch completed, but model controls could not refresh.",
                            uncertainFailureMessage:
                                "The live switch outcome could not be confirmed; model controls could not refresh."
                        )
                    }
                }
            } catch is CancellationError {
                if saved {
                    errorMessage = "Model was saved, but Apply Live was not completed. Refresh model controls before trying again."
                }
            } catch let error as ProviderControlError {
                let detail = controlErrorMessage(
                    error,
                    action: applyingLive ? "apply models live" : "save"
                )
                errorMessage = saved ? "Model was saved, but \(detail)" : detail
            } catch let error as ProviderConfigError {
                errorMessage = configErrorMessage(error)
            } catch {
                errorMessage = saved
                    ? "Model was saved, but could not apply the selection live."
                    : (applyingLive
                        ? "Could not apply the saved model selection live."
                        : "Could not save the model selection.")
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    func download(_ modelID: String) async {
        guard let generation = begin(.downloading(modelID)) else { return }
        latestDownloadProgressLine = nil
        let controller = self.controller
        let progress = DownloadProgressAccumulator(sanitizer: diagnosticSanitizer)
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await controller.performDownload(
                    modelID,
                    onOutput: { [weak self] chunk in
                        guard let line = progress.accept(chunk) else { return }
                        Task { @MainActor [weak self] in
                            guard self?.operation == .downloading(modelID) else { return }
                            self?.latestDownloadProgressLine = line
                        }
                    },
                    onPhase: { [weak self] phase in
                        await self?.advanceMutationPhase(phase, generation: generation)
                    }
                )
                latestDownloadProgressLine = progress.latestLine
                await reconcileCompletedMutation(
                    completion,
                    preserving: draft,
                    failureMessage: "Download completed, but model controls could not refresh.",
                    uncertainFailureMessage:
                        "Download outcome could not be confirmed; model controls could not refresh."
                )
            } catch is CancellationError {
                // Cancellation is surfaced by returning to idle.
            } catch let error as ProviderControlError {
                errorMessage = controlErrorMessage(error, action: "download")
            } catch {
                errorMessage = "Could not download '\(Self.safeIdentifier(modelID))'."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    func delete(_ modelID: String) async {
        guard let generation = begin(.deleting(modelID)) else { return }
        let controller = self.controller
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let completion = try await controller.performDelete(
                    modelID,
                    onPhase: { [weak self] phase in
                        await self?.advanceMutationPhase(phase, generation: generation)
                    }
                )
                await reconcileCompletedMutation(
                    completion,
                    preserving: draft,
                    failureMessage: "Delete completed, but model controls could not refresh.",
                    uncertainFailureMessage:
                        "Delete outcome could not be confirmed; model controls could not refresh."
                )
            } catch is CancellationError {
                // Cancellation is surfaced by returning to idle.
            } catch let error as ProviderControlError {
                errorMessage = controlErrorMessage(error, action: "delete")
            } catch {
                errorMessage = "Could not delete '\(Self.safeIdentifier(modelID))'."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    /// Opt-in host protection uses the ordinary serialized native lifecycle.
    /// It never confirms unknown/active activity or restarts an unowned stop.
    func performHostGPUProtection(
        _ action: ProviderLifecycleAction,
        permitted: @escaping @MainActor () -> Bool,
        confirmed: @escaping @MainActor () -> Bool
    ) async -> Bool {
        guard action != .restart, pendingConfirmation == nil, draft?.hasChanges != true,
              (action == .stop ? permitted() : ownsHostGPUPause),
              let generation = begin(.lifecycle(action), trigger: .automatic,
                  historyAction: action == .stop ? .hostGPUPause : .hostGPUResume) else { return false }
        var succeeded = false
        let intentGeneration = manualProviderIntentGeneration
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                // Periodic status can be 30 seconds old. Establish stopped
                // evidence now before permitting an owned automatic restart.
                if action == .start {
                    await refreshTelemetry()
                    try Task.checkCancellation()
                }
                let refreshed = try await controller.refresh()
                try Task.checkCancellation()
                accept(refreshed, preserving: draft)
                guard manualProviderIntentGeneration == intentGeneration,
                      draft?.hasChanges != true, pendingConfirmation == nil, permitted() else {
                    finish(generation, observedOutcome: .skipped)
                    return
                }
                let revision = refreshed.draft.sourceRevision
                if action == .start {
                    guard hostGPUResumeRevision == revision, hostGPUResumeHosting == hostingOptions(),
                          refreshed.daemonState == nil || refreshed.daemonState?.processIdentity == hostGPUStoppedIdentity else {
                        relinquishHostGPUPause()
                        finish(generation, observedOutcome: .skipped)
                        return
                    }
                } else {
                    guard await controller.activityRisk() == .idle else {
                        finish(generation, observedOutcome: .skipped)
                        return
                    }
                    try Task.checkCancellation()
                    guard await controller.activityRisk() == .idle, permitted(),
                          manualProviderIntentGeneration == intentGeneration else {
                        finish(generation, observedOutcome: .skipped)
                        return
                    }
                }
                try Task.checkCancellation()
                let hosting = hostingOptions()
                try await executeLifecycle(action, enabledModels: refreshed.draft.original.enabled,
                    generation: generation)
                try Task.checkCancellation()
                succeeded = errorMessage == nil && confirmed()
                    && manualProviderIntentGeneration == intentGeneration
                if succeeded && action == .stop {
                    hostGPUResumeRevision = revision
                    hostGPUResumeHosting = hosting
                    hostGPUStoppedIdentity = refreshed.daemonState?.processIdentity
                } else if action == .start {
                    relinquishHostGPUPause()
                }
                if !succeeded && errorMessage == nil {
                    errorMessage = "GPU protection could not confirm the provider state. Check Health & Logs."
                }
            } catch is CancellationError {
                relinquishHostGPUPause()
            } catch {
                errorMessage = "GPU protection could not complete the provider action. Check Health & Logs."
                relinquishHostGPUPause()
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
        return succeeded
    }

    func request(_ action: ProviderLifecycleAction) async {
        manualProviderIntentGeneration &+= 1
        relinquishHostGPUPause()
        onManualProviderIntent?()
        pendingConfirmation = nil
        guard let generation = begin(.lifecycle(action)) else { return }
        let controller = self.controller
        let savedEnabledModels = draft?.original.enabled ?? snapshot?.draft.original.enabled ?? []
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if action == .start {
                    try await executeLifecycle(
                        action,
                        enabledModels: savedEnabledModels,
                        generation: generation
                    )
                } else {
                    if action == .restart, snapshot?.daemonState?.advertisedModels != nil {
                        let refreshed = try await controller.refresh()
                        try Task.checkCancellation()
                        accept(refreshed, preserving: draft)
                        let comparison = ProviderSelectionComparison.make(snapshot: refreshed, now: now())
                        if comparison.differs || comparison.advertised == nil {
                            let risk = await controller.activityRisk()
                            try Task.checkCancellation()
                            pendingConfirmation = .restartSelection(risk, comparison)
                            finish(generation)
                            return
                        }
                    }
                    let firstRisk = await controller.activityRisk()
                    try Task.checkCancellation()
                    if firstRisk == .idle {
                        let finalRisk = await controller.activityRisk()
                        try Task.checkCancellation()
                        if finalRisk == .idle {
                            try await executeLifecycle(
                                action,
                                enabledModels: savedEnabledModels,
                                generation: generation
                            )
                        } else {
                            pendingConfirmation = Self.confirmation(action: action, risk: finalRisk)
                        }
                    } else {
                        pendingConfirmation = Self.confirmation(action: action, risk: firstRisk)
                    }
                }
            } catch is CancellationError {
                // Cancellation leaves authoritative state unchanged.
            } catch let error as ProviderControlError {
                errorMessage = gracefulStopFailureMessage()
                    ?? controlErrorMessage(error, action: action.rawValue)
            } catch {
                errorMessage = gracefulStopFailureMessage()
                    ?? "Could not \(action.rawValue) the provider."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    func confirmPendingLifecycle() async {
        guard let confirmation = pendingConfirmation,
              let generation = begin(.lifecycle(confirmation.action))
        else { return }
        let action = confirmation.action
        let controller = self.controller
        let savedEnabledModels = draft?.original.enabled ?? snapshot?.draft.original.enabled ?? []
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let finalRisk = await controller.activityRisk()
                try Task.checkCancellation()
                if case .restartSelection(_, let confirmed) = confirmation {
                    let refreshed = try await controller.refresh()
                    try Task.checkCancellation()
                    accept(refreshed, preserving: draft)
                    let current = ProviderSelectionComparison.make(snapshot: refreshed, now: now())
                    guard current == confirmed else {
                        pendingConfirmation = .restartSelection(finalRisk, current)
                        finish(generation)
                        return
                    }
                }
                pendingConfirmation = Self.confirmation(action: action, risk: finalRisk)
                pendingConfirmation = nil
                try await executeLifecycle(
                    action,
                    enabledModels: savedEnabledModels,
                    generation: generation
                )
            } catch is CancellationError {
                // Cancellation leaves authoritative state unchanged.
            } catch let error as ProviderControlError {
                pendingConfirmation = nil
                errorMessage = gracefulStopFailureMessage()
                    ?? controlErrorMessage(error, action: action.rawValue)
            } catch {
                pendingConfirmation = nil
                errorMessage = gracefulStopFailureMessage()
                    ?? "Could not \(action.rawValue) the provider."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
    }

    var autopilotEnrollmentUnavailableReason: String? {
        guard operation == .idle else { return "Another provider action is in progress." }
        guard pendingConfirmation == nil else { return "Finish the pending provider action first." }
        guard draft?.hasChanges != true else { return "Save or discard pending model changes before enrolling." }
        guard hostingOptions().mode != .standalone else { return "Autopilot requires network provider serving." }
        return nil
    }

    /// The native consent sheet authorizes this single graceful startup. Its
    /// authoritative preflight and reconciliation are owned by the controller.
    @discardableResult
    func enrollAutopilot() async -> Bool {
        guard autopilotEnrollmentUnavailableReason == nil,
              let generation = begin(.lifecycle(.start), historyAction: .autopilotEnrollment) else { return false }
        autopilotEnrollmentMessage = nil
        let controller = self.controller
        let hosting = hostingOptions()
        var confirmed = false
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            var observedEnrollmentOutcome: ActionHistoryOutcome?
            defer { finish(generation, observedOutcome: observedEnrollmentOutcome) }
            do {
                let completion = try await controller.performAutopilotEnrollment(hosting: hosting,
                    onPhase: { [weak self] phase in
                        await self?.advanceMutationPhase(phase, generation: generation)
                    })
                observedEnrollmentOutcome = .unconfirmed
                if let refreshed = completion.controls.snapshot {
                    accept(refreshed, preserving: draft?.hasChanges == true ? draft : nil)
                } else {
                    invalidateActionableSnapshot()
                }
                if completion.liveEnrollmentConfirmed {
                    confirmed = true
                    observedEnrollmentOutcome = .succeeded
                    autopilotEnrollmentMessage = "Autopilot enrollment confirmed."
                } else if completion.savedEnrollmentConfirmed {
                    autopilotEnrollmentMessage = "Autopilot consent was saved. Refresh to check its current mode."
                    errorMessage = "Autopilot consent is saved, but live confirmation is pending."
                } else {
                    errorMessage = "Autopilot enrollment could not be confirmed. Saved settings were refreshed; review them before retrying."
                }
                await refreshTelemetry()
            } catch let error as ProviderControlError {
                errorMessage = controlErrorMessage(error, action: "enroll Autopilot")
            } catch let error as ProviderConfigError {
                errorMessage = configErrorMessage(error)
            } catch is CancellationError {
                errorMessage = "Autopilot enrollment was cancelled before dispatch."
            } catch {
                errorMessage = "Autopilot enrollment could not be confirmed. Refresh before trying again."
            }
        }
        currentTask = task
        await awaitTask(task)
        return confirmed
    }

    /// Serialize official CLI setting writes with every existing model/lifecycle
    /// operation. A pending confirmation or staged model draft must be resolved
    /// first, because the CLI changes the same TOML revision.
    func performSettingsMutation(
        _ label: String,
        failureMessage: String? = nil,
        mutation: @escaping @Sendable () async throws -> Void
    ) async -> Bool {
        let historyAction: ActionHistoryAction = label == "Autopilot pause" ? .autopilotPause
            : label == "Autopilot resume" ? .autopilotResume
            : label == "Autopilot disable" ? .autopilotDisable
            : label == "hosting" ? .hosting
            : label.hasPrefix("fan control") ? .cooling
            : label == "idle memory policy" ? .idleSettings
            : label.hasPrefix("beta ") ? .betaSettings
            : label == "automatic provider updates" ? .providerUpdates : .saveSettings
        guard pendingConfirmation == nil, draft?.hasChanges != true,
              let generation = begin(.saving, historyAction: historyAction) else { return false }
        var succeeded = false
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try Task.checkCancellation()
                try await mutation()
                advanceMutationPhase(.reconciling, generation: generation)
                // Once saved, always reconcile even if the view disappeared.
                let refreshed = try await refreshControlsAfterCompletedMutation()
                accept(refreshed)
                succeeded = true
            } catch {
                invalidateActionableSnapshot()
                errorMessage = failureMessage
                    ?? "Provider settings could not be confirmed. Refresh before trying again."
            }
            finish(generation)
        }
        currentTask = task
        await awaitTask(task)
        return succeeded
    }

    /// Applies monitor-owned hosting start flags through the official
    /// non-interactive start path. `mode == .off` re-runs start without
    /// endpoint flags, removing the endpoint from the next provider
    /// registration. Like every other start, the CLI drains and replaces the
    /// running provider rather than interrupting accepted work.
    func applyHosting(_ options: HostingOptions) async -> Bool {
        await performSettingsMutation(
            "hosting",
            failureMessage: "Hosting settings could not be applied. Refresh before trying again."
        ) { [controller] in
            _ = try await controller.performLifecycle(
                .start,
                enabledModels: [],
                hosting: options,
                onPhase: nil
            )
        }
    }

    func cancelPendingLifecycle() {
        pendingConfirmation = nil
    }

    func cancelCurrentOperation() {
        historyCancelled = currentTask != nil
        currentTask?.cancel()
    }

    func cancelCurrentOperationAndWait() async {
        // Keep the owned task even if its finish() clears currentTask while
        // cancellation or completed-mutation reconciliation is running.
        let task = currentTask
        cancelCurrentOperation()
        await task?.value
    }

    private func executeLifecycle(
        _ action: ProviderLifecycleAction,
        enabledModels: [String],
        generation: UInt64
    ) async throws {
        let requestedAt = now()
        let completion: ProviderMutationCompletion
        do {
            completion = try await controller.performLifecycle(
                action,
                enabledModels: enabledModels,
                hosting: action == .stop ? .default : hostingOptions(),
                onPhase: { [weak self] phase in
                    await self?.advanceMutationPhase(phase, generation: generation)
                }
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let commandError = error
            advanceMutationPhase(.reconciling, generation: generation)
            do {
                try await reconcileFailedLifecycleState()
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Preserve the command failure when its best-effort
                // reconciliation also fails.
            }
            throw commandError
        }
        guard await reconcileLifecycleState(after: completion) else {
            errorMessage = completion.isOutcomeUncertain
                ? "Provider \(action.rawValue) outcome could not be confirmed; current state could not refresh."
                : "Provider \(action.rawValue) completed, but current state could not be confirmed."
            return
        }
        if action == .start || action == .restart {
            do {
                try await awaitStartup(requestedAt)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                errorMessage = "Startup is taking longer than expected. Check Health & Logs before trying again."
            }
        }
    }

    private func reconcileLifecycleState(
        after completion: ProviderMutationCompletion
    ) async -> Bool {
        await refreshTelemetryAfterCompletedMutation()
        do {
            let refreshed = try await refreshControlsAfterCompletedMutation()
            accept(refreshed, preserving: draft)
            return true
        } catch {
            guard let refreshed = completion.snapshot else {
                invalidateActionableSnapshot()
                return false
            }
            accept(refreshed, preserving: draft)
            return true
        }
    }

    private func reconcileFailedLifecycleState() async throws {
        await refreshTelemetry()
        try Task.checkCancellation()
        let refreshed = try await controller.refresh()
        try Task.checkCancellation()
        accept(refreshed, preserving: draft)
    }

    private func gracefulStopFailureMessage() -> String? {
        guard let lifecycle = snapshot?.daemonState?.lifecycle,
              lifecycle.outcome == .draining
        else { return nil }
        guard let remaining = lifecycle.remainingRequests else {
            return "Provider remains in graceful drain. New requests are paused; select Stop again to continue."
        }
        if remaining == 0 {
            return "Provider is confirming completed usage before shutdown. New requests are paused; select Stop again to continue."
        }
        return "Provider remains in graceful drain. \(remaining) accepted request(s) remain; new requests are paused. Select Stop again to continue."
    }

    private func recordSelectionWarmup() {
        switch switchWarmupStatus {
        case .checking(let model):
            historyWarmupID = actionHistory?.record(action: .nudge, trigger: .manual,
                outcome: .started, model: model, correlationID: historyOperationID)
        case .result(_, let result, _):
            let outcome: ActionHistoryOutcome
            let reason: ActionHistoryReason?
            switch result {
            case .sent: outcome = .succeeded; reason = nil
            case .missingKey: outcome = .skipped; reason = .keyMissing
            case .keyRejected: outcome = .failed; reason = .keyRejected
            case .modelUnavailable: outcome = .skipped; reason = .modelUnavailable
            case .failed: outcome = .unconfirmed; reason = .requestFailed
            }
            actionHistory?.finish(historyWarmupID, outcome: outcome, reason: reason)
        case nil: historyWarmupID = nil
        }
    }

    private func recordSwapStatus() {
        switch swapStatus {
        case .checking(let model):
            historySwapID = actionHistory?.record(action: .swap, trigger: .manual, outcome: .started, model: model)
        case .confirmed: actionHistory?.finish(historySwapID, outcome: .succeeded)
        case .unconfirmed: actionHistory?.finish(historySwapID, outcome: .unconfirmed, reason: .notConfirmed)
        case .failed: actionHistory?.finish(historySwapID, outcome: .failed, reason: .requestFailed)
        case nil: break
        }
    }

    private func recordSwapNudgeStatus() {
        switch swapNudgeStatus {
        case .checking(let model):
            historyNudgeID = actionHistory?.record(action: .nudge, trigger: .swap, outcome: .started,
                model: model, correlationID: historySwapID)
        case .result(let model, let result, _):
            if historyNudgeID == nil {
                historyNudgeID = actionHistory?.record(action: .nudge, trigger: .swap, outcome: .started,
                    model: model, correlationID: historySwapID)
            }
            let outcome: ActionHistoryOutcome
            let reason: ActionHistoryReason?
            switch result {
            case .sent: outcome = .succeeded; reason = nil
            case .missingKey: outcome = .skipped; reason = .keyMissing
            case .keyRejected: outcome = .failed; reason = .keyRejected
            case .modelUnavailable: outcome = .skipped; reason = .modelUnavailable
            case .failed: outcome = .unconfirmed; reason = .requestFailed
            }
            actionHistory?.finish(historyNudgeID, outcome: outcome, reason: reason)
        case nil: historyNudgeID = nil
        }
    }

    private func begin(_ newOperation: ProviderOperation, trigger: ActionHistoryTrigger = .manual, model: String? = nil, historyAction: ActionHistoryAction? = nil) -> UInt64? {
        if trigger == .manual, newOperation != .idle, newOperation != .refreshing {
            manualProviderIntentGeneration &+= 1
            relinquishHostGPUPause()
            onManualProviderIntent?()
        }
        guard operation == .idle else { return nil }
        operationGeneration &+= 1
        historyCancelled = false
        let action: ActionHistoryAction?
        var recordedModel = model
        switch newOperation {
        case .idle, .refreshing, .nudging: action = nil
        case .saving: action = historyAction ?? .saveSettings
        case .liveSwitch: action = .modelSelection
        case .downloading(let id): action = .downloadModel; recordedModel = id
        case .deleting(let id): action = .deleteModel; recordedModel = id
        case .lifecycle(let value):
            switch value {
            case .start: action = historyAction ?? .startProvider
            case .stop: action = historyAction ?? .stopProvider
            case .restart: action = .restartProvider
            }
        }
        historyOperationID = action.map {
            actionHistory?.record(action: $0, trigger: trigger, outcome: .started, model: recordedModel)
        } ?? nil
        operation = newOperation
        switch newOperation {
        case .saving, .liveSwitch, .downloading, .deleting, .lifecycle:
            operationPhase = .mutating
        case .idle, .refreshing, .nudging:
            operationPhase = nil
        }
        errorMessage = nil
        switchWarmupStatus = nil
        swapStatus = nil
        swapNudgeStatus = nil
        return operationGeneration
    }

    private func advanceMutationPhase(
        _ phase: ProviderMutationPhase,
        generation: UInt64
    ) {
        guard operationGeneration == generation, operation != .idle else { return }
        operationPhase = phase
    }

    private func finish(_ generation: UInt64, observedOutcome: ActionHistoryOutcome? = nil) {
        guard operationGeneration == generation else { return }
        actionHistory?.finish(historyOperationID,
            outcome: observedOutcome ?? (historyCancelled || Task.isCancelled ? .cancelled : (pendingConfirmation != nil ? .skipped : (errorMessage == nil ? .succeeded : .unconfirmed))),
            reason: pendingConfirmation != nil ? .confirmationRequired : (errorMessage == nil ? nil : .notConfirmed))
        historyOperationID = nil
        currentTask = nil
        operation = .idle
        operationPhase = nil
    }

    private func awaitTask(_ task: Task<Void, Never>) async {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func accept(
        _ refreshed: ProviderControlSnapshot,
        preserving stagedDraft: ProviderConfigDraft? = nil
    ) {
        snapshot = refreshed
        draft = stagedDraft ?? refreshed.draft
        savedCapacity = .available(
            value: ProviderSavedCapacity(draft: refreshed.draft),
            capturedAt: refreshed.capturedAt
        )
    }

    private static func resolvedCatalogID(
        for selector: String,
        in inventory: ModelInventory
    ) -> String? {
        let exact = inventory.myCatalog.filter { $0.catalogID == selector }
        if exact.count == 1 {
            return exact[0].catalogID
        }
        guard exact.isEmpty else { return nil }
        let aliases = inventory.myCatalog.filter {
            $0.enabledSelector == selector || $0.preloadSelector == selector
        }
        guard aliases.count == 1 else { return nil }
        return aliases[0].catalogID
    }

    private func reconcileCompletedMutation(
        _ completion: ProviderMutationCompletion,
        preserving stagedDraft: ProviderConfigDraft?,
        failureMessage: String,
        uncertainFailureMessage: String
    ) async {
        do {
            let refreshed = try await refreshControlsAfterCompletedMutation()
            accept(refreshed, preserving: stagedDraft)
        } catch {
            if let refreshed = completion.snapshot {
                accept(refreshed, preserving: stagedDraft)
            } else {
                invalidateActionableSnapshot()
                errorMessage = completion.isOutcomeUncertain
                    ? uncertainFailureMessage
                    : failureMessage
            }
        }
    }

    private func refreshControlsAfterCompletedMutation() async throws -> ProviderControlSnapshot {
        let controller = self.controller
        let refresh = Task.detached(priority: Task.currentPriority) {
            try await controller.refresh()
        }
        return try await refresh.value
    }

    private func refreshTelemetryAfterCompletedMutation() async {
        let refreshTelemetry = self.refreshTelemetry
        let refresh = Task.detached(priority: Task.currentPriority) {
            await refreshTelemetry()
        }
        await refresh.value
    }

    private func invalidateActionableSnapshot() {
        guard let snapshot else { return }
        self.snapshot = ProviderControlSnapshot(
            inventory: snapshot.inventory,
            draft: snapshot.draft,
            daemonState: snapshot.daemonState,
            residentModelIDs: snapshot.residentModelIDs,
            capturedAt: snapshot.capturedAt,
            sources: .unknown,
            effectiveCacheDirectory: snapshot.effectiveCacheDirectory
        )
    }

    private static func setMembership(
        _ included: Bool,
        modelID: String,
        in values: inout [String]
    ) {
        if included {
            if !values.contains(modelID) {
                values.append(modelID)
            }
        } else {
            values.removeAll { $0 == modelID }
        }
    }

    private static func confirmation(
        action: ProviderLifecycleAction,
        risk: ProviderActivityRisk
    ) -> LifecycleConfirmation? {
        switch (action, risk) {
        case (.stop, .active), (.stop, .unknown): .stop(risk)
        case (.restart, .active), (.restart, .unknown): .restart(risk)
        case (_, .idle), (.start, _): nil
        }
    }

    private func controlErrorMessage(
        _ error: ProviderControlError,
        action: String
    ) -> String {
        switch error {
        case .commandAlreadyRunning:
            "Another provider action is already running."
        case .executableUnavailable:
            "The Darkbloom command is unavailable."
        case .noEnabledModels:
            "Start requires at least one saved enabled model."
        case .inventoryUnavailable(let reason):
            Self.safeInventoryDiagnostics.contains(reason)
                ? diagnosticSanitizer.sanitize(reason)
                : (action == "enroll Autopilot"
                    ? "Saved models could not be verified for Autopilot. Refresh Models before trying again."
                    : "Model inventory is unavailable.")
        case .deleteBlocked(let reason):
            Self.safeDeleteDiagnostics.contains(reason)
                ? diagnosticSanitizer.sanitize(reason)
                : "The model cannot be deleted safely."
        case .invalidOutput:
            "Darkbloom returned an invalid response while trying to \(action)."
        case .hostingRequiresSupervision:
            "Standalone serving is not available in \(MonitorApplicationIdentity.displayName)."
        case .hostingUnsupportedByController:
            "This build cannot apply hosting settings."
        case .invalidHostingOptions:
            "Enter a valid port and bind address before applying hosting settings."
        case .liveSwitchUnavailable(let reason):
            Self.safeLiveSwitchDiagnostics.contains(reason)
                ? diagnosticSanitizer.sanitize(reason)
                : (action == "enroll Autopilot"
                    ? "Autopilot enrollment is unavailable. Refresh before trying again."
                    : "Apply Live is unavailable.")
        }
    }

    private func configErrorMessage(_ error: ProviderConfigError) -> String {
        switch error {
        case .changedExternally:
            "Provider settings changed outside the app. Reload and try again."
        case .preloadRequiresEnabled(let modelID):
            "Enable '\(Self.safeIdentifier(modelID))' or remove it from preload."
        case .validationFailed(let reason):
            configValidationMessage(reason)
        case .invalidUTF8, .missingArray, .missingInteger, .duplicateArray,
             .duplicateInteger, .duplicateBoolean, .malformedArray, .malformedInteger,
             .malformedBoolean,
             .nonStringValue, .unsupportedInteger, .duplicateModel:
            "Provider settings could not be read safely."
        }
    }

    private func configValidationMessage(_ reason: String) -> String {
        let message: String
        switch reason {
        case "Darkbloom rejected the candidate configuration":
            message = "Darkbloom rejected the provider settings."
        case "Could not read the provider configuration":
            message = "Could not read the provider configuration."
        case "Could not save the provider configuration":
            message = "Could not save the provider configuration."
        case "Provider configuration changed during recovery; recovery data was preserved beside it":
            message = "Provider configuration changed during recovery; recovery data was preserved beside it."
        case "Could not preserve provider configuration security metadata":
            message = "Could not preserve provider configuration security metadata."
        case "Provider configuration is busy; try again":
            message = "Provider configuration is busy; try again."
        case "Could not remove the candidate configuration; recovery data was preserved beside the provider configuration":
            message = "Could not remove the candidate configuration; recovery data was preserved beside the provider configuration."
        default:
            message = "Could not save provider settings."
        }
        return diagnosticSanitizer.sanitize(message)
    }

    private static let safeInventoryDiagnostics: Set<String> = [
        "Every saved model must be eligible for this provider before enrolling",
        "Saved preload aliases would lose their enabled match during enrollment. In Models, clear those preloads or reselect the exact downloaded model IDs, save, then retry.",
        "The requested model is not a fresh available catalog entry",
        "Saved model selection is not an unambiguous downloaded catalog model",
        "Model catalog is unavailable",
        "Local model list is unavailable",
    ]

    private static let safeRefreshInventoryDiagnostics: Set<String> = [
        "Model catalog is unavailable",
        "Local model list is unavailable",
        "Model catalog is unavailable: command timed out. If the model cache is on an external volume, check this app's macOS file access.",
        "Local model list is unavailable: command timed out. If the model cache is on an external volume, check this app's macOS file access.",
        "Model catalog is unavailable: command could not launch.",
        "Local model list is unavailable: command could not launch.",
        "Model catalog is unavailable: command output exceeded the allowed size.",
        "Local model list is unavailable: command output exceeded the allowed size.",
    ]

    private static func safeRefreshInventoryDiagnostic(_ reason: String) -> String? {
        if safeRefreshInventoryDiagnostics.contains(reason) { return reason }
        for source in ["Model catalog", "Local model list"] {
            let prefix = "\(source) is unavailable: command exited with code "
            guard reason.hasPrefix(prefix), reason.hasSuffix(".") else { continue }
            let codeText = reason.dropFirst(prefix.count).dropLast()
            guard let code = Int32(codeText), String(code) == codeText else { continue }
            return reason
        }
        return nil
    }

    private static let safeLiveSwitchDiagnostics: Set<String> = [
        "Autopilot enrollment is unavailable in this build",
        "Autopilot requires network provider serving",
        "Refresh Autopilot status before enrolling",
        "Autopilot is already enrolled. Refresh its current settings instead of restarting.",
        "Autopilot requires a saved network model selection",
        "Refresh current provider state before applying live",
        "Upgrade the running provider to use Apply Live",
        "The running provider uses a different configuration",
        "Finish the current provider lifecycle action before applying live",
        "A live model switch is already in progress",
    ]

    private static let safeDeleteDiagnostics: Set<String> = {
        let fixed = [
            "The local model identity is ambiguous",
            "Disable the model and save before deleting it",
            "Remove the model from preload and save before deleting it",
            "The local model could not be matched safely",
            "The active model cannot be deleted",
            "A loaded model cannot be deleted",
        ]
        let residency = [
            "Provider activity is unavailable",
            "Provider activity timestamp is invalid",
            "Provider activity is stale",
            "Provider activity timestamp is in the future",
            "Loaded model state is unavailable",
            "Loaded model state timestamp is invalid",
            "Loaded model state is stale",
            "Loaded model state timestamp is in the future",
        ].map { "\($0); deletion was not attempted" }
        return Set(fixed + residency)
    }()

    private static func safeIdentifier(_ value: String) -> String {
        let allowed = value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0) || "-_.".unicodeScalars.contains($0)
        }
        let sanitized = String(String.UnicodeScalarView(allowed))
        return String(sanitized.prefix(80))
    }
}

private func modelSwapStateReason(
    modelID: String,
    snapshot: ProviderControlSnapshot,
    at now: Date,
    expectedIdentity: ProcessIdentity? = nil,
    expectedAdvertised: Set<String>? = nil
) -> String? {
    guard snapshot.sources.daemon.evaluated(
        at: now,
        invalidReason: "Provider state unavailable",
        staleReason: "Provider state stale",
        futureReason: "Provider state timestamp invalid"
    ).isMarkedFresh,
        snapshot.sources.loadedModels.evaluated(
            at: now,
            invalidReason: "Loaded models unavailable",
            staleReason: "Loaded models stale",
            futureReason: "Loaded models timestamp invalid"
        ).isMarkedFresh,
        let daemon = snapshot.daemonState,
        let advertised = daemon.advertisedModels else {
        return "Refresh local model status before swapping"
    }
    guard expectedIdentity == nil || daemon.processIdentity == expectedIdentity else {
        return "Provider changed; refresh before swapping"
    }
    guard expectedAdvertised == nil || Set(advertised) == expectedAdvertised else {
        return "Advertised models changed; refresh before swapping"
    }
    guard advertised.contains(modelID) else { return "Add this model to the advertised set first" }
    guard snapshot.draft.originalMaxModelSlots == 1,
          daemon.warmModels.count == 1,
          snapshot.residentModelIDs == Set(daemon.warmModels) else {
        return "Swap requires one saved model slot and one loaded model"
    }
    guard !snapshot.residentModelIDs.contains(modelID) else { return "This model is already loaded" }
    guard !daemon.inferenceActive,
          (daemon.lifecycle?.remainingRequests ?? 0) == 0,
          (daemon.modelSwitch?.remainingRequests ?? 0) == 0 else {
        return "Wait for current work to finish before swapping"
    }
    if let lifecycle = daemon.lifecycle,
       lifecycle.outcome != .serving {
        return "Wait for the provider to finish its current action"
    }
    if let modelSwitch = daemon.modelSwitch,
       [.validating, .draining, .switching].contains(modelSwitch.outcome) {
        return "Wait for the current model switch to finish"
    }
    return nil
}

private func modelSwapConfirmed(
    modelID: String,
    snapshot: ProviderControlSnapshot,
    at now: Date,
    expectedIdentity: ProcessIdentity,
    expectedAdvertised: Set<String>
) -> Bool {
    guard snapshot.sources.daemon.evaluated(
        at: now,
        invalidReason: "Provider state unavailable",
        staleReason: "Provider state stale",
        futureReason: "Provider state timestamp invalid"
    ).isMarkedFresh,
        snapshot.sources.loadedModels.evaluated(
            at: now,
            invalidReason: "Loaded models unavailable",
            staleReason: "Loaded models stale",
            futureReason: "Loaded models timestamp invalid"
        ).isMarkedFresh,
        let daemon = snapshot.daemonState,
        daemon.processIdentity == expectedIdentity,
        Set(daemon.advertisedModels ?? []) == expectedAdvertised else { return false }
    return snapshot.draft.originalMaxModelSlots == 1 &&
        daemon.warmModels == [modelID] && snapshot.residentModelIDs == [modelID]
}

private final class UserDiagnosticSanitizer: @unchecked Sendable {
    private static let maximumLength = 200
    private let homePath: String

    init(homeDirectory: URL) {
        homePath = Self.normalizedForMatching(homeDirectory.standardizedFileURL.path)
    }

    func sanitize(_ value: String) -> String {
        var result = Self.normalizedForMatching(value)
        if homePath != "/" && !homePath.isEmpty {
            result = result.replacingOccurrences(of: homePath, with: "~")
        }
        result = Self.replacing(
            pattern: #"(?i)Authorization\s*:\s*Bearer\s+[^\s,;]+"#,
            in: result,
            with: "Authorization: <redacted>"
        )
        result = Self.replacing(
            pattern: #"(?i)\b(access[_ -]?token|refresh[_ -]?token|auth(?:orization)?[_ -]?token|token|api[_ -]?key|password|secret)\b\s*[:=]\s*(?:\"[^\"]*\"|'[^']*'|[^\s,;]+)"#,
            in: result,
            with: "$1=<redacted>"
        )
        result = Self.normalizedForMatching(result)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return String(result.prefix(Self.maximumLength))
    }

    private static func normalizedForMatching(_ value: String) -> String {
        var normalized = value.precomposedStringWithCanonicalMapping
        // Collapse obfuscating controls while retaining ANSI delimiters long
        // enough to remove the entire sequence, including its visible payload.
        normalized = String(normalized.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
                || $0.value == 0x07
                || $0.value == 0x1B
        })
        let ansiPatterns = [
            #"\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)"#,
            #"\x1B\[[0-?]*[ -/]*[@-~]"#,
            #"\x1B[@-_]"#,
        ]
        for pattern in ansiPatterns {
            normalized = replacing(
                pattern: pattern,
                in: normalized,
                with: ""
            )
        }
        return String(normalized.unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0)
        })
    }

    private static func replacing(
        pattern: String,
        in value: String,
        with replacement: String
    ) -> String {
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return value }
        let range = NSRange(value.startIndex..., in: value)
        return expression.stringByReplacingMatches(
            in: value,
            range: range,
            withTemplate: replacement
        )
    }
}

private final class DownloadProgressAccumulator: @unchecked Sendable {
    private struct StreamState {
        var line = Data()
        var isTruncated = false
        var lastUpdate: UInt64 = 0

        mutating func accept(
            _ data: Data,
            maximumLineBytes: Int,
            sanitizer: UserDiagnosticSanitizer
        ) -> String? {
            var latestCompletedLine: String?
            for byte in data {
                if byte == 0x0A || byte == 0x0D {
                    if !isTruncated,
                       let candidate = Self.sanitized(line, using: sanitizer) {
                        latestCompletedLine = candidate
                    }
                    line.removeAll(keepingCapacity: true)
                    isTruncated = false
                } else if !isTruncated {
                    if line.count < maximumLineBytes {
                        line.append(byte)
                    } else {
                        // Never retain a suffix after losing its identifying
                        // prefix: the entire logical line becomes unrenderable.
                        line.removeAll(keepingCapacity: false)
                        isTruncated = true
                    }
                }
            }
            return latestCompletedLine
        }

        func sanitizedIncompleteLine(
            using sanitizer: UserDiagnosticSanitizer
        ) -> String? {
            guard !isTruncated else { return nil }
            return Self.sanitized(line, using: sanitizer)
        }

        private static func sanitized(
            _ data: Data,
            using sanitizer: UserDiagnosticSanitizer
        ) -> String? {
            guard !data.isEmpty else { return nil }
            let value = sanitizer.sanitize(String(decoding: data, as: UTF8.self))
            return value.isEmpty ? nil : value
        }
    }

    private struct StoredLine {
        let sequence: UInt64
        let value: String
    }

    private static let maximumLineBytes = 4_096
    private let lock = NSLock()
    private let sanitizer: UserDiagnosticSanitizer
    private var standardOutput = StreamState()
    private var standardError = StreamState()
    private var storedLatestLine: StoredLine?
    private var sequence: UInt64 = 0

    init(sanitizer: UserDiagnosticSanitizer) {
        self.sanitizer = sanitizer
    }

    var latestLine: String? {
        lock.withLock {
            var candidates = [StoredLine]()
            if let storedLatestLine {
                candidates.append(storedLatestLine)
            }
            if let value = standardOutput.sanitizedIncompleteLine(using: sanitizer) {
                candidates.append(StoredLine(
                    sequence: standardOutput.lastUpdate,
                    value: value
                ))
            }
            if let value = standardError.sanitizedIncompleteLine(using: sanitizer) {
                candidates.append(StoredLine(
                    sequence: standardError.lastUpdate,
                    value: value
                ))
            }
            return candidates.max { $0.sequence < $1.sequence }?.value
        }
    }

    func accept(_ chunk: ProcessOutputChunk) -> String? {
        lock.withLock {
            sequence &+= 1
            let completed: String?
            switch chunk.destination {
            case .standardOutput:
                standardOutput.lastUpdate = sequence
                completed = standardOutput.accept(
                    chunk.data,
                    maximumLineBytes: Self.maximumLineBytes,
                    sanitizer: sanitizer
                )
            case .standardError:
                standardError.lastUpdate = sequence
                completed = standardError.accept(
                    chunk.data,
                    maximumLineBytes: Self.maximumLineBytes,
                    sanitizer: sanitizer
                )
            }
            if let completed {
                storedLatestLine = StoredLine(sequence: sequence, value: completed)
            }
            return completed
        }
    }
}
