import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Provider model load readiness")
struct ProviderModelLoadReadinessTests {
    func state(usable: Any = 20.0, headroom: Any = 6.5, free: Any = 17.0,
               pending: Bool? = false, transition: Bool? = false, active: Bool = false,
               startup: [String] = [], identity: ProcessIdentity = .init(pid: 123, startTimeMicros: 1),
               at timestamp: TimeInterval = 1000, cache: Any = 1) throws -> DaemonState {
        var object: [String: Any] = [
            "schema": 1, "pid": identity.pid, "process_identity": ["pid": identity.pid, "start_time_micros": identity.startTimeMicros],
            "version": "0.10.4", "written_at": timestamp, "started_at": timestamp - 100,
            "inference_active": active, "warm_models": [], "advertised_models": ["model-a"],
            "startup_preload_pending_models": startup,
            "stats": ["tokens_generated": 0, "requests_served": 0, "usage_gaps": 0],
            "capacity": ["total_memory_gb": 32, "gpu_memory_active_gb": 5, "gpu_memory_cache_gb": cache,
                         "load_usable_gb": usable, "load_headroom_gb": headroom, "free_for_load_gb": free,
                         "load_transition_active": false, "activity_observed_at": timestamp]
        ]
        if let pending { object["request_work_pending"] = pending }
        if let transition { object["load_transition_active"] = transition }
        return try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: object))
    }

    @Test("classifies no eviction, request eviction and real shortfall separately")
    func classifications() throws {
        let skipped = try #require(ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state()))
        #expect(skipped.kind == .preloadSkipped)
        #expect(skipped.noEvictionShortfallGB == 1.5)
        #expect(ModelLoadReadinessText.detail(skipped)?.contains("may load it by evicting idle models") == true)
        let blocked = try #require(ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state(free: 12)))
        #expect(blocked.kind == .coldLoadBlocked)
        #expect(blocked.coldLoadShortfallGB == 3)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state(free: "invalid"))?.kind == .preloadBlocked)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 12, state: state())?.kind == .onDemand)
    }

    @Test("busy or incomplete observations never produce a definitive block")
    func busyAndMissing() throws {
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state(pending: true))?.kind == .temporarilyBusy)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state(active: true))?.kind == .temporarilyBusy)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state(pending: nil)) == nil)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: 15, state: state(usable: "invalid")) == nil)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: nil, state: state()) == nil)
        #expect(try ProviderModelLoadReadiness.make(modelID: "other", estimatedMemoryGB: 15, state: state()) == nil)
        #expect(try ProviderModelLoadReadiness.make(modelID: "model-a", estimatedMemoryGB: nil, state: state(startup: ["model-a"]))?.kind == .preloading)
    }

    @Test("missing GPU cache does not discard the provider state")
    func optionalGPUCache() throws {
        let parsed = try state(cache: NSNull())
        #expect(parsed.capacity?.gpuMemoryCacheGB == nil)
        #expect(parsed.capacity?.loadUsableGB == 20)
    }

    @Test("readiness requires current matching process, configuration and inventory")
    @MainActor func evidenceFreshness() throws {
        let now = Date()
        let identity = try #require(ProcessIdentity.current())
        let daemon = try state(identity: identity, at: now.timeIntervalSince1970)
        let item = ModelInventoryItem(catalogID: "model-a", localID: "model-a", displayName: "A", modelType: "text", capabilities: [], sizeGB: 10, minimumRAMGB: 16, isDownloaded: true, isEnabled: true, isPreloaded: false, liveState: .unloaded, issue: nil, estimatedMemoryGB: 15)
        let selection = ProviderModelSelection(enabled: ["model-a"], preloaded: [])
        let draft = ProviderConfigDraft(sourceRevision: "fixture", original: selection, selection: selection)
        let source = ProviderControlSourceState.fresh(evidenceAt: now)
        func snapshot(_ matches: Bool, _ local: ProviderControlSourceState = source) -> ProviderControlSnapshot {
            ProviderControlSnapshot(inventory: .init(myCatalog: [item], available: [], issues: []), draft: draft,
                daemonState: daemon, capturedAt: now,
                sources: .init(catalog: source, localModels: local, daemon: source, loadedModels: source),
                inventoryMatchesDaemonConfig: matches)
        }
        let status: SourceAvailability<StatusSnapshot> = .unavailable(reason: "fixture")
        let unavailable: SourceAvailability<DaemonState> = .unavailable(reason: "fixture")
        func evidence(_ control: ProviderControlSnapshot, _ date: Date) -> ModelManagerResidencyEvidence {
            .make(control: control, status: status, daemon: unavailable, at: date)
        }
        #expect(evidence(snapshot(true), now).loadReadiness(for: item)?.kind == .preloadSkipped)
        #expect(evidence(snapshot(false), now).loadReadiness(for: item) == nil)
        #expect(evidence(snapshot(true, .stale("fixture")), now).loadReadiness(for: item) == nil)
        #expect(evidence(snapshot(true), now.addingTimeInterval(11)).loadReadiness(for: item) == nil)
        #expect(evidence(snapshot(true), now.addingTimeInterval(-1)).loadReadiness(for: item) == nil)
        let later = now.addingTimeInterval(1)
        let busy = try state(pending: true, identity: identity, at: later.timeIntervalSince1970)
        let latest = ModelManagerResidencyEvidence.make(control: snapshot(true), status: status,
            daemon: .available(value: busy, capturedAt: later), at: later)
        #expect(latest.loadReadiness(for: item)?.kind == .temporarilyBusy)
        let different = try state(pending: true, at: later.timeIntervalSince1970)
        let mismatched = ModelManagerResidencyEvidence.make(control: snapshot(true), status: status,
            daemon: .available(value: different, capturedAt: later), at: later)
        #expect(mismatched.loadReadiness(for: item) == nil)
    }
}
