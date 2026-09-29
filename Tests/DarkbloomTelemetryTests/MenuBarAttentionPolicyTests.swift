import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Menu-bar attention")
struct MenuBarAttentionPolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000_000)

    @Test("a fresh continuous five-minute idle window shows a quiet manual-nudge prompt")
    func sustainedIdle() {
        var policy = MenuBarAttentionPolicy()
        #expect(policy.attention(for: snapshot(at: start), at: start) == nil)
        for elapsed in stride(from: 0, through: 290, by: 10) {
            let date = start.addingTimeInterval(TimeInterval(elapsed))
            #expect(policy.observe(snapshot(at: date), at: date) == nil)
        }
        let date = start.addingTimeInterval(300)
        let alert = policy.observe(snapshot(at: date), at: date)
        #expect(alert?.title == "Provider idle")
        #expect(alert?.shortText == "Idle 5m")
        #expect(alert?.detail.contains("manual nudge") == true)
        #expect(alert?.idleStartedAt == start)
        #expect(policy.attention(for: snapshot(at: date), at: date.addingTimeInterval(11)) == nil)
    }

    @Test("work, model or process changes, and stale or offline sources clear the prompt")
    func invalidation() {
        let ready = start.addingTimeInterval(300)
        let scenarios: [TelemetrySnapshot] = [
            snapshot(at: ready.addingTimeInterval(10), inferenceActive: true),
            snapshot(at: ready.addingTimeInterval(10), model: "model-b"),
            snapshot(at: ready.addingTimeInterval(10), process: 2),
            snapshot(at: ready.addingTimeInterval(10), stats: .init(tokensGenerated: 1, requestsServed: 0, usageGaps: 0)),
            snapshot(at: ready.addingTimeInterval(10), status: .offline),
            snapshot(at: ready.addingTimeInterval(10), sourceStale: true),
        ]
        for changed in scenarios {
            var policy = MenuBarAttentionPolicy()
            for elapsed in stride(from: 0, through: 300, by: 10) {
                let date = start.addingTimeInterval(TimeInterval(elapsed))
                policy.observe(snapshot(at: date), at: date)
            }
            #expect(policy.attention(for: snapshot(at: ready), at: ready) != nil)
            #expect(policy.observe(changed, at: ready.addingTimeInterval(10)) == nil)
            #expect(policy.attention(for: changed, at: ready.addingTimeInterval(10)) == nil)
        }
    }

    @Test("an old idle daemon state on launch and a polling gap do not create false inactivity")
    func observationWindow() {
        var policy = MenuBarAttentionPolicy()
        let late = start.addingTimeInterval(300)
        #expect(policy.observe(snapshot(at: late), at: late) == nil)
        let gap = late.addingTimeInterval(11)
        #expect(policy.observe(snapshot(at: gap), at: gap) == nil)
        #expect(policy.attention(for: snapshot(at: gap), at: gap) == nil)
    }

    @Test("idle threshold options include Off and reject unknown saved values")
    func preferences() {
        #expect(MenuBarAttentionPolicy.supportedMinutes == [0, 5, 10, 15, 30])
        #expect(MenuBarAttentionPolicy.threshold(for: 0) == nil)
        #expect(MenuBarAttentionPolicy.threshold(for: 10) == 600)
        #expect(MenuBarAttentionPolicy.threshold(for: 99) == 300)
    }

    private func snapshot(
        at date: Date,
        model: String = "model-a",
        process: Int32 = 1,
        stats: ProviderStats = .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
        inferenceActive: Bool = false,
        status: MenuPresentationStatus = .online,
        sourceStale: Bool = false
    ) -> TelemetrySnapshot {
        let state = DaemonState(
            schema: 1, version: "test", currentModel: model, warmModels: [model], stats: stats,
            trust: .init(level: "hardware", status: "online", reason: "test", receivedAt: date.timeIntervalSince1970),
            capacity: nil, slots: [], inferenceActive: inferenceActive,
            startedAt: start.timeIntervalSince1970 - 100, writtenAt: date.timeIntervalSince1970,
            pid: process, processIdentity: .init(pid: process, startTimeMicros: Int64(process)),
            advertisedModels: [model], lifecycle: .init(outcome: .serving, remainingRequests: 0),
            startupPreloadPendingModels: []
        )
        let source: SourceAvailability<DaemonState> = sourceStale
            ? .stale(value: state, capturedAt: date, reason: "fixture")
            : .available(value: state, capturedAt: date)
        return TelemetrySnapshot(
            state: source,
            loadedModels: .unavailable(reason: "fixture"),
            status: .unavailable(reason: "fixture"),
            eventFeed: .unavailable(reason: "fixture"),
            tokenRate: .unavailable(reason: "fixture"),
            diagnostics: [], capturedAt: date, menuStatus: status
        )
    }
}
