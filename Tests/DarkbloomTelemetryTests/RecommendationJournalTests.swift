import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Recommendation journal")
struct RecommendationJournalTests {
    @Test("stay and consider decisions survive reopen and duplicate recording")
    func persistsAndReplaysDecisions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("recommendations.sqlite3")
        let now = Date(timeIntervalSince1970: 1_000_000)
        let stay = input(at: now, queued: 0)
        let consider = input(at: now.addingTimeInterval(1), queued: 2)

        do {
            let journal = try RecommendationJournal(url: url, limit: 10)
            #expect(try await journal.record(stay).outcome == .stay)
            #expect(try await journal.record(consider).outcome == .consider(modelID: "better"))
            _ = try await journal.record(consider)
            #expect(try await journal.recent(limit: 10).count == 2)
        }

        let reopened = try RecommendationJournal(url: url, limit: 10)
        let entries = try await reopened.replay(limit: 10)
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0.matches })
        #expect(entries.map(\.storedDecision.outcome) == [.stay, .consider(modelID: "better")])
        #expect((try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int) == 0o600)
    }

    @Test("retention caps rows and reads do not prune newer evidence")
    func capsRetention() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try RecommendationJournal(url: directory.appendingPathComponent("recommendations.sqlite3"), limit: 2)
        let now = Date(timeIntervalSince1970: 1_000_000)
        for offset in 0..<4 {
            _ = try await journal.record(input(at: now.addingTimeInterval(Double(offset)), queued: offset))
        }
        let entries = try await journal.recent(limit: 10)
        #expect(entries.count == 2)
        #expect(entries.map(\.input.evaluatedAt) == [now.addingTimeInterval(2), now.addingTimeInterval(3)])
        #expect(try await journal.recent(limit: 1).count == 1)
        #expect(try await journal.recent(limit: 10).count == 2)
    }

    private func input(at now: Date, queued: Int) -> RecommendationInput {
        RecommendationInput(
            evaluatedAt: now, currentModelID: "current", inventoryCapturedAt: now,
            capacityIsDraining: false,
            candidates: [
                .init(
                    modelID: "current", enabled: true, downloaded: true,
                    capacity: .init(capturedAt: now, ready: true, activeRequests: 0, queuedRequests: 0, warmProviders: 1),
                    readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true)
                ),
                .init(
                    modelID: "better", enabled: true, downloaded: true,
                    capacity: .init(capturedAt: now, ready: true, activeRequests: queued > 0 ? 1 : 0, queuedRequests: queued, warmProviders: 1),
                    readiness: .init(capturedAt: now, compatible: true, locallyReady: true, memoryFits: true)
                ),
            ]
        )
    }
}
