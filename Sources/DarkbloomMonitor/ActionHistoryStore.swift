import Foundation
import Combine
import DarkbloomTelemetry

/// Durable, bounded metadata only. Recording failure never blocks provider work.
@MainActor
final class ActionHistoryStore: ObservableObject {
    @Published private(set) var events: [ActionHistoryEvent] = []
    @Published private var persistentStorageError: String?
    @Published private var ingestionError: String?
    var storageError: String? { persistentStorageError ?? ingestionError }
    @Published private(set) var recordingStartedAt: Date?
    private var database: ActionHistoryDatabase?
    private var unresolvedJobIDs: Set<UUID> = []
    private let now: () -> Date

    init(url: URL, now: @escaping () -> Date = Date.init) {
        self.now = now
        do {
            database = try ActionHistoryDatabase(url: url)
            let previous = try database!.recent(limit: 5_000)
            for event in previous where event.outcome == .started {
                try database!.updateOutcome(id: event.id, outcome: .interrupted, reason: .interrupted)
            }
            recordingStartedAt = (try? FileManager.default.attributesOfItem(atPath: url.path)[.creationDate]) as? Date ?? now()
        } catch {
            database = nil
            persistentStorageError = "Action history could not be opened. New activity is not being saved."
        }
        refresh()
    }

    @discardableResult
    func record(action: ActionHistoryAction, trigger: ActionHistoryTrigger,
                outcome: ActionHistoryOutcome, model: String? = nil,
                reason: ActionHistoryReason? = nil, correlationID: UUID? = nil) -> UUID {
        let id = UUID()
        guard let database else { return id }
        do {
            try database.record(.init(id: id, occurredAt: now(), action: action,
                trigger: trigger, outcome: outcome, model: model, reason: reason,
                correlationID: correlationID))
            refresh()
        } catch { persistentStorageError = "Action history could not be saved. Some activity may be missing." }
        return id
    }

    func finish(_ id: UUID?, outcome: ActionHistoryOutcome, reason: ActionHistoryReason? = nil) {
        guard let id, let database else { return }
        do {
            try database.updateOutcome(id: id, outcome: outcome, reason: reason)
            refresh()
        } catch { persistentStorageError = "An action outcome could not be saved. Its result may be incomplete." }
    }

    /// Account-wide reported earnings, not inferred requests or nudge attribution.
    func ingest(_ account: AccountEarningsResponse, capturedAt: Date) async {
        guard let database else { return }
        let result = await Task.detached(priority: .utility) {
            var saved: Set<UUID> = []
            var failed: Set<UUID> = []
            for row in account.earnings where row.createdAt <= capturedAt
                && row.createdAt >= capturedAt.addingTimeInterval(-30 * 86_400)
                && row.promptTokens >= 0 && row.completionTokens >= 0 && row.amountMicroUSD >= 0 {
                let id = ActionHistoryEvent.deterministicID(namespace: account.accountID, key: String(row.id))
                do { try database.record(.init(id: id, occurredAt: row.createdAt, updatedAt: capturedAt,
                    action: row.model == "base_reward" ? .baseReward : .job,
                    trigger: .provider, outcome: .succeeded, model: row.model,
                    job: .init(earningID: row.id, promptTokens: Int64(row.promptTokens),
                        completionTokens: Int64(row.completionTokens), amountMicroUSD: row.amountMicroUSD)))
                    saved.insert(id)
                } catch { failed.insert(id) }
            }
            return (saved: saved, failed: failed)
        }.value
        unresolvedJobIDs.subtract(result.saved)
        unresolvedJobIDs.formUnion(result.failed)
        ingestionError = unresolvedJobIDs.isEmpty ? nil : "Some reported job records could not be saved. History may be incomplete."
        refresh()
    }

    func refresh() {
        guard let database else { return }
        do { events = try database.recent(limit: 5_000) }
        catch { persistentStorageError = "Action history could not be read. Existing records have been retained." }
    }
}
