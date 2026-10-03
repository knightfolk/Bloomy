import DarkbloomTelemetry
import Foundation

enum ActivityChartStyle: String, CaseIterable, Identifiable {
    case bars = "Bars"
    case lines = "Lines"
    case area = "Area"

    var id: Self { self }
}

enum ActivityBarArrangement: String, CaseIterable, Identifiable {
    case stacked = "Stacked"
    case sideBySide = "Side by side"

    var id: Self { self }
}

enum ActivityChartMetric: String, CaseIterable, Identifiable {
    case earnings = "Earnings"
    case estimatedProfit = "Est. profit / hour"

    var id: Self { self }
}

struct ActivityChartValue: Equatable, Identifiable {
    let interval: DateInterval
    let series: String
    let amountUSD: Double
    let run: Int

    var id: String { "\(interval.start.timeIntervalSince1970)-\(series)" }
    var runKey: String { "\(series)-run-\(run)" }
}

enum ActivityAmountPresentation {
    static func tableAmount(_ microUSD: Int64?, locale: Locale = .current) -> String {
        guard let microUSD else { return "—" }
        return (Decimal(microUSD) / 1_000_000)
            .formatted(.number.locale(locale).precision(.fractionLength(4...6)))
    }

    /// Estimated hourly amounts can be smaller than one ledger micro-dollar.
    /// Share the point formatter so cards never round nonzero evidence to zero.
    static func hourlyAmount(_ amountUSD: Double, locale: Locale = .current) -> String {
        guard amountUSD.isFinite else { return "—" }
        return ChartSeriesCueSelection.pointAmountLabel(amountUSD, locale: locale)
    }
}

struct ActivityChartColorComponents: Equatable {
    let hue: Double
    let saturation: Double
    let brightness: Double
}

enum ActivityChartPalette {
    static func components(for model: String) -> ActivityChartColorComponents {
        let family = ModelFamilyIcon.select(status: .online, activeModel: model)
        let baseHue: Double
        switch family {
        case .google: baseHue = 0.59
        case .qwen: baseHue = 0.09
        case .openai: baseHue = 0.75
        case .nvidia: baseHue = 0.34
        case .prismml: baseHue = 0.95
        case .darkbloom: baseHue = 0.52
        }

        // Closely related hues keep each provider recognizable while still
        // making the provider's individual models distinguishable.
        let hash = stableHash(model)
        let hueOffsets = [-0.018, -0.009, 0.0, 0.009, 0.018]
        let saturationLevels = [0.58, 0.65, 0.72]
        let brightnessLevels = [0.82, 0.90, 0.98]
        let hue = (baseHue + hueOffsets[Int(hash % UInt64(hueOffsets.count))] + 1)
            .truncatingRemainder(dividingBy: 1)
        return ActivityChartColorComponents(
            hue: hue,
            saturation: saturationLevels[Int((hash / 5) % UInt64(saturationLevels.count))],
            brightness: brightnessLevels[Int((hash / 15) % UInt64(brightnessLevels.count))]
        )
    }

    private static func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
            (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
    }
}

struct ActivityChartSegment: Equatable, Identifiable {
    let interval: DateInterval
    let series: String
    let startUSD: Double
    let endUSD: Double

    var id: String { "\(interval.start.timeIntervalSince1970)-\(series)" }
}

enum ActivityChartData {
    /// Custom clients may repeat a presentation identity. Retain an original
    /// amount without introducing a trapping dictionary into chart rendering.
    static func originalAmounts(values: [ActivityChartValue]) -> [String: Double] {
        values.reduce(into: [:]) { $0[$1.id] = $1.amountUSD }
    }
    /// One aggregate marker for an interval whose displayed series are all
    /// recorded zero. Missing buckets have no values and never create a marker.
    static func recordedZeroValues(_ values: [ActivityChartValue]) -> [ActivityChartValue] {
        Dictionary(grouping: values, by: \.interval.start).values.compactMap { intervalValues in
            intervalValues.allSatisfy { $0.amountUSD == 0 } ? intervalValues.first : nil
        }.sorted { $0.interval.start < $1.interval.start }
    }
    static func colorScaleDomain(models: [String], selectedModel: String? = nil) -> [String] {
        var seen = Set<String>()
        return (models + (selectedModel.map { [$0] } ?? []) + ["Work", "Base rewards"])
            .filter { seen.insert($0).inserted }
    }

