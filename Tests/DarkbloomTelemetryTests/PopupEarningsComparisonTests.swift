import Testing
@testable import DarkbloomMonitor

@Suite("Popup earnings bars compare observed amounts without inventing targets")
struct PopupEarningsComparisonTests {
    @Test func commonScale() {
        let comparison = PopupEarningsComparison(today: 2, week: 8)
        #expect(comparison.maximum == 8)
        #expect(comparison.fraction(comparison.today) == 0.25)
        #expect(comparison.fraction(comparison.week) == 1)
    }

    @Test func zeroAndUnknownStayDistinct() {
        let comparison = PopupEarningsComparison(today: 0, week: nil)
        #expect(comparison.fraction(comparison.today) == 0)
        #expect(comparison.fraction(comparison.week) == nil)
        #expect(PopupEarningsComparison(today: nil, week: nil).maximum == 0)
    }

    @Test func tinyAmountsAndPartialPeriods() {
        let comparison = PopupEarningsComparison(today: 0.000002, week: 0.000001)
        #expect(comparison.fraction(comparison.today) == 1)
        #expect(comparison.fraction(comparison.week) == 0.5)
    }

    @Test(arguments: [Double.nan, .infinity, -.infinity, -1])
    func invalidAmount(amount: Double) {
        let comparison = PopupEarningsComparison(today: amount, week: 1)
        #expect(comparison.today == nil)
        #expect(comparison.maximum == 1)
        #expect(comparison.fraction(amount) == nil)
    }
}
