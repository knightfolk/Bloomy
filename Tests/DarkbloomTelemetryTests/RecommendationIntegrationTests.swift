@testable import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Recommendation integration")
@MainActor
struct RecommendationIntegrationTests {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    @Test("fresh resident alternative can be considered with dated local and network evidence")
    func residentAlternative() throws {
        let control = controlSnapshot(alternativeState: .loadedIdle)
        let input = RecommendationEvidenceAssembler.make(
            at: now,
            network: .available(value: try network(), capturedAt: now),
            telemetry: telemetry(), control: control,
            observedWork: [.init(
                model: "better", queryPeriod: .init(start: now.addingTimeInterval(-3_600), end: now),
                sourceCapturedAt: now, workMicroUSD: 500, jobs: 2,
                recordedHours: 1, unknownHours: 0, uncertainBoundaryHours: 0
            )]
        )
        let decision = RecommendationEvaluator.evaluate(input)
        #expect(input.currentModelID == "current")
        #expect(decision.outcome == .consider(modelID: "better"))
        let better = try #require(decision.assessments.first { $0.modelID == "better" })
        #expect(better.eligible)
        let hasFreshMemory = better.factors.contains(where: { factor in
            factor.kind == .memory && factor.freshness == .fresh && factor.numericValue == 1
        })
        let hasObservedWork = better.factors.contains(where: { factor in
            factor.kind == .observedWork && factor.provenance == .accountObservedWork
        })
        #expect(hasFreshMemory)
        #expect(hasObservedWork)
        #expect(better.factors.first { $0.kind == .networkDemand }?.sourceCapturedAt == now)
    }

    @Test("downloaded model has no readiness or memory proof until resident")
    func unloadedAlternativeStays() throws {
        let input = RecommendationEvidenceAssembler.make(
            at: now,
            network: .available(value: try network(), capturedAt: now),
            telemetry: telemetry(), control: controlSnapshot(alternativeState: .unloaded),
            observedWork: []
        )
        let decision = RecommendationEvaluator.evaluate(input)
        #expect(decision.outcome == .stay)
        let better = try #require(decision.assessments.first { $0.modelID == "better" })
        #expect(better.blockers.contains(.missingReadiness))
        #expect(better.factors.first { $0.kind == .memory }?.freshness == .missing)
    }

    @Test("resident IDs without a matching daemon identity cannot prove memory admission")
    func missingIdentityStays() throws {
        let original = controlSnapshot(alternativeState: .loadedIdle)
        let unverified = ProviderControlSnapshot(
            inventory: original.inventory, draft: original.draft, daemonState: nil,
            residentModelIDs: original.residentModelIDs, capturedAt: original.capturedAt,
            sources: original.sources
        )
        let input = RecommendationEvidenceAssembler.make(
            at: now, network: .available(value: try network(), capturedAt: now),
            telemetry: telemetry(), control: unverified, observedWork: []
        )
        let decision = RecommendationEvaluator.evaluate(input)
        #expect(decision.outcome == .stay)
        let better = try #require(decision.assessments.first { $0.modelID == "better" })
        #expect(better.blockers.contains(.missingReadiness))
    }

    @Test("stale network or inventory cannot produce a consideration")
    func staleInputsFailClosed() throws {
        let fresh = try network()
        let staleNetwork = RecommendationEvidenceAssembler.make(
            at: now, network: .stale(value: fresh, capturedAt: now, reason: "old"),
            telemetry: telemetry(), control: controlSnapshot(alternativeState: .loadedIdle),
            observedWork: []
        )
        #expect(RecommendationEvaluator.evaluate(staleNetwork).outcome == .insufficientEvidence)

        let staleControl = controlSnapshot(alternativeState: .loadedIdle, sourceAt: now.addingTimeInterval(-11))
        let staleInventory = RecommendationEvidenceAssembler.make(
            at: now, network: .available(value: fresh, capturedAt: now),
            telemetry: telemetry(), control: staleControl, observedWork: []
        )
        #expect(RecommendationEvaluator.evaluate(staleInventory).outcome == .insufficientEvidence)
    }

