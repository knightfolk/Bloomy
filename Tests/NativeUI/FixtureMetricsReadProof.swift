import DarkbloomTelemetry
import Foundation

enum FixtureMetricsReadMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal, hold, fail, empty
    var id: Self { self }
}

/// Small bounded evidence: no row payloads, paths, or raw error descriptions.
struct FixtureMetricsReadTiming: Codable, Sendable {
    let readID: UInt64
    let intervalSeconds: Double
    let queryStartUnix: Double
    let queryEndUnix: Double
    let rows: Int
    let reusedRows: Int
    let milliseconds: Double
}

struct FixtureMetricsReadSnapshot: Codable, Sendable {
    let nextMode: FixtureMetricsReadMode
    let started: UInt64
    let completed: UInt64
    let failed: UInt64
    let cancelled: UInt64
    let empty: UInt64
    let heldReadID: UInt64?
    let lastStartedAt: Date?
    let lastCompletedAt: Date?
    let cacheReleases: UInt64
    let lastReleasedDecodedRows: Int
    let totalReleasedDecodedRows: UInt64
    let retainedSnapshotRows: Int
    let lastReleasedSnapshotRows: Int
    let recentReads: [FixtureMetricsReadTiming]
}

/// Owns only the explicitly supplied synthetic database. Modes affect one
/// display read, never production preferences, telemetry, or provider actions.
actor FixtureMetricsReads {
    private let database: PerformanceHistoryDatabase
    private let proofURL: URL?
    private var nextMode = FixtureMetricsReadMode.normal
    private var pending: (id: UInt64, continuation: CheckedContinuation<FixtureMetricsReadMode, Error>)?
    private var started: UInt64 = 0
    private var completed: UInt64 = 0
    private var failed: UInt64 = 0
    private var cancelled: UInt64 = 0
    private var empty: UInt64 = 0
    private var lastStartedAt: Date?
    private var lastCompletedAt: Date?
    private var cacheReleases: UInt64 = 0
    private var lastReleasedDecodedRows = 0
    private var totalReleasedDecodedRows: UInt64 = 0
    private var recentReads: [FixtureMetricsReadTiming] = []
    private var readSnapshot: PerformanceHistoryReadSnapshot?
    private var lastReleasedSnapshotRows = 0

    init(url: URL, proofURL: URL? = nil) throws {
        database = try PerformanceHistoryDatabase(url: url)
        self.proofURL = proofURL
    }

    private func persistProof() {
        guard let proofURL, let data = try? JSONEncoder().encode(snapshot()) else { return }
        try? data.write(to: proofURL, options: .atomic)
    }

    func setNext(_ mode: FixtureMetricsReadMode) { nextMode = mode }

    func clearReadCache() {
        lastReleasedSnapshotRows = readSnapshot?.samples.count ?? 0
        readSnapshot = nil
        lastReleasedDecodedRows = database.clearDecodedReadCache()
        totalReleasedDecodedRows &+= UInt64(lastReleasedDecodedRows)
        cacheReleases &+= 1
        persistProof()
    }

    func samples(in interval: DateInterval) async throws -> [PerformanceSample] {
        try Task.checkCancellation()
        started &+= 1
        let readID = started
        lastStartedAt = Date()
        persistProof()
        defer { persistProof() }
        var mode = nextMode
        nextMode = .normal
        do {
            if mode == .hold { mode = try await hold(readID) }
            try Task.checkCancellation()
            let began = ContinuousClock.now
            let rows: [PerformanceSample]
            let next: PerformanceHistoryReadSnapshot?
            switch mode {
            case .fail: throw FixtureMetricsReadError.synthetic
            case .empty: rows = []; next = nil
            case .normal, .hold:
                let snapshot = try database.readSnapshot(in: interval, reusing: readSnapshot)
                rows = snapshot.samples
                next = snapshot
            }
            try Task.checkCancellation()
            readSnapshot = next
            let duration = began.duration(to: .now).components
            recentReads.append(.init(readID: readID, intervalSeconds: interval.duration,
                queryStartUnix: interval.start.timeIntervalSince1970,
                queryEndUnix: interval.end.timeIntervalSince1970,
                rows: rows.count, reusedRows: next?.reusedSampleCount ?? 0,
                milliseconds: Double(duration.seconds) * 1_000 + Double(duration.attoseconds) / 1e15))
            if recentReads.count > 12 { recentReads.removeFirst(recentReads.count - 12) }
            completed &+= 1
            if rows.isEmpty { empty &+= 1 }
            lastCompletedAt = Date()
            return rows
        } catch {
            if error is CancellationError || Task.isCancelled {
                cancelled &+= 1
                throw CancellationError()
            }
            failed &+= 1
            throw error
        }
    }

    /// Release returns the latest synthetic rows within the original interval.
    /// Holding is not a terminal outcome, so a .hold release behaves as normal.
    func releaseHeld(as mode: FixtureMetricsReadMode = .normal) {
        guard let held = pending else { return }
        pending = nil
        held.continuation.resume(returning: mode == .hold ? .normal : mode)
    }

    func cancelHeld() {
        guard let held = pending else { return }
        pending = nil
        held.continuation.resume(throwing: CancellationError())
    }

    func snapshot() -> FixtureMetricsReadSnapshot {
        .init(nextMode: nextMode, started: started, completed: completed, failed: failed,
              cancelled: cancelled, empty: empty, heldReadID: pending?.id,
              lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt,
              cacheReleases: cacheReleases, lastReleasedDecodedRows: lastReleasedDecodedRows,
              totalReleasedDecodedRows: totalReleasedDecodedRows,
              retainedSnapshotRows: readSnapshot?.samples.count ?? 0,
              lastReleasedSnapshotRows: lastReleasedSnapshotRows, recentReads: recentReads)
    }

    private func hold(_ readID: UInt64) async throws -> FixtureMetricsReadMode {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    // No accumulating waiter list when review input races.
                    cancelHeld()
                    pending = (readID, continuation)
                }
            }
        } onCancel: {
            Task { await self.cancelHeld(readID) }
        }
    }

    private func cancelHeld(_ readID: UInt64) {
        guard pending?.id == readID else { return }
        cancelHeld()
    }
}

private enum FixtureMetricsReadError: Error { case synthetic }
