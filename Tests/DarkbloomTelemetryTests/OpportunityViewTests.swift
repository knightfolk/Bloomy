import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Opportunity rendering", .serialized)
@MainActor
struct OpportunityViewTests {
    @Test("network cards fit a narrow dashboard with fresh and failed-refresh data", arguments: [false, true])
    func render(stale: Bool) async throws {
        let store = MonitorStore(service: TelemetryService(source: OpportunityUnusedSource()),
                                 initial: .unavailable(now: Date()), networkCapacityClient: OpportunityFixture(),
                                 publicCatalogClient: OpportunityMetadataFixture())
        await store.refreshNetworkCapacity()
        await store.refreshPublicCatalog()
        if stale {
            await store.refreshNetworkCapacity()
            await store.refreshPublicCatalog()
        }
        #expect(PopupNetworkDemandPresentation.freshness(of: store.networkCapacity, at: Date()) == (stale ? .stale : .current))
        let host = NSHostingController(rootView: OpportunityView(store: store, controlStore: nil))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 570, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width <= 570)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-opportunity-\(stale ? "stale" : "fresh").png"]
        try capture.run()
        capture.waitUntilExit()
    }
}

private actor OpportunityFixture: NetworkCapacityFetching {
    var fetched = false
    func fetch(at capturedAt: Date) async throws -> NetworkCapacitySnapshot {
        guard !fetched else { throw NetworkCapacityError.httpStatus(429) }
        fetched = true
        return NetworkCapacitySnapshot(models: [
            NetworkModelCapacity(
                id: "Example/Attributed-Model", ready: true, canAccept: true, routableProviders: 12,
                warmProviders: 4, runningProviders: 2, coldProviders: 8, activeRequests: 3,
                queuedRequests: 1, queueLimit: 16, aggregateTokensPerSecond: 120,
                estimatedTimeToFirstTokenMS: 100, tokenBudgetRemaining: 500, tokenBudgetTotal: 1000
            ),
            NetworkModelCapacity(
                id: "Example/Second-Model", ready: true, canAccept: true, routableProviders: 8,
                warmProviders: 3, runningProviders: 1, coldProviders: 5, activeRequests: 2,
                queuedRequests: 0, queueLimit: 16, aggregateTokensPerSecond: 80,
                estimatedTimeToFirstTokenMS: 150, tokenBudgetRemaining: 600, tokenBudgetTotal: 1000
            ),
        ], capturedAt: capturedAt)
    }
}

