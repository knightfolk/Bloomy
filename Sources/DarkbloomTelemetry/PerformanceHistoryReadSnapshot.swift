import Foundation

/// Validated chronological measurements and an opaque reuse token. Only the
/// database can create this value; callers cannot supply trusted row payloads.
/// Retain one snapshot while reading, then release it when the consumer hides.
public struct PerformanceHistoryReadSnapshot: Sendable {
    public let samples: [PerformanceSample]
    public let reusedSampleCount: Int
    let rowIDs: [Int64]
    let sourceID: UUID
    let dataVersion: Int64?
    let insertionSequence: UInt64
}
