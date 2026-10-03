import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Profit chart aggregation", .serialized)
struct ActivityProfitAggregationTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func bucket(_ offset: TimeInterval, duration: TimeInterval = 3_600) -> ActivityBucket {
        ActivityBucket(interval: DateInterval(start: start.addingTimeInterval(offset), duration: duration),
                       totals: nil, coverage: .unavailable)
    }

    private func profit(_ offset: TimeInterval, model: String = "qwen", amount: Double,
                        duration: TimeInterval = 3_600) -> ModelHourlyProfit {
        ModelHourlyProfit(interval: DateInterval(start: start.addingTimeInterval(offset), duration: duration),
            model: model, grossUSD: amount, allocatedElectricityUSD: 0, profitUSD: amount, estimated: true)
    }

    @Test("signed, duplicate, zero and nonfinite observations retain exact original-order means")
    func originalOrderMeans() {
        let buckets = [bucket(0), bucket(3_600), bucket(7_200), bucket(10_800)]
        let rows = [profit(0, amount: 1e16), profit(0, amount: -1e16), profit(0, amount: 1),
                    profit(0, model: "gemma", amount: -0.25), profit(3_600, amount: 0),
                    profit(10_800, amount: 0.5), profit(7_200, amount: .nan),
                    profit(7_200, amount: .infinity), profit(10_800, model: "gemma", amount: -.infinity)]
        for input in [rows, Array(rows.reversed())] {
            for selected in [nil, "qwen", "absent"] as [String?] {
                #expect(ActivityChartData.profitValues(hourly: input, buckets: buckets, selectedModel: selected)
                        == referenceProfits(hourly: input, buckets: buckets, selectedModel: selected))
            }
        }
        let qwen = ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: "qwen")
        #expect(qwen.map(\.run) == [0, 0, 1])
        #expect(qwen.map(\.amountUSD) == [1.0 / 3, 0, 0.5])
    }

    @Test("whole-record containment includes exact edges and excludes crossing/outside records")
    func containment() {
        let buckets = [bucket(0), bucket(7_200), bucket(10_800, duration: 1_800)]
        let rows = [profit(0, amount: 1), profit(-1, amount: 2), profit(3_599, amount: 3),
                    profit(3_600, amount: 4), profit(7_200, amount: 5),
                    profit(10_800, amount: 6, duration: 1_800), profit(10_800, amount: 7),
                    profit(14_400, amount: 8)]
        let result = ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: nil)
        #expect(result == referenceProfits(hourly: rows, buckets: buckets, selectedModel: nil))
        #expect(result.map(\.amountUSD) == [1, 5, 6])
        // Runs follow supplied bucket positions; omitted calendar buckets are not invented.
        #expect(result.map(\.run) == [0, 0, 0])
    }

    @Test("unordered, overlapping, duplicate and zero-length intervals preserve generic containment")
    func genericIntervals() {
        let rows = [profit(0, amount: 1), profit(3_600, amount: 2),
                    profit(3_600, amount: 4, duration: 0), profit(7_200, amount: 8, duration: 0)]
        let cases = [[bucket(3_600), bucket(0)],
                     [bucket(0, duration: 7_200), bucket(3_600, duration: 7_200)],
                     [bucket(0), bucket(0), bucket(3_600)],
                     [bucket(0), bucket(3_600), bucket(7_200, duration: 0)]]
        for buckets in cases {
            #expect(ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: nil)
                    == referenceProfits(hourly: rows, buckets: buckets, selectedModel: nil))
        }
    }

    @Test("actual spring and fall calendar days retain 23 and 25 complete hours", arguments: [true, false])
    func daylightSaving(spring: Bool) throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/New_York"))
        let date = try #require(calendar.date(from: DateComponents(year: 2026,
            month: spring ? 3 : 11, day: spring ? 8 : 1, hour: 12)))
        let day = try #require(calendar.dateInterval(of: .day, for: date))
        let hours = try ActivityCalendar.intervals(in: day, unit: .hour, calendar: calendar)
        #expect(hours.count == (spring ? 23 : 25))
        let buckets = [ActivityBucket(interval: day, totals: nil, coverage: .unavailable)]
        let rows = hours.enumerated().map { i, interval in
            ModelHourlyProfit(interval: interval, model: "qwen", grossUSD: 0,
                allocatedElectricityUSD: 0, profitUSD: Double(i) / 10, estimated: true)
        }
        #expect(ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: nil)
                == referenceProfits(hourly: rows, buckets: buckets, selectedModel: nil))
    }

    @Test("empty input and overflow remain absent instead of becoming zero")
    func emptyAndOverflow() {
        let buckets = [bucket(0)]
        let rows = [profit(0, amount: .greatestFiniteMagnitude), profit(0, amount: .greatestFiniteMagnitude)]
        #expect(ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: nil).isEmpty)
        #expect(ActivityChartData.profitValues(hourly: [], buckets: buckets, selectedModel: nil).isEmpty)
        #expect(ActivityChartData.profitValues(hourly: rows, buckets: [], selectedModel: nil).isEmpty)
    }

    @Test("isolated Release scaling benchmark", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_PROFIT_BENCHMARK"] == "1"))
    func scalingBenchmark() throws {
        let clock = ContinuousClock()
        for (label, days, modelCount, hourlyBuckets) in [("366d_1model", 366, 1, false),
                                                        ("366d_8models", 366, 8, false),
                                                        ("24h_8models", 1, 8, true)] {
            let count = hourlyBuckets ? 24 : days
            let duration: TimeInterval = hourlyBuckets ? 3_600 : 86_400
            let buckets = (0..<count).map { bucket(Double($0) * duration, duration: duration) }
            let rows = (0..<(days * 24)).flatMap { hour in
                (0..<modelCount).map { model in
                    profit(Double(hour) * 3_600, model: "model-\(model)", amount: Double((hour + model) % 17 - 8) / 100)
                }
            }
            let expected = referenceProfits(hourly: rows, buckets: buckets, selectedModel: nil)
            #expect(ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: nil) == expected)
            var referenceMS: [Double] = []
            var currentMS: [Double] = []
            for _ in 0..<5 {
                let beforeReference = clock.now
                let old = referenceProfits(hourly: rows, buckets: buckets, selectedModel: nil)
                referenceMS.append(milliseconds(beforeReference.duration(to: clock.now)))
                let beforeCurrent = clock.now
                let current = ActivityChartData.profitValues(hourly: rows, buckets: buckets, selectedModel: nil)
                currentMS.append(milliseconds(beforeCurrent.duration(to: clock.now)))
                #expect(old == current)
            }
            let result: [String: Any] = ["case": label, "buckets": buckets.count, "rows": rows.count,
                "reference_median_ms": referenceMS.sorted()[2], "current_median_ms": currentMS.sorted()[2],
                "reference_samples_ms": referenceMS, "current_samples_ms": currentMS]
            let data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            print("BLOOMY_PROFIT_BENCHMARK \(String(decoding: data, as: UTF8.self))")
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }
}

// Exact pre-optimization algorithm retained as an independent equivalence oracle.
private func referenceProfits(hourly: [ModelHourlyProfit], buckets: [ActivityBucket],
                             selectedModel: String?) -> [ActivityChartValue] {
    let points = hourly.filter { $0.profitUSD.isFinite && (selectedModel == nil || $0.model == selectedModel) }
    var lastBucketIndex: [String: Int] = [:]
    var runBySeries: [String: Int] = [:]
    var result: [ActivityChartValue] = []
    for (bucketIndex, bucket) in buckets.enumerated() {
        let inBucket = points.filter { $0.interval.start >= bucket.interval.start && $0.interval.end <= bucket.interval.end }
        let byModel = Dictionary(grouping: inBucket, by: \.model)
        for model in byModel.keys.sorted() {
            guard let values = byModel[model], !values.isEmpty else { continue }
            let amount = values.reduce(0) { $0 + $1.profitUSD } / Double(values.count)
            guard amount.isFinite else { continue }
            let run: Int
            if let previous = lastBucketIndex[model] {
                run = runBySeries[model, default: 0] + (previous == bucketIndex - 1 ? 0 : 1)
            } else { run = 0 }
            runBySeries[model] = run
            lastBucketIndex[model] = bucketIndex
            result.append(ActivityChartValue(interval: bucket.interval, series: model, amountUSD: amount, run: run))
        }
    }
    return result
}
