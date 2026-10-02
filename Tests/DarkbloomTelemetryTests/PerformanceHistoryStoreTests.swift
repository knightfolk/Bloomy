import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Performance recording integration", .serialized)
@MainActor
struct PerformanceHistoryStoreTests {
    @Test("completed work between idle polls is recorded immediately")
    func recordsShortWork() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("performance-short-work-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let store = PerformanceHistoryStore(url: root.appendingPathComponent("metrics.sqlite3"))
        for (offset, count) in [(0.0, Int64(4)), (1, 4), (2, 5)] {
            let date = now.addingTimeInterval(offset)
            await store.observe(.init(observedAt: date, sourceCapturedAt: date,
                quality: .current, providerSession: "1:100", model: "gemma",
                residentModels: ["gemma"], inferenceActive: false,
                tokensGenerated: count * 100, requestsServed: count))
        }
        let samples = try await store.samples(in: .init(start: now, end: now.addingTimeInterval(5)))
        #expect(samples.map(\.requestsServed) == [4, 5])
    }

    @Test("inventory waiting records phase boundaries and retains ordinary serving activity")
    func waitingInventoryRecording() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("performance-inventory-wait-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("metrics.sqlite3")
        let now = Date()
        let store = PerformanceHistoryStore(url: url)
        let observations: [(Double, String, Bool)] = [
            (0, "active", true), (1, "waiting_inventory", true),
            (2, "waiting_inventory", false), (3, "active", true), (33, "active", true)
        ]
        for (offset, phase, active) in observations {
            let date = now.addingTimeInterval(offset)
            let telemetry = try snapshot(now: date, active: active, phase: phase)
            #expect(telemetry.state.value?.autopilotPhase == phase)
            let sample = PerformanceSample.capture(telemetry, at: date)
            #expect(sample.isValid)
            #expect(sample.autopilotPhase == phase)
            #expect(sample.inferenceActive == active)
            #expect(sample.tokensPerSecond == (active ? 12 : nil))
            await store.observe(sample)
            #expect(store.storageError == nil)
        }
        let interval = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(34))
        let samples = try await store.samples(in: interval)
        #expect(samples.map(\.autopilotPhase) == observations.map { $0.1 })
        #expect(samples.map(\.requestsServed) == Array(repeating: 2, count: 5))
        #expect(store.revision == 5)
        #expect(try await PerformanceHistoryStore(url: url).samples(in: interval) == samples)
        let summary = PerformanceSummary(samples: samples)
        #expect(summary.coveredSeconds == 33)
        #expect(summary.activeCoveredSeconds == 33)
        #expect(summary.activeSeconds == 31)
        #expect(summary.averageTokenRate == 12)
        #expect(summary.completedRequests == 0)
        #expect(summary.generatedTokens == 0)
    }

    @Test("periodic cadence records state boundaries and survives reopening")
    func cadenceAndReopen() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("performance-store-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("metrics.sqlite3")
        let now = Date()
        let store = PerformanceHistoryStore(url: url)
        for (offset, model) in [(0.0, "qwen"), (1, "qwen"), (2, "gemma"), (31, "gemma"), (32, "gemma")] {
            let date = now.addingTimeInterval(offset)
            await store.observe(.init(observedAt: date, sourceCapturedAt: date,
                                      quality: .current, providerSession: "1:100",
                                      model: model, inferenceActive: false))
        }
        let interval = DateInterval(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(40))
        let samples = try await store.samples(in: interval)
        #expect(samples.map(\.model) == ["qwen", "gemma", "gemma"])
        #expect(store.revision == 3)
        #expect(store.recordingStartedAt != nil)
        #expect(store.storageError == nil)
        let reopened = PerformanceHistoryStore(url: url)
        #expect(try await reopened.samples(in: interval) == samples)
    }

    @Test("failed writes retry with original IDs and visible errors")
    func failureRecovery() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("performance-blocked-\(UUID())")
        try Data("not a directory".utf8).write(to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = PerformanceHistoryStore(url: root.appendingPathComponent("metrics.sqlite3"))
        let now = Date()
        let first = PerformanceSample(observedAt: now)
        await store.observe(first)
        #expect(store.storageError != nil)
        #expect(store.recordingStartedAt == nil)
        await store.observe(.init(observedAt: now.addingTimeInterval(1), model: "gemma"))
        #expect(store.revision == 1) // failed disk is not retried every tick
        try FileManager.default.removeItem(at: root)
        let second = PerformanceSample(observedAt: now.addingTimeInterval(31))
        await store.observe(second)
        #expect(store.storageError == nil)
        let rows = try await store.samples(in: .init(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(40)))
        #expect(rows.map(\.id) == [first.id, second.id])
    }

    @Test("capture excludes secrets and stale readings without fabricating rate")
    func whitelistCapture() throws {
        let now = Date()
        let fresh = try snapshot(now: now, active: true)
        let sample = PerformanceSample.capture(fresh, at: now, gpuPercentage: 80)
        #expect(sample.quality == .current)
        #expect(sample.tokensPerSecond == 12)
        #expect(sample.autopilotPhase == "shadow")
        let text = String(decoding: try JSONEncoder().encode(sample), as: UTF8.self)
        #expect(!text.contains("SECRET"))
        let stale = PerformanceSample.capture(fresh, at: now.addingTimeInterval(16))
        #expect(stale.quality == .stale)
        #expect(stale.tokensPerSecond == nil)
        #expect(stale.requestsServed == nil)
        #expect(stale.inferenceActive == nil)
        #expect(stale.autopilotPhase == nil)
        let idle = PerformanceSample.capture(try snapshot(now: now, active: false), at: now)
        #expect(idle.tokensPerSecond == nil)
        let missing = PerformanceSample.capture(.unavailable(now: now), at: now)
        #expect(missing.quality == .unavailable)
    }

    @Test("path-like model values cannot enter the private measurement journal")
    func pathRedaction() throws {
        let now = Date()
        for model in ["/Users/SECRET/model", "../SECRET/model", "C:/SECRET/model", "model//SECRET"] {
            let daemon = try state(now: now, active: true, phase: "active", model: model)
            let telemetry = TelemetrySnapshot(state: .available(value: daemon, capturedAt: now),
                loadedModels: .unavailable(reason: "unused"), status: .unavailable(reason: "unused"),
                eventFeed: .unavailable(reason: "unused"), tokenRate: .unavailable(reason: "unused"),
                diagnostics: [], capturedAt: now, menuStatus: .online)
            let sample = PerformanceSample.capture(telemetry, at: now)
            #expect(sample.model == nil)
            #expect(!String(decoding: try JSONEncoder().encode(sample), as: UTF8.self).contains("SECRET"))
            #expect(!PerformanceSample(model: model).isValid)
        }
        #expect(PerformanceSample(model: "EigenLabs/Qwen3.8-27B-4bit-mtp").isValid)
        #expect(PerformanceSample(model: "model:tag").isValid)
    }

    @Test("malformed optional Autopilot phase does not break old daemon decoding")
    func optionalAutopilotPhase() throws {
        for phase: Any in ["active", "waiting_inventory", "waiting_inventory_SECRET", "SECRET provider prose", 42, true, ["unexpected": true], NSNull()] {
            let state = try state(now: Date(), active: false, phase: phase)
            let expected = (phase as? String).flatMap { ["active", "waiting_inventory"].contains($0) ? $0 : nil }
            #expect(state.autopilotPhase == expected)
            #expect(state.autopilotPhaseIsUnrecognized == (!(phase is NSNull) && expected == nil))
            #expect(state.currentModel == "gemma")
            let text = String(decoding: try JSONEncoder().encode(PerformanceSample.capture(
                try snapshot(now: Date(), active: false, phase: phase), at: Date())), as: UTF8.self)
            #expect(!text.contains("SECRET"))
        }
    }

    private func snapshot(now: Date, active: Bool, phase: Any = "shadow") throws -> TelemetrySnapshot {
        TelemetrySnapshot(state: .available(value: try state(now: now, active: active, phase: phase), capturedAt: now),
                          loadedModels: .unavailable(reason: "SECRET"), status: .unavailable(reason: "SECRET"),
                          eventFeed: .unavailable(reason: "SECRET"), tokenRate: .available(tokensPerSecond: 12, label: "SECRET"),
                          diagnostics: [], capturedAt: now, menuStatus: .online)
    }

    private func state(now: Date, active: Bool, phase: Any, model: String = "gemma") throws -> DaemonState {
        let json: [String: Any] = [
            "schema": 1, "version": "test", "current_model": model, "warm_models": [model],
            "advertised_models": ["gemma", "qwen"], "pid": 1,
            "stats": ["tokens_generated": 40, "requests_served": 2, "usage_gaps": 0],
            "inference_active": active, "started_at": now.timeIntervalSince1970 - 60,
            // A persisted provider observation precedes its app capture. Avoid
            // epoch roundtrip precision making an exact-equality fixture future.
            "written_at": now.timeIntervalSince1970 - 1,
            "process_identity": ["pid": 1, "start_time_micros": 100],
            "autopilot_phase": phase, "config_path": "SECRET", "coordinator_url": "SECRET"
        ]
        return try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: json))
    }

    @Test("accepted app telemetry records metrics without a dashboard or provider command")
    func monitorIntegration() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("performance-monitor-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let history = PerformanceHistoryStore(url: root.appendingPathComponent("metrics.sqlite3"))
        let monitor = MonitorStore(service: TelemetryService(source: PerformanceUnusedSource()),
                                   initial: .unavailable(now: now), now: { now })
        monitor.performanceHistory = history
        await monitor.accept(try snapshot(now: now, active: true))
        let samples = try await history.samples(in: .init(start: now.addingTimeInterval(-1), end: now.addingTimeInterval(1)))
        #expect(samples.count == 1)
        #expect(samples.first?.model == "gemma")
        #expect(samples.first?.tokensGenerated == 40)
        await monitor.stop()
    }
}

private struct PerformanceUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw PerformanceUnusedError() }
    func readLoadedModels() async throws -> LoadedModelsState { throw PerformanceUnusedError() }
    func readStatus() async throws -> StatusSnapshot { throw PerformanceUnusedError() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw PerformanceUnusedError() }
}
private struct PerformanceUnusedError: Error {}
