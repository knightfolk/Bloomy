import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Recorded performance trend charts")
struct PerformanceTrendChartTests {
    let end = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("five shared visible ranges keep their exact successful read intervals")
    func ranges() {
        #expect(PerformanceMetricsPeriod.allCases.map(\.seconds) == [3_600, 7_200, 28_800, 43_200, 86_400])
        #expect(PerformanceMetricsPeriod.allCases.map(\.pickerTitle) == ["1h", "2h", "8h", "12h", "24h"])
        for period in PerformanceMetricsPeriod.allCases {
            #expect(period.range(endingAt: end).duration == period.seconds)
            #expect(period.range(endingAt: end).end == end)
        }
    }

    @Test("actual idle zero survives while missing stale and bad captures split measured lines")
    func gaps() {
        let samples = [
            sample(0, gpu: 0), sample(30, gpu: 12), sample(60, gpu: nil),
            sample(90, gpu: 20), sample(120, quality: .stale, gpu: 99),
            sample(150, gpu: 21), sample(180, gpu: 22, captureOffset: -120), sample(210, gpu: 23),
        ]
        let trend = PerformanceTrend(metric: .gpu, samples: samples)
        #expect(trend.points.map(\.value) == [0, 12, 20, 21, 23])
        #expect(trend.points.map(\.run) == [1, 1, 2, 3, 4])
        #expect(trend.status(at: end.addingTimeInterval(210), storageError: nil) == "Provider idle · measured")
        #expect(PerformanceMetricsPresentation.ratePoints(samples: samples).isEmpty)
    }

    @Test("model changes session changes counter resets and long gaps never connect")
    func boundaries() {
        let samples = [sample(0), sample(30), sample(60, model: "other"), sample(90),
            sample(120, session: "2:3"), sample(150, session: "2:3", counter: 10),
            sample(180, session: "2:3", counter: 0), sample(300, session: "2:3")]
        let trend = PerformanceTrend(metric: .power, samples: samples)
        #expect(trend.points.map(\.run) == [1, 1, 2, 3, 4, 4, 5, 6])
        let filtered = PerformanceTrend(metric: .memory, samples: samples, model: "model")
        #expect(filtered.points.count == 7)
        #expect(filtered.points[1].run != filtered.points[2].run)
    }

    @Test("one observation unavailable recording and stale recording have distinct states")
    func states() {
        let one = PerformanceTrend(metric: .gpu, samples: [sample(0)])
        #expect(one.status(at: end, storageError: nil) == "Insufficient history · one measurement")
        #expect(one.status(at: end.addingTimeInterval(91), storageError: nil) == "Stale measurements")
        #expect(one.status(at: end, storageError: "read failed") == "History unavailable · last known")
        let missing = PerformanceTrend(metric: .gpu, samples: [sample(0, gpu: nil)])
        #expect(missing.points.isEmpty)
        #expect(missing.status(at: end, storageError: nil) == "Current measurement unavailable")
        let unavailable = PerformanceTrend(metric: .gpu, samples: [sample(0, quality: .unavailable)])
        #expect(unavailable.points.isEmpty)
        #expect(unavailable.status(at: end, storageError: nil) == "Waiting for provider observation")
        #expect(PerformanceTrend(metric: .gpu, samples: []).status(at: end, storageError: nil) == "Insufficient history")
    }

    @Test("large windows stay bounded preserve original values and do not invent gap data")
    func boundedPoints() {
        let samples = (0..<2_000).map { sample(Double($0) * 30, gpu: Double($0 % 100)) }
        let trend = PerformanceTrend(metric: .gpu, samples: samples)
        #expect(trend.measurementCount == 2_000)
        #expect(trend.points.count == 600)
        #expect(trend.wasReduced)
        #expect(trend.points.first?.id == samples.first?.id)
        #expect(trend.points.last?.id == samples.last?.id)
        let saved = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        #expect(trend.points.allSatisfy { saved[$0.id]?.gpuUtilizationPercent == $0.value })
    }

