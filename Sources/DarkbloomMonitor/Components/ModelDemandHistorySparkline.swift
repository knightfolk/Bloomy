import DarkbloomTelemetry
import SwiftUI

struct ModelDemandHistoryPoint: Equatable, Sendable {
    let capturedAt: Date
    let bucketStart: Date
    let pressure: Double?
}

struct ModelDemandHistorySeries: Equatable, Sendable {
    enum State: Equatable, Sendable { case pending, available, retained, unavailable }
    var state: State
    let range: DateInterval?
    let readAt: Date?
    let points: [ModelDemandHistoryPoint]
    let upperBound: Double
    let validCount: Int
    let median: Double?
    let segments: [[ModelDemandHistoryPoint]]

    static let pending = Self(state: .pending, range: nil, readAt: nil, points: [], upperBound: 1)
    static let unavailable = Self(state: .unavailable, range: nil, readAt: nil, points: [], upperBound: 1)
    init(state: State, range: DateInterval?, readAt: Date?, points: [ModelDemandHistoryPoint], upperBound: Double) {
        self.state = state; self.range = range; self.readAt = readAt
        self.points = points; self.upperBound = upperBound
        let values = points.compactMap(\.pressure).sorted()
        validCount = values.count
        let middle = values.count / 2
        median = values.count < 12 ? nil : values.count.isMultiple(of: 2)
            ? values[middle - 1] / 2 + values[middle] / 2 : values[middle]
        segments = Self.connectedSegments(points)
    }

