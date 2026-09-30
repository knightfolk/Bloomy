import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Action history integration")
@MainActor
struct ActionHistoryStoreTests {
    private func location() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("history-\(UUID())/actions.sqlite3")
    }

    @Test("unfinished attempts become interrupted after reopening")
    func interruptedAttempt() throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = ActionHistoryStore(url: url)
        let id = first.record(action: .nudge, trigger: .automatic, outcome: .started, model: "gemma")
        let reopened = ActionHistoryStore(url: url)
        #expect(reopened.events.first(where: { $0.id == id })?.outcome == .interrupted)
        #expect(reopened.storageError == nil)
    }

    @Test("reported jobs and base rewards deduplicate without storing provider keys")
    func reportedJobs() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ActionHistoryStore(url: url)
        let now = Date()
        let rows = ["gemma", "base_reward"].enumerated().map { index, model in
            AccountEarning(id: Int64(index + 1), providerID: "private-provider",
                providerKey: "SECRET-PROVIDER-KEY", model: model, amountMicroUSD: 25,
                promptTokens: 3, completionTokens: 8, createdAt: now.addingTimeInterval(-10))
        }
        let account = AccountEarningsResponse(accountID: "private-account", earnings: rows,
            count: 2, historyLimit: 1000, recentCount: 2)
        await store.ingest(account, capturedAt: now)
        await store.ingest(account, capturedAt: now)
        #expect(store.events.count == 2)
        #expect(Set(store.events.map(\.action)) == [.job, .baseReward])
        #expect(store.events.allSatisfy { $0.job?.completionTokens == 8 })
        #expect(store.storageError == nil)
        let encoded = try JSONEncoder().encode(store.events)
        let text = String(decoding: encoded, as: UTF8.self)
        #expect(!text.contains("SECRET-PROVIDER-KEY"))
        #expect(!text.contains("private-provider"))
        #expect(!text.contains("private-account"))
    }

    @Test("a successful job retry clears only the job ingestion warning")
    func ingestionRecovery() async throws {
        let url = location()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let store = ActionHistoryStore(url: url)
        let now = Date()
        func account(model: String) -> AccountEarningsResponse {
            .init(accountID: "test-account", earnings: [
                .init(id: 42, providerID: "test-provider", providerKey: "unused",
                      model: model, amountMicroUSD: 56, promptTokens: 3,
                      completionTokens: 8, createdAt: now.addingTimeInterval(-10))
            ], count: 1, historyLimit: 1000, recentCount: 1)
        }
        await store.ingest(account(model: "invalid model"), capturedAt: now)
        #expect(store.storageError != nil)
        await store.ingest(.init(accountID: "test-account", earnings: [], count: 0,
                                 historyLimit: 1000, recentCount: 0), capturedAt: now)
        #expect(store.storageError != nil)
        await store.ingest(account(model: "gemma"), capturedAt: now)
        #expect(store.storageError == nil)
        #expect(store.events.count == 1)

        store.record(action: .nudge, trigger: .manual, outcome: .started, model: "invalid model")
        let actionError = store.storageError
        #expect(actionError != nil)
        await store.ingest(account(model: "gemma"), capturedAt: now)
        #expect(store.storageError == actionError)
    }

    @Test("storage errors remain visible instead of claiming recording succeeded")
    func unavailableStorage() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-file-\(UUID())")
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ActionHistoryStore(url: root.appendingPathComponent("actions.sqlite3"))
        store.record(action: .nudge, trigger: .manual, outcome: .started)
        #expect(store.storageError != nil)
        #expect(store.events.isEmpty)
    }
}
