import DarkbloomTelemetry
import Foundation

/// The complete report and its interpretation travel together across reads.
struct ActivityReadSnapshot {
    let query: ActivityQuery
    let capturedAt: Date
    let buckets: [ActivityBucket]
    let models: [String]
    let modelWorkByBucket: [Date: [String: Int64]]
    let modelHourlyAverages: [ModelHourlyEarningsAverage]
    let modelHourlyProfits: [ModelHourlyProfit]
    let modelHourlyProfitAverages: [ModelHourlyProfitAverage]
    let tokenRates: [Date: ModelRateBucket]

    /// Calendar storage supplies unknown buckets even when no ledger entries
    /// exist. Recorded zero and signed corrections are still recorded activity.
    var hasRecordedActivity: Bool { buckets.contains { $0.totals != nil } }
    var hasBoundaryUncertainty: Bool { buckets.contains { $0.coverage == .boundaryUncertain } }

    init(query: ActivityQuery, capturedAt: Date = Date(), buckets: [ActivityBucket] = [], models: [String] = [],
         modelWorkByBucket: [Date: [String: Int64]] = [:], modelHourlyAverages: [ModelHourlyEarningsAverage] = [],
         modelHourlyProfits: [ModelHourlyProfit] = [], modelHourlyProfitAverages: [ModelHourlyProfitAverage] = [],
         tokenRates: [Date: ModelRateBucket] = [:]) {
        self.query = query; self.capturedAt = capturedAt; self.buckets = buckets; self.models = models
        self.modelWorkByBucket = modelWorkByBucket; self.modelHourlyAverages = modelHourlyAverages
        self.modelHourlyProfits = modelHourlyProfits; self.modelHourlyProfitAverages = modelHourlyProfitAverages
        self.tokenRates = tokenRates
    }
}

struct ActivityReadTicket: Equatable {
    let id: UUID
    let query: ActivityQuery
}

struct ActivityReadState {
    private(set) var completed: ActivityReadSnapshot?
    private(set) var pending: ActivityReadTicket?
    private(set) var message: String?
    private var requestedContext: AccountEarningsContext?
    private var requestedEpoch: UInt64?

    mutating func begin(_ query: ActivityQuery) -> ActivityReadTicket {
        if completed?.query.context != query.context || completed?.query.sessionEpoch != query.sessionEpoch || !query.ledgerReady { completed = nil }
        let ticket = ActivityReadTicket(id: UUID(), query: query)
        pending = ticket
        requestedContext = query.context
        requestedEpoch = query.sessionEpoch
        message = nil
        return ticket
    }

    mutating func finish(_ snapshot: ActivityReadSnapshot, for ticket: ActivityReadTicket) {
        guard pending == ticket, snapshot.query == ticket.query, ticket.query.ledgerReady else { return }
        completed = snapshot
        pending = nil
        message = nil
    }

    mutating func fail(_ reason: String, for ticket: ActivityReadTicket) {
        guard pending == ticket else { return }
        if completed?.query.context != ticket.query.context || !ticket.query.ledgerReady { completed = nil }
        message = reason
        pending = nil
    }

    mutating func cancel(_ ticket: ActivityReadTicket) {
        guard pending == ticket else { return }
        pending = nil
    }

    /// Also used while rendering: account changes suppress retained data before
    /// SwiftUI has cancelled the old task or scheduled the replacement.
    func presentation(context: AccountEarningsContext?, ledgerReady: Bool, sessionEpoch: UInt64 = 0) -> Self {
        var visible = self
        if context == nil || !ledgerReady {
            visible.completed = nil
            visible.pending = nil
            visible.message = Self.unavailableMessage(context: context, ledgerReady: ledgerReady)
        } else {
            if visible.completed?.query.context != context || visible.completed?.query.sessionEpoch != sessionEpoch { visible.completed = nil }
            if visible.requestedContext != context || visible.requestedEpoch != sessionEpoch { visible.pending = nil; visible.message = nil }
        }
        return visible
    }

    static func unavailableMessage(context: AccountEarningsContext?, ledgerReady: Bool) -> String {
        context == nil ? "Connect an account to read its local credit history."
            : "Local credit history is unavailable until this account's ledger is ready."
    }

