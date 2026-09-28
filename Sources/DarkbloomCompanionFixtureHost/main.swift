import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import DarkbloomTelemetry
import Foundation

@main
enum FixtureHostMain {
    static func main() async throws {
        let port: UInt16 = 49_444
        let routeHost = ProcessInfo.processInfo.environment["DARKBLOOM_FIXTURE_HOST"] ?? "127.0.0.1"
        let hostID = UUID()
        let runtimeEpoch = UUID()
        let identity = try CompanionIdentity.makeEphemeral(role: .host)
        let registry = InMemoryPairedDeviceRegistry()
        let routes = PeerRouteHints(candidates: [
            .init(kind: .lan, host: routeHost, port: port),
        ])
        let fixtureNow = Date()
        let pairing = PairingCoordinator(
            hostID: hostID,
            hostName: "Fixture Mac",
            hostSPKIPin: identity.spkiSHA256,
            routes: routes,
            registry: registry,
            now: { fixtureNow }
        )
        let provider = FixtureProvider()
        let settings = CompanionSettingsCoordinator(provider: provider)
        let authorization = CommandAuthorizationCoordinator(
            hostID: hostID,
            runtimeEpoch: runtimeEpoch,
            registry: registry,
            revision: { await settings.currentRevision() }
        )
        let dispatcher = HostCommandDispatcher(
            provider: provider,
            settings: settings,
            app: FixtureAppLifecycle()
        )
        let snapshots = FixtureSnapshotProvider(try makeSnapshot(
            hostID: hostID, runtimeEpoch: runtimeEpoch
        ))
        let coordinator = CompanionHostCoordinator(
            hostID: hostID,
            runtimeEpoch: runtimeEpoch,
            pairing: pairing,
            registry: registry,
            authorization: authorization,
            dispatcher: dispatcher,
            settings: settings,
            snapshots: snapshots
        )
        let server = try AuthenticatedCompanionServer(
            identity: identity,
            port: port,
            bindHost: routeHost,
            authenticate: { value, challenge in
                await coordinator.authenticate(value, challenge: challenge)
            },
            bootstrapHandler: { envelope in
                guard case let .enrollmentProof(proof) = envelope.payload else {
                    return .init(
                        requestID: envelope.requestID,
                        payload: .safeError(.init(code: .malformedRequest))
                    )
                }
                let pending = try await coordinator.beginEnrollment(proof)
                _ = try await coordinator.approveEnrollment(
                    pending.enrollmentID,
                    capabilities: [
                        .monitor, .history, .settingsRead, .settingsWrite,
                        .providerLifecycle, .providerLiveSwitch, .appLifecycle,
                        .deviceManagement,
                    ]
                )
                return .init(requestID: envelope.requestID, payload: .pendingEnrollment(pending))
            },
            onError: { message in
                FileHandle.standardError.write(Data("fixture transport: \(message)\n".utf8))
            },
            handler: { deviceID, envelope in
                await coordinator.handle(deviceID: deviceID, envelope: envelope)
            }
        )
        _ = try await server.start()
        let invitation = try await coordinator.makeInvitation()
        let code = try PairingQRCode.encode(invitation)
        let record = try JSONEncoder().encode(["pairingCode": code])
        try record.write(to: URL(fileURLWithPath: "/tmp/darkbloom-companion-fixture.json"), options: .atomic)
        print(code)
        fflush(stdout)
        while !Task.isCancelled { try await Task.sleep(for: .seconds(60)) }
        await server.stop()
    }

    private static func makeSnapshot(hostID: UUID, runtimeEpoch: UUID) throws -> CompanionSnapshot {
        let now = Date()
        let states = RuntimeStates(
            provider: .init(state: .running, observedAt: now),
            macApp: .init(state: .connected, observedAt: now),
            helper: .init(state: .running, observedAt: now),
            connection: .init(state: .connected, observedAt: now)
        )
        return try .validated(
            hostID: hostID,
            runtimeEpoch: runtimeEpoch,
            sequence: 1,
            generatedAt: now,
            observations: [
                .init(metric: .tokenRate, value: 42.5, unit: .tokensPerSecond, scope: .localProvider, provenance: .direct, capturedAt: now, sourceAgeSeconds: 0, availability: .available, reason: nil),
                .init(metric: .systemGPUPercent, value: 23, unit: .percent, scope: .wholeMac, provenance: .direct, capturedAt: now, sourceAgeSeconds: 0, availability: .available, reason: nil),
                .init(metric: .accountEarnings, value: 12.34, unit: .currency, scope: .account, provenance: .direct, capturedAt: now, sourceAgeSeconds: 0, availability: .available, reason: nil, currencyCode: "USD"),
            ],
            models: [
                .init(id: "fixture-model", name: "Fixture Model", enabled: true, advertised: true, resident: true, active: true, tokenRate: 42.5, rateWindow: .activeSample),
            ],
            states: states,
            capabilities: [
                .monitor, .settingsRead, .settingsWrite, .providerLifecycle,
                .providerLiveSwitch, .appLifecycle, .deviceManagement,
            ]
        )
    }
}

private actor FixtureAppLifecycle: MacAppLifecycleControlling {
    func perform(_ action: DarkbloomCompanionProtocol.AppLifecycleAction) {}
}

private actor FixtureProvider: ProviderControlling {
    private var draft = ProviderConfigDraft(
        sourceRevision: "fixture-r1",
        original: .init(enabled: ["fixture-model"], preloaded: ["fixture-model"]),
        selection: .init(enabled: ["fixture-model"], preloaded: ["fixture-model"]),
        originalMaxModelSlots: 1,
        maxModelSlots: 1,
        originalEngineV2MaxConcurrent: 1,
        engineV2MaxConcurrent: 1
    )

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
            ),
            liveSwitchAvailability: .available
        )
    }

    func save(_ draft: ProviderConfigDraft) -> ProviderConfigSaveResult {
        self.draft = ProviderConfigDraft(
            sourceRevision: "fixture-r2",
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
    func execute(_ action: DarkbloomTelemetry.ProviderLifecycleAction, enabledModels: [String]) {}
    func performLifecycle(
        _ action: DarkbloomTelemetry.ProviderLifecycleAction,
        enabledModels: [String],
        onPhase: ProviderMutationPhaseObserver?
    ) -> ProviderMutationCompletion { .refreshed(refresh()) }
    func performLiveSwitch(
        enabledModels: [String],
        onPhase: ProviderMutationPhaseObserver?
    ) -> ProviderMutationCompletion { .refreshed(refresh()) }
}
