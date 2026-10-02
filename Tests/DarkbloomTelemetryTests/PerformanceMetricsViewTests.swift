import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Performance metrics presentation", .serialized)
@MainActor
struct PerformanceMetricsViewTests {
    @Test("coalesced display reads retain every immediate counter observation and stop on cancellation")
    func displayCadencePreservesRecording() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = PerformanceHistoryStore(url: directory.appendingPathComponent("metrics.sqlite3"))
        let now = Date()
        let range = DateInterval(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        var displayedCounts: [Int] = []
        let task = Task {
            await MetricsRefreshLoop.run(interval: .milliseconds(150)) {
                if let rows = try? await history.samples(in: range) { displayedCounts.append(rows.count) }
            }
        }
        defer { task.cancel() }
        for _ in 0..<100 where displayedCounts.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        #expect(displayedCounts == [0])
        for index in 0..<25 {
            await history.observe(metricSample(at: now.addingTimeInterval(Double(index)), counter: Int64(index * 900)))
        }
        for _ in 0..<100 where displayedCounts.last != 25 { try await Task.sleep(for: .milliseconds(5)) }
        task.cancel()
        await task.value
        #expect(displayedCounts.last == 25)
        #expect(displayedCounts.count < 25)
        #expect(try await history.samples(in: range).count == 25)
        let readsAtCancellation = displayedCounts.count
        try await Task.sleep(for: .milliseconds(180))
        #expect(displayedCounts.count == readsAtCancellation)
    }

    @Test("hidden metrics do not schedule minute updates")
    func hiddenMetricsClock() {
        let start = Date(timeIntervalSince1970: 1_000)
        var hidden = MetricsTimelineSchedule(isVisible: false).entries(from: start, mode: .normal)
        #expect(hidden.next() == start)
        #expect(hidden.next() == nil)
        var visible = MetricsTimelineSchedule(isVisible: true).entries(from: start, mode: .normal)
        #expect(visible.next() == start)
        #expect(visible.next() == start.addingTimeInterval(60))
    }

