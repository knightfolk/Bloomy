import AppKit
@testable import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Provider live throughput", .serialized)
@MainActor
struct ProviderLiveThroughputTests {
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    @Test("idle and missing token progress never become zero throughput")
    func idleAndWaiting() {
        let idle = ProviderLiveThroughput.make(snapshot: snapshot(active: false, rate: 40), now: now)
        #expect(idle.state == .idle)
        #expect(idle.value == nil)
        #expect(idle.reading.stateLabel == "Idle")
        let waiting = ProviderLiveThroughput.make(snapshot: snapshot(active: true, rate: nil), now: now)
        #expect(waiting.state == .waiting)
        #expect(waiting.reading.stateLabel == "Waiting")
        #expect(waiting.value == nil)
        let measured = ProviderLiveThroughput.make(snapshot: snapshot(active: true, rate: 40), now: now)
        #expect(measured.state == .measured)
        #expect(measured.value == 40)
    }

    @Test("expired failed and future observations are never current")
    func freshness() {
        let old = ProviderLiveThroughput.make(snapshot: snapshot(active: true, rate: 40, offset: -11), now: now)
        #expect(old.state == .stale)
        #expect(old.value == 40)
        #expect(old.reading.stateLabel == "Last sample")
        #expect(ProviderLiveThroughput.make(snapshot: snapshot(active: true, rate: 40, offset: 1), now: now).value == nil)
        #expect(ProviderLiveThroughput.make(snapshot: .unavailable(now: now), now: now).state == .unavailable)
        #expect(ProviderLiveThroughput.make(snapshot: snapshot(active: true, rate: .infinity), now: now).state == .waiting)
    }

    @Test("observed provider peak ignores stale rates and resets on process changes")
    func processPeak() {
        var peak = ProviderThroughputPeak()
        peak.observe(snapshot(active: true, rate: 100), now: now)
        peak.observe(snapshot(active: true, rate: 40), now: now)
        #expect(peak.value == 100)
        peak.observe(snapshot(active: true, rate: 500, offset: -20), now: now)
        #expect(peak.value == 100)
        peak.observe(snapshot(active: false, rate: 999, pid: 2), now: now)
        #expect(peak.value == nil)
        peak.observe(snapshot(active: true, rate: 30, pid: 2), now: now)
        #expect(peak.value == 30)
    }

    @Test("full-width popup cards keep consistent geometry across live states", arguments: [526.0, 760.0])
    func horizontalCards(width: Double) {
        for state: ProviderLiveThroughput.State in [.measured, .idle, .waiting, .stale, .unavailable] {
            let live = ProviderLiveThroughput(value: state == .measured || state == .stale ? 124.7 : nil,
                age: state == .stale ? 20 : 1, state: state)
            let card = CompactModelCard(modelID: "EigenLabs/Qwen3.8-27B-4bit-mtp", status: "Serving now",
                metrics: [.init(id: "speed", symbol: "speedometer", value: "91.2", caption: "avg tok/s today")],
                compact: true, compactWidth: width, horizontal: true, liveThroughput: live,
                throughputPeak: 160, activate: {}, swapModel: {}, switchModel: {})
            let size = NSHostingController(rootView: card).sizeThatFits(in: .init(width: width, height: 0))
            #expect(abs(size.width - width) < 0.5)
            #expect(size.height == CompactModelCard.horizontalPopupHeight)
        }
    }

    private func snapshot(active: Bool, rate: Double?, offset: TimeInterval = 0, pid: Int32 = 1) -> TelemetrySnapshot {
        let date = now.addingTimeInterval(offset)
        let daemon = DaemonState(schema: 1, version: "fixture", currentModel: "qwen", warmModels: ["qwen"],
            stats: .init(tokensGenerated: 400, requestsServed: 2, usageGaps: 0), trust: nil, capacity: nil,
            slots: [], inferenceActive: active, startedAt: now.addingTimeInterval(-60).timeIntervalSince1970,
            writtenAt: date.timeIntervalSince1970, pid: pid, processIdentity: .init(pid: pid, startTimeMicros: 100))
        return .init(state: .available(value: daemon, capturedAt: date),
            loadedModels: .unavailable(reason: "fixture"), status: .unavailable(reason: "fixture"),
            eventFeed: .unavailable(reason: "fixture"),
            tokenRate: rate.map { .available(tokensPerSecond: $0, label: "provider") } ?? .unavailable(reason: "No token progress"),
            diagnostics: [], capturedAt: date, menuStatus: .online)
    }
}
