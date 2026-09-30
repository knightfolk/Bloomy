import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Action history rendering", .serialized)
@MainActor
struct ActionHistoryViewTests {
    @Test("account actions, skipped nudges, jobs, and rewards fit a 900 by 650 window")
    func renderHistory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("action-history-view-\(UUID().uuidString)", isDirectory: true)
        let databaseURL = directory.appendingPathComponent("actions.sqlite3")
        defer { try? FileManager.default.removeItem(at: directory) }

        let now = Date()
        let store = ActionHistoryStore(url: databaseURL, now: { now })
        store.record(action: .nudge, trigger: .manual, outcome: .succeeded,
                     model: "gemma-4-26b-qat-4bit", reason: .completed)
        store.record(action: .nudge, trigger: .automatic, outcome: .skipped,
                     model: "gemma-4-26b-qat-4bit", reason: .workRecorded)

        let earnings = [
            AccountEarning(id: 4101, providerID: "fixture", providerKey: "", model: "gemma-4-26b-qat-4bit",
                           amountMicroUSD: 1_250, promptTokens: 24, completionTokens: 9,
                           createdAt: now.addingTimeInterval(-60)),
            AccountEarning(id: 4102, providerID: "fixture", providerKey: "", model: "base_reward",
                           amountMicroUSD: 75, promptTokens: 0, completionTokens: 0,
                           createdAt: now.addingTimeInterval(-30)),
        ]
        await store.ingest(AccountEarningsResponse(
            accountID: "render-fixture", earnings: earnings, count: 2,
            historyLimit: 1_000, recentCount: earnings.count
        ), capturedAt: now)

        #expect(store.events.count == 4)
        #expect(Set(store.events.map(\.action)) == [.nudge, .job, .baseReward])

        let host = NSHostingController(
            rootView: ActionHistoryView(store: store, selectedID: store.events.first(where: { $0.action == .job })?.id)
                .frame(width: 900, height: 650, alignment: .topLeading)
        )
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 900, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.view.layoutSubtreeIfNeeded()
        #expect(host.view.frame.width <= 900)
        #expect(host.view.frame.height <= 650)

        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-action-history-900x650.png"))
    }
}