    @Test("cancelled history reads preserve storage health and later reads")
    func cancelledReadIsNotStorageFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = PerformanceHistoryStore(url: directory.appendingPathComponent("metrics.sqlite3"))
        let now = Date()
        await history.observe(metricSample(at: now))
        let range = DateInterval(start: now.addingTimeInterval(-60), end: now.addingTimeInterval(60))
        let task = Task {
            try? await Task.sleep(for: .seconds(60))
            return try await history.samples(in: range)
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("Cancelled read should throw cancellation")
        } catch is CancellationError {} catch { Issue.record("Unexpected storage failure: \(error)") }
        #expect(history.storageError == nil)
        #expect(try await history.samples(in: range).count == 1)
    }

    @Test("cancelled metrics tasks discard analysis instead of publishing obsolete results")
    func cancelledAnalysis() async {
        let now = Date()
        let samples = metricsFixture(now: now)
        let task = Task {
            try? await Task.sleep(for: .seconds(60))
            return await PerformanceMetricsAnalysis.make(
                samples: samples, range: DateInterval(start: now.addingTimeInterval(-86_400), end: now), model: nil
            )
        }
        task.cancel()
        #expect(await task.value == nil)
    }

    @Test("cooperative cancellation stops between analysis passes")
    func cancelsAnalysisPasses() {
        let now = Date()
        let checks = MetricsCancellationChecks()
        let result = PerformanceMetricsSnapshot(
            samples: metricsFixture(now: now),
            range: DateInterval(start: now.addingTimeInterval(-86_400), end: now), model: nil,
            cancellationRequested: { checks.reachedLimit() }
        )
        #expect(checks.count == 4)
        #expect(result.sampleCount == 0)
        #expect(result.ratePoints.isEmpty)
        #expect(result.visits.isEmpty)
    }

    @Test("background analysis preserves recorded measurements and model filtering")
    func backgroundAnalysis() async throws {
        let now = Date()
        let samples = metricsFixture(now: now)
        let range = DateInterval(start: now.addingTimeInterval(-86_400), end: now)
        let expected = PerformanceMetricsSnapshot(samples: samples, range: range, model: "google/gemma-4-26b")
        let result = try #require(await PerformanceMetricsAnalysis.make(samples: samples, range: range, model: "google/gemma-4-26b"))
        #expect(result.sampleCount == expected.sampleCount)
        #expect(result.summary.coveredSeconds == expected.summary.coveredSeconds)
        #expect(result.summary.generatedTokens == expected.summary.generatedTokens)
        #expect(result.visits.map(\.id) == expected.visits.map(\.id))
        #expect(result.ratePoints.map(\.id) == expected.ratePoints.map(\.id))
    }

    @Test("synthetic metrics fit narrow and wide dashboard columns", arguments: [420.0, 780.0, 1_080.0])
    func rendersMetrics(width: Double) async throws {
        let now = Date()
        let samples = metricsFixture(now: now)
        let summary = PerformanceSummary(samples: samples)
        #expect(summary.coveredSeconds > 10_000)
        #expect(summary.activeCoveredSeconds > 0)
        #expect(summary.averageTokenRate != nil)
        #expect((summary.generatedTokens ?? 0) > 0)
        let host = NSHostingController(rootView: PerformanceMetricsContent(
            samples: samples, recordingStartedAt: samples.first?.observedAt, now: now
        ))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: 850))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(350))
        host.view.layoutSubtreeIfNeeded()
        #expect(abs(Double(host.view.frame.width) - width) < 1)
        #expect(host.view.frame.height >= 800)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-metrics-fixture-\(Int(width)).png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }

    @Test("unknown metrics and storage failures render without fabricated measurements")
    func rendersUnknownMetrics() async throws {
        let host = NSHostingController(rootView: PerformanceMetricsContent(
            samples: [], recordingStartedAt: nil, storageError: "Synthetic storage failure", onRefresh: {}
        ))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 420, height: 650))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutSubtreeIfNeeded()
        #expect(abs(Double(host.view.frame.width) - 420) < 1)
    }

    @Test("chart never connects model changes, inactive measurements, stale captures, resets, or missing time")
    func preservesChartGaps() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            metricSample(at: start, counter: 0),
            metricSample(at: start.addingTimeInterval(30), counter: 900),
            metricSample(at: start.addingTimeInterval(60), model: "qwen/qwen3.8-27b", counter: 1_800),
            metricSample(at: start.addingTimeInterval(90), counter: 2_700),
            metricSample(at: start.addingTimeInterval(120), active: false, counter: 3_600),
            metricSample(at: start.addingTimeInterval(150), counter: 4_500),
            metricSample(at: start.addingTimeInterval(180), counter: 0),
            metricSample(at: start.addingTimeInterval(210), quality: .stale, counter: 900),
            metricSample(at: start.addingTimeInterval(240), counter: 1_800),
            metricSample(at: start.addingTimeInterval(450), counter: 2_700),
        ]
        let points = PerformanceMetricsPresentation.ratePoints(samples: samples, model: "google/gemma-4-26b")
        #expect(points.count == 7)
        #expect(points[0].run == points[1].run)
        for (before, after) in zip(points.dropFirst(), points.dropFirst(2)) {
            #expect(before.run != after.run)
        }
    }

    @Test("large speed charts retain actual observations and original gap identifiers")
    func capsChartObservations() {
        let source = (0..<2_000).map { index in
            PerformanceRatePoint(id: UUID(), date: Date(timeIntervalSince1970: Double(index)), rate: Double(index), model: "synthetic/model", run: index < 1_000 ? 1 : 2)
        }
        let displayed = PerformanceMetricsPresentation.reducedRatePoints(source)
        #expect(displayed.count == 600)
        #expect(displayed.first?.id == source.first?.id)
        #expect(displayed.last?.id == source.last?.id)
        #expect(Set(displayed.map(\.run)) == [1, 2])
        #expect(displayed.allSatisfy { point in source.contains { $0.id == point.id && $0.rate == point.rate && $0.run == point.run } })
    }

    @Test("timeline retains phase changes, restarts, and unknown gaps without a model switch")
    func preservesTransitionStates() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            metricSample(at: start, phase: "shadow"),
            metricSample(at: start.addingTimeInterval(30), phase: "transitioning"),
            metricSample(at: start.addingTimeInterval(60), session: "44:1799999990", phase: "transitioning"),
            metricSample(at: start.addingTimeInterval(300), session: "44:1799999990", phase: "transitioning"),
        ]
        let transitions = PerformanceMetricsPresentation.transitions(samples: samples)
        #expect(transitions.count == 5)
        #expect(transitions[1].autopilotPhase == "transitioning")
        #expect(transitions[3].model == nil)
        #expect(transitions[4].model == "google/gemma-4-26b")
    }
}

private final class MetricsCancellationChecks: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    var count: Int { lock.withLock { value } }
    func reachedLimit() -> Bool {
        lock.withLock { value += 1; return value >= 4 }
    }
}

private func metricSample(
    at date: Date, model: String = "google/gemma-4-26b", quality: PerformanceSampleQuality = .current,
    active: Bool = true, counter: Int64 = 0, session: String = "42:1799999990", phase: String? = nil
) -> PerformanceSample {
    PerformanceSample(
        observedAt: date, sourceCapturedAt: date, quality: quality, providerSession: session,
        model: model, residentModels: [model], advertisedModels: [model], inferenceActive: active,
        activeRequests: active ? 1 : 0, tokensPerSecond: 30, tokensGenerated: counter,
        requestsServed: counter / 900, gpuUtilizationPercent: 64, gpuMemoryGB: 21, autopilotPhase: phase
    )
}

private func metricsFixture(now: Date) -> [PerformanceSample] {
    (0..<360).map { index in
        let date = now.addingTimeInterval(Double(index - 359) * 30)
        return PerformanceSample(
            observedAt: date, sourceCapturedAt: date,
            quality: (60..<70).contains(index) ? .stale : .current,
            providerSession: "42:1799999990",
            model: index < 180 ? "google/gemma-4-26b" : "qwen/qwen3.8-27b",
            residentModels: ["google/gemma-4-26b", "qwen/qwen3.8-27b"],
            advertisedModels: ["google/gemma-4-26b", "qwen/qwen3.8-27b"],
            inferenceActive: index % 40 < 30, activeRequests: index % 40 < 30 ? 1 : 0,
            tokensPerSecond: index % 40 < 30 ? Double(24 + index % 16) : nil,
            tokensGenerated: Int64(index * 900), requestsServed: Int64(index / 20),
            gpuUtilizationPercent: Double(40 + index % 40), gpuMemoryGB: 21,
            autopilotPhase: index < 180 ? "shadow" : "active"
        )
    }
}
