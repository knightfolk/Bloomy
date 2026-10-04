import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Graphic earnings summary preserves ledger meaning")
struct EarningsCompositionTests {
    private let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 3_600)

    private func value(_ series: String, _ usd: Double) -> ActivityChartValue {
        ActivityChartValue(interval: interval, series: series, amountUSD: usd, run: 0)
    }

    @Test("Missing values stay unknown; recorded zero does not become a share")
    func zeroAndMissing() {
        let missing = EarningsComposition(values: [])
        #expect(missing.totalUSD == nil && missing.parts.isEmpty && !missing.canShowShare)
        let zero = EarningsComposition(values: [value("Work", 0)])
        #expect(zero.totalUSD == 0 && zero.parts.count == 1 && !zero.canShowShare)
    }

    @Test("Signed corrections are retained and never shown as positive pie slices")
    func signedCorrections() {
        let result = EarningsComposition(values: [value("Qwen", 0.1), value("Qwen", -0.025), value("Base rewards", -0.000001)])
        #expect(abs((result.totalUSD ?? 0) - 0.074999) < 1e-12)
        #expect(result.parts.first?.name == "Qwen")
        #expect(result.parts.last?.usd == -0.000001)
        #expect(!result.canShowShare)
    }

    @Test("The summary follows model and reward filtering, including micro-dollar work")
    func filters() {
        let bucket = ActivityBucket(interval: interval,
            totals: ActivityTotals(workMicroUSD: 4, rewardMicroUSD: 2, jobs: 2, promptTokens: 0, completionTokens: 0), coverage: .recorded)
        let work: [Date: [String: Int64]] = [interval.start: ["Qwen": 1, "Gemma": 3]]
        func summary(model: String?, rewards: Bool) -> EarningsComposition {
            EarningsComposition(values: ActivityChartData.values(buckets: [bucket], models: ["Qwen", "Gemma"],
                modelWorkByBucket: work, selectedModel: model, includeRewards: rewards))
        }
        #expect(abs((summary(model: nil, rewards: true).totalUSD ?? 0) - 0.000006) < 1e-15)
        #expect(abs((summary(model: nil, rewards: false).totalUSD ?? 0) - 0.000004) < 1e-15)
        #expect(summary(model: "Qwen", rewards: true).totalUSD == 0.000001)
        #expect(summary(model: "Qwen", rewards: true).parts.map(\.name) == ["Qwen"])
    }

    @Test("Invalid custom client values cannot form a misleading partial total", arguments: [Double.nan, .infinity, -.infinity])
    func invalidValues(_ amount: Double) {
        let result = EarningsComposition(values: [value("Work", 1), value("Bad", amount)])
        #expect(result.totalUSD == nil && result.parts.isEmpty && !result.canShowShare)
    }
}
