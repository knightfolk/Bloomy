import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Live telemetry meter", .serialized)
@MainActor
struct LiveTelemetryMeterTests {
    private func reading(_ value: Double?, age: TimeInterval? = 1,
                         freshness: LiveTelemetryReading.Freshness = .current,
                         status: LiveTelemetryReading.Status = .measured) -> LiveTelemetryReading {
        .init(value: value, unit: .percent, age: age, freshness: freshness, status: status)
    }

    @Test("measured zero is distinct from unavailable and invalid numbers")
    func zeroAndUnknown() {
        let zero = reading(0)
        #expect(zero.displayValue == "0%")
        #expect(zero.stateLabel == "Measured")
        #expect(LiveTelemetryScale.percent.fraction(for: zero.acceptedValue) == 0)
        #expect(zero.accessibilityValue.contains("0 percent"))
        let invalidValues: [Double?] = [nil, .nan, .infinity, -.infinity]
        for value in invalidValues {
            let unavailable = reading(value)
            #expect(unavailable.acceptedValue == nil)
            #expect(unavailable.displayValue == "—")
            #expect(unavailable.stateLabel == "Unavailable")
            #expect(LiveTelemetryScale.percent.fraction(for: unavailable.acceptedValue) == nil)
        }
        #expect(reading(42, freshness: .unavailable).acceptedValue == nil)
    }

    @Test("stale estimated and idle labels preserve the reading's meaning")
    func sourceStates() {
        let stale = reading(23.5, age: 25, freshness: .stale)
        #expect(stale.displayValue == "24%")
        #expect(stale.stateLabel == "Last sample")
        #expect(stale.accessibilityValue.contains("23.5 percent"))
        #expect(stale.accessibilityValue.contains("25 seconds"))
        #expect(reading(23, freshness: .stale, status: .estimated).stateLabel == "Last · estimated")
        #expect(reading(0, status: .idle).stateLabel == "Idle")
        let idle = LiveTelemetryReading(value: nil, unit: .tokensPerSecond, age: 1, freshness: .current, status: .idle)
        #expect(idle.displayValue == "—")
        #expect(idle.stateLabel == "Idle")
        #expect(idle.accessibilityValue.contains("Idle. No current throughput measurement"))
        #expect(LiveTelemetryScale.percent.fraction(for: idle.acceptedValue) == nil)
        #expect(reading(nil, status: .waiting).stateLabel == "Waiting")
        #expect(reading(nil, freshness: .unavailable, status: .idle).stateLabel == "Unavailable")
        #expect(reading(23, status: .estimated).stateLabel == "Estimated")
        #expect(reading(23, age: -1).effectiveFreshness == .stale)
        #expect(reading(23, age: .nan).effectiveFreshness == .stale)
        #expect(reading(23, age: nil).accessibilityValue.contains("Sample age unknown"))
    }

    @Test("observed token range never implies a capacity and missing scales remain missing")
    func truthfulScales() {
        let observed = LiveTelemetryScale.observed(minimum: 0, maximum: 53)
        #expect(observed.fraction(for: 26.5) == 0.5)
        #expect(observed.caption(unit: .tokensPerSecond).hasPrefix("Observed"))
        #expect(observed.accessibilityDescription(unit: .tokensPerSecond).contains("not a capacity limit"))
        for scale in [LiveTelemetryScale.unscaled, .observed(minimum: 0, maximum: 0),
                      .bounded(minimum: 100, maximum: 0), .bounded(minimum: 0, maximum: .infinity)] {
            #expect(scale.bounds == nil)
            #expect(scale.fraction(for: 26.5) == nil)
            #expect(scale.caption(unit: .tokensPerSecond) == "Range unavailable")
        }
        let speed = LiveTelemetryReading(value: 26.53, unit: .tokensPerSecond, age: 3, freshness: .current)
        #expect(speed.displayValue == "26.5 tok/s")
        #expect(speed.accessibilityValue.contains("26.53 tokens per second"))
        #expect(LiveTelemetryScale.percent.fraction(for: 150) == 1)
        #expect(reading(150).displayValue == "150%")
    }

    @Test("only a changed current measured value can interpolate")
    func motionGates() {
        let previous = reading(25)
        let current = reading(45)
        func animates(_ next: LiveTelemetryReading, from prior: LiveTelemetryReading = previous,
                      scale: LiveTelemetryScale = .percent, visible: Bool = true, reduced: Bool = false) -> Bool {
            next.shouldAnimate(from: prior, scale: scale, previousScale: .percent,
                               isVisible: visible, reduceMotion: reduced)
        }
        #expect(animates(current))
        #expect(!animates(reading(25, age: 2)))
        #expect(!animates(current, visible: false))
        #expect(!animates(current, reduced: true))
        #expect(!animates(reading(45, freshness: .stale)))
        #expect(!animates(reading(45, status: .idle)))
        #expect(!animates(reading(45, status: .estimated)))
        #expect(!animates(current, from: reading(nil)))
        #expect(!animates(current, from: reading(25, freshness: .stale)))
        #expect(!animates(current, from: reading(25, status: .estimated)))
        #expect(!animates(current, scale: .bounded(minimum: 0, maximum: 200)))
        #expect(!animates(current, scale: .unscaled))
    }

    @Test("all source states keep the same native meter height", arguments: [180.0, 300.0])
    func stableGeometry(width: Double) {
        let readings = [reading(0), reading(99.9), reading(nil), reading(nil, status: .idle), reading(nil, status: .waiting),
                        reading(42, freshness: .stale), reading(42, status: .estimated), reading(0, status: .idle)]
        for style in [LiveTelemetryMeter.Style.bar, .gauge] {
            let heights = readings.map { reading in
                NSHostingView(rootView: LiveTelemetryMeter(label: "Mac GPU", symbol: "cpu", reading: reading,
                    scale: .percent, isVisible: false, style: style).frame(width: width)).fittingSize.height
            }
            #expect(heights.allSatisfy { $0.isFinite && $0 > 20 && $0 < 80 })
            #expect((heights.max() ?? 0) - (heights.min() ?? 0) < 1)
        }
    }

    @Test("inline model meters keep stable compact geometry through unknown and stale states")
    func inlineGeometry() {
        let readings = [reading(0), reading(99.9), reading(nil), reading(nil, status: .idle),
                        reading(nil, status: .waiting), reading(42, freshness: .stale),
                        reading(42, status: .estimated)]
        let heights = readings.map { reading in
            NSHostingView(rootView: LiveTelemetryMeter(label: "Provider tok/s", symbol: "speedometer",
                reading: reading, scale: .percent, isVisible: false, style: .inline,
                showsScale: false).frame(width: 180)).fittingSize.height
        }
        #expect(heights.allSatisfy { $0 > 0 && $0 <= 26 })
        #expect((heights.max() ?? 0) - (heights.min() ?? 0) < 1)
    }
}
