import Foundation

/// Provider-wide evidence between adjacent fresh measurements. This neither
/// attributes work to a model nor establishes continuous inference or payment.
public struct PerformanceActivityHistory: Equatable, Sendable {
    public enum Evidence: String, CaseIterable, Sendable {
        case active, betweenReadings, idle, uncertain
    }
    public struct Segment: Equatable, Identifiable, Sendable {
        public let id: UUID
        public let start: Date
        public let end: Date
        public let evidence: Evidence
    }
    public let segments: [Segment]
    public let totalSegmentCount: Int

    public init(samples: [PerformanceSample], period: DateInterval, maximumSegments: Int = 600) {
        guard maximumSegments > 0, period.duration > 0,
              PerformanceSample.validTimestamp(period.start), PerformanceSample.validTimestamp(period.end) else {
            segments = []; totalSegmentCount = 0; return
        }
        var result: [Segment] = []
        let valid = samples.map(\.isValid)
        var precedingSession: String?
        for index in samples.indices.dropFirst() {
            let first = samples[index - 1], second = samples[index]
            guard valid[index - 1], valid[index], PerformanceSummary.validPair(first, second) else {
                precedingSession = nil
                continue
            }
            let start = max(first.observedAt, period.start)
            let end = min(second.observedAt, period.end)
            guard end > start else { continue }
            let evidence: Evidence
            let counterWork = (first.requestsServed.flatMap { before in second.requestsServed.map { $0 > before } } ?? false)
                || (first.tokensGenerated.flatMap { before in second.tokensGenerated.map { $0 > before } } ?? false)
            if first.hasActiveInference == true, second.hasActiveInference == true {
                evidence = .active
            } else if counterWork {
                // The increment could fall outside a clipped bracket. Do not
                // place completed work inside a period containing only its tail.
                evidence = start == first.observedAt && end == second.observedAt ? .betweenReadings : .uncertain
            } else if first.hasActiveInference == false, second.hasActiveInference == false,
                      first.requestsServed != nil, first.requestsServed == second.requestsServed,
                      first.tokensGenerated != nil, first.tokensGenerated == second.tokensGenerated,
                      (first.activeRequests ?? 0) == 0, (second.activeRequests ?? 0) == 0,
                      (first.tokensPerSecond ?? 0) == 0, (second.tokensPerSecond ?? 0) == 0 {
                evidence = .idle
            } else {
                evidence = .uncertain
            }
            // Merge identical adjacent evidence only within one uninterrupted
            // provider session. Missing rows and resets remain visible gaps.
            if let last = result.last, last.end == start, last.evidence == evidence,
               precedingSession == first.providerSession {
                result[result.count - 1] = Segment(id: last.id, start: last.start, end: end, evidence: evidence)
            } else {
                result.append(Segment(id: first.id, start: start, end: end, evidence: evidence))
            }
            precedingSession = second.providerSession
        }
        totalSegmentCount = result.count
        segments = Array(result.suffix(maximumSegments))
    }
}
