import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

private let activationNow = Date(timeIntervalSince1970: 1_750_000_000)

@Suite("Popup model activation")
@MainActor
struct ProviderPopupActivationTests {
    @Test("running activation saves only the requested model and applies the saved selection")
    func savesAndApplies() async throws {
        let controller = ActivationController(snapshot: try activationSnapshot(advertised: ["saved-model"]))
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()

        #expect(store.activationUnavailableReason(for: "second-model") == nil)
        await store.activateModel("second-model")

        #expect(await controller.savedSelections == [["saved-model", "second-model"]])
        #expect(await controller.appliedSelections == [["saved-model", "second-model"]])
        #expect(store.draft?.original.enabled == ["saved-model", "second-model"])
        #expect(store.draft?.hasChanges == false)
        #expect(store.errorMessage == nil)
    }

    @Test("a saved model missing from the running advertisement applies without saving")
    func appliesAlreadySaved() async throws {
        let controller = ActivationController(snapshot: try activationSnapshot(
            enabled: ["saved-model", "second-model"], advertised: ["saved-model"]
        ))
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        await store.activateModel("second-model")

        #expect(await controller.savedSelections.isEmpty)
        #expect(await controller.appliedSelections == [["saved-model", "second-model"]])
    }

    @Test("offline activation saves for the next start without a live switch or restart")
    func savesOffline() async throws {
        let controller = ActivationController(snapshot: try activationSnapshot(advertised: nil))
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        #expect(store.activationUnavailableReason(for: "second-model") ==
            "Refresh current provider state before activating a model")
        await store.activateModel("second-model", providerKnownRunning: false)

        #expect(await controller.savedSelections == [["saved-model", "second-model"]])
        #expect(await controller.appliedSelections.isEmpty)
        #expect(await controller.lifecycleActions.isEmpty)
        #expect(store.draft?.original.enabled == ["saved-model", "second-model"])
        #expect(store.errorMessage == nil)
    }

    @Test("pending drafts and stale inventory block activation without publishing")
    func blocksUnsafeActivation() async throws {
        let controller = ActivationController(snapshot: try activationSnapshot(advertised: ["saved-model"]))
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        store.setMaxModelSlots(2)
        let staged = try #require(store.draft)
        #expect(store.activationUnavailableReason(for: "second-model") ==
            "Save or discard pending changes before activating a model")
        await store.activateModel("second-model")
        #expect(store.draft == staged)
        #expect(await controller.savedSelections.isEmpty)

        let stale = ActivationController(snapshot: try activationSnapshot(
            advertised: ["saved-model"], staleModels: true
        ))
        let staleStore = ProviderControlStore(controller: stale, now: { activationNow })
        await staleStore.refresh()
        #expect(staleStore.activationUnavailableReason(for: "second-model") ==
            "Refresh model controls before activating a model")
        await staleStore.activateModel("second-model")
        #expect(await stale.savedSelections.isEmpty)
        #expect(await stale.appliedSelections.isEmpty)
    }

    @Test("a failed save never dispatches Apply Live")
    func failedSaveDoesNotApply() async throws {
        let controller = ActivationController(
            snapshot: try activationSnapshot(advertised: ["saved-model"]),
            saveFailure: .changedExternally
        )
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        await store.activateModel("second-model")

        #expect(await controller.saveAttempts == 1)
        #expect(await controller.appliedSelections.isEmpty)
        #expect(store.draft?.original.enabled == ["saved-model"])
        #expect(store.errorMessage == "Provider settings changed outside the app. Reload and try again.")
    }

    @Test("running provider without verified live switching does not save")
    func blocksUnsupportedLiveActivation() async throws {
        let controller = ActivationController(snapshot: try activationSnapshot(
            advertised: ["saved-model"], liveAvailable: false
        ))
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        #expect(store.activationUnavailableReason(for: "second-model") != nil)
        await store.activateModel("second-model")
        #expect(await controller.saveAttempts == 0)
        #expect(await controller.appliedSelections.isEmpty)
    }

    @Test("popup activation cannot withdraw a currently advertised model")
    func blocksAdvertisedExtra() async throws {
        let controller = ActivationController(snapshot: try activationSnapshot(
            advertised: ["saved-model", "other-live-model"]
        ))
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        #expect(store.activationUnavailableReason(for: "second-model") ==
            "The running model selection differs from saved settings. Use Models to review it.")
        await store.activateModel("second-model")
        #expect(await controller.saveAttempts == 0)
        #expect(await controller.appliedSelections.isEmpty)
    }

    @Test("a changed live advertisement after save blocks the live switch")
    func blocksPostSaveDrift() async throws {
        let controller = ActivationController(
            snapshot: try activationSnapshot(advertised: ["saved-model"]),
            postSaveAdvertised: ["saved-model", "other-live-model"]
        )
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        await store.activateModel("second-model")
        #expect(await controller.savedSelections == [["saved-model", "second-model"]])
        #expect(await controller.appliedSelections.isEmpty)
        #expect(store.errorMessage?.contains("Model was saved") == true)
    }

    @Test("a running provider lost after save reports that live activation is unconfirmed")
    func reportsLostProviderEvidence() async throws {
        let controller = ActivationController(
            snapshot: try activationSnapshot(advertised: ["saved-model"]),
            loseDaemonAfterSave: true
        )
        let store = ProviderControlStore(controller: controller, now: { activationNow })
        await store.refresh()
        await store.activateModel("second-model")
        #expect(await controller.savedSelections == [["saved-model", "second-model"]])
        #expect(await controller.appliedSelections.isEmpty)
        #expect(store.errorMessage ==
            "Model was saved, but current provider state could not be confirmed. Apply Live was not attempted.")
    }
}

