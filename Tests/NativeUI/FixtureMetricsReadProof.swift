import DarkbloomTelemetry
import Foundation

enum FixtureMetricsReadMode: String, CaseIterable, Identifiable, Codable, Sendable {
    case normal, hold, fail, empty
    var id: Self { self }
}

/// Small bounded evidence: no row payloads, paths, or raw error descriptions.
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
}

/// Owns only the explicitly supplied synthetic database. Modes affect one
/// display read, never production preferences, telemetry, or provider actions.
actor FixtureMetricsReads {
    private let database: PerformanceHistoryDatabase
    private var nextMode = FixtureMetricsReadMode.normal
    private var pending: (id: UInt64, continuation: CheckedContinuation<FixtureMetricsReadMode, Error>)?
    private var started: UInt64 = 0
    private var completed: UInt64 = 0
    private var failed: UInt64 = 0
    private var cancelled: UInt64 = 0
    private var empty: UInt64 = 0
    private var lastStartedAt: Date?
    private var lastCompletedAt: Date?

    init(url: URL) throws { database = try PerformanceHistoryDatabase(url: url) }

    func setNext(_ mode: FixtureMetricsReadMode) { nextMode = mode }

    func samples(in interval: DateInterval) async throws -> [PerformanceSample] {
        try Task.checkCancellation()
        started &+= 1
        let readID = started
        lastStartedAt = Date()
        var mode = nextMode
        nextMode = .normal
        do {
            if mode == .hold { mode = try await hold(readID) }
            try Task.checkCancellation()
            let rows: [PerformanceSample]
            switch mode {
            case .fail: throw FixtureMetricsReadError.synthetic
            case .empty: rows = []
            case .normal, .hold: rows = try database.samples(in: interval)
            }
            try Task.checkCancellation()
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
              lastStartedAt: lastStartedAt, lastCompletedAt: lastCompletedAt)
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
