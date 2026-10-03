import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Activity chart model colors")
struct ActivityChartDataTests {
    @Test("original accessibility amounts tolerate repeated custom-client identities")
    func originalAmountsDoNotTrap() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 0), duration: 3_600)
        let first = ActivityChartValue(interval: interval, series: "Qwen", amountUSD: 0.1, run: 0)
        let correction = ActivityChartValue(interval: interval, series: "Qwen", amountUSD: -0.000001, run: 0)
        let other = ActivityChartValue(interval: interval, series: "Gemma", amountUSD: 0.25, run: 0)
        let amounts = ActivityChartData.originalAmounts(values: [first, other, correction])
        #expect(amounts.count == 2)
        #expect(amounts[first.id] == -0.000001)
        #expect(amounts[other.id] == 0.25)
        #expect(ActivityChartData.originalAmounts(values: []).isEmpty)
    }
    @Test("table amounts distinguish recorded zero, unknown and micro-dollar values without floating-point loss")
    func exactTableAmounts() {
        let locale = Locale(identifier: "en_US")
        #expect(ActivityAmountPresentation.tableAmount(nil, locale: locale) == "—")
        #expect(ActivityAmountPresentation.tableAmount(0, locale: locale) == "0.0000")
        #expect(ActivityAmountPresentation.tableAmount(1, locale: locale) == "0.000001")
        #expect(ActivityAmountPresentation.tableAmount(3, locale: locale) == "0.000003")
        #expect(ActivityAmountPresentation.tableAmount(-1, locale: locale) == "-0.000001")
        #expect(ActivityAmountPresentation.tableAmount(150_000, locale: locale) == "0.1500")
        #expect(ActivityAmountPresentation.tableAmount(Int64.max, locale: locale) == "9,223,372,036,854.775807")
    }

    @Test("hourly currency keeps ordinary values compact and tiny signed estimates distinct from zero")
    func exactHourlyAmounts() {
        let locale = Locale(identifier: "en_US")
        let zero = ActivityAmountPresentation.hourlyAmount(0, locale: locale)
        #expect(zero == "$0.0000")
        #expect(ActivityAmountPresentation.hourlyAmount(-0.0, locale: locale) == zero)
        #expect(ActivityAmountPresentation.hourlyAmount(0.15, locale: locale) == "$0.1500")
        #expect(ActivityAmountPresentation.hourlyAmount(0.000001, locale: locale) == "$0.000001")
        #expect(ActivityAmountPresentation.hourlyAmount(-0.00000025, locale: locale) == "-$0.00000025")
        for amount in [0.000001, 0.00000025, 0.00000001, 1e-12] {
            let positive = ActivityAmountPresentation.hourlyAmount(amount, locale: locale)
            let negative = ActivityAmountPresentation.hourlyAmount(-amount, locale: locale)
            #expect(positive != zero)
            #expect(negative != zero && negative.contains("-"))
            #expect(positive != negative)
        }
        #expect(ActivityAmountPresentation.hourlyAmount(0.000001, locale: Locale(identifier: "de_DE")).contains("0,000001"))
        for amount in [Double.nan, .infinity, -.infinity] {
            #expect(ActivityAmountPresentation.hourlyAmount(amount, locale: locale) == "—")
        }
        for amount in [1e-13, -2.5e-20, Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude] {
            let label = ActivityAmountPresentation.hourlyAmount(amount, locale: locale)
            #expect(label.hasSuffix(" USD"))
            #expect(Double(String(label.dropLast(4))) == amount)
        }
    }

    @Test("zero markers represent recorded zero intervals rather than gaps or cancelling signed values")
    func recordedZeroMarkers() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let second = DateInterval(start: first.end, duration: 3_600)
        let third = DateInterval(start: second.end, duration: 3_600)
        let values = [
            ActivityChartValue(interval: first, series: "a", amountUSD: 0, run: 0),
            ActivityChartValue(interval: first, series: "b", amountUSD: 0, run: 0),
            ActivityChartValue(interval: second, series: "a", amountUSD: 1, run: 0),
            ActivityChartValue(interval: second, series: "b", amountUSD: -1, run: 0),
            ActivityChartValue(interval: third, series: "a", amountUSD: 0.000001, run: 0)
        ]
        #expect(ActivityChartData.recordedZeroValues(values).map(\.interval) == [first])
        #expect(ActivityChartData.recordedZeroValues([]).isEmpty)
    }

    @Test("gross cancellation preserves signed model observations rather than a recorded zero")
    func signedGrossCancellation() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(buckets: [bucket(interval, work: 0)],
            models: ["positive", "negative", "idle"],
            modelWorkByBucket: [interval.start: ["positive": 100_000, "negative": -100_000]],
            selectedModel: nil)
        #expect(values.map(\.series) == ["positive", "negative", "idle", "Base rewards"])
        #expect(values.map(\.amountUSD) == [0.1, -0.1, 0, 0])
        #expect(ActivityChartData.recordedZeroValues(values).isEmpty)
        let segments = ActivityChartData.segments(values: values)
        #expect(segments.map(\.series) == ["positive", "negative"])
        #expect(segments.map(\.startUSD) == [0, 0])
        #expect(segments.map(\.endUSD) == [0.1, -0.1])
        let bounds = ActivityChartData.profitBounds(values: values, stacked: true)
        #expect(bounds.minimum == -0.1 && bounds.maximum == 0.1)
        #expect(ActivityChartData.maximumUSD(values: values, stacked: true) == 0.1)
    }

    @Test("negative model work and rewards stack below zero in original series order without aggregate duplication")
    func signedGrossStacks() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(buckets: [bucket(interval, work: -300_000, reward: -50_000)],
            models: ["qwen", "gemma"],
            modelWorkByBucket: [interval.start: ["qwen": -100_000, "gemma": -200_000]],
            selectedModel: nil)
        #expect(values.map(\.series) == ["qwen", "gemma", "Base rewards"])
        #expect(values.map(\.amountUSD) == [-0.1, -0.2, -0.05])
        let segments = ActivityChartData.segments(values: values)
        #expect(segments.map(\.series) == values.map(\.series))
        for (actual, expected) in zip(segments.map(\.startUSD), [0, -0.1, -0.3]) {
            #expect(abs(actual - expected) < 1e-12)
        }
        for (actual, expected) in zip(segments.map(\.endUSD), [-0.1, -0.3, -0.35]) {
            #expect(abs(actual - expected) < 1e-12)
        }
        let bounds = ActivityChartData.profitBounds(values: values, stacked: true)
        #expect(abs(bounds.minimum + 0.35) < 1e-12 && bounds.maximum == 0)
    }

    @Test("negative aggregate fallback retains selected model identity and excludes rewards")
    func negativeSelectedFallback() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let total = bucket(interval, work: -1, reward: -2)
        let values = ActivityChartData.values(buckets: [total], models: [],
            modelWorkByBucket: [:], selectedModel: "retained")
        #expect(values.map(\.series) == ["retained"])
        #expect(values.map(\.amountUSD) == [-0.000001])
        #expect(ActivityChartData.segments(values: values).first?.endUSD == -0.000001)
    }

    @Test("negative aggregate work remains visible with missing per-model history")
    func negativeAggregateFallback() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(buckets: [bucket(interval, work: -125_000, reward: -5_000)],
            models: ["gemma"], modelWorkByBucket: [:], selectedModel: nil)
        #expect(values.map(\.series) == ["Work", "Base rewards"])
        #expect(values.map(\.amountUSD) == [-0.125, -0.005])
    }

    @Test("resolved gross zeros stay distinct from signed cancellation and unknown buckets")
    func resolvedGrossZeros() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let cancellation = DateInterval(start: first.end, duration: 3_600)
        let missing = DateInterval(start: cancellation.end, duration: 3_600)
        let values = ActivityChartData.values(buckets: [bucket(first, work: 0), bucket(cancellation, work: 0),
            ActivityBucket(interval: missing, totals: nil, coverage: .unavailable)],
            models: ["a", "b"], modelWorkByBucket: [cancellation.start: ["a": -1, "b": 1]],
            selectedModel: nil)
        #expect(ActivityChartData.recordedZeroValues(values).map(\.interval) == [first])
        #expect(values.filter { $0.interval == cancellation }.map(\.amountUSD) == [-0.000001, 0.000001, 0])
        #expect(!values.contains { $0.interval == missing })
    }

    @Test("chart values keep model earnings separate until the selected layout is applied")
    func independentChartValues() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(
            buckets: [bucket(interval, work: 300_000, reward: 10_000)],
            models: ["gemma", "qwen"],
            modelWorkByBucket: [interval.start: ["gemma": 100_000, "qwen": 200_000]],
            selectedModel: nil
        )

        #expect(values.map(\.series) == ["gemma", "qwen", "Base rewards"])
        #expect(values.map(\.amountUSD) == [0.1, 0.2, 0.01])
        #expect(values.map(\.run) == [0, 0, 0])
    }

    @Test("base rewards can be hidden independently from the model series")
    func hidesRewards() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(
            buckets: [bucket(interval, work: 100_000, reward: 20_000)],
            models: ["gemma"],
            modelWorkByBucket: [interval.start: ["gemma": 100_000]],
            selectedModel: nil,
            includeRewards: false
        )

        #expect(values.map(\.series) == ["gemma"])
        #expect(values.map(\.amountUSD) == [0.1])
    }

    @Test("selected model chart values exclude other models and account rewards")
    func selectedModelValues() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(
            buckets: [bucket(interval, work: 200_000, reward: 10_000)],
            models: ["gemma", "qwen"],
            modelWorkByBucket: [interval.start: ["gemma": 100_000, "qwen": 200_000]],
            selectedModel: "qwen"
        )

        #expect(values.map(\.series) == ["qwen"])
        #expect(values.map(\.amountUSD) == [0.2])
    }

    @Test("chart color scale stays anchored to the complete model list while filtering")
    func modelFilterKeepsStableColorScale() {
        let models = ["google/gemma-4-26b", "qwen/qwen3.8-27b"]
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let filteredValues = ActivityChartData.values(
            buckets: [bucket(interval, work: 200_000)],
            models: models,
            modelWorkByBucket: [interval.start: [models[0]: 100_000, models[1]: 200_000]],
            selectedModel: models[1]
        )

        #expect(filteredValues.map(\.series) == [models[1]])
        #expect(ActivityChartData.colorScaleDomain(models: models) == models + ["Work", "Base rewards"])
    }

    @Test("company palettes keep sibling models visually related and readable")
    func companyPaletteGroups() {
        let gemma = ActivityChartPalette.components(for: "google/gemma-4-26b")
        let anotherGemma = ActivityChartPalette.components(for: "google/gemma-4-12b")
        let qwen = ActivityChartPalette.components(for: "qwen/qwen3.8-27b")

        #expect(gemma == ActivityChartPalette.components(for: "google/gemma-4-26b"))
        #expect(abs(gemma.hue - anotherGemma.hue) < 0.04)
        #expect(abs(gemma.hue - qwen.hue) > 0.20)
        #expect(gemma.brightness >= 0.76)
    }

    @Test("chart choices cover bars, lines, and area with both bar arrangements")
    func availableChartChoices() {
        #expect(ActivityChartStyle.allCases.map(\.rawValue) == ["Bars", "Lines", "Area"])
        #expect(ActivityBarArrangement.allCases.map(\.rawValue) == ["Stacked", "Side by side"])
    }

    @Test("profit chart shows signed per-model hourly averages and honors model filtering")
    func profitValuesAverageCoveredModelHours() {
        let start = Date(timeIntervalSince1970: 86_400)
        let day = DateInterval(start: start, duration: 86_400)
        let firstHour = DateInterval(start: start, duration: 3_600)
        let secondHour = DateInterval(start: start.addingTimeInterval(3_600), duration: 3_600)
        let buckets = [bucket(day, work: 500_000)]
        let profits = [
            ModelHourlyProfit(interval: firstHour, model: "gemma", grossUSD: 0.3,
                              allocatedElectricityUSD: 0.1, profitUSD: 0.2, estimated: true),
            ModelHourlyProfit(interval: secondHour, model: "gemma", grossUSD: 0.1,
                              allocatedElectricityUSD: 0.2, profitUSD: -0.1, estimated: true),
            ModelHourlyProfit(interval: firstHour, model: "qwen", grossUSD: 0.5,
                              allocatedElectricityUSD: 0.1, profitUSD: 0.4, estimated: true),
        ]

        let all = ActivityChartData.profitValues(hourly: profits, buckets: buckets, selectedModel: nil)
        let selected = ActivityChartData.profitValues(hourly: profits, buckets: buckets, selectedModel: "gemma")

        #expect(all.map(\.series) == ["gemma", "qwen"])
        #expect(abs(all[0].amountUSD - 0.05) < 0.000_001)
        #expect(all[1].amountUSD == 0.4)
        #expect(selected.map(\.series) == ["gemma"])
        #expect(abs(selected[0].amountUSD - 0.05) < 0.000_001)
    }

    @Test("profit axis is symmetric around zero for positive and negative values")
    func signedProfitAxis() {
        let axis = ActivityChartAxis.signedYAxis(minimum: -0.13, maximum: 0.07)

        #expect(axis.lowerBound == -0.15)
        #expect(axis.upperBound == 0.15)
        #expect(axis.values == [-0.15, -0.1, -0.05, 0, 0.05, 0.1, 0.15])
    }

    @Test("tiny positive, negative, and mixed profit retains distinct finite ticks", arguments: [0.000004, 0.000001, 0.00000025, 0.00000001])
    func tinySignedProfitAxis(magnitude: Double) {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        for amounts in [[magnitude], [-magnitude], [-magnitude, magnitude / 2]] {
            let values = amounts.enumerated().map { index, amount in
                ActivityChartValue(interval: interval, series: "model-\(index)", amountUSD: amount, run: 0)
            }
            for stacked in [false, true] {
                let bounds = ActivityChartData.profitBounds(values: values, stacked: stacked)
                let axis = ActivityChartAxis.signedYAxis(minimum: bounds.minimum, maximum: bounds.maximum)
                expectUsableAxis(axis, minimum: bounds.minimum, maximum: bounds.maximum)
                #expect(axis.lowerBound == -axis.upperBound)
                // Formatting must not turn a tiny but nonzero range into a
                // chart whose currency tick labels all claim to be zero.
                let labels = axis.values.map {
                    $0.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US_POSIX"))
                        .precision(.fractionLength(axis.fractionDigits)))
                }
                #expect(Set(labels).count == axis.values.count)
            }
        }
    }

    @Test("tiny gross earnings retains distinct ticks and a covering positive domain", arguments: [0.000009, 0.000001, 0.00000025, 0.00000001])
    func tinyPositiveAxis(maximum: Double) {
        let axis = ActivityChartAxis.yAxis(maximum: maximum)
        expectUsableAxis(axis, minimum: 0, maximum: maximum)
        #expect(axis.lowerBound == 0)
    }

    @Test("finite numeric extremes cannot underflow the axis step or overflow its bounds", arguments: [Double.leastNonzeroMagnitude, Double.leastNormalMagnitude, Double.greatestFiniteMagnitude])
    func extremeAxis(magnitude: Double) {
        expectUsableAxis(ActivityChartAxis.yAxis(maximum: magnitude), minimum: 0, maximum: magnitude)
        expectUsableAxis(ActivityChartAxis.signedYAxis(minimum: -magnitude, maximum: magnitude),
            minimum: -magnitude, maximum: magnitude)
    }

    @Test("nonfinite and empty axis inputs use finite zero-containing fallback domains")
    func nonfiniteAxis() {
        for value in [Double.nan, .infinity, -.infinity, 0] {
            expectUsableAxis(ActivityChartAxis.yAxis(maximum: value), minimum: 0, maximum: 0)
            expectUsableAxis(ActivityChartAxis.signedYAxis(minimum: value, maximum: value), minimum: 0, maximum: 0)
        }
        expectUsableAxis(ActivityChartAxis.signedYAxis(minimum: .nan, maximum: 0.000001), minimum: 0, maximum: 0.000001)
        expectUsableAxis(ActivityChartAxis.signedYAxis(minimum: -0.000001, maximum: .infinity), minimum: -0.000001, maximum: 0)
    }

    private func expectUsableAxis(_ axis: ActivityChartYAxis, minimum: Double, maximum: Double) {
        #expect(axis.lowerBound.isFinite && axis.upperBound.isFinite)
        #expect(axis.lowerBound < axis.upperBound)
        #expect(axis.lowerBound <= minimum && axis.upperBound >= maximum)
        #expect(axis.values.count >= 2 && axis.values.count <= 13)
        #expect(axis.values.allSatisfy { $0.isFinite && $0 >= axis.lowerBound && $0 <= axis.upperBound })
        #expect(axis.values.contains(0))
        #expect(zip(axis.values, axis.values.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })
    }

    @Test("line and area series break into new runs across unknown buckets")
    func unknownBucketsBreakRuns() {
        let first = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let missing = DateInterval(start: Date(timeIntervalSince1970: 7_200), duration: 3_600)
        let last = DateInterval(start: Date(timeIntervalSince1970: 10_800), duration: 3_600)
        let buckets = [
            bucket(first, work: 200_000),
            ActivityBucket(interval: missing, totals: nil, coverage: .unavailable),
            bucket(last, work: 300_000),
        ]
        let values = ActivityChartData.values(
            buckets: buckets,
            models: ["qwen"],
            modelWorkByBucket: [first.start: ["qwen": 200_000], last.start: ["qwen": 300_000]],
            selectedModel: "qwen"
        )

        #expect(values.map(\.amountUSD) == [0.2, 0.3])
        #expect(values.map(\.run) == [0, 1])
    }

    @Test("stacked charts scale to combined series while side-by-side uses the largest value")
    func chartMaximumMatchesLayout() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let values = ActivityChartData.values(
            buckets: [bucket(interval, work: 300_000, reward: 10_000)],
            models: ["gemma", "qwen"],
            modelWorkByBucket: [interval.start: ["gemma": 100_000, "qwen": 200_000]],
            selectedModel: nil
        )

        let stacked = ActivityChartData.maximumUSD(values: values, stacked: true)
        let sideBySide = ActivityChartData.maximumUSD(values: values, stacked: false)
        #expect(abs(stacked - 0.31) < 0.000_001)
        #expect(abs(sideBySide - 0.2) < 0.000_001)
    }

    @Test("all-model bars are segmented by model and rewards remain separate")
    func segmentsAllModels() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let aggregate = bucket(interval, work: 300_000, reward: 10_000)
        let segments = ActivityChartData.segments(
            buckets: [aggregate],
            models: ["gemma", "qwen"],
            modelWorkByBucket: [interval.start: ["gemma": 100_000, "qwen": 200_000]],
            selectedModel: nil
        )

        #expect(segments.map(\.series) == ["gemma", "qwen", "Base rewards"])
        for (actual, expected) in zip(segments.map(\.startUSD), [0.0, 0.1, 0.3]) {
            #expect(abs(actual - expected) < 0.000_000_001)
        }
        for (actual, expected) in zip(segments.map(\.endUSD), [0.1, 0.3, 0.31]) {
            #expect(abs(actual - expected) < 0.000_000_001)
        }
    }

    @Test("single-model view retains its work-only bar")
    func segmentsSelectedModel() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let aggregate = bucket(interval, work: 200_000, reward: 10_000)

        let segments = ActivityChartData.segments(
            buckets: [aggregate],
            models: ["gemma", "qwen"],
            modelWorkByBucket: [interval.start: ["qwen": 200_000]],
            selectedModel: "qwen"
        )

        #expect(segments.map(\.series) == ["qwen"])
        #expect(segments[0].startUSD == 0)
        #expect(segments[0].endUSD == 0.2)
    }

    @Test("aggregate work remains visible when per-model history is unavailable")
    func fallsBackToAggregateWork() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let aggregate = bucket(interval, work: 125_000, reward: 5_000)

        let segments = ActivityChartData.segments(
            buckets: [aggregate], models: ["gemma"], modelWorkByBucket: [:], selectedModel: nil
        )

        #expect(segments.map(\.series) == ["Work", "Base rewards"])
        #expect(segments[0].endUSD == 0.125)
        #expect(segments[1].startUSD == 0.125)
        #expect(segments[1].endUSD == 0.13)
    }

    @Test("totals-only selected model keeps the same identity in stacked bars and other charts")
    func selectedTotalsKeepIdentity() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let total = bucket(interval, work: 125_000, reward: 5_000)
        let model = "qwen3.8-27b"
        let values = ActivityChartData.values(buckets: [total], models: [model],
            modelWorkByBucket: [:], selectedModel: model)
        let segments = ActivityChartData.segments(buckets: [total], models: [model],
            modelWorkByBucket: [:], selectedModel: model)
        #expect(segments.map(\.series) == values.map(\.series))
        #expect(segments.map(\.series) == [model])
        #expect(segments.first?.startUSD == 0)
        #expect(segments.first?.endUSD == values.first?.amountUSD)
        #expect(!segments.contains { $0.series == "Base rewards" })
    }

    @Test("explicit model zero cannot become a positive fallback bar")
    func selectedRecordedZeroIsNotAbsence() {
        let interval = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let total = bucket(interval, work: 125_000)
        let model = "qwen3.8-27b"
        let attribution = [interval.start: [model: Int64(0)]]
        let values = ActivityChartData.values(buckets: [total], models: [model],
            modelWorkByBucket: attribution, selectedModel: model)
        let segments = ActivityChartData.segments(buckets: [total], models: [model],
            modelWorkByBucket: attribution, selectedModel: model)
        #expect(values.first?.amountUSD == 0)
        #expect(segments.isEmpty)
    }

    @Test("a retained model missing from the period list still has its explicit color domain")
    func retainedModelColorDomain() {
        let models = ["gemma-4-26b", "gpt-oss-20b"]
        let selected = "qwen3.8-27b"
        #expect(ActivityChartData.colorScaleDomain(models: models, selectedModel: selected)
                == models + [selected, "Work", "Base rewards"])
        #expect(ActivityChartData.colorScaleDomain(models: models, selectedModel: models[0])
                == ActivityChartData.colorScaleDomain(models: models))
    }

    @Test("currency axis rounds up to readable increments")
    func currencyAxis() {
        let small = ActivityChartAxis.yAxis(maximum: 0.17)
        #expect(small.upperBound == 0.2)
        for (actual, expected) in zip(small.values, [0.0, 0.05, 0.1, 0.15, 0.2]) {
            #expect(abs(actual - expected) < 0.000_001)
        }
        #expect(small.fractionDigits == 2)

        let large = ActivityChartAxis.yAxis(maximum: 18.2)
        #expect(large.upperBound == 20)
        #expect(large.values == [0, 5, 10, 15, 20])
    }

    @Test("time axis marks five evenly spaced local hour boundaries")
    func hourlyAxis() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let start = Date(timeIntervalSince1970: 0)
        let ticks = ActivityChartAxis.xValues(
            in: DateInterval(start: start, duration: 86_400), unit: .hour, calendar: calendar
        )
        #expect(ticks.map { $0.timeIntervalSince(start) } == [0, 21_600, 43_200, 64_800, 86_400])
    }

    private func bucket(_ interval: DateInterval, work: Int64, reward: Int64 = 0) -> ActivityBucket {
        ActivityBucket(
            interval: interval,
            totals: ActivityTotals(
                workMicroUSD: work,
                rewardMicroUSD: reward,
                jobs: 1,
                promptTokens: 0,
                completionTokens: 0
            ),
            coverage: .recorded
        )
    }
}