private actor ActivationController: ProviderControlling {
    private var current: ProviderControlSnapshot
    private let saveFailure: ProviderConfigError?
    private let postSaveAdvertised: [String]?
    private let loseDaemonAfterSave: Bool
    private(set) var saveAttempts = 0
    private(set) var savedSelections: [[String]] = []
    private(set) var appliedSelections: [[String]] = []
    private(set) var lifecycleActions: [ProviderLifecycleAction] = []

    init(
        snapshot: ProviderControlSnapshot,
        saveFailure: ProviderConfigError? = nil,
        postSaveAdvertised: [String]? = nil,
        loseDaemonAfterSave: Bool = false
    ) {
        current = snapshot
        self.saveFailure = saveFailure
        self.postSaveAdvertised = postSaveAdvertised
        self.loseDaemonAfterSave = loseDaemonAfterSave
    }

    func refresh() async throws -> ProviderControlSnapshot { current }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        saveAttempts += 1
        if let saveFailure { throw saveFailure }
        savedSelections.append(draft.selection.enabled)
        let saved = ProviderConfigDraft(
            sourceRevision: "saved-\(saveAttempts)",
            original: draft.selection,
            selection: draft.selection,
            originalMaxModelSlots: draft.maxModelSlots,
            maxModelSlots: draft.maxModelSlots
        )
        let postSave = try postSaveAdvertised.map {
            try activationSnapshot(enabled: draft.selection.enabled, advertised: $0)
        }
        current = ProviderControlSnapshot(
            inventory: postSave?.inventory ?? current.inventory,
            draft: saved,
            daemonState: loseDaemonAfterSave ? nil : (postSave?.daemonState ?? current.daemonState),
            capturedAt: activationNow,
            sources: current.sources,
            liveSwitchAvailability: current.liveSwitchAvailability
        )
        return ProviderConfigSaveResult(draft: saved, restartRequired: true)
    }

    func performLiveSwitch(
        enabledModels: [String],
        onPhase: ProviderMutationPhaseObserver?
    ) async throws -> ProviderMutationCompletion {
        appliedSelections.append(enabledModels)
        await onPhase?(.reconciling)
        return .refreshed(current)
    }

    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {
        throw CancellationError()
    }

    func delete(_ localModelID: String) async throws { throw CancellationError() }

    func activityRisk() async -> ProviderActivityRisk { .idle }

    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        lifecycleActions.append(action)
    }
}

private func activationSnapshot(
    enabled: [String] = ["saved-model"],
    advertised: [String]?,
    staleModels: Bool = false,
    liveAvailable: Bool = true
) throws -> ProviderControlSnapshot {
    let selection = ProviderModelSelection(enabled: enabled, preloaded: [])
    let draft = ProviderConfigDraft(
        sourceRevision: "initial",
        original: selection,
        selection: selection
    )
    let catalog = ["saved-model", "second-model"].map { id in
        CatalogModel(
            id: id, displayName: id, family: id, modelType: "text",
            capabilities: ["text"], sizeGB: 1, minimumRAMGB: 4, active: true
        )
    }
    let local = ["saved-model", "second-model"].map { id in
        LocalModel(id: id, modelType: "text", sizeBytes: 1, estimatedMemoryGB: nil)
    }
    let daemon: DaemonState?
    if let advertised {
        let raw: [String: Any] = [
            "schema": 1, "version": "0.9.7", "current_model": "saved-model",
            "warm_models": ["saved-model"], "advertised_models": advertised,
            "stats": ["tokens_generated": 0, "requests_served": 0, "usage_gaps": 0],
            "trust": ["trust_level": "hardware", "status": "online", "reason": "same_binary", "received_at": activationNow.timeIntervalSince1970],
            "capacity": ["total_memory_gb": 64, "gpu_memory_active_gb": 1, "gpu_memory_cache_gb": 0],
            "slots": [], "inference_active": false,
            "started_at": activationNow.timeIntervalSince1970 - 100,
            "written_at": activationNow.timeIntervalSince1970,
            "pid": 42, "process_identity": ["pid": 42, "start_time_micros": 1234]
        ]
        daemon = try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: raw))
    } else {
        daemon = nil
    }
    let modelState: ProviderControlSourceState = staleModels
        ? .stale("stale inventory") : .fresh(evidenceAt: activationNow)
    return ProviderControlSnapshot(
        inventory: ModelInventoryBuilder.build(
            catalog: catalog, local: local, selection: selection,
            daemon: daemon, loadedModels: []
        ),
        draft: draft,
        daemonState: daemon,
        capturedAt: activationNow,
        sources: ProviderControlSourceStates(
            catalog: modelState,
            localModels: modelState,
            daemon: daemon == nil ? .unavailable("offline") : .fresh(evidenceAt: activationNow),
            loadedModels: .unavailable("offline")
        ),
        liveSwitchAvailability: liveAvailable ? .available : .unavailable("Upgrade the running provider to use Apply Live")
    )
}
