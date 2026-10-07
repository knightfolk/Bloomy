import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Shared network demand ruler")
struct ModelDemandRulerTests {
    @Test("all models use the same linear requests per loaded provider scale")
    func sharedScale() {
        let busy = model("busy", active: 14, queued: 0, warm: 2)
        let queued = model("queued", active: 5, queued: 3, warm: 4)
        let quiet = model("quiet", active: 0, queued: 0, warm: 8)
        let scale = ModelDemandScale(models: [busy, queued, quiet])
        #expect(scale.upperBound == 7)
        #expect(scale.fraction(for: busy) == 1)
        #expect(scale.fraction(for: queued) == 2.0 / 7)
        #expect(scale.fraction(for: quiet) == 0)
        #expect(ModelDemandScale(models: [quiet]).upperBound == 1)
        #expect(ModelDemandScale(models: []).upperBound == 1)
    }

    @Test("unknown denominator and malformed counts do not become a zero marker or inflate the scale")
    func unknownAndInvalid() {
        let noLoaded = model("no-loaded", active: 500, queued: 20, warm: 0)
        let invalid = model("invalid", active: -1, queued: 0, warm: 1)
        let invalidQueue = model("invalid-queue", active: 2, queued: -1, warm: 1)
        let invalidWarm = model("invalid-warm", active: 2, queued: 1, warm: -1)
        let scale = ModelDemandScale(models: [noLoaded, invalid, invalidQueue, invalidWarm])
        #expect(scale.upperBound == 1)
        for value in [noLoaded, invalid, invalidQueue, invalidWarm] {
            #expect(ModelDemandScale.pressure(value) == nil)
            #expect(scale.fraction(for: value) == nil)
        }
    }

    @Test("extreme request counts stay finite and tiny nonzero values stay visible")
    func extremes() {
        let huge = model("huge", active: Int.max, queued: Int.max, warm: 1)
        let tiny = model("tiny", active: 1, queued: 0, warm: Int.max)
        let scale = ModelDemandScale(models: [huge, tiny])
        #expect(scale.upperBound.isFinite)
        #expect(scale.fraction(for: huge) == 1)
        #expect(scale.fraction(for: tiny)! > 0)
        #expect(ModelDemandScale.label(ModelDemandScale.pressure(tiny)!) != "0")
        #expect(ModelDemandScale.label(scale.upperBound) != "0")
    }

    @Test("search and staged selection do not rescale retained network readings")
    @MainActor func filteredScale() {
        let now = Date(timeIntervalSince1970: 1_000)
        let capacities = [model("visible", active: 1, queued: 0, warm: 4), model("hidden", active: 14, queued: 0, warm: 2)]
        let items = capacities.map {
            ModelInventoryItem(catalogID: $0.id, localID: $0.id, displayName: $0.id,
                modelType: "llm", capabilities: [], sizeGB: 1, minimumRAMGB: 1,
                isDownloaded: true, isEnabled: true, isPreloaded: false, liveState: .unloaded, issue: nil)
        }
        var telemetry = ModelManagerTelemetry(networkCapacity: .init(models: capacities, capturedAt: now))
        let cache = ModelManagerPresentationCache()
        let initial = cache.prepare(myCatalog: items, available: [], enabledSelectors: nil,
            search: "", telemetry: telemetry, at: now)
        let searched = cache.prepare(myCatalog: items, available: [], enabledSelectors: ["visible"],
            search: "visible", telemetry: telemetry, at: now)
        #expect(searched.grouping.enabled.count == 1)
        #expect(searched.demandScale == initial.demandScale)
        #expect(searched.demandScale.upperBound == 7)
        #expect(cache.telemetryIndexBuildCount == 1)
        telemetry.networkSourceAvailable = false
        let failed = cache.prepare(myCatalog: items, available: [], enabledSelectors: ["visible"],
            search: "visible", telemetry: telemetry, at: now)
        #expect(failed.demandScale == initial.demandScale)
        #expect(!failed.demand(for: items[0]).isCurrent)
        #expect(failed.demand(for: items[0]).model == capacities[0])
        telemetry.networkCapacity = .init(models: [capacities[0]], capturedAt: now)
        let changed = cache.prepare(myCatalog: items, available: [], enabledSelectors: nil,
            search: "", telemetry: telemetry, at: now)
        #expect(changed.demandScale.upperBound == 1)
        #expect(cache.telemetryIndexBuildCount == 2)
    }

    @Test("current stale missing and zero-loaded rulers render at narrow and wide widths", arguments: [180.0, 300.0, 460.0])
    @MainActor func rendering(width: Double) throws {
        let capacity = model("example", active: 5, queued: 3, warm: 4)
        let scale = ModelDemandScale(models: [capacity])
        let states: [ModelCardDemand] = [.init(model: capacity, isCurrent: true),
            .init(model: capacity, isCurrent: false), .init(model: nil, isCurrent: false),
            .init(model: model("example", active: 8, queued: 2, warm: 0), isCurrent: true)]
        for state in states {
            let renderer = ImageRenderer(content: ModelDemandRuler(modelID: "example", demand: state, scale: scale)
                .frame(width: width).padding(8))
            let image = try #require(renderer.nsImage)
            // ImageRenderer can return subpixel floating-point differences.
            #expect(abs(image.size.width - (width + 16)) < 0.01)
            #expect(image.size.height > 30 && image.size.height < 80)
        }
    }

    private func model(_ id: String, active: Int, queued: Int, warm: Int) -> NetworkModelCapacity {
        .init(id: id, ready: true, canAccept: true, routableProviders: max(0, warm),
            warmProviders: warm, runningProviders: 0, coldProviders: 0, activeRequests: active,
            queuedRequests: queued, queueLimit: 8, aggregateTokensPerSecond: 10,
            estimatedTimeToFirstTokenMS: 100, tokenBudgetRemaining: 9, tokenBudgetTotal: 10)
    }
}
