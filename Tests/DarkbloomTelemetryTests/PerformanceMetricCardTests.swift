import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Performance metric graphics", .serialized)
@MainActor
struct PerformanceMetricCardTests {
    @Test("unknown and invalid readings never become known-zero gauges")
    func fractions() {
        #expect(PerformanceMetricFraction.measured(nil, outOf: 100) == nil)
        #expect(PerformanceMetricFraction.measured(0, outOf: 100) == 0)
        #expect(PerformanceMetricFraction.measured(100, outOf: 100) == 1)
        #expect(PerformanceMetricFraction.measured(12, outOf: 100) == 0.12)
        #expect(PerformanceMetricFraction.measured(30, outOf: 60) == 0.5)
        for numerator in [-1.0, 101, .infinity, .nan] {
            #expect(PerformanceMetricFraction.measured(numerator, outOf: 100) == nil)
        }
        for denominator in [-1.0, 0, .infinity, .nan] {
            #expect(PerformanceMetricFraction.measured(0, outOf: denominator) == nil)
        }
    }

    @Test("performance cards fit the three-card row with complete qualifiers", arguments: [380.0, 550.0, 1_040.0])
    func nativeCardRows(width: Double) async throws {
        var frames: [Int: CGRect] = [:]
        let root = AdaptiveChoiceLayout(minimumWidth: 115, spacing: 10) {
            ForEach(0..<3) { index in
                PerformanceMetricCard(id: "test\(index)", title: index == 0 ? "Model speed" : "GPU while idle",
                    symbol: index == 0 ? "speedometer" : "cpu", value: index == 0 ? "999.9 tok/s" : "100.0%",
                    detail: index == 0 ? "Average during measured work" : "Whole Mac · 693h 59m observed",
                    graphic: index == 0 ? .none : .utilization(1))
                    .background(GeometryReader { geometry in
                        Color.clear.preference(key: MetricsCardBounds.self,
                            value: [index: geometry.frame(in: .named("metric-row"))])
                    })
            }
        }
        .frame(width: width, alignment: .topLeading)
        .coordinateSpace(name: "metric-row")
        .onPreferenceChange(MetricsCardBounds.self) { frames = $0 }
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: 300))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutSubtreeIfNeeded()
        let measured = try (0..<3).map { try #require(frames[$0]) }
        if measured.contains(where: { abs($0.minY - measured[0].minY) >= 1 || abs($0.height - measured[0].height) >= 1 }) {
            print("Metric row geometry at \(width): \(measured)")
        }
        #expect(measured.allSatisfy { $0.width >= 115 && $0.maxX <= width + 1 })
        #expect(measured.allSatisfy { abs($0.minY - measured[0].minY) < 1 })
        #expect(measured.allSatisfy { abs($0.height - measured[0].height) < 1 })
        #expect(measured.allSatisfy { $0.height.isFinite && $0.height < 180 })
    }
}

private struct MetricsCardBounds: PreferenceKey {
    static var defaultValue: [Int: CGRect] { [:] }
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}
