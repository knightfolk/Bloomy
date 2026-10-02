import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Chart series identity", .serialized)
@MainActor
struct ChartSeriesStyleTests {
    @Test("series retain their distinct shape and number when the visible model is filtered")
    func stableFilteredIdentity() {
        let styles = ChartSeriesStyles(domain: ["gemma", "qwen", "Work", "Base rewards", "qwen"])
        #expect(styles.entries.count == 4)
        #expect(styles.entries.map(\.number) == [1, 2, 3, 4])
        #expect(Set(styles.entries.map { $0.symbol.rawValue }).count == 4)
        #expect(styles["gemma"].dash != styles["qwen"].dash)
        let filtered = styles.visibleEntries(in: ["qwen", "qwen"])
        #expect(filtered.map(\.series) == ["qwen"])
        #expect(filtered.first?.number == 2)
        #expect(filtered.first?.symbol == styles["qwen"].symbol)
        #expect(styles.visibleEntries(in: []).isEmpty)
    }

    @Test("canonical model identities remain distinct even when their display names collide")
    func canonicalSeriesIdentity() {
        let first = "owner-a/shared-model"
        let second = "owner-b/shared-model"
        let styles = ChartSeriesStyles(domain: [first, second])
        #expect(styles.entries.map(\.series) == [first, second])
        #expect(styles[first].number != styles[second].number)
        #expect(styles[first].symbol != styles[second].symbol)
    }

    @Test("a month of activity gets at most one existing direct cue per series")
    func boundedActivityCues() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let values = (0..<30).flatMap { index in
            ["gemma", "qwen"].enumerated().map { offset, model in
                ActivityChartValue(
                    interval: DateInterval(start: start.addingTimeInterval(Double(index) * 86_400), duration: 86_400),
                    series: model, amountUSD: Double(index + offset + 1), run: 0
                )
            }
        }
        let cues = ChartSeriesCueSelection.values(values)
        #expect(cues.count == 2)
        #expect(cues.isSubset(of: Set(values.map(\.id))))
        #expect(cues == Set(values.suffix(2).map(\.id)))
        let segments = values.map {
            ActivityChartSegment(interval: $0.interval, series: $0.series, startUSD: 0, endUSD: -$0.amountUSD)
        }
        #expect(ChartSeriesCueSelection.segments(segments) == cues)
    }

    @Test("zero, empty, and nonfinite values do not invent chart cues")
    func noInventedCues() {
        let interval = DateInterval(start: .distantPast, duration: 3_600)
        #expect(ChartSeriesCueSelection.values([]).isEmpty)
        #expect(ChartSeriesCueSelection.segments([]).isEmpty)
        let scalar = ActivityChartValue(interval: interval, series: "Work", amountUSD: 2, run: 0)
        #expect(ChartSeriesCueSelection.values([scalar]) == [scalar.id])
        let zero = ActivityChartValue(interval: interval, series: "Base rewards", amountUSD: 0, run: 0)
        let invalid = ActivityChartValue(interval: interval, series: "unknown", amountUSD: .nan, run: 0)
        #expect(ChartSeriesCueSelection.values([scalar, zero, invalid]) == [scalar.id])
    }

    @Test("series cues respect selected model, base rewards, and unknown bucket gaps")
    func preservedActivityRules() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let first = DateInterval(start: start, duration: 3_600)
        let second = DateInterval(start: first.end, duration: 3_600)
        let buckets = [
            ActivityBucket(interval: first, totals: ActivityTotals(workMicroUSD: 50_000, rewardMicroUSD: 10_000,
                jobs: 1, promptTokens: 10, completionTokens: 20), coverage: .recorded),
            ActivityBucket(interval: second, totals: nil, coverage: .unavailable),
        ]
        let work: [Date: [String: Int64]] = [first.start: ["gemma": 30_000, "qwen": 20_000]]
        let all = ActivityChartData.values(buckets: buckets, models: ["gemma", "qwen"], modelWorkByBucket: work, selectedModel: nil)
        #expect(Set(all.map(\.series)) == ["gemma", "qwen", "Base rewards"])
        #expect(all.allSatisfy { $0.interval == first })
        #expect(ChartSeriesCueSelection.values(all).count == 3)
        let filtered = ActivityChartData.values(buckets: buckets, models: ["gemma", "qwen"], modelWorkByBucket: work, selectedModel: "qwen")
        #expect(filtered.map(\.series) == ["qwen"])
        #expect(filtered.first?.amountUSD == 0.02)
        #expect(ChartSeriesCueSelection.values(filtered) == Set(filtered.map(\.id)))
    }

    @Test("selected-model Area cues retain totals-only attribution instead of inventing aggregate Work")
    func totalsOnlySelectedModelAreaCue() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), duration: 3_600)
        let bucket = ActivityBucket(interval: interval, totals: ActivityTotals(workMicroUSD: 50_000,
            rewardMicroUSD: 10_000, jobs: 1, promptTokens: 10, completionTokens: 20), coverage: .recorded)
        let values = ActivityChartData.values(buckets: [bucket], models: ["qwen"],
            modelWorkByBucket: [:], selectedModel: "qwen")
        let cues = ChartSeriesCueSelection.areaCues(values)
        #expect(values.map(\.series) == ["qwen"])
        #expect(cues.map(\.series) == ["qwen"])
        #expect(cues.map(\.id) == values.map(\.id))
        #expect(cues.first?.startUSD == 0)
        #expect(cues.first?.endUSD == values.first?.amountUSD)
        let styles = ChartSeriesStyles(domain: ["qwen", "Work", "Base rewards"])
        #expect(styles.visibleEntries(in: values.map(\.series)).map(\.series) == cues.map(\.series))
    }

    @Test("Area cue positions follow plotted order and signs and never fill an unknown bucket")
    func areaCueStacksAndGaps() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 1_800_000_000), duration: 3_600)
        let afterGap = DateInterval(start: first.end.addingTimeInterval(3_600), duration: 3_600)
        let values = [
            ActivityChartValue(interval: first, series: "z-positive", amountUSD: 2, run: 0),
            ActivityChartValue(interval: first, series: "z-negative", amountUSD: -3, run: 0),
            ActivityChartValue(interval: first, series: "a-positive", amountUSD: 4, run: 0),
            ActivityChartValue(interval: first, series: "a-negative", amountUSD: -5, run: 0),
            ActivityChartValue(interval: afterGap, series: "z-positive", amountUSD: 8, run: 1),
        ]
        let cues = ChartSeriesCueSelection.areaCues(values)
        #expect(cues.map(\.series) == ["z-positive", "z-negative", "a-positive", "a-negative"])
        #expect(cues.map(\.startUSD) == [0, 0, 2, -3])
        #expect(cues.map(\.endUSD) == [8, -3, 6, -8])
        #expect(cues.first?.interval == afterGap)
        #expect(cues.allSatisfy { $0.interval == first || $0.interval == afterGap })
        #expect(Set(cues.map(\.id)).isSubset(of: Set(values.map(\.id))))
        #expect(ChartSeriesCueSelection.areaCues([]).isEmpty)
    }

}
