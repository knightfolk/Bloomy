import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model earnings precision")
@MainActor
struct ModelMoneyPrecisionTests {
    private let locale = Locale(identifier: "en_US")

    @Test("model history preserves tiny income losses and known zero")
    func smallAmounts() {
        #expect(ModelCardSummary.money(0.005, locale: locale) == "$0.0050")
        #expect(ModelCardSummary.money(0.025, locale: locale) == "$0.0250")
        #expect(ModelCardSummary.money(-0.005, locale: locale) == "-$0.0050")
        #expect(ModelCardSummary.money(0.000001, locale: locale) == "$0.000001")
        #expect(ModelCardSummary.money(-0.00000025, locale: locale) == "-$0.00000025")
        #expect(ModelCardSummary.money(0, locale: locale) == "$0.0000")
        #expect(ModelCardSummary.money(-0.0, locale: locale) == "$0.0000")
        #expect(ModelCardSummary.money(1.20, locale: locale) == "$1.2000")
    }

    @Test("invalid amounts stay unknown and locale preserves currency and digits")
    func unavailableAndLocale() {
        for value in [Double.nan, .infinity, -.infinity] {
            #expect(ModelCardSummary.money(value, locale: locale) == "—")
        }
        let german = ModelCardSummary.money(0.000001, locale: Locale(identifier: "de_DE"))
        #expect(german.contains("0,000001"))
        #expect(german.contains("$"))
        for value in [Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude] {
            let label = ModelCardSummary.money(value, locale: locale)
            #expect(label == "\(value) USD")
        }
    }

    @Test("tiny daily what-if keeps net digits units and qualification")
    func tinyDailyForecast() {
        let serving = ModelServingProfitAverage(
            model: "tiny-model", grossUSDPerActiveHour: 0.000002,
            incrementalElectricityUSDPerActiveHour: 0.000001,
            profitUSDPerActiveHour: 0.000001, activeHours: 2.5,
            coveredEarningHours: 3, activePowerSamples: 900, idlePowerSamples: 500)
        let forecast = ModelRunForecast.calculate(runPercent: 50, serving: serving, tokenRate: nil)
        let label = ModelCardSummary.whatIfEstimateText(forecast)
        #expect(label.contains(ModelCardSummary.money(0.000012)))
        #expect(label.contains("/day if it served 12 h/day"))
        #expect(label.contains("what-if, not actual"))
    }
}
