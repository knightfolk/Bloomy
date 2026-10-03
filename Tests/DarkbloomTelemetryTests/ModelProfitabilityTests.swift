import Foundation
import Testing
@testable import DarkbloomTelemetry

struct ModelProfitabilityTests {
    @Test("allocates covered whole-Mac electricity evenly across earning models per hour")
    func sharesHourlyDeviceCostAcrossModels() throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let activity = [
            ModelActivityBucket(interval: hour, model: "google/gemma", workMicroUSD: 300_000),
            ModelActivityBucket(interval: hour, model: "qwen/qwen", workMicroUSD: 500_000),
        ]

        let points = ModelProfitability.hourlyProfits(activity: activity, energy: powerIntervals(for: hour))

        #expect(points.map(\.model) == ["google/gemma", "qwen/qwen"])
        #expect(abs(points[0].allocatedElectricityUSD - 0.10) < 0.000_000_001)
        #expect(abs(points[0].profitUSD - 0.20) < 0.000_000_001)
        #expect(abs(points[1].profitUSD - 0.40) < 0.000_000_001)
        #expect(points.allSatisfy { $0.estimated })
    }

    @Test("signed corrections are aggregated and share hourly electricity across recorded models")
    func preservesSignedHourlyWork() throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let activity = [
            ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: 500_000),
            ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: -200_000),
            ModelActivityBucket(interval: hour, model: "qwen", workMicroUSD: -100_000),
        ]

        let points = ModelProfitability.hourlyProfits(activity: activity, energy: powerIntervals(for: hour))

        #expect(points.map(\.model) == ["gemma", "qwen"])
        let gemma = try #require(points.first { $0.model == "gemma" })
        let qwen = try #require(points.first { $0.model == "qwen" })
        #expect(abs(gemma.grossUSD - 0.3) < 0.000_000_001)
        #expect(abs(qwen.grossUSD - (-0.1)) < 0.000_000_001)
        #expect(points.allSatisfy { abs($0.allocatedElectricityUSD - 0.1) < 0.000_000_001 })
        #expect(abs(gemma.profitUSD - 0.2) < 0.000_000_001)
        #expect(abs(qwen.profitUSD - (-0.2)) < 0.000_000_001)
    }

    @Test("a negative-only recorded model retains its loss and whole-hour electricity cost")
    func preservesNegativeOnlyHourlyWork() throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let activity = [ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: -50_000)]

        let points = ModelProfitability.hourlyProfits(activity: activity, energy: powerIntervals(for: hour))
        let point = try #require(points.first)
        let average = try #require(ModelProfitability.averages(points).first)

        #expect(points.count == 1)
        #expect(point.grossUSD == -0.05)
        #expect(abs(point.allocatedElectricityUSD - 0.2) < 0.000_000_001)
        #expect(abs(point.profitUSD - (-0.25)) < 0.000_000_001)
        #expect(average.grossUSDPerHour == -0.05)
        #expect(abs(average.profitUSDPerHour - (-0.25)) < 0.000_000_001)
        #expect(average.coveredHours == 1)
    }

    @Test("recorded zero work participates while missing, unnamed and partial-hour work stays excluded")
    func preservesZeroAndUnknownHourlyDistinction() throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let missingHour = DateInterval(start: hour.end, duration: 3_600)
        let activity = [
            ModelActivityBucket(interval: hour, model: "zero", workMicroUSD: 0),
            ModelActivityBucket(interval: hour, model: "earning", workMicroUSD: 200_000),
            ModelActivityBucket(interval: hour, model: "", workMicroUSD: -100_000),
            ModelActivityBucket(interval: DateInterval(start: hour.start, duration: 1_800),
                                model: "partial", workMicroUSD: -100_000),
        ]

        let points = ModelProfitability.hourlyProfits(
            activity: activity, energy: powerIntervals(for: hour) + powerIntervals(for: missingHour)
        )
        let zero = try #require(points.first { $0.model == "zero" })

        #expect(points.map(\.model) == ["earning", "zero"])
        #expect(points.allSatisfy { $0.interval == hour })
        #expect(zero.grossUSD == 0)
        #expect(abs(zero.profitUSD - (-0.1)) < 0.000_000_001)
        #expect(ModelProfitability.hourlyProfits(activity: [], energy: powerIntervals(for: hour)).isEmpty)
    }

    @Test("signed hourly aggregation fails closed on overflow or underflow", arguments: [Int64.min, Int64.max])
    func rejectsSignedAggregationOverflow(bound: Int64) {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let activity = [
            ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: bound),
            ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: bound < 0 ? -1 : 1),
        ]

        #expect(ModelProfitability.hourlyProfits(activity: activity, energy: powerIntervals(for: hour)).isEmpty)
    }

    @Test("serving averages retain signed recorded hours with fresh activity and measured power")
    func preservesSignedServingWork() throws {
        let first = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let second = DateInterval(start: first.end, duration: 3_600)
        let activity = [
            ModelActivityBucket(interval: first, model: "gemma", workMicroUSD: 100_000),
            ModelActivityBucket(interval: second, model: "gemma", workMicroUSD: -300_000),
        ]

        let average = try #require(ModelProfitability.servingAverages(
            activity: activity, energy: servingPowerIntervals(for: first) + servingPowerIntervals(for: second)
        ).first)

        #expect(average.coveredEarningHours == 2)
        #expect(average.activeHours == 1)
        #expect(average.activePowerSamples == 360)
        #expect(average.idlePowerSamples == 360)
        #expect(abs(average.grossUSDPerActiveHour - (-0.2)) < 0.000_000_001)
        #expect(abs(try #require(average.incrementalElectricityUSDPerActiveHour) - 0.01) < 0.000_000_001)
        #expect(abs(try #require(average.profitUSDPerActiveHour) - (-0.21)) < 0.000_000_001)
    }

    @Test("negative-only and explicit zero serving rows stay recorded", arguments: [Int64(-100_000), Int64(0)])
    func preservesNonpositiveServingWork(amount: Int64) throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let activity = [ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: amount)]

        let average = try #require(ModelProfitability.servingAverages(
            activity: activity, energy: servingPowerIntervals(for: hour)
        ).first)

        let expectedGross = Double(amount) / 1_000_000 / 0.5
        #expect(average.coveredEarningHours == 1)
        #expect(average.activeHours == 0.5)
        #expect(abs(average.grossUSDPerActiveHour - expectedGross) < 0.000_000_001)
        #expect(abs(try #require(average.profitUSDPerActiveHour) - (expectedGross - 0.01)) < 0.000_000_001)
    }

    @Test("signed work does not bypass serving power coverage, model activity or idle-baseline requirements")
    func preservesServingEvidenceRequirements() throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 3_600), duration: 3_600)
        let activity = [ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: -100_000)]
        var gapped = servingPowerIntervals(for: hour)
        gapped.remove(at: 180)

        #expect(ModelProfitability.servingAverages(activity: activity, energy: gapped).isEmpty)
        #expect(ModelProfitability.servingAverages(activity: activity, energy: powerIntervals(for: hour)).isEmpty)
        #expect(ModelProfitability.servingAverages(activity: activity, energy: servingPowerIntervals(for: hour, model: "other")).isEmpty)
        #expect(ModelProfitability.servingAverages(activity: [], energy: servingPowerIntervals(for: hour)).isEmpty)
        let partial = [ModelActivityBucket(interval: DateInterval(start: hour.start, duration: 1_800),
                                           model: "gemma", workMicroUSD: -100_000)]
        #expect(ModelProfitability.servingAverages(activity: partial, energy: servingPowerIntervals(for: hour)).isEmpty)

        let withoutIdle = try #require(ModelProfitability.servingAverages(
            activity: activity, energy: servingPowerIntervals(for: hour, includeIdle: false)
        ).first)
        #expect(abs(withoutIdle.grossUSDPerActiveHour - (-0.1)) < 0.000_000_001)
        #expect(withoutIdle.incrementalElectricityUSDPerActiveHour == nil)
        #expect(withoutIdle.profitUSDPerActiveHour == nil)
    }

    @Test("does not estimate model profit for an hour with an energy coverage gap")
    func omitsUncoveredHour() throws {
        let hour = DateInterval(start: Date(timeIntervalSince1970: 7_200), duration: 3_600)
        var intervals = powerIntervals(for: hour)
        intervals.remove(at: 180)
        let activity = [ModelActivityBucket(interval: hour, model: "gemma", workMicroUSD: 100_000)]

        #expect(ModelProfitability.hourlyProfits(activity: activity, energy: intervals).isEmpty)
    }

    @Test("averages positive and negative net returns over covered model-hours")
    func averagesNetProfitPerModelHour() throws {
        let first = DateInterval(start: Date(timeIntervalSince1970: 10_800), duration: 3_600)
        let second = DateInterval(start: Date(timeIntervalSince1970: 14_400), duration: 3_600)
        let activity = [
            ModelActivityBucket(interval: first, model: "gemma", workMicroUSD: 300_000),
            ModelActivityBucket(interval: second, model: "gemma", workMicroUSD: 50_000),
        ]
        let points = ModelProfitability.hourlyProfits(
            activity: activity,
            energy: powerIntervals(for: first) + powerIntervals(for: second)
        )

        let average = try #require(ModelProfitability.averages(points).first)
        #expect(average.model == "gemma")
        #expect(average.coveredHours == 2)
        #expect(abs(average.profitUSDPerHour - (-0.025)) < 0.000_000_001)
    }
}

private func servingPowerIntervals(
    for hour: DateInterval, model: String = "gemma", includeIdle: Bool = true
) -> [EnergyInterval] {
    (0..<360).map { index in
        let start = hour.start.addingTimeInterval(Double(index * 10))
        let active = !includeIdle || index < 180
        let watts = active ? 100.0 : 50.0
        return EnergyInterval(
            start: start,
            end: start.addingTimeInterval(10),
            kWh: watts / 1_000 * 10 / 3_600,
            usdPerKWh: 0.2,
            source: "fixture-adapter",
            estimated: true,
            activeModelID: model,
            inferenceActive: active
        )
    }
}

private func powerIntervals(for hour: DateInterval) -> [EnergyInterval] {
    (0..<360).map { index in
        let start = hour.start.addingTimeInterval(Double(index * 10))
        return EnergyInterval(
            start: start,
            end: start.addingTimeInterval(10),
            kWh: 1.0 / 360.0,
            usdPerKWh: 0.2,
            source: "fixture-adapter",
            estimated: true
        )
    }
}