    @Test("a failed wider read retains chart points range and end time together")
    @MainActor
    func failedReadRetainsScope() async throws {
        var read = try await PerformanceMetricsRead.empty.refreshing(endingAt: end, period: .lastHour) {
            [sample(-30), sample(0)]
        }
        let token = try #require(read.token)
        let query = PerformanceMetricsQuery(period: .lastHour, model: nil, count: read.samples.count,
            lastID: read.samples.last?.id, readToken: token, isVisible: true)
        let snapshot = try #require(await PerformanceMetricsAnalysis.make(samples: read.samples, range: query.range, model: nil))
        let rendered = PerformanceMetricsRender(snapshot: snapshot, completedQuery: query)
        do {
            read = try await read.refreshing(endingAt: end.addingTimeInterval(30), period: .last12Hours) { throw ChartReadError.failed }
            Issue.record("Failed read unexpectedly replaced retained data")
        } catch ChartReadError.failed {}
        let pending = PerformanceMetricsQuery(period: .last12Hours, model: nil, count: read.samples.count,
            lastID: read.samples.last?.id, readToken: token, isVisible: true)
        #expect(rendered.query(pending: pending).range.duration == 3_600)
        #expect(rendered.query(pending: pending).range.end == end)
        #expect(rendered.snapshot.trends.first?.measurementCount == 2)
        #expect(read.token == token)
        #expect(read.period == .lastHour)
    }

    @Test("dense chart symbols are derived separately from unchanged line observations and summaries")
    func denseSymbolsPreserveMeasurements() {
        let samples = (0..<300).map { index in
            let date = end.addingTimeInterval(Double(index) * 30)
            return PerformanceSample(observedAt: date, sourceCapturedAt: date,
                quality: .current, providerSession: "1:2", model: "model", residentModels: ["model"],
                inferenceActive: true, tokensPerSecond: 45 + Double(index % 5),
                tokensGenerated: Int64(index * 1_500), requestsServed: Int64(index),
                gpuUtilizationPercent: Double(index % 100), gpuMemoryGB: 4, powerWatts: 20)
        }
        let range = DateInterval(start: end, duration: 86_400)
        let snapshot = PerformanceMetricsSnapshot(samples: samples, range: range, model: nil)
        let expectedRates = PerformanceMetricsPresentation.ratePoints(samples: samples)
        #expect(snapshot.ratePoints.map(\.id) == expectedRates.map(\.id))
        #expect(snapshot.ratePoints.map(\.rate) == expectedRates.map(\.rate))
        #expect(snapshot.ratePoints.map(\.run) == expectedRates.map(\.run))
        #expect(snapshot.rateMarkerIDs.count < 60)
        #expect(snapshot.rateSingletonIDs.isEmpty)
        #expect(snapshot.rateMarkerIDs.isSubset(of: Set(expectedRates.map(\.id))))
        let expectedSummary = PerformanceSummary(samples: samples)
        #expect(snapshot.summary == expectedSummary)
        for trend in snapshot.trends {
            let expected = PerformanceTrend(metric: trend.metric, samples: samples, range: range)
            #expect(trend.points.count == samples.count)
            #expect(trend.points.map(\.id) == expected.points.map(\.id))
            #expect(trend.points.map(\.value) == expected.points.map(\.value))
            #expect(trend.markerIDs.count < 60)
            #expect(trend.markerIDs.isSubset(of: Set(trend.points.map(\.id))))
            #expect(trend.measurementCount == samples.count)
        }
    }

    private func sample(_ offset: Double, quality: PerformanceSampleQuality = .current,
                        gpu: Double? = 10, model: String = "model", session: String = "1:2",
                        counter: Int64 = 0, captureOffset: Double = 0) -> PerformanceSample {
        .init(observedAt: end.addingTimeInterval(offset), sourceCapturedAt: end.addingTimeInterval(offset + captureOffset),
            quality: quality, providerSession: session, model: model, inferenceActive: false,
            tokensGenerated: counter, requestsServed: counter, gpuUtilizationPercent: gpu, gpuMemoryGB: 4, powerWatts: 20)
    }
}

