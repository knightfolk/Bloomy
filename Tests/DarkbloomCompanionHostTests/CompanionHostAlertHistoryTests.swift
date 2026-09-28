import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import DarkbloomTelemetry
import Foundation
import Testing

@Suite("Companion host alert history", .serialized)
struct CompanionHostAlertHistoryTests {
    @Test("alert history pages are bounded, newest first, and scoped to the host")
    func pagesSanitizedHistory() async throws {
        let hostID = UUID()
        let deviceID = UUID()
        let registry = InMemoryPairedDeviceRegistry()
        try await registry.enroll(pairedRecord(deviceID: deviceID, capabilities: [.history]))
        let database = try AlertHistoryDatabase(url: temporaryURL(), historyLimit: 20)
        try await database.record([
            transition(.providerOffline, .raised, at: 1),
            transition(.lifecycleTimedOut, .raised, at: 2),
            transition(.modelUnknown, .raised, at: 3),
            transition(.modelUnknown, .recovered, at: 4),
        ])
        let coordinator = makeCoordinator(hostID: hostID, registry: registry, history: database)

        let first = await coordinator.handle(deviceID: deviceID, envelope: .init(
            requestID: UUID(),
            payload: .alertHistoryQuery(.init(cursor: nil, maximumRecords: 2))
        ))
        guard case let .alertHistoryPage(firstPage) = first.payload else {
            Issue.record("Expected the first alert page")
            return
        }
        #expect(firstPage.hostID == hostID)
        #expect(firstPage.records.map(\.code) == [.modelUnknown, .modelUnknown])
        #expect(firstPage.records.map(\.transition) == [.recovered, .raised])
        #expect(firstPage.records.map(\.id) == [4, 3])
        #expect(firstPage.nextCursor == 3)

        let second = await coordinator.handle(deviceID: deviceID, envelope: .init(
            requestID: UUID(),
            payload: .alertHistoryQuery(.init(cursor: firstPage.nextCursor, maximumRecords: 2))
        ))
        guard case let .alertHistoryPage(secondPage) = second.payload else {
            Issue.record("Expected the older alert page")
            return
        }
        #expect(secondPage.records.map(\.id) == [2, 1])
        #expect(secondPage.nextCursor == nil)
    }

    @Test("history reads require only the paired host history capability")
    func requiresHistoryCapability() async throws {
        let hostID = UUID()
        let deviceID = UUID()
        let registry = InMemoryPairedDeviceRegistry()
        try await registry.enroll(pairedRecord(deviceID: deviceID, capabilities: [.monitor]))
        let coordinator = makeCoordinator(hostID: hostID, registry: registry, history: nil)
        let response = await coordinator.handle(deviceID: deviceID, envelope: .init(
            requestID: UUID(),
            payload: .alertHistoryQuery(.init())
        ))

        #expect(response.payload == .safeError(.init(code: .forbidden)))
    }

    @Test("self-revocation removes only the requesting host pairing")
    func selfRevokeIsHostLocal() async throws {
        let hostID = UUID()
        let firstPhoneID = UUID()
        let secondPhoneID = UUID()
        let registry = InMemoryPairedDeviceRegistry()
        try await registry.enroll(pairedRecord(deviceID: firstPhoneID, capabilities: []))
        try await registry.enroll(pairedRecord(deviceID: secondPhoneID, capabilities: []))
        let coordinator = makeCoordinator(hostID: hostID, registry: registry, history: nil)

        let response = await coordinator.handle(deviceID: firstPhoneID, envelope: .init(
            requestID: UUID(), payload: .deviceRevoke(.init(deviceID: firstPhoneID))
        ))
        #expect(response.payload == .deviceRevokeResponse(.init(deviceID: firstPhoneID)))
        #expect(await registry.record(for: firstPhoneID) == nil)
        #expect(await registry.record(for: secondPhoneID) != nil)
    }

    @Test("a phone cannot revoke a different phone on the same host")
    func cannotRevokePeerDevice() async throws {
        let hostID = UUID()
        let firstPhoneID = UUID()
        let secondPhoneID = UUID()
        let registry = InMemoryPairedDeviceRegistry()
        try await registry.enroll(pairedRecord(deviceID: firstPhoneID, capabilities: []))
        try await registry.enroll(pairedRecord(deviceID: secondPhoneID, capabilities: []))
        let coordinator = makeCoordinator(hostID: hostID, registry: registry, history: nil)

        let response = await coordinator.handle(deviceID: firstPhoneID, envelope: .init(
            requestID: UUID(), payload: .deviceRevoke(.init(deviceID: secondPhoneID))
        ))
        #expect(response.payload == .safeError(.init(code: .forbidden)))
        #expect(await registry.record(for: firstPhoneID) != nil)
        #expect(await registry.record(for: secondPhoneID) != nil)
    }