private actor OpportunityMetadataFixture: PublicCatalogFetching {
    var fetched = false
    func fetch(at capturedAt: Date) async throws -> PublicCatalogSnapshot {
        guard !fetched else { throw PublicCatalogError.httpStatus(429) }
        fetched = true
        return try PublicCatalogSnapshot.parse(Data(#"{"models":[{"id":"Example/Attributed-Model","display_name":"Example","family":"example","model_type":"llm","capabilities":["text"],"size_gb":20,"min_ram_gb":32,"active":true},{"id":"Example/Second-Model","display_name":"Second model","family":"example","model_type":"llm","capabilities":["text"],"size_gb":16,"min_ram_gb":24,"active":true}]}"#.utf8), capturedAt: capturedAt)
    }
}

private struct OpportunityUnusedSource: TelemetrySource {
    struct Unused: Error {}
    func readDaemonState() async throws -> DaemonState { throw Unused() }
    func readLoadedModels() async throws -> LoadedModelsState { throw Unused() }
    func readStatus() async throws -> StatusSnapshot { throw Unused() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw Unused() }
}

@Suite("Opportunity comparison labels")
struct OpportunityComparisonTests {
    @Test("waiting work leads, closed models follow, equal demand sorts deterministically")
    func demandOrder() {
        let waiting = model("waiting", active: 1, queued: 2)
        let busy = model("busy", active: 8)
        let quietA = model("a", active: 0)
        let quietB = model("b", active: 0)
        let closed = model("closed", active: 90, queued: 30, accepting: false)
        #expect(OpportunityPresentation.ordered([closed, quietB, busy, quietA, waiting]).map(\.id)
            == ["waiting", "busy", "a", "b", "closed"])
        #expect(OpportunityPresentation.demand(waiting) == "Work waiting")
        #expect(OpportunityPresentation.demand(closed) == "Not accepting")
    }

    @Test("network comparison hides idle retired entries but keeps live ones")
    func retiredNetworkEntries() {
        let idleLegacy = ["gemma-4-26b", "gemma-4-26b-8bit"].map { id in
            NetworkModelCapacity(
                id: id, ready: false, canAccept: false,
                routableProviders: 0, warmProviders: 0, runningProviders: 0,
                coldProviders: 0, activeRequests: 0, queuedRequests: 0,
                queueLimit: 0, aggregateTokensPerSecond: 0,
                estimatedTimeToFirstTokenMS: 0, tokenBudgetRemaining: 0,
                tokenBudgetTotal: 0
            )
        }
        let current = [model("gemma-4-26b-qat-4bit", active: 1), model("Qwen3.5-9B", active: 1)]
        #expect(Set(OpportunityPresentation.ordered(idleLegacy + current).map(\.id)) ==
            ["gemma-4-26b-qat-4bit", "Qwen3.5-9B"])
        #expect(OpportunityPresentation.ordered([model("gemma-4-26b", active: 1)]).map(\.id) ==
            ["gemma-4-26b"])
    }

    @Test("display name only comes from matching metadata")
    func matchedName() {
        let value = model("organization/technical-id", active: 1)
        let metadata = CatalogModel(id: value.id, displayName: "Readable model", family: "example", modelType: "text",
            capabilities: [], sizeGB: 10, minimumRAMGB: 16, active: true)
        #expect(OpportunityPresentation.name(value, metadata: metadata) == "Readable model")
        #expect(OpportunityPresentation.name(model("different", active: 1), metadata: metadata) == "different")
        #expect(OpportunityPresentation.name(value, metadata: nil) == value.id)
    }

    @Test("visible aliases remain searchable without catalog metadata", arguments: [
        ("gemma-4-26b-qat-4bit", "Gemma 4"),
        ("EigenLabs/Qwen3.8-27B-4bit-mtp", "Qwen 3.8"),
    ])
    func absentMetadataSearch(example: (String, String)) {
        let value = model(example.0, active: 1)
        #expect(OpportunityPresentation.matchesSearch(example.1, model: value, metadata: nil))
        #expect(OpportunityPresentation.matchesSearch(ModelDisplayName.short(value.id), model: value, metadata: nil))
        #expect(OpportunityPresentation.matchesSearch(value.id.uppercased(), model: value, metadata: nil))
        #expect(OpportunityPresentation.matchesSearch("", model: value, metadata: nil))
        #expect(!OpportunityPresentation.matchesSearch("unrelated model", model: value, metadata: nil))
    }

    @Test("search preserves catalog names and canonical identity without borrowing another model's name")
    func catalogNameSearch() {
        let value = model("organization/technical-id", active: 1)
        let metadata = CatalogModel(id: value.id, displayName: "Readable model", family: "example", modelType: "text",
            capabilities: [], sizeGB: 10, minimumRAMGB: 16, active: true)
        #expect(OpportunityPresentation.matchesSearch("readable", model: value, metadata: metadata))
        #expect(OpportunityPresentation.matchesSearch(value.id, model: value, metadata: metadata))
        #expect(!OpportunityPresentation.matchesSearch("Readable model", model: model("different", active: 1), metadata: metadata))
    }

    private func model(_ id: String, active: Int, queued: Int = 0, accepting: Bool = true) -> NetworkModelCapacity {
        NetworkModelCapacity(id: id, ready: true, canAccept: accepting, routableProviders: 10,
            warmProviders: 10, runningProviders: 1, coldProviders: 0, activeRequests: active,
            queuedRequests: queued, queueLimit: 50, aggregateTokensPerSecond: 10,
            estimatedTimeToFirstTokenMS: 1, tokenBudgetRemaining: 10, tokenBudgetTotal: 10)
    }
}
