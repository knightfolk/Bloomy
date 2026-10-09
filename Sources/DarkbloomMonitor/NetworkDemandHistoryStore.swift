import DarkbloomTelemetry
import Foundation
import SwiftUI

/// The database is created only on first use, on this actor rather than the UI
/// actor. Synchronous writes cannot interleave, including injected test writes.
private actor NetworkDemandJournal {
    struct WriteResult: Sendable {
        let changed: Bool
        let failed: Bool
        let lostSamples: Bool
    }

    private let url: URL
    private let now: @Sendable () -> Date
    private let recordSnapshot: (@Sendable (NetworkCapacitySnapshot) throws -> Bool)?
    private var database: NetworkDemandHistoryDatabase?
    private struct PendingObservation {
        let id: UUID
        let snapshot: NetworkCapacitySnapshot
    }
    private var pending: [PendingObservation] = []
    private var lostSamples = false

    init(url: URL, now: @escaping @Sendable () -> Date,
         recordSnapshot: (@Sendable (NetworkCapacitySnapshot) throws -> Bool)?) {
        self.url = url
        self.now = now
        self.recordSnapshot = recordSnapshot
    }

    private func opened() throws -> NetworkDemandHistoryDatabase {
        if let database { return database }
        let opened = try NetworkDemandHistoryDatabase(url: url, now: now)
        database = opened
        return opened
    }

    func record(_ snapshot: NetworkCapacitySnapshot) throws -> WriteResult {
        // A task cancelled while waiting for the journal never adds its input.
        try Task.checkCancellation()
        let inputID = UUID()
        pending.append(PendingObservation(id: inputID, snapshot: snapshot))
        if pending.count > 120 {
            pending.removeFirst(pending.count - 120)
            lostSamples = true
        }
        var changed = false
        do {
            while let first = pending.first {
                try Task.checkCancellation()
                let accepted: Bool
                if let recordSnapshot { accepted = try recordSnapshot(first.snapshot) }
                else { accepted = try opened().record(first.snapshot) }
                changed = changed || accepted
                pending.removeFirst()
            }
            return WriteResult(changed: changed, failed: false, lostSamples: lostSamples)
        } catch is CancellationError {
            pending.removeAll { $0.id == inputID }
            throw CancellationError()
        } catch {
            if Task.isCancelled {
                pending.removeAll { $0.id == inputID }
                throw CancellationError()
            }
            return WriteResult(changed: changed, failed: true, lostSamples: lostSamples)
        }
    }

    func report(in range: DateInterval) throws -> NetworkDemandHistoryReport {
        try Task.checkCancellation()
        let report = try opened().report(in: range)
        try Task.checkCancellation()
        return report
    }
}

@MainActor
final class NetworkDemandHistoryStore: ObservableObject {
    @Published private(set) var revision: UInt64 = 0
    @Published private(set) var storageError: String?
    private let journal: NetworkDemandJournal
    private let readReport: (@Sendable (DateInterval) async throws -> NetworkDemandHistoryReport)?
    private var writeError: String?
    private var readError: String?

    init(url: URL, now: @escaping @Sendable () -> Date = Date.init,
         recordSnapshot: (@Sendable (NetworkCapacitySnapshot) throws -> Bool)? = nil,
         readReport: (@Sendable (DateInterval) async throws -> NetworkDemandHistoryReport)? = nil) {
        journal = NetworkDemandJournal(url: url, now: now, recordSnapshot: recordSnapshot)
        self.readReport = readReport
    }

    /// Receives an immutable, already accepted public-network observation.
    /// Saving failures never affect the current capacity source.
    func observe(_ snapshot: NetworkCapacitySnapshot) async {
        do {
            try Task.checkCancellation()
            let result = try await journal.record(snapshot)
            try Task.checkCancellation()
            if result.lostSamples {
                writeError = "Some network demand samples could not be saved. Gaps remain unknown."
            } else if result.failed {
                writeError = "Network demand recording needs attention. Bloomy will retry automatically."
            } else {
                writeError = nil
            }
            publishStorageError(journalChanged: result.changed)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            writeError = "Network demand recording needs attention. Bloomy will retry automatically."
            publishStorageError()
        }
    }

    func report(in range: DateInterval) async throws -> NetworkDemandHistoryReport {
        do {
            try Task.checkCancellation()
            let report: NetworkDemandHistoryReport
            if let readReport { report = try await readReport(range) }
            else { report = try await journal.report(in: range) }
            try Task.checkCancellation()
            readError = nil
            publishStorageError()
            return report
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            // Dependencies can return an ordinary error after cancellation.
            // That obsolete result is not a new disk fault.
            guard !Task.isCancelled else { throw CancellationError() }
            readError = "Network demand history could not be read. Refresh to retry."
            publishStorageError()
            throw error
        }
    }

    private func publishStorageError(journalChanged: Bool = false) {
        let next = writeError ?? readError
        let faultChanged = next != storageError
        if faultChanged { storageError = next }
        // Repeated reads, duplicate writes and repeated identical failures do
        // not start another revision-driven history refresh.
        if journalChanged || faultChanged { revision &+= 1 }
    }
}
