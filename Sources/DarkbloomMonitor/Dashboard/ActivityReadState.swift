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

    mutating func begin(_ query: ActivityQuery) -> ActivityReadTicket {
        let ticket = ActivityReadTicket(id: UUID(), query: query)
        pending = ticket
        message = nil
        return ticket
    }

    mutating func finish(_ snapshot: ActivityReadSnapshot, for ticket: ActivityReadTicket) {
        guard pending == ticket, snapshot.query == ticket.query else { return }
        completed = snapshot
        pending = nil
        message = nil
    }

    mutating func fail(_ reason: String, for ticket: ActivityReadTicket) {
        guard pending == ticket else { return }
        message = reason
        pending = nil
    }

    mutating func cancel(_ ticket: ActivityReadTicket) {
        guard pending == ticket else { return }
        pending = nil
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
        range == other.range && unit == other.unit && calendar == other.calendar && model == other.model && metric == other.metric
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
