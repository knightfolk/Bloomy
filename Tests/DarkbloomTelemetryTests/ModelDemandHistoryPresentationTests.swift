import AppKit
@testable import DarkbloomMonitor
import DarkbloomTelemetry
import SwiftUI
import Testing

@Suite("Model demand history presentation")
struct ModelDemandHistoryPresentationTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("one full report owns scale and model lookup independent of search")
    func sharedReport() throws {
        let rows = [observation(0, [value("small", 1, 4), value("large", 20, 2)]),
            observation(1, [value("small", 0, 4), value("large", 2, 2)])]
        let presentation = try prepared(rows)
        #expect(presentation.upperBound == 10)
        #expect(presentation.history(for: "small").upperBound == 10)
        #expect(presentation.history(for: "small").validCount == 2)
        #expect(presentation.history(for: "large").validCount == 2)
        #expect(presentation.history(for: "unknown").points.isEmpty)
        #expect(presentation.history(for: "unknown").state == .available)
        #expect(presentation.history(for: "unknown").range == presentation.range)
    }

    @Test("missing buckets models draining and zero denominators break lines; zero remains measured")
    func gapsAndZero() throws {
        let rows = [observation(0, [value("a", 0, 4)]), observation(1, [value("a", 4, 4)]),
            observation(2, []), observation(3, [value("a", 5, 4)]),
            observation(4, [value("a", 2, 0)]), observation(5, [value("a", 8, 4)]),
            observation(7, [value("a", 1, 4)]), observation(8, [], draining: true),
            observation(9, [value("a", 9, 4)])]
        let series = try prepared(rows).history(for: "a")
        #expect(series.validCount == 6)
        #expect(series.points.first?.pressure == 0)
        #expect(series.points[3].pressure == nil)
        #expect(series.segments.map(\.count) == [2, 1, 1, 1, 1])
        #expect(series.median == nil)
    }

    @Test("median needs twelve valid observations and ignores undefined ratios")
    func medianCoverage() throws {
        let rows = (0..<12).map { observation($0, [value("a", $0, 1)]) }
        #expect(try prepared(Array(rows.dropLast())).history(for: "a").median == nil)
        let result = try prepared(rows + [observation(12, [value("a", 999, 0)])])
        #expect(result.history(for: "a").median == 5.5)
        #expect(result.upperBound == 11)
        #expect(result.history(for: "a").validCount == 12)
    }

    @Test("retained reports preserve original range read time scale and gaps")
    func retainedScope() throws {
        var presentation = try prepared([observation(0, [value("a", 9, 3)])])
        let previous = presentation.history(for: "a")
        presentation.state = .retained
        let retained = presentation.history(for: "a")
        #expect(retained.state == .retained)
        #expect(retained.range == previous.range)
        #expect(retained.readAt == previous.readAt)
        #expect(retained.points == previous.points)
        #expect(retained.upperBound == previous.upperBound)
        #expect(ModelDemandHistoryPresentation.pending.history(for: "a").state == .pending)
        #expect(ModelDemandHistoryPresentation.unavailable.history(for: "a").state == .unavailable)
    }

    @Test("history states keep one stable native footprint", arguments: [180.0, 300.0, 460.0])
    @MainActor func renderStates(width: Double) throws {
        let available = try prepared((0..<12).map { observation($0, [value("a", $0, 2)]) }).history(for: "a")
        var retained = available; retained.state = .retained
        let empty = try prepared([]).history(for: "a")
        let one = try prepared([observation(0, [value("a", 0, 2)])]).history(for: "a")
        var sizes: [CGSize] = []
        for series in [available, retained, empty, one, .pending, .unavailable] {
            let renderer = ImageRenderer(content: ModelDemandHistorySparkline(modelID: "a", series: series).frame(width: width))
            sizes.append(try #require(renderer.nsImage).size)
        }
        #expect(sizes.allSatisfy { abs($0.width - width) < 0.01 && $0.height >= 35 && $0.height < 60 })
        #expect((sizes.map(\.height).max() ?? 0) - (sizes.map(\.height).min() ?? 0) < 0.01)
    }

    private func value(_ id: String, _ active: Int, _ loaded: Int) -> NetworkDemandHistoryValue {
        .init(modelID: id, activeRequests: active, queuedRequests: 0, loadedProviders: loaded)
    }
    private func observation(_ bucket: Int, _ models: [NetworkDemandHistoryValue], draining: Bool = false) -> NetworkDemandHistoryObservation {
        .init(capturedAt: start.addingTimeInterval(Double(bucket) * 300 + 30), models: models, isDraining: draining)
    }
    private func prepared(_ observations: [NetworkDemandHistoryObservation]) throws -> ModelDemandHistoryPresentation {
        try .init(report: .init(range: DateInterval(start: start, duration: 86_400),
            readAt: start.addingTimeInterval(86_400), observations: observations))
    }
}