    mutating func unavailable(_ reason: String, for ticket: ActivityReadTicket) {
        guard pending == ticket else { return }
        completed = nil
        pending = nil
        message = reason
    }

    var status: String {
        if let message {
            return completed == nil ? message : "\(message) Showing the last completed read."
        }
        if let pending, let completed {
            return completed.query.hasSameScope(as: pending.query)
                ? "Refreshing local history…"
                : "Reading the requested selection; previous results remain visible."
        }
        if let completed {
            return "Read \(completed.capturedAt.formatted(completed.query.dateFormat.hour().minute().second()))"
        }
        return "Reading local history…"
    }
}

extension ActivityQuery {
    var dateFormat: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, calendar: calendar, timeZone: calendar.timeZone)
    }

    var dateAndTimeFormat: Date.FormatStyle {
        Date.FormatStyle(date: .abbreviated, time: .shortened, calendar: calendar, timeZone: calendar.timeZone)
    }

    func hasSameScope(as other: Self) -> Bool {
        context == other.context && ledgerReady == other.ledgerReady && sessionEpoch == other.sessionEpoch && range == other.range && unit == other.unit && calendar == other.calendar && model == other.model && metric == other.metric
    }

    var scopeSummary: String {
        let format = Date.FormatStyle(date: .abbreviated, time: .omitted,
                                      calendar: calendar, timeZone: calendar.timeZone)
        let period: String
        if let range {
            let last = range.end.addingTimeInterval(-1)
            period = calendar.isDate(range.start, inSameDayAs: last)
                ? range.start.formatted(format)
                : "\(range.start.formatted(format))–\(last.formatted(format))"
        } else { period = "Invalid date range" }
        return "Showing \(period) · \(model.map(ModelDisplayName.short) ?? "All models") · \(metric.rawValue)"
    }
}

/// Every financial component comes from the same atomic report for its scope.
/// Local token samples are supplementary and must pass the final session check.
extension ActivityReadSnapshot {
    @MainActor
    static func fetch(query: ActivityQuery, store: MonitorStore,
                      powerIntervals: [EnergyInterval] = []) async throws -> Self? {
        guard let context = query.context, query.ledgerReady, let range = query.range else { return nil }
        guard query.sessionEpoch == store.financialSessionEpoch else { throw AccountEarningsClientError.sessionChanged }
        let capturedReport: AccountCreditReport?
        if query.metric == .estimatedProfit {
            capturedReport = try await store.localProviderFinancialReport(context: context, in: range,
                unit: query.unit, calendar: query.calendar)
        } else {
            capturedReport = try await store.financialReport(context: context, in: range,
                unit: query.unit, calendar: query.calendar)
        }
        guard let report = capturedReport else { return nil }
        try Task.checkCancellation()
        let hourlyProfits: [ModelHourlyProfit]
        if query.metric == .estimatedProfit {
            // Daily and hourly attribution belong to the same ledger transaction.
            // Older inert hourly fixtures can still supply their primary series.
            let hourlyActivity = report.modelHourlyActivity.isEmpty && query.unit == .hour
                ? report.modelActivity : report.modelHourlyActivity
            hourlyProfits = ModelProfitability.hourlyProfits(activity: hourlyActivity, energy: powerIntervals)
        } else { hourlyProfits = [] }
        let perModel = Dictionary(grouping: report.modelActivity, by: \.interval.start).mapValues { values in
            Dictionary(uniqueKeysWithValues: values.map { ($0.model, $0.workMicroUSD) })
        }
        let rates: [ModelRateBucket]
        if let model = query.model {
            rates = (try? await store.activityTokenRates(in: range, unit: query.unit,
                calendar: query.calendar, model: model)) ?? []
        } else { rates = [] }
        try Task.checkCancellation()
        try await store.validateFinancialContext(context)
        guard query.sessionEpoch == store.financialSessionEpoch else { throw AccountEarningsClientError.sessionChanged }
        try Task.checkCancellation()
        return Self(query: query, buckets: report.activityBuckets(model: query.model), models: report.models,
            modelWorkByBucket: perModel, modelHourlyAverages: report.hourlyEarningsAverages,
            modelHourlyProfits: hourlyProfits, modelHourlyProfitAverages: ModelProfitability.averages(hourlyProfits),
            tokenRates: Dictionary(uniqueKeysWithValues: rates.map { ($0.id, $0) }))
    }
}
