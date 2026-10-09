import Charts
import DarkbloomTelemetry
import Foundation
import SwiftUI

enum PerformanceTrendMetric: String, CaseIterable, Identifiable, Sendable {
    case gpu, memory, power
    var id: Self { self }
    var title: String {
        switch self {
        case .gpu: "GPU use"
        case .memory: "Provider GPU memory"
        case .power: "Mac power"
        }
    }
    var unit: String {
        switch self {
        case .gpu: "%"
        case .memory: "GB"
        case .power: "W"
        }
    }
    var scope: String { self == .memory ? "Reported by the provider" : "Whole Mac · includes other apps" }
    func value(in sample: PerformanceSample) -> Double? {
        let value: Double? = switch self {
        case .gpu: sample.gpuUtilizationPercent
        case .memory: sample.gpuMemoryGB
        case .power: sample.powerWatts
        }
        guard let value, value.isFinite, value >= 0,
              value <= (self == .gpu ? 100 : self == .memory ? 1_000_000 : 10_000_000) else { return nil }
        return value
    }
}

struct PerformanceTrendPoint: Identifiable, Sendable {
    let id: UUID
    let date: Date
    let value: Double
    let run: Int
}

/// Derived once in the screen's background analysis, never in a chart body.
/// Points are recorded observations: missing values do not become zero or idle.
struct PerformanceTrend: Identifiable, Sendable {
    let metric: PerformanceTrendMetric
    let points: [PerformanceTrendPoint]
    let measurementCount: Int
    let latest: PerformanceSample?
    let wasReduced: Bool
    let upperBound: Double
    var id: PerformanceTrendMetric { metric }

    init(metric: PerformanceTrendMetric, samples: [PerformanceSample], model: String? = nil, limit: Int = 600) {
        self.metric = metric
        latest = samples.last { model == nil || $0.model == model }
        var points: [PerformanceTrendPoint] = []
        var previous: PerformanceSample?
        var run = 0
        var maximum = 0.0
        for sample in samples {
            guard model == nil || sample.model == model,
                  sample.quality == .current,
                  let value = metric.value(in: sample),
                  let capture = sample.sourceCapturedAt,
                  (0...90).contains(sample.observedAt.timeIntervalSince(capture)) else {
                previous = nil
                continue
            }
            let continuous = previous.map { before in
                let delta = sample.observedAt.timeIntervalSince(before.observedAt)
                return delta > 0 && delta <= 90
                    && before.providerSession != nil && before.providerSession == sample.providerSession
                    && before.model == sample.model
                    && !(before.tokensGenerated.flatMap { first in sample.tokensGenerated.map { $0 < first } } ?? false)
                    && !(before.requestsServed.flatMap { first in sample.requestsServed.map { $0 < first } } ?? false)
                    && before.sourceCapturedAt.map { capture > $0 && capture.timeIntervalSince($0) <= 90 } == true
            } ?? false
            if !continuous { run += 1 }
            points.append(.init(id: sample.id, date: sample.observedAt, value: value, run: run))
            maximum = max(maximum, value)
            previous = sample
        }
        measurementCount = points.count
        // A fixed budget includes actual observations and preserves run IDs;
        // reduction never joins unknown boundaries into a continuous run.
        let budget = max(2, limit)
        wasReduced = points.count > budget
        if wasReduced {
            self.points = (0..<budget).map { index in
                points[Int(Double(index) * Double(points.count - 1) / Double(budget - 1))]
            }
        } else { self.points = points }
        upperBound = metric == .gpu ? 100 : max(1, maximum * 1.1)
    }

    func status(at now: Date, storageError: String?) -> String {
        if storageError != nil { return points.isEmpty ? "History unavailable" : "History unavailable · last known" }
        guard let latest else { return "Insufficient history" }
        guard MetricsRecordingFreshness.isCurrent(latest, at: now) else {
            return latest.quality == .unavailable ? "Waiting for provider observation" : "Stale measurements"
        }
        guard metric.value(in: latest) != nil, points.last?.id == latest.id else { return "Current measurement unavailable" }
        if measurementCount == 0 { return "Measurement unavailable" }
        if measurementCount == 1 { return "Insufficient history · one measurement" }
        if latest.inferenceActive == false { return "Provider idle · measured" }
        return "Recorded measurements"
    }
}

/// Reusable with a precomputed screen summary; it never owns a history reader.
struct PerformanceTrendChart: View {
    let trend: PerformanceTrend
    let range: DateInterval
    var now = Date()
    var storageError: String?
    var height: CGFloat = 155

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(trend.metric.title).font(.headline)
                Spacer(minLength: 8)
                Text(trend.status(at: now, storageError: storageError))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if trend.points.isEmpty {
                Text("No usable recorded \(trend.metric.title.lowercased()) measurements in this period.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: height)
            } else {
                Chart(trend.points) { point in
                    LineMark(x: .value("Observed", point.date), y: .value(trend.metric.unit, point.value),
                        series: .value("Measured run", point.run))
                        .interpolationMethod(.linear)
                        .lineStyle(StrokeStyle(lineWidth: 1.8))
                    PointMark(x: .value("Observed", point.date), y: .value(trend.metric.unit, point.value))
                        .symbolSize(12)
                }
                .foregroundStyle(Color.accentColor)
                .chartXScale(domain: range.start...range.end)
                .chartYScale(domain: 0...trend.upperBound)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .chartYAxis { AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) }
                .chartYAxisLabel(trend.metric.unit)
                .chartLegend(.hidden)
                .frame(height: height)
            }
            HStack {
                Text(trend.metric.scope)
                Spacer(minLength: 8)
                Text("\(trend.measurementCount.formatted()) measurements")
            }
            .font(.caption).foregroundStyle(.secondary)
            Text("Recorded alongside current provider observations. Lines stop at missing or stale readings, model changes, restarts, and gaps over 90 seconds.")
                .font(.caption2).foregroundStyle(.secondary)
            if trend.wasReduced {
                Text("Showing up to 600 recorded points; summaries use all saved measurements.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(trend.metric.title), \(trend.metric.unit), by observation time")
        .accessibilityIdentifier("activity.metrics.chart.\(trend.metric.rawValue)")
    }
}