    static func values(
        buckets: [ActivityBucket],
        models: [String],
        modelWorkByBucket: [Date: [String: Int64]],
        selectedModel: String?,
        includeRewards: Bool = true
    ) -> [ActivityChartValue] {
        let chartModels = selectedModel.map { [$0] } ?? models
        var lastBucketIndex: [String: Int] = [:]
        var runBySeries: [String: Int] = [:]
        var result: [ActivityChartValue] = []

        for (bucketIndex, bucket) in buckets.enumerated() {
            guard let totals = bucket.totals else { continue }
            let amounts = modelWorkByBucket[bucket.id] ?? [:]
            var seriesValues: [(String, Double)] = []

            for model in chartModels {
                if let work = amounts[model] {
                    seriesValues.append((model, Double(work) / 1_000_000))
                }
            }

            if selectedModel == nil {
                let modelTotal = amounts.values.reduce(Int64(0)) { total, value in
                    let (sum, overflow) = total.addingReportingOverflow(value)
                    return overflow ? Int64.max : sum
                }
                if modelTotal == totals.workMicroUSD {
                    let known = Set(amounts.keys)
                    for model in models where !known.contains(model) {
                        seriesValues.append((model, 0))
                    }
                }
            } else if !seriesValues.contains(where: { $0.0 == selectedModel }) {
                // A selected-model query is already model-filtered. Retain its
                // totals when an older client does not provide per-model rows.
                seriesValues.append((selectedModel!, Double(totals.workMicroUSD) / 1_000_000))
            }

            let hasModelEarnings = seriesValues.contains { $0.0 != "Base rewards" && $0.1 != 0 }
            if !hasModelEarnings, selectedModel == nil, totals.workMicroUSD != 0 {
                // Legacy/custom clients can supply aggregate work only.
                seriesValues.append(("Work", Double(totals.workMicroUSD) / 1_000_000))
            }

            if includeRewards, selectedModel == nil {
                seriesValues.append(("Base rewards", Double(totals.rewardMicroUSD) / 1_000_000))
            }

            for (series, amountUSD) in seriesValues {
                let run: Int
                if let previous = lastBucketIndex[series] {
                    run = runBySeries[series, default: 0] + (previous == bucketIndex - 1 ? 0 : 1)
                } else {
                    run = 0
                }
                runBySeries[series] = run
                lastBucketIndex[series] = bucketIndex
                result.append(ActivityChartValue(
                    interval: bucket.interval,
                    series: series,
                    amountUSD: amountUSD,
                    run: run
                ))
            }
        }
        return result
    }

    static func maximumUSD(values: [ActivityChartValue], stacked: Bool) -> Double {
        profitBounds(values: values, stacked: stacked).maximum
    }

    static func profitValues(
        hourly: [ModelHourlyProfit],
        buckets: [ActivityBucket],
        selectedModel: String?
    ) -> [ActivityChartValue] {
        let points = hourly.filter {
            $0.profitUSD.isFinite && (selectedModel == nil || $0.model == selectedModel)
        }
        guard !points.isEmpty, !buckets.isEmpty else { return [] }
        var aggregates = Array(repeating: [String: ProfitMean](), count: buckets.count)
        // Calendar buckets are ordered and disjoint. Positive-length records
        // can belong to at most one bucket, found without scanning the history
        // again for every bucket. Retain generic containment for custom clients.
        let ordered = buckets.enumerated().allSatisfy { index, bucket in
            bucket.interval.duration > 0 && bucket.interval.start.timeIntervalSince1970.isFinite
                && bucket.interval.end.timeIntervalSince1970.isFinite
                && (index == 0 || buckets[index - 1].interval.end <= bucket.interval.start)
        }
        let positiveRecords = points.allSatisfy { $0.interval.duration > 0 }
        for point in points {
            if ordered && positiveRecords {
                var lower = 0
                var upper = buckets.count
                while lower < upper {
                    let middle = lower + (upper - lower) / 2
                    if buckets[middle].interval.end < point.interval.end { lower = middle + 1 }
                    else { upper = middle }
                }
                if lower < buckets.count,
                   point.interval.start >= buckets[lower].interval.start,
                   point.interval.end <= buckets[lower].interval.end {
                    aggregates[lower][point.model, default: ProfitMean()].record(point.profitUSD)
                }
            } else {
                // Zero-length observations can match both sides of an edge;
                // overlapping, duplicate or unordered buckets may match many.
                for index in buckets.indices where point.interval.start >= buckets[index].interval.start
                    && point.interval.end <= buckets[index].interval.end {
                    aggregates[index][point.model, default: ProfitMean()].record(point.profitUSD)
                }
            }
        }
        var lastBucketIndex: [String: Int] = [:]
        var runBySeries: [String: Int] = [:]
        var result: [ActivityChartValue] = []

        for (bucketIndex, bucket) in buckets.enumerated() {
            for model in aggregates[bucketIndex].keys.sorted() {
                guard let mean = aggregates[bucketIndex][model] else { continue }
                let amount = mean.sum / Double(mean.count)
                guard amount.isFinite else { continue }
                let run: Int
                if let previous = lastBucketIndex[model] {
                    run = runBySeries[model, default: 0] + (previous == bucketIndex - 1 ? 0 : 1)
                } else {
                    run = 0
                }
                runBySeries[model] = run
                lastBucketIndex[model] = bucketIndex
                result.append(ActivityChartValue(
                    interval: bucket.interval,
                    series: model,
                    amountUSD: amount,
                    run: run
                ))
            }
        }
        return result
    }