private enum ChartReadError: Error { case failed }

@Suite("Single performance chart refresh stream", .serialized)
@MainActor
struct PerformanceMetricsRevisionRefreshTests {
    @Test("a mounted compact chart reads on opening and suspends recorder events while hidden")
    func compactVisibility() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let probe = CompactChartReadProbe()
        let history = PerformanceHistoryStore(url: directory.appendingPathComponent("metrics.sqlite"),
            readSamples: { _ in await probe.read(); return [] })
        let host = NSHostingController(rootView: PerformanceMetricsView(history: history, isVisible: false, compact: true))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 400, height: 500))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(await probe.count == 0)
        host.rootView = PerformanceMetricsView(history: history, isVisible: true, compact: true)
        for _ in 0..<100 where await probe.count == 0 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(await probe.count == 1)
        host.rootView = PerformanceMetricsView(history: history, isVisible: false, compact: true)
        try await Task.sleep(for: .milliseconds(50))
        let now = Date()
        await history.observe(.init(observedAt: now, sourceCapturedAt: now, quality: .current,
            providerSession: "1:2", model: "model", inferenceActive: false, tokensGenerated: 0, requestsServed: 0))
        #expect(history.revision == 1)
        try await Task.sleep(for: .milliseconds(100))
        #expect(await probe.count == 1)
        host.rootView = PerformanceMetricsView(history: nil, isVisible: false, compact: true)
    }

    @Test("recorder bursts coalesce into one serial read then wait without polling")
    func burstAndCancellation() async throws {
        let events = PerformanceMetricsRefreshEvents()
        var count = 0
        let task = Task {
            await PerformanceMetricsRevisionRefreshLoop.run(events: events, cadence: .seconds(10), minimumSpacing: .milliseconds(80)) {
                count += 1
            }
        }
        defer { task.cancel() }
        for _ in 0..<100 where count == 0 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(count == 1)
        for _ in 0..<100 { events.requestRefresh() }
        try await Task.sleep(for: .milliseconds(20))
        #expect(count == 1)
        for _ in 0..<100 where count < 2 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(count == 2)
        try await Task.sleep(for: .milliseconds(120))
        #expect(count == 2)
        task.cancel()
        await task.value
        events.requestRefresh()
        try await Task.sleep(for: .milliseconds(100))
        #expect(count == 2)
    }

    @Test("a visible fallback retries without a new recorder revision")
    func fallback() async throws {
        let events = PerformanceMetricsRefreshEvents()
        var count = 0
        let task = Task {
            await PerformanceMetricsRevisionRefreshLoop.run(events: events, cadence: .milliseconds(80), minimumSpacing: .milliseconds(10)) { count += 1 }
        }
        defer { task.cancel() }
        for _ in 0..<100 where count < 2 { try await Task.sleep(for: .milliseconds(2)) }
        #expect(count >= 2)
        task.cancel()
        await task.value
        let stoppedCount = count
        try await Task.sleep(for: .milliseconds(100))
        #expect(count == stoppedCount)
    }

    @Test("an obsolete screen cannot finish or trigger the replacement connection")
    func connectionOwnership() async throws {
        let events = PerformanceMetricsRefreshEvents()
        let old = events.connect()
        let replacement = events.connect()
        events.stop(connection: old.id)
        events.requestRefresh(connection: old.id)
        var iterator = replacement.stream.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        events.requestRefresh(connection: replacement.id)
        #expect(await iterator.next() != nil)
        events.stop(connection: replacement.id)
        #expect(await iterator.next() == nil)
    }
}

private actor CompactChartReadProbe {
    private(set) var count = 0
    func read() { count += 1 }
}
