@testable import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model manager presentation cache")
@MainActor
struct ModelManagerPresentationCacheTests {
    @Test("7 and 100 cards share one grade calculation across unchanged ticks", arguments: [7, 100])
    func sharedCalculation(count: Int) {
        let date = Date(timeIntervalSince1970: 1_000)
        let models = (0..<count).map { item($0) }
        let telemetry = fixtureTelemetry(models: models, at: date)
        let cache = ModelManagerPresentationCache()
        var legacyGradePasses = 0
        let peers = legacyPeers(models: models, telemetry: telemetry, at: date)
        let prepared = cache.prepare(myCatalog: models, available: [], enabledSelectors: nil,
            search: "", telemetry: telemetry, at: date)
        for model in models {
            legacyGradePasses += 1
            #expect(prepared.grades[model.catalogID] == legacyGrade(modelID: model.catalogID, peers: peers))
            #expect(prepared.tokenRate(for: model) == telemetry.tokenRates.first { $0.model == model.catalogID || $0.model == model.localID })
            #expect(prepared.servingAverage(for: model) == telemetry.servingAverages.first { $0.model == model.catalogID || $0.model == model.localID })
        }
        for second in 1...60 {
            _ = cache.prepare(myCatalog: models, available: [], enabledSelectors: nil,
                search: "", telemetry: telemetry, at: date.addingTimeInterval(Double(second)))
        }
        #expect(legacyGradePasses == count)
        #expect(cache.gradeBuildCount == 1)
        #expect(cache.groupingBuildCount == 1)
        #expect(cache.telemetryIndexBuildCount == 1)
        #expect(prepared.grouping.enabled.map(\.id) == models.map(\.id))
        let stale = cache.prepare(myCatalog: models, available: [], enabledSelectors: nil,
            search: "", telemetry: telemetry, at: date.addingTimeInterval(121))
        #expect(stale.grades.isEmpty)
        #expect(cache.gradeBuildCount == 2)
        #expect(cache.groupingBuildCount == 1)
        #expect(cache.telemetryIndexBuildCount == 1)
        for model in models {
            #expect(stale.capacity(for: model) == nil)
            #expect(stale.demand(for: model).model == prepared.demand(for: model).model)
            #expect(!stale.demand(for: model).isCurrent)
        }
    }

    @Test("draft aliases update grouping and grades without changing card identity or telemetry index")
    func draftChanges() {
        let date = Date(timeIntervalSince1970: 1_000)
        let models = (0..<7).map { item($0, alias: "enabled-\($0)") }
        let telemetry = fixtureTelemetry(models: models, at: date)
        let cache = ModelManagerPresentationCache()
        let initial = cache.prepare(myCatalog: models, available: [], enabledSelectors: ["enabled-0"], search: "",
            telemetry: telemetry, at: date)
        let changed = cache.prepare(myCatalog: models, available: [], enabledSelectors: [models[1].catalogID, "enabled-2"], search: "",
            telemetry: telemetry, at: date)
        #expect(initial.grouping.enabled.map(\.id) == [models[0].id])
        #expect(changed.grouping.enabled.map(\.id) == [models[1].id, models[2].id])
        #expect(Set(changed.grouping.enabled.map(\.id) + changed.grouping.available.map(\.id)) == Set(models.map(\.id)))
        #expect(changed.grades[models[0].catalogID] == nil)
        #expect(changed.grades[models[1].catalogID] != nil)
        #expect(changed.grades[models[2].catalogID] != nil)
        #expect(cache.gradeBuildCount == 2)
        #expect(cache.groupingBuildCount == 2)
        #expect(cache.telemetryIndexBuildCount == 1)
        _ = cache.prepare(myCatalog: models, available: [], enabledSelectors: [models[1].catalogID, "enabled-2"], search: "model-1",
            telemetry: telemetry, at: date)
        #expect(cache.gradeBuildCount == 2)
        #expect(cache.groupingBuildCount == 3)
    }