    private struct ProfitMean {
        var sum = 0.0
        var count = 0

        mutating func record(_ amount: Double) {
            // Visit records in original order: floating-point addition and
            // duplicate weighting must match the previous aggregation exactly.
            sum += amount
            count += 1
        }
    }

    static func profitBounds(values: [ActivityChartValue], stacked: Bool) -> (minimum: Double, maximum: Double) {
        guard stacked else {
            return (values.map(\.amountUSD).min() ?? 0, values.map(\.amountUSD).max() ?? 0)
        }
        let groups = Dictionary(grouping: values, by: \.interval.start).values
        let minimum = groups.map { $0.reduce(0) { $0 + min(0, $1.amountUSD) } }.min() ?? 0
        let maximum = groups.map { $0.reduce(0) { $0 + max(0, $1.amountUSD) } }.max() ?? 0
        return (minimum, maximum)
    }

    static func profitSegments(values: [ActivityChartValue]) -> [ActivityChartSegment] {
        let groups = Dictionary(grouping: values, by: \.interval.start)
        var result: [ActivityChartSegment] = []
        for start in groups.keys.sorted() {
            guard let intervalValues = groups[start]?.sorted(by: { $0.series < $1.series }),
                  let interval = intervalValues.first?.interval else { continue }
            var positive = 0.0
            var negative = 0.0
            for value in intervalValues where value.amountUSD != 0 {
                let beginning = value.amountUSD > 0 ? positive : negative
                let end = beginning + value.amountUSD
                result.append(ActivityChartSegment(
                    interval: interval,
                    series: value.series,
                    startUSD: beginning,
                    endUSD: end
                ))
                if value.amountUSD > 0 { positive = end } else { negative = end }
            }
        }
        return result
    }

    static func segments(
        buckets: [ActivityBucket],
        models: [String],
        modelWorkByBucket: [Date: [String: Int64]],
        selectedModel: String?,
        includeRewards: Bool = true
    ) -> [ActivityChartSegment] {
        segments(values: values(buckets: buckets, models: models, modelWorkByBucket: modelWorkByBucket,
                                selectedModel: selectedModel, includeRewards: includeRewards))
    }

    /// Stack the already resolved observations. Every chart style shares the
    /// same attribution, zero and fallback rules; input order keeps series stable.
    static func segments(values: [ActivityChartValue]) -> [ActivityChartSegment] {
        var result: [ActivityChartSegment] = []
        var cursors: [Date: (positive: Double, negative: Double)] = [:]
        for value in values where value.amountUSD.isFinite && value.amountUSD != 0 {
            var cursor = cursors[value.interval.start] ?? (positive: 0, negative: 0)
            let beginning = value.amountUSD > 0 ? cursor.positive : cursor.negative
            let end = beginning + value.amountUSD
            result.append(ActivityChartSegment(interval: value.interval, series: value.series,
                startUSD: beginning, endUSD: end))
            if value.amountUSD > 0 { cursor.positive = end } else { cursor.negative = end }
            cursors[value.interval.start] = cursor
        }
        return result
    }
}

