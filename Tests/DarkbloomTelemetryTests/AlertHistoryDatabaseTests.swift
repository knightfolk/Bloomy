import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Operational alert history")
struct AlertHistoryDatabaseTests {
    @Test("history and active alert state survive reopening the database")
    func restartPersistence() async throws {
        let url = temporaryDatabaseURL()
        do {
            let database = try AlertHistoryDatabase(url: url, historyLimit: 10)
            try await database.record([
                transition(.providerOffline, .raised, at: 100, duration: 60, observations: 8),
                transition(.modelBackendUnavailable, .raised, at: 110),
            ])
        }

        let reopened = try AlertHistoryDatabase(url: url, historyLimit: 10)
        let history = try await reopened.recentHistory(limit: 10)
        #expect(history.map(\.code) == [.providerOffline, .modelBackendUnavailable])
        #expect(try await reopened.activeAlertCodes() == [.providerOffline, .modelBackendUnavailable])
    }

    @Test("retention keeps the newest bounded records and closes recovered alerts")
    func retentionAndRecovery() async throws {
        let database = try AlertHistoryDatabase(url: temporaryDatabaseURL(), historyLimit: 3)
        try await database.record([
            transition(.providerOffline, .raised, at: 1, duration: 60),
            transition(.providerOffline, .recovered, at: 2),
            transition(.lifecycleTimedOut, .raised, at: 3),
            transition(.lifecycleTimedOut, .suppressed, at: 4),
            transition(.modelUnknown, .raised, at: 5),
        ])

        let history = try await database.recentHistory(limit: 10)
        #expect(history.count == 3)
        #expect(history.map(\.code) == [.lifecycleTimedOut, .lifecycleTimedOut, .modelUnknown])
        #expect(history.map(\.kind) == [.raised, .suppressed, .raised])
        #expect(try await database.activeAlertCodes() == [.modelUnknown])
    }

    @Test("replayed transition batches are idempotent")
    func idempotentReplay() async throws {
        let database = try AlertHistoryDatabase(url: temporaryDatabaseURL(), historyLimit: 10)
        let event = transition(.providerOffline, .raised, at: 10, duration: 45, observations: 4)
        try await database.record([event])
        try await database.record([event])

        #expect(try await database.recentHistory(limit: 10).count == 1)
        #expect(try await database.activeAlertCodes() == [.providerOffline])
    }

    @Test("history database file is private to the current user")
    func privatePermissions() throws {
        let url = temporaryDatabaseURL()
        _ = try AlertHistoryDatabase(url: url)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    private func transition(
        _ code: OperationalAlertCode,
        _ kind: AlertTransitionKind,
        at seconds: Int,
        duration: Int? = nil,
        observations: Int = 1
    ) -> AlertTransition {
        AlertTransition(
            code: code,
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: TimeInterval(seconds)),
            observedDurationSeconds: duration,
            observationCount: observations
        )
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("darkbloom-alert-history-\(UUID().uuidString).sqlite3")
    }
}
