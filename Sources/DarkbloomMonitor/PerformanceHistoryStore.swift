import DarkbloomTelemetry
import Foundation
import SwiftUI

/// Serialized disk access stays off the UI actor. Failed writes remain bounded
/// in memory and are replayed with their original IDs on the next attempt.
private actor PerformanceJournal {
    private let url: URL
    private var database: PerformanceHistoryDatabase?
    private var pending: [PerformanceSample] = []
    private var lostSamples = false

    init(url: URL) { self.url = url }

    private func opened() throws -> PerformanceHistoryDatabase {
        if let database { return database }
        let opened = try PerformanceHistoryDatabase(url: url)
        database = opened
        return opened
    }

    func record(_ sample: PerformanceSample) throws -> Date? {
        pending.append(sample)
        if pending.count > 120 {
            pending.removeFirst(pending.count - 120)
            lostSamples = true
        }
        let database = try opened()
        while let first = pending.first {
            try database.record(first)
            pending.removeFirst()
        }
        if lostSamples { throw PerformanceRecordingError.backlogOverflow }
        return (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate]) as? Date
    }

    func samples(in interval: DateInterval) throws -> [PerformanceSample] {
        try Task.checkCancellation()
        return try opened().samples(in: interval)
    }
}

private enum PerformanceRecordingError: Error { case backlogOverflow }

@MainActor
final class PerformanceHistoryStore: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var storageError: String?
    @Published private(set) var recordingStartedAt: Date?
    private let journal: PerformanceJournal
    private var lastObserved: PerformanceSample?
    private var lastAttemptAt: Date?
    private var recordError: String?
    private var readError: String?

    init(url: URL) { journal = PerformanceJournal(url: url) }

    /// Called for every accepted observation. Persist every 30 seconds and at
    /// state boundaries, including activity changes and missing observations.
    func observe(_ sample: PerformanceSample) async {
        let elapsed = lastAttemptAt.map { sample.observedAt.timeIntervalSince($0) }
        let changed = lastObserved.map { previous in
            previous.quality != sample.quality || previous.providerSession != sample.providerSession
                || previous.model != sample.model || previous.residentModels != sample.residentModels
                || previous.advertisedModels != sample.advertisedModels
                || previous.autopilotPhase != sample.autopilotPhase
                || previous.inferenceActive != sample.inferenceActive
                || (sample.quality == .current && previous.quality == .current
                    && (previous.requestsServed != sample.requestsServed
                        || previous.tokensGenerated != sample.tokensGenerated))
        } ?? true
        // A failing disk gets one retry every 30 seconds, not a retry per tick.
        if let elapsed, elapsed >= 0, elapsed < 30,
           (!changed || recordError != nil) { return }
        lastObserved = sample
        lastAttemptAt = sample.observedAt
        do {
            recordingStartedAt = try await journal.record(sample)
            recordError = nil
        } catch PerformanceRecordingError.backlogOverflow {
            recordError = "Some performance samples could not be saved. Gaps remain unknown."
        } catch {
            recordError = "Performance recording needs attention. Bloomy will retry automatically."
        }
        storageError = recordError ?? readError
        revision &+= 1
    }

    func samples(in interval: DateInterval) async throws -> [PerformanceSample] {
        do {
            try Task.checkCancellation()
            let samples = try await journal.samples(in: interval)
            try Task.checkCancellation()
            readError = nil
            storageError = recordError
            return samples
        } catch is CancellationError {
            // Changing the filter or closing a window is not a storage fault.
            throw CancellationError()
        } catch {
            readError = "Performance history could not be read. Refresh to retry."
            storageError = recordError ?? readError
            throw error
        }
    }
}

extension PerformanceSample {
    /// Whitelist only structured measurements. Provider error text, credentials,
    /// coordinator identifiers and request content never enter this history.
    static func capture(
        _ snapshot: TelemetrySnapshot, at date: Date,
        gpuPercentage: Double? = nil, powerWatts: Double? = nil
    ) -> PerformanceSample {
        let state = snapshot.state.value
        let sourceDate = state.flatMap { $0.writtenAt.isFinite ? Date(timeIntervalSince1970: $0.writtenAt) : nil }
        let age = sourceDate.map { date.timeIntervalSince($0) }
        let current: Bool
        if case .available = snapshot.state, let age, age.isFinite, (0...15).contains(age) { current = true }
        else { current = false }
        let quality: PerformanceSampleQuality = state == nil ? .unavailable : (current ? .current : .stale)
        let identity = state?.processIdentity
        let session = identity.flatMap { $0.pid > 0 && $0.startTimeMicros >= 0 ? "\($0.pid):\($0.startTimeMicros)" : nil }
        let rate: Double?
        if current, state?.inferenceActive == true, case .available(let value, _) = snapshot.tokenRate {
            rate = validMetric(value, maximum: 1_000_000_000)
        } else { rate = nil }
        return PerformanceSample(
            observedAt: date,
            sourceCapturedAt: sourceDate.flatMap { $0 <= date && $0.timeIntervalSince1970 >= 0 ? $0 : nil },
            quality: quality, providerSession: session,
            model: safeModel(state?.currentModel),
            residentModels: Array((state?.warmModels ?? []).compactMap(safeModel).prefix(64)).sorted(),
            advertisedModels: Array((state?.advertisedModels ?? []).compactMap(safeModel).prefix(64)).sorted(),
            inferenceActive: current ? state?.inferenceActive : nil,
            tokensPerSecond: rate,
            tokensGenerated: current ? state?.stats.tokensGenerated.nonnegative : nil,
            requestsServed: current ? state?.stats.requestsServed.nonnegative : nil,
            gpuUtilizationPercent: validMetric(gpuPercentage, maximum: 100),
            gpuMemoryGB: current ? validMetric(state?.capacity?.gpuMemoryActiveGB, maximum: 1_000_000) : nil,
            powerWatts: validMetric(powerWatts, maximum: 10_000_000),
            autopilotPhase: current ? state?.autopilotPhase : nil
        )
    }

    private static func safeModel(_ model: String?) -> String? {
        guard let model, !model.isEmpty, model.utf8.count <= 160,
              !model.hasPrefix("/"), !model.contains(":/"),
              model.split(separator: "/", omittingEmptySubsequences: false).allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
        else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/+-")
        return model.unicodeScalars.allSatisfy(allowed.contains) ? model : nil
    }

    private static func validMetric(_ value: Double?, maximum: Double) -> Double? {
        guard let value, value.isFinite, (0...maximum).contains(value) else { return nil }
        return value
    }
}

private extension Int64 {
    var nonnegative: Int64? { self >= 0 ? self : nil }
}
