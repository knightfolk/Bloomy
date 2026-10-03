import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Performance metrics presentation", .serialized)
@MainActor
struct PerformanceMetricsViewTests {
    @Test("pending period and model analysis cannot change retained chart axes or coverage scope")
    func renderedAnalysisKeepsItsQuery() async throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let read = try await PerformanceMetricsRead.empty.refreshing(endingAt: end, period: .last24Hours) {
            [metricSample(at: end.addingTimeInterval(-30)), metricSample(at: end)]
        }
        let original = metricsQuery(read: read)
        let snapshot = try #require(await PerformanceMetricsAnalysis.make(samples: read.samples, range: original.range, model: nil))
        let shown = PerformanceMetricsRender(snapshot: snapshot, completedQuery: original)
        let pending = metricsQuery(read: read, period: .last7Days, model: "google/gemma-4-26b")
        #expect(shown.query(pending: pending) == original)
        #expect(shown.query(pending: pending).range.duration == 86_400)
        #expect(shown.query(pending: pending).model == nil)
        #expect(shown.snapshot.summary.coveredSeconds == snapshot.summary.coveredSeconds)
        let replacement = try #require(await PerformanceMetricsAnalysis.make(samples: read.samples, range: pending.range, model: pending.model))
        let committed = PerformanceMetricsRender(snapshot: replacement, completedQuery: pending)
        #expect(committed.query(pending: pending) == pending)
        #expect(committed.query(pending: pending).range.duration == 7 * 86_400)
        #expect(committed.query(pending: pending).model == "google/gemma-4-26b")
    }

    @Test("a requested wider period never relabels the last successful narrower read")
    func retainedReadPeriod() async throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [metricSample(at: end.addingTimeInterval(-30)), metricSample(at: end)]
        var read = try await PerformanceMetricsRead.empty.refreshing(endingAt: end, period: .last24Hours) { samples }
        let originalToken = read.token
        for loading in [true, false] {
            let content = PerformanceMetricsContent(samples: read.samples, recordingStartedAt: nil,
                loading: loading, now: end, readToken: read.token, readPeriod: read.period, initialPeriod: .last7Days)
            #expect(content.analysisQuery.period == .last24Hours)
            #expect(content.analysisQuery.range.duration == 86_400)
            #expect(content.retainedPeriodNotice?.contains("last 24 hours") == true)
            #expect(content.retainedPeriodNotice?.contains("7 days") == true)
        }
        do {
            read = try await read.refreshing(endingAt: end.addingTimeInterval(30), period: .last7Days) {
                throw MetricsReadFailure.synthetic
            }
            Issue.record("Failed period read unexpectedly replaced the result")
        } catch MetricsReadFailure.synthetic {}
        #expect(read.period == .last24Hours)
        #expect(read.token == originalToken)
        #expect(read.samples == samples)
        let task = Task {
            try await read.refreshing(endingAt: end.addingTimeInterval(30), period: .last7Days) { [] }
        }
        task.cancel()
        do { read = try await task.value; Issue.record("Cancelled period read replaced the result") }
        catch is CancellationError {}
        #expect(read.period == .last24Hours)
        read = try await read.refreshing(endingAt: end.addingTimeInterval(60), period: .last7Days) { samples }
        let recovered = PerformanceMetricsContent(samples: read.samples, recordingStartedAt: nil,
            now: end, readToken: read.token, readPeriod: read.period, initialPeriod: .last7Days)
        #expect(recovered.analysisQuery.period == .last7Days)
        #expect(recovered.analysisQuery.range.duration == 7 * 86_400)
        #expect(recovered.retainedPeriodNotice == nil)
        #expect(read.token?.generation == 2)
    }

    @Test("an open worked visit is qualified as last observed residency after recording expires")
    func openWorkedVisitIsHistorical() throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [metricSample(at: end.addingTimeInterval(-30), counter: 0), metricSample(at: end, counter: 900)]
        let visits = ModelVisitHistory(samples: samples).visits
        let visit = try #require(visits.last)
        #expect(visit.outcome == .stillLoaded)
        #expect(visit.workEvidence == .observedWork)
        #expect(!MetricsRecordingFreshness.isCurrent(samples.last, at: end.addingTimeInterval(180)))
        #expect(ModelVisitRow(visit: visit).statusText == "Last loaded · worked")
    }

    @Test("successful refreshes invalidate analysis when only a middle observation changes")
    func successfulReadGeneration() async throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            metricSample(at: end.addingTimeInterval(-60), counter: 0),
            metricSample(at: end.addingTimeInterval(-30), counter: 900),
            metricSample(at: end, counter: 1_800),
        ]
        let first = try await PerformanceMetricsRead.empty.refreshing(endingAt: end) { samples }
        var replacement = samples
        replacement[1] = metricSample(at: samples[1].observedAt, quality: .stale, counter: 900, id: samples[1].id)
        let second = try await first.refreshing(endingAt: end) { replacement }
        let firstQuery = metricsQuery(read: first)
        let secondQuery = metricsQuery(read: second)
        #expect(firstQuery.count == secondQuery.count)
        #expect(firstQuery.lastID == secondQuery.lastID)
        #expect(firstQuery != secondQuery)
        #expect(first.token?.generation == 1)
        #expect(second.token?.generation == 2)
        let before = try #require(await PerformanceMetricsAnalysis.make(samples: first.samples, range: firstQuery.range, model: nil))
        let after = try #require(await PerformanceMetricsAnalysis.make(samples: second.samples, range: secondQuery.range, model: nil))
        #expect(before.summary.coveredSeconds == 60)
        #expect(after.summary.coveredSeconds == 0)
        #expect(before.ratePoints.count == 3)
        #expect(after.ratePoints.count == 2)
        let unchanged = try await second.refreshing(endingAt: end) { replacement }
        #expect(unchanged.token?.generation == 3)
        #expect(metricsQuery(read: unchanged) != secondQuery)
    }

    @Test("failed and cancelled refreshes retain the preceding successful read")
    func unsuccessfulReadPreservesGeneration() async throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [metricSample(at: end)]
        var read = try await PerformanceMetricsRead.empty.refreshing(endingAt: end) { samples }
        let token = read.token
        do {
            read = try await read.refreshing(endingAt: end.addingTimeInterval(30)) {
                throw MetricsReadFailure.synthetic
            }
            Issue.record("A failed read must not produce a successful result")
        } catch MetricsReadFailure.synthetic {} catch { Issue.record("Unexpected failure: \(error)") }
        let task = Task {
            try await read.refreshing(endingAt: end.addingTimeInterval(60)) { [] }
        }
        task.cancel()
        do {
            read = try await task.value
            Issue.record("A cancelled read must not produce a successful result")
        } catch is CancellationError {} catch { Issue.record("Unexpected failure: \(error)") }
        #expect(read.token == token)
        #expect(read.samples == samples)
    }

    @Test("freshness label time does not move the successful read's analysis window")
    func labelClockDoesNotInvalidateAnalysis() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [metricSample(at: end)]
        let token = PerformanceMetricsReadToken(generation: 1, endingAt: end)
        let initial = PerformanceMetricsContent(samples: samples, recordingStartedAt: nil, now: end, readToken: token)
        let later = PerformanceMetricsContent(samples: samples, recordingStartedAt: nil, now: end.addingTimeInterval(120), readToken: token)
        #expect(initial.analysisQuery == later.analysisQuery)
        #expect(later.analysisQuery.range.end == end)
        #expect(later.now.timeIntervalSince(samples[0].observedAt) > 90)
        var synthetic = PerformanceMetricsContent(samples: samples, recordingStartedAt: nil, now: end)
        let syntheticQuery = synthetic.analysisQuery
        synthetic.now = end.addingTimeInterval(120)
        #expect(synthetic.analysisQuery == syntheticQuery)
        #expect(synthetic.analysisQuery.range.end == end)
    }

    @Test("period, model, visibility and successful reads independently key analysis")
    func analysisQueryChanges() {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let read = PerformanceMetricsRead(samples: [metricSample(at: end)], token: PerformanceMetricsReadToken(generation: 1, endingAt: end))
        let query = metricsQuery(read: read)
        let week = metricsQuery(read: read, period: .last7Days)
        #expect(week != query)
        #expect(week.range.duration == 7 * 86_400)
        #expect(metricsQuery(read: read, model: "google/gemma-4-26b") != query)
        let hidden = metricsQuery(read: read, isVisible: false)
        #expect(hidden != query)
        #expect(metricsQuery(read: read, isVisible: true) != hidden)
        #expect(hidden.range == query.range)
    }

    @Test("value-driven content includes newer input observations without following label time")
    func newerValueDrivenObservation() async throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let first = metricSample(at: end, counter: 0)
        let newer = metricSample(at: end.addingTimeInterval(30), counter: 900)
        let initial = PerformanceMetricsContent(samples: [first], recordingStartedAt: nil, now: end)
        var updated = PerformanceMetricsContent(samples: [first, newer], recordingStartedAt: nil, now: end)
        let updatedQuery = updated.analysisQuery
        #expect(updatedQuery != initial.analysisQuery)
        #expect(updatedQuery.range.end == newer.observedAt)
        updated.now = end.addingTimeInterval(120)
        #expect(updated.analysisQuery == updatedQuery)
        let result = try #require(await PerformanceMetricsAnalysis.make(
            samples: updated.samples, range: updatedQuery.range, model: nil
        ))
        #expect(result.sampleCount == 2)
        #expect(result.latest?.id == newer.id)
        #expect(result.summary.coveredSeconds == 30)
        #expect(result.ratePoints.last?.id == newer.id)
    }

    @Test("rolling read windows clip observations and retain visit boundary evidence")
    func rollingReadWindow() async throws {
        let end = Date(timeIntervalSince1970: 1_800_000_000)
        let start = end.addingTimeInterval(-86_400)
        let samples = [-30.0, 30, 60].map { metricSample(at: start.addingTimeInterval($0)) }
            + [-30.0, 0, 30].map { metricSample(at: end.addingTimeInterval($0)) }
        let read = try await PerformanceMetricsRead.empty.refreshing(endingAt: end) { samples }
        let query = metricsQuery(read: read)
        let result = try #require(await PerformanceMetricsAnalysis.make(samples: read.samples, range: query.range, model: nil))
        #expect(result.sampleCount == 4)
        #expect(result.summary.coveredSeconds == 60)
        #expect(result.ratePoints.allSatisfy { query.range.contains($0.date) })
        #expect(result.latest?.observedAt == end)
        #expect(result.visits.first?.observedStart == start)
        #expect(result.visits.first?.isStartTruncated == true)
        #expect(result.visits.last?.observedEnd == end)
        #expect(result.visits.last?.isEndTruncated == true)
    }

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

private enum MetricsReadFailure: Error { case synthetic }

private func metricsQuery(
    read: PerformanceMetricsRead, period: PerformanceMetricsPeriod = .last24Hours,
    model: String? = nil, isVisible: Bool = true
) -> PerformanceMetricsQuery {
    PerformanceMetricsQuery(
        period: period, model: model, count: read.samples.count, lastID: read.samples.last?.id,
        readToken: read.token!, isVisible: isVisible
    )
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
    active: Bool = true, counter: Int64 = 0, session: String = "42:1799999990", phase: String? = nil,
    id: UUID = UUID()
) -> PerformanceSample {
    PerformanceSample(
        id: id, observedAt: date, sourceCapturedAt: date, quality: quality, providerSession: session,
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