struct ActivityChartYAxis: Equatable {
    let lowerBound: Double
    let upperBound: Double
    let values: [Double]
    let fractionDigits: Int
}

enum ActivityChartAxis {
    static func xValues(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) -> [Date] {
        guard range.duration > 0 else { return [range.start] }
        let component: Calendar.Component = unit == .hour ? .hour : .day
        let intervalCount: Double
        if unit == .hour {
            intervalCount = range.duration / 3_600
        } else {
            intervalCount = Double(max(1, calendar.dateComponents([.day], from: range.start, to: range.end).day ?? 1))
        }
        let stride = unit == .hour ? 6 : max(1, Int(ceil(intervalCount / 6)))
        guard let containingInterval = calendar.dateInterval(of: component, for: range.start) else {
            return [range.start, range.end]
        }
        var cursor = containingInterval.start
        if cursor < range.start {
            guard let next = calendar.date(byAdding: component, value: stride, to: cursor) else {
                return [range.start, range.end]
            }
            cursor = next
        }

        var values: [Date] = []
        while cursor <= range.end, values.count < 8 {
            if cursor >= range.start { values.append(cursor) }
            guard let next = calendar.date(byAdding: component, value: stride, to: cursor), next > cursor else { break }
            cursor = next
        }
        if values.last != range.end { values.append(range.end) }
        return values
    }

    static func yAxis(maximum: Double) -> ActivityChartYAxis {
        let safeMaximum = maximum.isFinite ? max(0, maximum) : 0
        let scale = numericScale(maximum: safeMaximum)
        return ActivityChartYAxis(
            lowerBound: 0,
            upperBound: max(safeMaximum, tick(scale.upperBound, step: scale.step)),
            values: (0...scale.count).map { tick(Double($0) * scale.step, step: scale.step) },
            fractionDigits: fractionDigits(step: scale.step)
        )
    }

    static func signedYAxis(minimum: Double, maximum: Double) -> ActivityChartYAxis {
        let safeMinimum = minimum.isFinite ? minimum : 0
        let safeMaximum = maximum.isFinite ? maximum : 0
        let magnitude = max(abs(safeMinimum), abs(safeMaximum))
        // Keep the numeric step: display rounding can make adjacent tiny ticks
        // identical, and subtracting those ticks would produce a zero divisor.
        let scale = numericScale(maximum: magnitude)
        let roundedBound = tick(scale.upperBound, step: scale.step)
        let upperBound = max(magnitude, roundedBound)
        return ActivityChartYAxis(
            lowerBound: -upperBound,
            upperBound: upperBound,
            values: (-scale.count...scale.count).map { tick(Double($0) * scale.step, step: scale.step) },
            fractionDigits: fractionDigits(step: scale.step)
        )
    }

    private static func numericScale(maximum: Double) -> (step: Double, count: Int, upperBound: Double) {
        guard maximum > 0 else { return (0.25, 4, 1) }
        let rawStep = maximum / 4
        let magnitude = rawStep > 0 ? pow(10, floor(log10(rawStep))) : 0
        // Subnormal values may underflow either the division or power of ten.
        guard magnitude > 0, magnitude.isFinite else { return (maximum, 1, maximum) }
        let normalized = rawStep / magnitude
        let preferred: Double = normalized <= 1 ? 1 : normalized <= 2 ? 2 : normalized <= 2.5 ? 2.5 : normalized <= 5 ? 5 : 10
        let step = preferred * magnitude
        let count = max(1, Int(ceil(maximum / step)))
        let upperBound = Double(count) * step
        // Rounding up near Double's limit can overflow even for finite input.
        guard upperBound.isFinite else { return (rawStep, 4, maximum) }
        return (step, count, upperBound)
    }

    private static func tick(_ value: Double, step: Double) -> Double {
        let scaled = value * 1_000_000
        // Preserve the existing micro-dollar normalization for ordinary axes,
        // while keeping fractional-micro-dollar ticks and large values intact.
        guard step >= 0.000001, scaled.isFinite else { return value }
        return scaled.rounded() / 1_000_000
    }

    private static func fractionDigits(step: Double) -> Int {
        guard step < 0.0001 else { return step < 0.01 ? 4 : 2 }
        return max(4, Int(min(12, ceil(-log10(step)) + 1)))
    }
}
