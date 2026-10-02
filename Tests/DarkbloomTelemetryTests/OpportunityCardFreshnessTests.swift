import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Opportunity card freshness")
struct OpportunityCardFreshnessTests {
    @Test("each standalone metric describes its model and current or retained source", arguments: [false, true])
    func standaloneMetrics(current: Bool) {
        for (title, value, observation) in [
            ("In progress", "3", "Network in progress for example/model: 3"),
            ("Waiting", "0", "Network waiting for example/model: 0"),
            ("Loaded", "4", "Network loaded for example/model: 4"),
            ("Network tok/s", "120.5", "Network throughput in tokens per second for example/model: 120.5")
        ] {
            let label = OpportunityCardFreshness.metricLabel(title, value: value, modelID: "example/model", isCurrent: current)
            #expect(label == (current ? observation : "Last reported: \(observation). Current network status is unknown."))
        }
        let help = OpportunityCardFreshness.metricHelp(isCurrent: current, throughput: true)
        #expect(help.contains("not the speed of this Mac"))
        #expect(help.contains("current value is unknown") == !current)
    }

    @Test("retained accepting and quiet states never imply present routing", arguments: [false, true])
    func retainedStatus(accepting: Bool) {
        let model = capacity(accepting: accepting)
        let demand = OpportunityPresentation.demand(model)
        #expect(demand == (accepting ? "Quiet" : "Not accepting"))
        #expect(OpportunityCardFreshness.status(demand, isCurrent: true) == demand)
        #expect(OpportunityCardFreshness.status(demand, isCurrent: false)
            == "Last reported: \(demand). Current network status is unknown.")
        let routing = "7 routable providers · \(accepting ? "accepting requests" : "not accepting requests")"
        #expect(OpportunityCardFreshness.status(routing, isCurrent: false)
            == "Last reported: \(routing). Current network status is unknown.")
    }

    @Test("aged and future network snapshots produce retained standalone labels", arguments: [121.0, -6.0])
    func invalidCurrentAge(age: TimeInterval) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = NetworkCapacitySnapshot(models: [capacity(accepting: true)], capturedAt: now.addingTimeInterval(-age))
        let source: SourceAvailability<NetworkCapacitySnapshot> = .available(value: snapshot, capturedAt: snapshot.capturedAt)
        let current = PopupNetworkDemandPresentation.freshness(of: source, at: now) == .current
        #expect(!current)
        #expect(OpportunityCardFreshness.metricLabel("Waiting", value: "0", modelID: snapshot.models[0].id, isCurrent: current)
            == "Last reported: Network waiting for example/model: 0. Current network status is unknown.")
    }

    private func capacity(accepting: Bool) -> NetworkModelCapacity {
        NetworkModelCapacity(id: "example/model", ready: true, canAccept: accepting, routableProviders: 7,
            warmProviders: 4, runningProviders: 0, coldProviders: 3, activeRequests: 0, queuedRequests: 0,
            queueLimit: 16, aggregateTokensPerSecond: 0, estimatedTimeToFirstTokenMS: 0,
            tokenBudgetRemaining: 100, tokenBudgetTotal: 100)
    }
}