    @Test("monitor persists decisions and a reopened journal replays the same evidence")
    func monitorPersistsAndReplays() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recommendations.sqlite3")
        let journal = try RecommendationJournal(url: url, limit: 10)
        let control = controlSnapshot(alternativeState: .loadedIdle)
        let store = MonitorStore(
            service: TelemetryService(source: InertRecommendationTelemetrySource(), now: { now }),
            initial: telemetry(), networkCapacityClient: FixedRecommendationNetworkClient(value: try network()),
            recommendationJournal: journal, now: { now }
        )
        store.attachRecommendationInventory { control }
        await store.refreshNetworkCapacity()
        #expect(store.recommendationDecision?.outcome == .consider(modelID: "better"))
        #expect(store.recommendationHistoryAvailable)
        #expect(store.recommendationHistory.count == 1)
        let reopened = try RecommendationJournal(url: url, limit: 10)
        let replay = try await reopened.replay(limit: 10)
        #expect(replay.count == 1)
        #expect(replay[0].matches)
    }

    @Test("opportunity copy identifies observed values without claiming a forecast")
    func presentationCopy() {
        #expect(OpportunityPresentation.recommendationTitle(.stay) == "Stay with the current model")
        #expect(OpportunityPresentation.factorTitle(.memory) == "Memory admission")
    }

    private func network() throws -> NetworkCapacitySnapshot {
        try NetworkCapacityParser.parse(Data(#"""
        {"models":[
            {"id":"current","ready":true,"can_accept":true,"routable_providers":2,"warm_providers":1,"running_providers":1,"cold_providers":0,"active_requests":0,"queued_requests":0,"queue_limit":8,"aggregate_tps":10,"estimated_ttft_ms":100,"token_budget_remaining":9,"token_budget_total":10},
            {"id":"better","ready":true,"can_accept":true,"routable_providers":2,"warm_providers":1,"running_providers":1,"cold_providers":0,"active_requests":1,"queued_requests":2,"queue_limit":8,"aggregate_tps":20,"estimated_ttft_ms":100,"token_budget_remaining":9,"token_budget_total":10}
        ]}
        """#.utf8), capturedAt: now)
    }

    private func telemetry() -> TelemetrySnapshot {
        let daemon = daemonState()
        return TelemetrySnapshot(
            state: .available(value: daemon, capturedAt: now),
            loadedModels: .available(value: .init(schema: 1, models: ["current", "better"], updatedAt: now.timeIntervalSince1970), capturedAt: now),
            status: .unavailable(reason: "unused"), eventFeed: .unavailable(reason: "unused"),
            tokenRate: .available(tokensPerSecond: 20, label: "active sample"),
            diagnostics: [], capturedAt: now, menuStatus: .online
        )
    }

    private func daemonState() -> DaemonState {
        DaemonState(
            schema: 1, version: "1", currentModel: "current", warmModels: ["current", "better"],
            stats: .init(tokensGenerated: 10, requestsServed: 1, usageGaps: 0),
            trust: nil, capacity: nil, slots: [], inferenceActive: false,
            startedAt: now.timeIntervalSince1970 - 60,
            writtenAt: now.timeIntervalSince1970, pid: 42,
            processIdentity: .init(pid: 42, startTimeMicros: 123)
        )
    }

    private func controlSnapshot(
        alternativeState: InventoryLiveState,
        sourceAt: Date? = nil
    ) -> ProviderControlSnapshot {
        let observedAt = sourceAt ?? now
        let selection = ProviderModelSelection(enabled: ["current", "better"], preloaded: [])
        let draft = ProviderConfigDraft(sourceRevision: "test", original: selection, selection: selection)
        let sources = ProviderControlSourceStates(
            catalog: .fresh(evidenceAt: observedAt),
            localModels: .fresh(evidenceAt: observedAt),
            daemon: .fresh(evidenceAt: observedAt),
            loadedModels: .fresh(evidenceAt: observedAt)
        )
        return ProviderControlSnapshot(
            inventory: ModelInventory(
                myCatalog: [item("current", state: .active), item("better", state: alternativeState)],
                available: [], issues: []
            ),
            draft: draft, daemonState: daemonState(),
            residentModelIDs: alternativeState == .unloaded ? ["current"] : ["current", "better"],
            capturedAt: now, sources: sources
        )
    }

    private func item(_ id: String, state: InventoryLiveState) -> ModelInventoryItem {
        ModelInventoryItem(
            catalogID: id, localID: id, displayName: id, modelType: "text",
            capabilities: [], sizeGB: 5, minimumRAMGB: 8,
            isDownloaded: true, isEnabled: true, isPreloaded: false,
            liveState: state, issue: nil
        )
    }
}

private struct InertRecommendationTelemetrySource: TelemetrySource {
    private struct Unused: Error {}
    func readDaemonState() async throws -> DaemonState { throw Unused() }
    func readLoadedModels() async throws -> LoadedModelsState { throw Unused() }
    func readStatus() async throws -> StatusSnapshot { throw Unused() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw Unused() }
}

private actor FixedRecommendationNetworkClient: NetworkCapacityFetching {
    let value: NetworkCapacitySnapshot
    init(value: NetworkCapacitySnapshot) { self.value = value }
    func fetch(at capturedAt: Date) -> NetworkCapacitySnapshot { value }
}