    @Test("missing telemetry and source failure keep unknown and stale demand distinct")
    func missingAndFailedSources() {
        let date = Date(timeIntervalSince1970: 1_000)
        let models = (0..<7).map { item($0) }
        var telemetry = fixtureTelemetry(models: Array(models.prefix(6)), at: date)
        let cache = ModelManagerPresentationCache()
        let initial = cache.prepare(myCatalog: models, available: [], enabledSelectors: nil, search: "", telemetry: telemetry, at: date)
        #expect(initial.grades[models[6].catalogID] == nil)
        #expect(initial.demand(for: models[6]).title == "Demand unavailable")
        telemetry.networkSourceAvailable = false
        let failed = cache.prepare(myCatalog: models, available: [], enabledSelectors: nil, search: "", telemetry: telemetry, at: date)
        #expect(failed.grades.isEmpty)
        #expect(failed.demand(for: models[0]).title == "Demand stale")
        #expect(failed.demand(for: models[0]).model == initial.demand(for: models[0]).model)
        #expect(failed.demand(for: models[6]).title == "Demand unavailable")
        telemetry.networkSourceAvailable = true
        let restored = cache.prepare(myCatalog: models, available: [], enabledSelectors: nil, search: "", telemetry: telemetry, at: date)
        #expect(restored.grades == initial.grades)
        #expect(cache.telemetryIndexBuildCount == 1)
    }

    @Test("indexed aliases preserve whichever catalog or local match appeared first")
    func aliasOrder() {
        let model = item(0)
        let local = ModelTokenRateAverage(model: model.localID!, tokensPerSecond: 20, sampleCount: 4, queryPeriod: nil)
        let catalog = ModelTokenRateAverage(model: model.catalogID, tokensPerSecond: 99, sampleCount: 4, queryPeriod: nil)
        let cache = ModelManagerPresentationCache()
        for values in [[local, catalog], [catalog, local], [local, local, catalog]] {
            let prepared = cache.prepare(myCatalog: [model], available: [], enabledSelectors: nil, search: "",
                telemetry: ModelManagerTelemetry(tokenRates: values), at: Date())
            #expect(prepared.tokenRate(for: model) == values.first)
        }
    }

    @Test("freshness transition schedule expires without a new payload and accepts bounded future skew")
    func freshnessTransitions() {
        let captured = Date(timeIntervalSince1970: 1_000)
        let capacity = NetworkCapacitySnapshot(models: [], capturedAt: captured)
        let before = captured.addingTimeInterval(-6)
        #expect(ModelDemandFreshnessSchedule.nextTransition(capacity: capacity, at: before) == captured.addingTimeInterval(-5))
        #expect(ModelDemandFreshnessSchedule.nextTransition(capacity: capacity, at: captured) == captured.addingTimeInterval(120.001))
        #expect(capacity.isFresh(at: captured.addingTimeInterval(120)))
        #expect(!capacity.isFresh(at: captured.addingTimeInterval(120.001)))
        #expect(ModelDemandFreshnessSchedule.nextTransition(capacity: capacity, at: captured.addingTimeInterval(121)) == nil)
        #expect(ModelDemandFreshnessSchedule.nextTransition(capacity: nil, at: captured) == nil)
    }

