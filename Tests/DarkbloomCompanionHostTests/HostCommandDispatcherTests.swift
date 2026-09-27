import DarkbloomCompanionProtocol
import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomCompanionHost

@Suite(.serialized)
struct HostCommandDispatcherTests {
    @Test func lifecycleAndAppCommandsUseTypedAdapters() async throws {
        let provider = RecordingProvider()
        let app = RecordingApp()
        let settings = CompanionSettingsCoordinator(provider: provider)
        let dispatcher = HostCommandDispatcher(provider: provider, settings: settings, app: app)
        let stop = AuthorizedCommand(
            commandID: UUID(),
            proposal: .init(requestID: UUID(), action: .providerLifecycle(.stop)),
            deviceID: UUID()
        )
        let stopResult = try await dispatcher.dispatch(stop)
        #expect(stopResult.state == .succeeded)
        #expect(await provider.lifecycleActions == [.stop])

        let quit = AuthorizedCommand(
            commandID: UUID(),
            proposal: .init(requestID: UUID(), action: .appLifecycle(.quit)),
            deviceID: UUID()
        )
        _ = try await dispatcher.dispatch(quit)
        #expect(await app.actions == [.quit])
    }

    @Test func settingsDraftPreservesOpaqueRevisionAndDoesNotImplicitlyRestart() async throws {
        let provider = RecordingProvider()
        let coordinator = CompanionSettingsCoordinator(provider: provider)
        let initial = try await coordinator.makeDraft()
        let patch = SettingsPatch(provider: .init(
            enabledModels: ["model-a"], preloadModels: ["model-a"],
            maximumConcurrentRequests: 3, residentModelSlots: 2, startupPreload: true
        ))
        let changed = try await coordinator.patch(.init(
            draftID: initial.draftID, expectedRevision: initial.revision, patch: patch
        ))
        #expect(changed.revision == initial.revision)
        #expect(changed.saved.enabledModels == ["model-a"])
        #expect(changed.restartRequired)
        _ = try await coordinator.save(draftID: initial.draftID, expectedRevision: initial.revision)
        #expect(await provider.saveCount == 1)
        #expect(await provider.lifecycleActions.isEmpty)
    }

    @Test func failedMutationReturnsAQueryableTerminalOperation() async throws {
        let provider = RecordingProvider(failLifecycle: true)
        let app = RecordingApp()
        let settings = CompanionSettingsCoordinator(provider: provider)
        let dispatcher = HostCommandDispatcher(provider: provider, settings: settings, app: app)
        let deviceID = UUID()
        let command = AuthorizedCommand(
            commandID: UUID(),
            proposal: .init(requestID: UUID(), action: .providerLifecycle(.stop)),
            deviceID: deviceID
        )

        let result = try await dispatcher.dispatch(command)

        #expect(result.state == .failed)
        #expect(result.error?.code == .internalFailure)
        #expect(await dispatcher.operation(result.operationID, deviceID: deviceID) == result)
    }
}

private actor RecordingApp: MacAppLifecycleControlling {
    private(set) var actions: [DarkbloomCompanionProtocol.AppLifecycleAction] = []
    func perform(_ action: DarkbloomCompanionProtocol.AppLifecycleAction) { actions.append(action) }
}

private actor RecordingProvider: ProviderControlling {
    private(set) var lifecycleActions: [DarkbloomTelemetry.ProviderLifecycleAction] = []
    private(set) var saveCount = 0
    private let failLifecycle: Bool
    private var draft = ProviderConfigDraft(
        sourceRevision: "opaque-r1",
        original: .init(enabled: [], preloaded: []),
        selection: .init(enabled: [], preloaded: []),
        originalMaxModelSlots: 1, maxModelSlots: 1,
        originalEngineV2MaxConcurrent: 1, engineV2MaxConcurrent: 1
    )

    init(failLifecycle: Bool = false) { self.failLifecycle = failLifecycle }

    func refresh() -> ProviderControlSnapshot {
        ProviderControlSnapshot(
            inventory: ModelInventoryBuilder.build(
                catalog: [], local: [], selection: draft.selection, daemon: nil, loadedModels: []
            ),
            draft: draft,
            capturedAt: .now,
            sources: .init(
                catalog: .fresh(evidenceAt: .now),
                localModels: .fresh(evidenceAt: .now),
                daemon: .fresh(evidenceAt: .now),
                loadedModels: .fresh(evidenceAt: .now)
            )
        )
    }

    func save(_ draft: ProviderConfigDraft) -> ProviderConfigSaveResult {
        saveCount += 1
        self.draft = ProviderConfigDraft(
            sourceRevision: "opaque-r2",
            original: draft.selection,
            selection: draft.selection,
            originalMaxModelSlots: draft.maxModelSlots,
            maxModelSlots: draft.maxModelSlots,
            originalEngineV2MaxConcurrent: draft.engineV2MaxConcurrent,
            engineV2MaxConcurrent: draft.engineV2MaxConcurrent
        )
        return .init(draft: self.draft, restartRequired: true)
    }

    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) {}
    func delete(_ localModelID: String) {}
    func activityRisk() -> ProviderActivityRisk { .idle }
    func execute(_ action: DarkbloomTelemetry.ProviderLifecycleAction, enabledModels: [String]) {
        lifecycleActions.append(action)
    }

    func performLifecycle(
        _ action: DarkbloomTelemetry.ProviderLifecycleAction,
        enabledModels: [String],
        onPhase: ProviderMutationPhaseObserver?
    ) throws -> ProviderMutationCompletion {
        if failLifecycle { throw RecordingProviderError.expectedFailure }
        lifecycleActions.append(action)
        return .refreshed(refresh())
    }
}

private enum RecordingProviderError: Error { case expectedFailure }
