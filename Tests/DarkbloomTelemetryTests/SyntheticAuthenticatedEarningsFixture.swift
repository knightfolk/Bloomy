import Foundation
@testable import DarkbloomTelemetry

/// Explicit opt-in for inert financial fixtures. These values authenticate only
/// test data and never supply compatibility authorization to production clients.
protocol SyntheticAuthenticatedEarningsFixture: AccountEarningsFetching {}

extension SyntheticAuthenticatedEarningsFixture {
    var syntheticFinancialContext: AccountEarningsContext {
        AccountEarningsContext(accountScope: "test-only-synthetic:\(String(reflecting: Self.self))",
            generation: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1)))
    }

    func financialSessionState() async -> AccountEarningsSessionState {
        AccountEarningsSessionState(context: syntheticFinancialContext, ledgerReady: true,
            revision: syntheticFinancialContext.generation)
    }

    func financialSessionChanges() async -> AsyncStream<AccountEarningsSessionState> {
        let state = await financialSessionState()
        return AsyncStream { continuation in
            continuation.yield(state)
            continuation.finish()
        }
    }

    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? {
        try await validateFinancialContext(context)
        let buckets = try await activity(in: range, unit: unit, calendar: calendar) ?? []
        let modelActivity = try await activityByModel(in: range, unit: unit, calendar: calendar) ?? []
        let hourlyActivity: [ModelActivityBucket]
        if unit == .hour { hourlyActivity = modelActivity }
        else { hourlyActivity = try await activityByModel(in: range, unit: .hour, calendar: calendar) ?? [] }
        let fixtureModels = try await activityModels(in: range)
        let models = Array(Set(fixtureModels + modelActivity.map(\.model))).sorted()
        var modelBuckets: [ModelAccountCreditBucket] = []
        for fixtureModel in models {
            if let values = try await self.modelActivity(in: range, unit: unit, calendar: calendar, model: fixtureModel) {
                modelBuckets += values.compactMap { bucket in
                    bucket.totals.map { ModelAccountCreditBucket(interval: bucket.interval, model: fixtureModel,
                        totals: SyntheticAccountCreditReport.totals($0)) }
                }
            } else {
                modelBuckets += modelActivity.filter { $0.model == fixtureModel }.map {
                    ModelAccountCreditBucket(interval: $0.interval, model: $0.model,
                        totals: .init(workMicroUSD: $0.workMicroUSD, rewardMicroUSD: 0,
                            workCreditCount: 1, rewardCreditCount: 0, promptTokens: 0, completionTokens: 0))
                }
            }
        }
        let averages = try await modelHourlyEarningsAverages(in: range) ?? []
        try await validateFinancialContext(context)
        return SyntheticAccountCreditReport.make(context: context, providerID: providerID, model: model,
            range: range, buckets: buckets, models: models, modelActivity: modelActivity,
            modelBuckets: modelBuckets, hourlyEarningsAverages: averages, modelHourlyActivity: hourlyActivity)
    }
}

enum SyntheticAccountCreditReport {
    static func totals(_ value: ActivityTotals) -> AccountCreditTotals {
        .init(workMicroUSD: value.workMicroUSD, rewardMicroUSD: value.rewardMicroUSD,
            workCreditCount: value.jobs, rewardCreditCount: value.rewardMicroUSD == 0 ? 0 : 1,
            promptTokens: value.promptTokens, completionTokens: value.completionTokens)
    }

    static func make(context: AccountEarningsContext, providerID: String? = nil, model: String? = nil,
        range: DateInterval, buckets: [ActivityBucket] = [], models: [String] = [],
        modelActivity: [ModelActivityBucket] = [], modelBuckets: [ModelAccountCreditBucket] = [],
        hourlyEarningsAverages: [ModelHourlyEarningsAverage] = [],
        modelHourlyActivity: [ModelActivityBucket] = []) -> AccountCreditReport {
        let creditBuckets = buckets.map {
            AccountCreditBucket(interval: $0.interval, totals: $0.totals.map(totals), coverage: $0.coverage)
        }
        let recorded = creditBuckets.compactMap(\.totals)
        let sum: AccountCreditTotals? = recorded.isEmpty ? nil : .init(
            workMicroUSD: recorded.reduce(0) { $0 + $1.workMicroUSD },
            rewardMicroUSD: recorded.reduce(0) { $0 + $1.rewardMicroUSD },
            workCreditCount: recorded.reduce(0) { $0 + $1.workCreditCount },
            rewardCreditCount: recorded.reduce(0) { $0 + $1.rewardCreditCount },
            promptTokens: recorded.reduce(0) { $0 + $1.promptTokens },
            completionTokens: recorded.reduce(0) { $0 + $1.completionTokens })
        return AccountCreditReport(accountScope: context.accountScope, providerID: providerID, model: model,
            range: range, observation: nil, reconciliation: .unavailable, lifetimeBalanceChange: nil,
            totals: sum, buckets: creditBuckets, models: models, modelActivity: modelActivity,
            modelHourlyActivity: modelHourlyActivity, modelBuckets: modelBuckets, hourlyEarningsAverages: hourlyEarningsAverages)
    }
}