    @Test("batch calibration matches legacy grades for missing, loss, invalid, and duplicate signals")
    func calibrationEquivalence() {
        let peers = [
            ModelOpportunitySignal(modelID: "fast", tokensPerSecond: 40, activeHours: 3, demand: .urgent, netProfitUSDPerActiveHour: 1),
            ModelOpportunitySignal(modelID: "slow", tokensPerSecond: 20, activeHours: 3, demand: .low, netProfitUSDPerActiveHour: 0.1),
            ModelOpportunitySignal(modelID: "loss", tokensPerSecond: 50, activeHours: 3, demand: .high, netProfitUSDPerActiveHour: -1),
            ModelOpportunitySignal(modelID: "zero", tokensPerSecond: 30, activeHours: 3, demand: .moderate, netProfitUSDPerActiveHour: 0),
            ModelOpportunitySignal(modelID: "new", tokensPerSecond: 70, activeHours: 1.9, demand: .urgent, netProfitUSDPerActiveHour: 3),
            ModelOpportunitySignal(modelID: "missing", tokensPerSecond: nil, activeHours: 3, demand: nil, netProfitUSDPerActiveHour: nil),
            ModelOpportunitySignal(modelID: "invalid", tokensPerSecond: .infinity, activeHours: 3, demand: .urgent, netProfitUSDPerActiveHour: .nan),
            ModelOpportunitySignal(modelID: "fast", tokensPerSecond: 200, activeHours: 3, demand: .urgent, netProfitUSDPerActiveHour: 100),
        ]
        let grades = ModelManagerPresentation.opportunityGrades(peers: peers)
        for peer in peers { #expect(grades[peer.modelID] == legacyGrade(modelID: peer.modelID, peers: peers)) }
        #expect(grades["not-in-peers"] == nil)
    }

    private func item(_ index: Int, alias: String? = nil) -> ModelInventoryItem {
        ModelInventoryItem(catalogID: "vendor/model-\(index)", localID: "local/model-\(index)", displayName: "Model \(index)",
            modelType: "llm", capabilities: ["text"], sizeGB: 4, minimumRAMGB: 8,
            isDownloaded: true, isEnabled: true, isPreloaded: false,
            liveState: .unloaded, issue: nil, enabledSelector: alias)
    }

    private func fixtureTelemetry(models: [ModelInventoryItem], at date: Date) -> ModelManagerTelemetry {
        ModelManagerTelemetry(
            tokenRates: models.enumerated().map { offset, item in
                ModelTokenRateAverage(model: item.catalogID, tokensPerSecond: Double(offset + 10), sampleCount: 10, queryPeriod: nil)
            },
            servingAverages: models.enumerated().map { offset, item in
                ModelServingProfitAverage(model: item.catalogID, grossUSDPerActiveHour: 1,
                    incrementalElectricityUSDPerActiveHour: 0.1, profitUSDPerActiveHour: Double(offset + 1) / 10,
                    activeHours: 3, coveredEarningHours: 3, activePowerSamples: 10, idlePowerSamples: 10)
            },
            networkCapacity: NetworkCapacitySnapshot(models: models.map { model in
                NetworkModelCapacity(id: model.catalogID, ready: true, canAccept: true,
                    routableProviders: 4, warmProviders: 2, runningProviders: 1, coldProviders: 2,
                    activeRequests: 3, queuedRequests: 2, queueLimit: 8, aggregateTokensPerSecond: 40,
                    estimatedTimeToFirstTokenMS: 300, tokenBudgetRemaining: 9, tokenBudgetTotal: 10)
            }, capturedAt: date)
        )
    }

    private func legacyPeers(models: [ModelInventoryItem], telemetry: ModelManagerTelemetry, at date: Date) -> [ModelOpportunitySignal] {
        models.filter(\.isEnabled).map { model in
            let rate = telemetry.tokenRates.first { $0.model == model.catalogID || $0.model == model.localID }
            let serving = telemetry.servingAverages.first { $0.model == model.catalogID || $0.model == model.localID }
            let demand = telemetry.networkSourceAvailable && telemetry.networkCapacity?.isFresh(at: date) == true
                ? telemetry.networkCapacity?.models.first { $0.id == model.catalogID } : nil
            return ModelOpportunitySignal(modelID: model.catalogID, tokensPerSecond: rate?.tokensPerSecond,
                activeHours: serving?.activeHours ?? 0, demand: demand?.demandBand,
                netProfitUSDPerActiveHour: serving?.profitUSDPerActiveHour)
        }
    }

    private func legacyGrade(modelID: String, peers: [ModelOpportunitySignal]) -> String? {
        func demandScore(_ demand: NetworkDemandBand) -> Double {
            switch demand { case .low: 0.25; case .moderate: 0.5; case .high: 0.75; case .urgent: 1 }
        }
        let calibrated = peers.filter { peer in
            guard peer.activeHours >= 2, let speed = peer.tokensPerSecond, speed.isFinite, speed > 0,
                  peer.demand != nil, let profit = peer.netProfitUSDPerActiveHour, profit.isFinite else { return false }
            return true
        }
        guard let target = calibrated.first(where: { $0.modelID == modelID }), let speed = target.tokensPerSecond,
              let demand = target.demand, let profit = target.netProfitUSDPerActiveHour,
              let fastest = calibrated.compactMap(\.tokensPerSecond).max(), fastest > 0 else { return nil }
        guard profit > 0 else { return "F" }
        let bestProfit = calibrated.compactMap(\.netProfitUSDPerActiveHour).filter { $0 > 0 }.max() ?? 0
        let score = speed / fastest * 40 + demandScore(demand) * 30 + min(30, bestProfit == 0 ? 0 : profit / bestProfit * 30)
        switch score { case 90...: return "A"; case 80..<90: return "B"; case 70..<80: return "C"; case 60..<70: return "D"; default: return "F" }
    }
}
