import Foundation

public enum ModelVisitWorkEvidence: String, Equatable, Sendable {
    case observedWork, noObservedWork, unknown
}

public enum ModelVisitOutcome: String, Equatable, Sendable {
    case worked, noObservedWork, unknown, stillLoaded
}

public enum ModelVisitBoundary: String, Equatable, Sendable {
    case modelChanged, providerRestart, staleOrMissing, longGap, counterReset
    case periodBoundary, historyBoundary, residencyChanged
}

/// A resident model observed over one uninterrupted provider visit. A sole
/// resident is authoritative; `PerformanceSample.model` can be an older
/// most-recently-used label. Concurrent residence retains an uncertain selected
/// visit only when the last-used label identifies one of the resident models.
/// Times describe polling observations, not exact model load/unload times.
/// `noObservedWork` is an evidence statement, never a claim that the model
/// has never served a request. Provider counters are attributed only with one
/// resident model at both ends of an uninterrupted same-model interval.
public struct ModelVisit: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let model: String
    public let observedStart: Date
    public let observedEnd: Date
    public var durationSeconds: TimeInterval { observedEnd.timeIntervalSince(observedStart) }
    /// Fresh monitored intervals, including a final observed switch interval.
    /// A switch interval does not establish the precise residence duration.
    public let coveredSeconds: TimeInterval
    /// Same-model intervals with inactive endpoints and unchanged counters.
    /// Short completed work between inactive polls is excluded from idle time.
    public let observedIdleSeconds: TimeInterval
    public let workEvidence: ModelVisitWorkEvidence
    public let outcome: ModelVisitOutcome
    public let startReason: ModelVisitBoundary
    public let endReason: ModelVisitBoundary
    public let isStartTruncated: Bool
    public let isEndTruncated: Bool
    public let isOpen: Bool
    /// Observations in the original visit, including those outside a clipped period.
    public let sampleCount: Int
}

public struct ModelVisitSummary: Equatable, Sendable {
    public let visitCount: Int
    public let workedCount: Int
    public let completedNoObservedWorkCount: Int
    public let completedNoObservedWorkSeconds: TimeInterval
    public let unknownCount: Int
    public let stillLoadedCount: Int

    public init(visits: [ModelVisit]) {
        visitCount = visits.count
        workedCount = visits.filter { $0.workEvidence == .observedWork }.count
        completedNoObservedWorkCount = visits.filter { $0.outcome == .noObservedWork }.count
        completedNoObservedWorkSeconds = visits.filter { $0.outcome == .noObservedWork }
            .reduce(0) { $0 + $1.durationSeconds }
        unknownCount = visits.filter { $0.outcome == .unknown }.count
        stillLoadedCount = visits.filter(\.isOpen).count
    }
}

/// Pure analysis of chronological measurements. Never sort/filter away
/// intervening models or missing measurements before calling this initializer.
/// The latest `maximumVisits` are retained in chronological order. Period
/// clipping happens after analysis, preserving interruptions and truncation.
public struct ModelVisitHistory: Equatable, Sendable {
    public let visits: [ModelVisit]
    public var completedNoObservedWorkVisits: [ModelVisit] {
        visits.filter { $0.outcome == .noObservedWork }
    }
    public var summary: ModelVisitSummary { ModelVisitSummary(visits: visits) }

    public init(samples: [PerformanceSample], period: DateInterval? = nil, maximumVisits: Int = 500) {
        guard maximumVisits > 0 else { visits = []; return }
        var builders: [VisitBuilder] = []
        var current: VisitBuilder?
        var previous: ObservationFacts?
        for sample in samples {
            let facts = ObservationFacts(sample)
            let eligible = facts.fresh && facts.selectedResident != nil
            if let prior = previous, var visit = current {
                // Release the previous builder before appending to its arrays.
                // Otherwise every observation copies the growing visit storage.
                current = nil
                if let interruption = Self.interruption(prior, facts) {
                    visit.finish(at: prior.sample.observedAt, reason: interruption, truncated: true)
                    builders.append(visit)
                    current = eligible ? VisitBuilder(facts, reason: interruption, truncated: true) : nil
                } else if !eligible {
                    if facts.confirmedEmptySlot {
                        visit.addEmptySlotBoundary(prior, facts)
                        visit.finish(at: sample.observedAt, reason: .residencyChanged, truncated: false)
                    } else {
                        let reason: ModelVisitBoundary = sample.model == nil ? .staleOrMissing : .residencyChanged
                        visit.finish(at: prior.sample.observedAt, reason: reason, truncated: true)
                    }
                    builders.append(visit)
                    current = nil
                } else if prior.selectedResident != facts.selectedResident {
                    // Neither side owns a provider-wide increment spanning a
                    // switch. Both visits retain the attribution uncertainty.
                    let counters = Self.counterEvidence(prior.sample, sample)
                    visit.addSwitchInterval(prior, facts, counters: counters)
                    visit.finish(at: sample.observedAt, reason: .modelChanged, truncated: false)
                    builders.append(visit)
                    var next = VisitBuilder(facts, reason: .modelChanged, truncated: false)
                    if counters != .zero || !prior.singleResident || !facts.singleResident {
                        next.uncertain = true
                    }
                    current = next
                } else {
                    visit.add(prior, facts)
                    current = visit
                }
            } else if eligible {
                if let prior = previous, prior.confirmedEmptySlot, Self.interruption(prior, facts) == nil {
                    var next = VisitBuilder(facts, reason: .residencyChanged, truncated: false)
                    if Self.counterEvidence(prior.sample, sample) != .zero { next.uncertain = true }
                    current = next
                } else {
                    current = VisitBuilder(facts, reason: previous == nil ? .historyBoundary : .staleOrMissing, truncated: true)
                }
            }
            previous = facts
        }
        if var visit = current {
            visit.finish(at: visit.last.observedAt, reason: .historyBoundary, truncated: true, open: true)
            builders.append(visit)
        }
        visits = Array(builders.compactMap { $0.value(period: period) }.suffix(maximumVisits))
    }