    private func makeCoordinator(
        hostID: UUID,
        registry: InMemoryPairedDeviceRegistry,
        history: (any AlertHistoryRecording)?
    ) -> CompanionHostCoordinator {
        let provider = HostFixtureProvider()
        let settings = CompanionSettingsCoordinator(provider: provider)
        let coordinator = CommandAuthorizationCoordinator(
            hostID: hostID,
            runtimeEpoch: UUID(),
            registry: registry,
            revision: { "fixture-r1" }
        )
        let dispatcher = HostCommandDispatcher(
            provider: provider,
            settings: settings,
            app: HostFixtureAppController()
        )
        return CompanionHostCoordinator(
            hostID: hostID,
            pairing: PairingCoordinator(
                hostID: hostID,
                hostName: "Fixture Mac",
                hostSPKIPin: Data(repeating: 1, count: 32),
                routes: .init(candidates: [.init(kind: .lan, host: "127.0.0.1", port: 49_444)]),
                registry: registry
            ),
            registry: registry,
            authorization: coordinator,
            dispatcher: dispatcher,
            settings: settings,
            snapshots: FixtureSnapshotProvider(.init(
                hostID: hostID,
                runtimeEpoch: UUID(),
                sequence: 1,
                generatedAt: .now,
                observations: [],
                models: [],
                states: .init(
                    provider: .init(state: .unavailable, observedAt: .now),
                    macApp: .init(state: .connected, observedAt: .now),
                    helper: .init(state: .running, observedAt: .now),
                    connection: .init(state: .connected, observedAt: .now)
                )
            )),
            alertHistory: history
        )
    }

    private func pairedRecord(deviceID: UUID, capabilities: Set<Capability>) -> PairedDeviceRecord {
        PairedDeviceRecord(
            device: .init(deviceID: deviceID, displayName: "Phone", capabilities: capabilities, enrolledAt: .now),
            identityCertificate: Data([1]),
            approvalPublicKey: Data([2])
        )
    }

    private func transition(
        _ code: OperationalAlertCode,
        _ kind: AlertTransitionKind,
        at seconds: Int
    ) -> AlertTransition {
        AlertTransition(code: code, kind: kind, occurredAt: Date(timeIntervalSince1970: TimeInterval(seconds)))
    }

    private func temporaryURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("companion-alert-history-\(UUID().uuidString).sqlite3")
    }
}

private actor HostFixtureAppController: MacAppLifecycleControlling {
    func perform(_ action: DarkbloomCompanionProtocol.AppLifecycleAction) async throws {}
}

private actor HostFixtureProvider: ProviderControlling {
    private var draft = ProviderConfigDraft(
        sourceRevision: "fixture-r1",
        original: .init(enabled: ["fixture-model"], preloaded: ["fixture-model"]),
        selection: .init(enabled: ["fixture-model"], preloaded: ["fixture-model"]),
        originalMaxModelSlots: 1,
        maxModelSlots: 1,
        originalEngineV2MaxConcurrent: 1,
        engineV2MaxConcurrent: 1
    )

    func refresh() async throws -> ProviderControlSnapshot {
        ProviderControlSnapshot(
            inventory: ModelInventoryBuilder.build(catalog: [], local: [], selection: draft.selection, daemon: nil, loadedModels: []),
            draft: draft,
            capturedAt: .now,
            sources: .init(
                catalog: .fresh(evidenceAt: .now),
                localModels: .fresh(evidenceAt: .now),
                daemon: .fresh(evidenceAt: .now),
                loadedModels: .fresh(evidenceAt: .now)
            ),
            liveSwitchAvailability: .available
        )
    }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        self.draft = draft
        return .init(draft: draft, restartRequired: false)
    }

    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {}
    func delete(_ localModelID: String) async throws {}
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: DarkbloomTelemetry.ProviderLifecycleAction, enabledModels: [String]) async throws {}
    func performLifecycle(
        _ action: DarkbloomTelemetry.ProviderLifecycleAction,
        enabledModels: [String],
        onPhase: ProviderMutationPhaseObserver?
    ) async throws -> ProviderMutationCompletion { .refreshed(try await refresh()) }
}