    /// A missing five-minute bucket, missing model, draining snapshot or zero
    /// denominator breaks the line. A single real zero remains a visible dot.
    private static func connectedSegments(_ points: [ModelDemandHistoryPoint]) -> [[ModelDemandHistoryPoint]] {
        var result: [[ModelDemandHistoryPoint]] = []
        var current: [ModelDemandHistoryPoint] = []
        for point in points {
            if point.pressure == nil {
                if !current.isEmpty { result.append(current); current.removeAll(keepingCapacity: true) }
                continue
            }
            if let previous = current.last,
               point.bucketStart.timeIntervalSince(previous.bucketStart) > NetworkDemandHistoryObservation.bucketSeconds {
                result.append(current); current.removeAll(keepingCapacity: true)
            }
            current.append(point)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}

/// Prepared once for the complete read before filtering. No card searches raw
/// observations, computes a scale, reads storage or creates a refresh timer.
struct ModelDemandHistoryPresentation: Equatable, Sendable {
    let range: DateInterval?
    let readAt: Date?
    var state: ModelDemandHistorySeries.State
    let upperBound: Double
    private let series: [String: ModelDemandHistorySeries]

    static let pending = Self(range: nil, readAt: nil, state: .pending, upperBound: 1, series: [:])
    static let unavailable = Self(range: nil, readAt: nil, state: .unavailable, upperBound: 1, series: [:])

    init(report: NetworkDemandHistoryReport) throws {
        try Task.checkCancellation()
        range = report.range; readAt = report.readAt; state = .available
        var indexed: [String: [ModelDemandHistoryPoint]] = [:]
        var maximum = 1.0
        for observation in report.observations {
            try Task.checkCancellation()
            for value in observation.models {
                let pressure = value.pressure
                if let pressure { maximum = max(maximum, pressure) }
                indexed[value.modelID, default: []].append(.init(capturedAt: observation.capturedAt,
                    bucketStart: observation.bucketStart, pressure: pressure))
            }
        }
        upperBound = maximum
        var prepared: [String: ModelDemandHistorySeries] = [:]
        for (id, points) in indexed {
            try Task.checkCancellation()
            prepared[id] = .init(state: .available, range: report.range, readAt: report.readAt,
                points: points, upperBound: maximum)
        }
        try Task.checkCancellation()
        series = prepared
    }

    private init(range: DateInterval?, readAt: Date?, state: ModelDemandHistorySeries.State,
        upperBound: Double, series: [String: ModelDemandHistorySeries]) {
        self.range = range; self.readAt = readAt; self.state = state
        self.upperBound = upperBound; self.series = series
    }

    func history(for modelID: String) -> ModelDemandHistorySeries {
        var value = series[modelID] ?? .init(state: state, range: range, readAt: readAt, points: [], upperBound: upperBound)
        value.state = state
        return value
    }
}

struct ModelDemandHistorySparkline: View {
    let modelID: String
    let series: ModelDemandHistorySeries
    private var tint: Color { series.state == .retained ? .secondary : .accentColor }
    private var caption: String {
        switch series.state {
        case .pending: "Reading history"
        case .unavailable: "History unavailable"
        case .available: series.validCount == 0 ? "No valid samples" : "\(series.validCount) \(series.validCount == 1 ? "sample" : "samples")"
        case .retained: "Last read · \(series.validCount) \(series.validCount == 1 ? "sample" : "samples")"
        }
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(series.range == nil ? "Observed · 24h" : "24h · 0–\(ModelDemandScale.label(series.upperBound))")
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(caption).lineLimit(1)
            }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            GeometryReader { geometry in
                let size = CGSize(width: max(1, geometry.size.width - 4), height: max(1, geometry.size.height - 4))
                ZStack(alignment: .topLeading) {
                    Path { path in
                        path.move(to: CGPoint(x: 2, y: size.height + 2))
                        path.addLine(to: CGPoint(x: size.width + 2, y: size.height + 2))
                    }.stroke(.quaternary, lineWidth: 1)
                    if let median = series.median {
                        Path { path in
                            let y = 2 + size.height * (1 - median / series.upperBound)
                            path.move(to: CGPoint(x: 2, y: y)); path.addLine(to: CGPoint(x: size.width + 2, y: y))
                        }.stroke(.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    ForEach(Array(series.segments.enumerated()), id: \.offset) { _, points in
                        Path { path in
                            for (index, point) in points.enumerated() {
                                let position = position(point, size: size)
                                if index == 0 { path.move(to: position) } else { path.addLine(to: position) }
                            }
                        }.stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        if let first = points.first, points.count == 1 {
                            Circle().fill(tint).frame(width: 4, height: 4)
                                .position(position(first, size: size))
                        }
                    }
                    if series.validCount == 0 {
                        Text(series.state == .pending ? "Collecting observations" : "Gaps stay unknown")
                            .font(.caption2).foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }.frame(height: 28).accessibilityHidden(true)
        }
        .help(help)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Observed network demand history for \(modelID)")
        .accessibilityValue(help)
        .accessibilityIdentifier("model.\(modelID).demandHistory")
    }

    private func position(_ point: ModelDemandHistoryPoint, size: CGSize) -> CGPoint {
        let duration = series.range?.duration ?? 0
        let fraction = duration > 0 ? point.capturedAt.timeIntervalSince(series.range!.start) / duration : 0
        return CGPoint(x: 2 + size.width * min(1, max(0, fraction)),
            y: 2 + size.height * (1 - min(1, max(0, (point.pressure ?? 0) / series.upperBound))))
    }

    private var help: String {
        let range = series.range.map { "\($0.start.formatted(date: .abbreviated, time: .shortened)) to \($0.end.formatted(date: .abbreviated, time: .shortened)). " } ?? ""
        let read = series.readAt.map { "Read \($0.formatted(date: .abbreviated, time: .shortened)). " } ?? ""
        let typical = series.median.map { "Dashed line: observed sample median \(ModelDemandScale.label($0)). " } ?? "Median appears after twelve valid samples. "
        return "\(caption). \(range)\(read)Network-wide requests per loaded provider, sampled while Bloomy collects. Latest accepted observation per five-minute bucket; missing buckets, missing models and zero loaded providers are gaps. All history graphs share 0 to \(ModelDemandScale.label(series.upperBound)); search does not rescale them. \(typical)This is sampled pressure, not completed work or expected earnings."
    }
}
