@testable import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model manager residency evidence")
@MainActor
struct ModelManagerResidencyTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private var missingStatus: SourceAvailability<StatusSnapshot> { .unavailable(reason: "fixture") }
    private var missingDaemon: SourceAvailability<DaemonState> { .unavailable(reason: "fixture") }

    @Test("fresh independent control evidence supports active loaded and unloaded")
    func freshResidency() {
        for state in [InventoryLiveState.active, .loadedIdle, .unloaded] {
            let model = item(state: state)
            let evidence = ModelManagerResidencyEvidence.make(control: snapshot(model), status: missingStatus,
                daemon: missingDaemon, at: now)
            #expect(evidence.presentation(for: model) == .known(state))
        }
        #expect(ModelCardResidencyPresentation.known(.active).status == "Serving now")
        #expect(ModelCardResidencyPresentation.known(.loadedIdle).status == "Ready in memory")
        #expect(ModelCardResidencyPresentation.known(.unloaded).status == "Not loaded")
    }

    @Test("stale missing future and invalid evidence cannot turn default unloaded into a definite status")
    func rejectsMissingResidency() {
        let invalidSources: [ProviderControlSourceState] = [
            .stale("fixture"), .unavailable("fixture"),
            .fresh(evidenceAt: now.addingTimeInterval(-10.001)),
            .fresh(evidenceAt: now.addingTimeInterval(0.001)),
            .fresh(evidenceAt: Date(timeIntervalSince1970: .infinity)),
            .fresh(evidenceAt: Date(timeIntervalSince1970: .nan)),
        ]
        for state in [InventoryLiveState.active, .loadedIdle, .unloaded] {
            let model = item(state: state)
            for source in invalidSources {
                for (daemon, loaded) in [(source, ProviderControlSourceState.fresh(evidenceAt: now)),
                                         (.fresh(evidenceAt: now), source)] {
                    let evidence = ModelManagerResidencyEvidence.make(control: snapshot(model, daemon: daemon, loaded: loaded),
                        status: missingStatus, daemon: missingDaemon, at: now)
                    #expect(evidence.presentation(for: model) == .unavailable)
                }
            }
        }
        let model = item()
        #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
            daemon: missingDaemon, at: now).presentation(for: model) == .unavailable)
        #expect(ModelManagerResidencyEvidence.make(control: snapshot(model), status: missingStatus,
            daemon: missingDaemon, at: Date(timeIntervalSince1970: .infinity)).presentation(for: model) == .unavailable)
        #expect(ModelCardResidencyPresentation.unavailable.status == "Status unavailable")
        #expect(ModelCardResidencyPresentation.unavailable.badge == "Unknown")
        #expect(ModelCardResidencyPresentation.unavailable.accessibilityValue == "Provider residency unavailable")
    }

    @Test("known stopped provider unloads stale residency while newer running evidence wins")
    func knownStopped() throws {
        var stopped = StatusSnapshot()
        stopped.daemon = "Stopped"
        let model = item(state: .active)
        let unavailable = ProviderControlSourceState.unavailable("fixture")
        let control = snapshot(model, daemon: unavailable, loaded: unavailable)
        let evidence = ModelManagerResidencyEvidence.make(control: control,
            status: .available(value: stopped, capturedAt: now), daemon: missingDaemon, at: now)
        #expect(evidence.presentation(for: model) == .known(.unloaded))
        for capturedAt in [now.addingTimeInterval(-61), now.addingTimeInterval(1),
                           Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan)] {
            #expect(ModelManagerResidencyEvidence.make(control: control,
                status: .available(value: stopped, capturedAt: capturedAt), daemon: missingDaemon,
                at: now).presentation(for: model) == .unavailable)
        }
        #expect(ModelManagerResidencyEvidence.make(control: snapshot(model),
            status: .available(value: stopped, capturedAt: now.addingTimeInterval(-1)),
            daemon: missingDaemon, at: now).presentation(for: model) == .known(.active))
        let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970)
        #expect(ModelManagerResidencyEvidence.make(control: control,
            status: .available(value: stopped, capturedAt: now.addingTimeInterval(-1)),
            daemon: .available(value: daemon, capturedAt: now), at: now).presentation(for: model) == .unavailable)
        // A future/invalid running payload cannot overrule a trustworthy stop.
        for writtenAt in [now.timeIntervalSince1970 + 1, now.timeIntervalSince1970 - 11] {
            #expect(ModelManagerResidencyEvidence.make(control: control,
                status: .available(value: stopped, capturedAt: now),
                daemon: .available(value: try runtimeDaemon(writtenAt: writtenAt), capturedAt: now),
                at: now).presentation(for: model) == .known(.unloaded))
        }
    }

    @Test("not downloaded remains independent of runtime evidence")
    func notDownloaded() {
        let model = item(downloaded: false)
        #expect(ModelManagerResidencyEvidence().presentation(for: model) == .notDownloaded)
        #expect(ModelManagerResidencyEvidence(providerKnownStopped: true, controlResidencyIsFresh: true)
            .presentation(for: model) == .notDownloaded)
        #expect(ModelCardResidencyPresentation.notDownloaded.status == "Not downloaded")
    }

    @Test("live telemetry keeps residency current after the one-time controls read expires")
    func liveTelemetryFallback() throws {
        let model = item()
        let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970, model: model.catalogID)
        let old = ProviderControlSourceState.fresh(evidenceAt: now.addingTimeInterval(-11))
        let evidence = ModelManagerResidencyEvidence.make(control: snapshot(model, daemon: old, loaded: old),
            status: missingStatus, daemon: .available(value: daemon, capturedAt: now),
            loadedModels: .available(value: LoadedModelsState(schema: 1, models: [model.catalogID],
                updatedAt: daemon.startedAt), capturedAt: now), at: now)
        #expect(evidence.presentation(for: model) == .known(.loadedIdle))
    }

    @Test("live inference matches local aliases and a retained current name alone does not mean loaded")
    func telemetryStates() throws {
        let model = item(localID: "local/gemma")
        for (active, resident, expected) in [(true, false, InventoryLiveState.active),
                                           (false, true, .loadedIdle), (false, false, .unloaded)] {
            let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970, model: "local/gemma",
                active: active, resident: resident)
            let evidence = ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
                daemon: .available(value: daemon, capturedAt: now),
                loadedModels: .available(value: LoadedModelsState(schema: 1, models: [],
                    updatedAt: daemon.startedAt), capturedAt: now), at: now)
            #expect(evidence.presentation(for: model) == .known(expected))
        }
    }

    @Test("live fallback requires both fresh reads and loaded state from this provider lifetime")
    func rejectsInvalidLiveTelemetry() throws {
        let model = item(state: .active)
        let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970, model: model.catalogID)
        let loaded = LoadedModelsState(schema: 1, models: [model.catalogID], updatedAt: daemon.startedAt)
        for capturedAt in [now.addingTimeInterval(-10.001), now.addingTimeInterval(0.001),
                           Date(timeIntervalSince1970: .infinity), Date(timeIntervalSince1970: .nan)] {
            for (daemonAt, loadedAt) in [(capturedAt, now), (now, capturedAt)] {
                #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
                    daemon: .available(value: daemon, capturedAt: daemonAt),
                    loadedModels: .available(value: loaded, capturedAt: loadedAt), at: now)
                    .presentation(for: model) == .unavailable)
            }
        }
        for updatedAt in [daemon.startedAt - 1, now.timeIntervalSince1970 + 1, Double.infinity, Double.nan] {
            #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
                daemon: .available(value: daemon, capturedAt: now),
                loadedModels: .available(value: LoadedModelsState(schema: 1, models: [model.catalogID],
                    updatedAt: updatedAt), capturedAt: now), at: now).presentation(for: model) == .unavailable)
        }
        #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
            daemon: missingDaemon, loadedModels: .available(value: loaded, capturedAt: now), at: now)
            .presentation(for: model) == .unavailable)
        #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
            daemon: .available(value: daemon, capturedAt: now), at: now)
            .presentation(for: model) == .unavailable)
    }

    @Test("fresh controls retain precedence over fallback telemetry")
    func freshControlWins() throws {
        let model = item(state: .unloaded)
        let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970, model: model.catalogID, active: true)
        #expect(ModelManagerResidencyEvidence.make(control: snapshot(model), status: missingStatus,
            daemon: .available(value: daemon, capturedAt: now),
            loadedModels: .available(value: LoadedModelsState(schema: 1, models: [model.catalogID],
                updatedAt: daemon.startedAt), capturedAt: now), at: now).presentation(for: model) == .known(.unloaded))
    }

    @Test("changing evidence invalidates residency without rebuilding catalog telemetry or grades")
    func cacheUpdatesOnlyResidency() {
        let model = item()
        let cache = ModelManagerPresentationCache()
        let initial = cache.prepare(myCatalog: [model], available: [], enabledSelectors: nil,
            search: "", telemetry: ModelManagerTelemetry(), at: now, controlSnapshot: snapshot(model))
        #expect(initial.residencyEvidence.presentation(for: model) == .known(.unloaded))
        let expired = cache.prepare(myCatalog: [model], available: [], enabledSelectors: nil,
            search: "", telemetry: ModelManagerTelemetry(), at: now.addingTimeInterval(10.001), controlSnapshot: snapshot(model))
        #expect(expired.residencyEvidence.presentation(for: model) == .unavailable)
        let unavailable = cache.prepare(myCatalog: [model], available: [], enabledSelectors: nil,
            search: "", telemetry: ModelManagerTelemetry(), at: now,
            controlSnapshot: snapshot(model, loaded: .unavailable("fixture")))
        #expect(unavailable.residencyEvidence.presentation(for: model) == .unavailable)
        #expect(cache.groupingBuildCount == 1)
        #expect(cache.telemetryIndexBuildCount == 1)
        #expect(cache.gradeBuildCount == 1)
    }

    @Test("telemetry changes update card state without rebuilding shared indexes")
    func cacheTracksLiveResidency() throws {
        let model = item()
        let cache = ModelManagerPresentationCache()
        for active in [false, true, false] {
            let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970, model: model.catalogID, active: active)
            let value = cache.prepare(myCatalog: [model], available: [], enabledSelectors: nil,
                search: "", telemetry: ModelManagerTelemetry(), at: now,
                providerDaemonState: .available(value: daemon, capturedAt: now),
                providerLoadedModels: .available(value: LoadedModelsState(schema: 1, models: [model.catalogID],
                    updatedAt: daemon.startedAt), capturedAt: now))
            #expect(value.residencyEvidence.presentation(for: model) == .known(active ? .active : .loadedIdle))
        }
        #expect(cache.groupingBuildCount == 1)
        #expect(cache.telemetryIndexBuildCount == 1)
        #expect(cache.gradeBuildCount == 1)
    }

    @Test("fresh loaded reads expire even if daemon reads continue")
    func loadedReadExpiry() throws {
        let model = item()
        let daemon = try runtimeDaemon(writtenAt: now.timeIntervalSince1970, model: model.catalogID)
        let loaded = LoadedModelsState(schema: 1, models: [model.catalogID], updatedAt: daemon.startedAt)
        let input = ModelResidencyFreshnessTaskInput(sources: nil, status: missingStatus,
            daemon: .available(value: daemon, capturedAt: now), isVisible: true,
            loadedModels: .available(value: loaded, capturedAt: now.addingTimeInterval(-5)))
        #expect(ModelResidencyFreshnessSchedule.nextTransition(input: input, at: now) == now.addingTimeInterval(5.001))
        #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
            daemon: input.daemon, loadedModels: input.loadedModels, at: now).presentation(for: model) == .known(.loadedIdle))
        #expect(ModelManagerResidencyEvidence.make(control: nil, status: missingStatus,
            daemon: input.daemon, loadedModels: input.loadedModels, at: now.addingTimeInterval(5.001))
            .presentation(for: model) == .unavailable)
    }

    @Test("residency schedules finite boundary transitions without new payloads")
    func freshnessSchedule() {
        let input = ModelResidencyFreshnessTaskInput(sources: snapshot(item()).sources,
            status: missingStatus, daemon: missingDaemon, isVisible: true)
        #expect(ModelResidencyFreshnessSchedule.nextTransition(input: input, at: now) == now.addingTimeInterval(10.001))
        #expect(ModelResidencyFreshnessSchedule.nextTransition(input: input, at: now.addingTimeInterval(10.001)) == nil)
        #expect(ModelResidencyFreshnessSchedule.nextTransition(input: input, at: now.addingTimeInterval(-1)) == now)
        let invalid = ModelResidencyFreshnessTaskInput(sources: snapshot(item(), daemon: .unavailable("fixture"),
            loaded: .fresh(evidenceAt: Date(timeIntervalSince1970: .infinity))).sources,
            status: missingStatus, daemon: missingDaemon, isVisible: true)
        #expect(ModelResidencyFreshnessSchedule.nextTransition(input: invalid, at: now) == nil)
    }

    private func item(state: InventoryLiveState = .unloaded, downloaded: Bool = true, localID: String = "google/gemma") -> ModelInventoryItem {
        ModelInventoryItem(catalogID: "google/gemma", localID: downloaded ? localID : nil,
            displayName: "Gemma", modelType: "text", capabilities: [], sizeGB: 1, minimumRAMGB: 1,
            isDownloaded: downloaded, isEnabled: true, isPreloaded: false, liveState: state, issue: nil)
    }

    private func snapshot(_ model: ModelInventoryItem,
                          daemon: ProviderControlSourceState? = nil,
                          loaded: ProviderControlSourceState? = nil) -> ProviderControlSnapshot {
        let selection = ProviderModelSelection(enabled: [model.catalogID], preloaded: [])
        return ProviderControlSnapshot(inventory: ModelInventory(myCatalog: [model], available: [], issues: []),
            draft: ProviderConfigDraft(sourceRevision: "fixture", original: selection, selection: selection),
            capturedAt: now, sources: ProviderControlSourceStates(catalog: .fresh(evidenceAt: now),
                localModels: .fresh(evidenceAt: now), daemon: daemon ?? .fresh(evidenceAt: now),
                loadedModels: loaded ?? .fresh(evidenceAt: now)))
    }

    private func runtimeDaemon(writtenAt: Double, model: String? = nil, active: Bool = false, resident: Bool = true) throws -> DaemonState {
        let url = try #require(Bundle.module.url(forResource: "daemon-state-online", withExtension: "json", subdirectory: "Fixtures"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["written_at"] = writtenAt
        if let model {
            json["current_model"] = model
            json["inference_active"] = active
            json["warm_models"] = resident ? [model] : []
            json["slots"] = []
        }
        return try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: json))
    }
}