    /// Classification is immutable and computed once for each original row.
    /// Only current/previous facts are retained; invalid and stale rows still
    /// participate in adjacency and boundary checks.
    private struct ObservationFacts {
        let sample: PerformanceSample
        let valid: Bool
        let fresh: Bool
        let selectedResident: String?
        let singleResident: Bool
        let directWork: Bool
        let knownInactive: Bool
        let confirmedEmptySlot: Bool

        init(_ sample: PerformanceSample) {
            self.sample = sample
            valid = sample.isValid
            if valid, sample.quality == .current, sample.providerSession != nil,
               let capture = sample.sourceCapturedAt {
                fresh = (0...90).contains(sample.observedAt.timeIntervalSince(capture))
            } else {
                fresh = false
            }
            // A sole distinct label is authoritative, including repeated labels.
            // Concurrent residence selects only an MRU present in the array.
            if let first = sample.residentModels.first,
               sample.residentModels.allSatisfy({ $0 == first }) {
                singleResident = true
                selectedResident = first
            } else {
                singleResident = false
                selectedResident = sample.model.flatMap { sample.residentModels.contains($0) ? $0 : nil }
            }
            directWork = singleResident && sample.model == selectedResident
                && (sample.inferenceActive == true || (sample.activeRequests ?? 0) > 0
                || (sample.tokensPerSecond ?? 0) > 0)
            knownInactive = singleResident && sample.hasActiveInference == false
                && (sample.activeRequests ?? 0) == 0 && (sample.tokensPerSecond ?? 0) == 0
            // Explicitly empty, fresh, idle slots establish observed unloads.
            // Retained MRU labels and incomplete readings cannot establish one.
            confirmedEmptySlot = fresh && sample.model == nil && sample.residentModels.isEmpty
                && sample.inferenceActive == false && (sample.activeRequests ?? 0) == 0
                && (sample.tokensPerSecond ?? 0) == 0
                && sample.requestsServed != nil && sample.tokensGenerated != nil
        }
    }

    private static func interruption(_ priorFacts: ObservationFacts, _ facts: ObservationFacts) -> ModelVisitBoundary? {
        let prior = priorFacts.sample
        let sample = facts.sample
        guard priorFacts.fresh, facts.fresh,
              sample.model != nil || facts.selectedResident != nil || facts.confirmedEmptySlot else { return .staleOrMissing }
        guard prior.providerSession == sample.providerSession else { return .providerRestart }
        let duration = sample.observedAt.timeIntervalSince(prior.observedAt)
        guard duration > 0 else { return .staleOrMissing }
        guard duration <= 90 else { return .longGap }
        guard let before = prior.sourceCapturedAt, let after = sample.sourceCapturedAt,
              after > before else { return .staleOrMissing }
        guard after.timeIntervalSince(before) <= 90 else { return .longGap }
        if let before = prior.requestsServed, let after = sample.requestsServed, after < before { return .counterReset }
        if let before = prior.tokensGenerated, let after = sample.tokensGenerated, after < before { return .counterReset }
        return nil
    }

    private enum CounterEvidence { case positive, zero, unknown }

    private static func counterEvidence(_ prior: PerformanceSample, _ sample: PerformanceSample) -> CounterEvidence {
        let requests = prior.requestsServed.flatMap { before in sample.requestsServed.map { $0 - before } }
        let tokens = prior.tokensGenerated.flatMap { before in sample.tokensGenerated.map { $0 - before } }
        if requests.map({ $0 > 0 }) == true || tokens.map({ $0 > 0 }) == true { return .positive }
        return requests != nil && tokens != nil ? .zero : .unknown
    }

