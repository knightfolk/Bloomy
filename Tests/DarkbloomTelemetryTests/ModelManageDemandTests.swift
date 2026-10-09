@testable import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model Manage demand")
@MainActor
struct ModelManageDemandTests {
    @Test("details retain failed and expired network readings without making them fresh",
          arguments: ["current", "failed", "expired", "missing"])
    func retainedReadings(state: String) {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let item = ModelInventoryItem(catalogID: "gemma", localID: "gemma", displayName: "Gemma",
            modelType: "llm", capabilities: [], sizeGB: 1, minimumRAMGB: 4,
            isDownloaded: true, isEnabled: true, isPreloaded: false, liveState: .unloaded, issue: nil)
        let model = NetworkModelCapacity(id: item.catalogID, ready: true, canAccept: true,
            routableProviders: 8, warmProviders: 3, runningProviders: 5, coldProviders: 1,
            activeRequests: 4, queuedRequests: 1, queueLimit: 8, aggregateTokensPerSecond: 125,
            estimatedTimeToFirstTokenMS: 240, tokenBudgetRemaining: 750, tokenBudgetTotal: 1_000)
        let telemetry = ModelManagerTelemetry(
            networkCapacity: state == "missing" ? nil : .init(models: [model], capturedAt: now),
            networkSourceAvailable: state != "failed")
        let prepared = ModelManagerPresentationCache().prepare(myCatalog: [item], available: [],
            enabledSelectors: [item.catalogID], search: "", telemetry: telemetry,
            at: state == "expired" ? now.addingTimeInterval(121) : now)
        let summary = ModelCardSummary(item: item, installedMemoryGB: 64, rate: nil,
            capacity: prepared.capacity(for: item), serving: nil, grade: nil,
            forecast: .calculate(runPercent: 0, serving: nil, tokenRate: nil),
            runPercent: 0, setRunPercent: { _ in }, showsDetails: true,
            demandPresentation: prepared.demand(for: item), demandScale: prepared.demandScale)
        if state == "current" {
            #expect(summary.displayedDemand.title == "Urgent demand")
            #expect(summary.displayedDemand.isCurrent)
            #expect(prepared.capacity(for: item) == model)
        } else {
            #expect(!summary.displayedDemand.isCurrent)
            #expect(prepared.capacity(for: item) == nil)
            #expect(summary.displayedDemand.title == (state == "missing" ? "Demand unavailable" : "Demand stale"))
        }
        if state != "missing" {
            #expect(summary.displayedDemand.model == model)
            #expect(summary.displayedDemand.counts == "4 active · 1 queued")
            #expect(ModelDemandScale.pressure(model) == 5.0 / 3.0)
        } else {
            #expect(summary.displayedDemand.model == nil)
            #expect(summary.displayedDemand.counts == "Waiting for network")
        }
    }
}
