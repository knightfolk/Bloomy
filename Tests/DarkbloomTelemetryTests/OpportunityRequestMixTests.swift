import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Opportunity request mix and visible aliases preserve network meaning")
struct OpportunityRequestMixTests {
    @Test("Only active and waiting requests contribute, with a distinct recorded zero")
    func composition() {
        let mix = OpportunityRequestMix(active: 9, waiting: 3)
        #expect(mix.isValid && mix.activeFraction == 0.75 && mix.waitingFraction == 0.25)
        let zero = OpportunityRequestMix(active: 0, waiting: 0)
        #expect(zero.isValid && zero.activeFraction == 0 && zero.waitingFraction == 0)
        let waiting = OpportunityRequestMix(active: 0, waiting: 12)
        #expect(waiting.activeFraction == 0 && waiting.waitingFraction == 1)
    }

    @Test("Invalid counts are unavailable, while maximum integer counts cannot overflow", arguments: [(-1, 3), (3, -1), (Int.max, Int.max)])
    func bounds(counts: (Int, Int)) {
        let value = OpportunityRequestMix(active: counts.0, waiting: counts.1)
        if counts.0 < 0 || counts.1 < 0 {
            #expect(!value.isValid && value.activeFraction == 0 && value.waitingFraction == 0)
        } else {
            #expect(value.isValid && value.activeFraction == 0.5 && value.waitingFraction == 0.5)
        }
    }

    @Test("Known aliases remain concise and searchable even when catalog names are longer")
    func aliases() {
        let model = capacity("ternary-bonsai-2-27b")
        let metadata = CatalogModel(id: model.id, displayName: "PrismML Bonsai 2 27B", family: "prismml",
            modelType: "llm", capabilities: [], sizeGB: 10, minimumRAMGB: 16, active: true)
        let name = OpportunityPresentation.cardName(model, metadata: metadata)
        #expect(name == "Bonsai 2 · 27B")
        #expect(OpportunityPresentation.matchesSearch(name, model: model, metadata: metadata))
        #expect(OpportunityPresentation.name(model, metadata: metadata) == metadata.displayName)
        let unknown = capacity("Example/new-model")
        let unknownMetadata = CatalogModel(id: unknown.id, displayName: "New model", family: "example",
            modelType: "llm", capabilities: [], sizeGB: 10, minimumRAMGB: 16, active: true)
        #expect(OpportunityPresentation.cardName(unknown, metadata: unknownMetadata) == "New model")
        #expect(OpportunityPresentation.cardName(unknown, metadata: metadata) == "new-model")
    }

    private func capacity(_ id: String) -> NetworkModelCapacity {
        NetworkModelCapacity(id: id, ready: true, canAccept: true, routableProviders: 5,
            warmProviders: 3, runningProviders: 2, coldProviders: 2, activeRequests: 9,
            queuedRequests: 3, queueLimit: 16, aggregateTokensPerSecond: 120,
            estimatedTimeToFirstTokenMS: 100, tokenBudgetRemaining: 500, tokenBudgetTotal: 1_000)
    }
}