    private struct Interval {
        let start: Date
        let end: Date
        let idle: Bool

        func duration(in period: DateInterval?) -> TimeInterval {
            max(0, min(end, period?.end ?? end).timeIntervalSince(max(start, period?.start ?? start)))
        }
    }

    private struct VisitBuilder {
        let first: PerformanceSample
        let model: String
        var last: PerformanceSample
        var startReason: ModelVisitBoundary
        var startTruncated: Bool
        var end: Date
        var endReason: ModelVisitBoundary = .historyBoundary
        var endTruncated = true
        var open = false
        var uncertain = false
        var count = 1
        var intervals: [Interval] = []
        var directWorkTimes: [Date] = []
        var counterWorkIntervals: [DateInterval] = []

        init(_ facts: ObservationFacts, reason: ModelVisitBoundary, truncated: Bool) {
            let sample = facts.sample
            first = sample
            model = facts.selectedResident!
            last = sample
            startReason = reason
            startTruncated = truncated
            end = sample.observedAt
            uncertain = !(facts.knownInactive || facts.directWork)
            if facts.directWork { directWorkTimes.append(sample.observedAt) }
        }

        mutating func add(_ priorFacts: ObservationFacts, _ facts: ObservationFacts) {
            let prior = priorFacts.sample
            let sample = facts.sample
            let unique = priorFacts.singleResident && facts.singleResident
            let counters = ModelVisitHistory.counterEvidence(prior, sample)
            let idle = unique && counters == .zero && priorFacts.knownInactive && facts.knownInactive
            intervals.append(Interval(start: prior.observedAt, end: sample.observedAt, idle: idle))
            if unique && counters == .positive {
                counterWorkIntervals.append(DateInterval(start: prior.observedAt, end: sample.observedAt))
            }
            if facts.directWork { directWorkTimes.append(sample.observedAt) }
            if !unique || counters == .unknown || !(facts.knownInactive || facts.directWork) { uncertain = true }
            last = sample
            end = sample.observedAt
            count += 1
        }

        mutating func addSwitchInterval(_ prior: ObservationFacts, _ facts: ObservationFacts, counters: CounterEvidence) {
            intervals.append(Interval(start: prior.sample.observedAt, end: facts.sample.observedAt, idle: false))
            if counters != .zero || !prior.singleResident || !facts.singleResident {
                uncertain = true
            }
        }

        mutating func addEmptySlotBoundary(_ prior: ObservationFacts, _ facts: ObservationFacts) {
            intervals.append(Interval(start: prior.sample.observedAt, end: facts.sample.observedAt, idle: false))
            if ModelVisitHistory.counterEvidence(prior.sample, facts.sample) != .zero
                || !prior.singleResident || !prior.knownInactive {
                uncertain = true
            }
        }

        mutating func finish(at end: Date, reason: ModelVisitBoundary, truncated: Bool, open: Bool = false) {
            self.end = end
            endReason = reason
            endTruncated = truncated
            self.open = open
        }

        func value(period: DateInterval?) -> ModelVisit? {
            let start = max(first.observedAt, period?.start ?? first.observedAt)
            let stop = min(end, period?.end ?? end)
            guard stop >= start else { return nil }
            if let period {
                // Periods use a half-open observation window. A single observed
                // point can still be shown, but a visit ending at the window's
                // start belongs to the preceding window.
                let pointInside = first.observedAt == end && first.observedAt >= period.start
                guard first.observedAt < period.end, end > period.start || pointInside else { return nil }
            }
            let clippedStart = start > first.observedAt
            let clippedEnd = stop < end
            let isOpen = open && !clippedEnd
            let startTruncated = self.startTruncated || clippedStart
            let endTruncated = self.endTruncated || clippedEnd
            let worked = directWorkTimes.contains { $0 >= start && $0 <= stop }
                || counterWorkIntervals.contains { $0.start >= start && $0.end <= stop }
            let covered = intervals.reduce(0) { $0 + $1.duration(in: period) }
            let idle = intervals.filter(\.idle).reduce(0) { $0 + $1.duration(in: period) }
            let complete = !uncertain && !startTruncated && !endTruncated && covered > 0
            let evidence: ModelVisitWorkEvidence = worked ? .observedWork : complete ? .noObservedWork : .unknown
            let outcome: ModelVisitOutcome = isOpen ? .stillLoaded : worked ? .worked : complete ? .noObservedWork : .unknown
            return ModelVisit(
                id: first.id, model: model, observedStart: start, observedEnd: stop,
                coveredSeconds: covered, observedIdleSeconds: idle, workEvidence: evidence, outcome: outcome,
                startReason: clippedStart ? .periodBoundary : startReason,
                endReason: clippedEnd ? .periodBoundary : endReason,
                isStartTruncated: startTruncated, isEndTruncated: endTruncated, isOpen: isOpen, sampleCount: count
            )
        }
    }
}
