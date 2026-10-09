import Foundation
import SwiftUI

/// Explicit units keep visible abbreviations separate from spoken values.
struct LiveTelemetryUnit: Equatable, Sendable {
    let symbol: String
    let accessibilityName: String
    var fractionDigits = 0

    static let percent = Self(symbol: "%", accessibilityName: "percent")
    static let tokensPerSecond = Self(symbol: "tok/s", accessibilityName: "tokens per second", fractionDigits: 1)
    static let rpm = Self(symbol: "RPM", accessibilityName: "revolutions per minute")
    static let gigabytes = Self(symbol: "GB", accessibilityName: "gigabytes", fractionDigits: 1)

    func format(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(min(6, max(0, fractionDigits)))))
    }
}

/// An observed range is a comparison with actual samples, never a capacity.
/// Callers own the sample window; this component creates no history or timers.
enum LiveTelemetryScale: Equatable, Sendable {
    case bounded(minimum: Double, maximum: Double)
    case observed(minimum: Double, maximum: Double)
    case unscaled

    static let percent = Self.bounded(minimum: 0, maximum: 100)

    var bounds: ClosedRange<Double>? {
        let lower: Double
        let upper: Double
        switch self {
        case .bounded(let minimum, let maximum), .observed(let minimum, let maximum):
            lower = minimum; upper = maximum
        case .unscaled: return nil
        }
        guard lower.isFinite, upper.isFinite, upper > lower, (upper - lower).isFinite else { return nil }
        return lower...upper
    }

    func fraction(for value: Double?) -> Double? {
        guard let value, value.isFinite, let bounds else { return nil }
        // Clamp the geometry, never the displayed measurement.
        return (min(bounds.upperBound, max(bounds.lowerBound, value)) - bounds.lowerBound)
            / (bounds.upperBound - bounds.lowerBound)
    }

    func caption(unit: LiveTelemetryUnit) -> String {
        guard let bounds else { return "Range unavailable" }
        let range = "\(unit.format(bounds.lowerBound))–\(unit.format(bounds.upperBound)) \(unit.symbol)"
        if case .observed = self { return "Observed \(range)" }
        return range
    }

    func accessibilityDescription(unit: LiveTelemetryUnit) -> String {
        guard let bounds else { return "No numeric scale available." }
        let range = "\(bounds.lowerBound.formatted()) to \(bounds.upperBound.formatted()) \(unit.accessibilityName)"
        if case .observed = self { return "Observed sample range: \(range). This is not a capacity limit." }
        return "Scale: \(range)."
    }
}

struct LiveTelemetryReading: Equatable, Sendable {
    enum Freshness: Equatable, Sendable { case current, stale, unavailable }
    enum Status: Equatable, Sendable { case measured, estimated, idle, waiting }

    let value: Double?
    let unit: LiveTelemetryUnit
    /// Age is supplied by the existing source policy. Nil means age unknown.
    let age: TimeInterval?
    let freshness: Freshness
    var status: Status = .measured

    var acceptedValue: Double? {
        guard freshness != .unavailable, let value, value.isFinite else { return nil }
        return value
    }

    var effectiveFreshness: Freshness {
        guard acceptedValue != nil else { return .unavailable }
        if let age, !age.isFinite || age < 0 { return .stale }
        return freshness
    }

    var stateLabel: String {
        guard acceptedValue != nil else {
            if freshness == .current, status == .idle { return "Idle" }
            if freshness == .current, status == .waiting { return "Waiting" }
            return "Unavailable"
        }
        if effectiveFreshness == .stale {
            switch status {
            case .measured: return "Last sample"
            case .estimated: return "Last · estimated"
            case .idle: return "Last · idle"
            case .waiting: return "Last sample"
            }
        }
        switch status {
        case .measured: return "Measured"
        case .estimated: return "Estimated"
        case .idle: return "Idle"
        case .waiting: return "Waiting"
        }
    }

    var displayValue: String {
        guard let acceptedValue else { return "—" }
        return "\(unit.format(acceptedValue))\(unit.symbol == "%" ? "" : " ")\(unit.symbol)"
    }

    var accessibilityValue: String {
        guard let acceptedValue else {
            if freshness == .current, status == .idle || status == .waiting {
                let measurement = unit == .tokensPerSecond ? "throughput measurement" : "measurement"
                return "\(stateLabel). No current \(measurement); this is not zero."
            }
            return "Unavailable. No measurement; this is not zero."
        }
        let ageDescription: String
        if let age, age.isFinite, age >= 0 {
            ageDescription = "Sample age \(age.formatted(.number.precision(.fractionLength(0...1)))) seconds."
        } else { ageDescription = "Sample age unknown." }
        let number = acceptedValue.formatted(.number.precision(.significantDigits(1...15)))
        return "\(number) \(unit.accessibilityName). \(stateLabel). \(ageDescription)"
    }

    /// Age-only updates, rescaling, first values, retained values and estimates
    /// must not look like fresh measured motion.
    func shouldAnimate(from previous: Self, scale: LiveTelemetryScale, previousScale: LiveTelemetryScale,
                       isVisible: Bool, reduceMotion: Bool) -> Bool {
        isVisible && !reduceMotion && status == .measured && previous.status == .measured
            && effectiveFreshness == .current && previous.effectiveFreshness == .current
            && acceptedValue != previous.acceptedValue && scale == previousScale
            && scale.fraction(for: acceptedValue) != nil && scale.fraction(for: previous.acceptedValue) != nil
    }
}

/// A passive SwiftUI meter: no task, poll, timeline, repeating animation, or
/// synthetic activity. Only accepted measured changes interpolate for 280 ms.
struct LiveTelemetryMeter: View {
    enum Style: Equatable { case bar, gauge, inline }
    private struct MotionInput: Equatable {
        let reading: LiveTelemetryReading
        let scale: LiveTelemetryScale
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var displayedFraction: Double
    @State private var hasAppeared = false

    let label: String
    let symbol: String
    let reading: LiveTelemetryReading
    let scale: LiveTelemetryScale
    var tint: Color
    let isVisible: Bool
    var style: Style
    var showsScale: Bool

    init(label: String, symbol: String, reading: LiveTelemetryReading, scale: LiveTelemetryScale,
         tint: Color = .accentColor, isVisible: Bool, style: Style = .bar, showsScale: Bool = true) {
        self.label = label; self.symbol = symbol; self.reading = reading; self.scale = scale
        self.tint = tint; self.isVisible = isVisible; self.style = style; self.showsScale = showsScale
        _displayedFraction = State(initialValue: scale.fraction(for: reading.acceptedValue) ?? 0)
    }

    private var motionInput: MotionInput { .init(reading: reading, scale: scale) }
    private var fraction: Double? { scale.fraction(for: reading.acceptedValue) }
    private var currentTint: Color { reading.effectiveFreshness == .current ? tint : .secondary }

    private var inlineDisplayValue: String {
        guard reading.acceptedValue != nil else { return reading.stateLabel }
        let prefix = reading.effectiveFreshness == .stale
            ? (reading.status == .estimated ? "Last est. " : "Last ")
            : (reading.status == .estimated ? "Est. " : "")
        return prefix + reading.displayValue
    }

    var body: some View {
        Group {
        if style == .inline {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(label).font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer(minLength: 0)
                    Image(systemName: stateSymbol).font(.system(size: 8)).foregroundStyle(currentTint)
                    Text(inlineDisplayValue)
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(reading.effectiveFreshness == .current ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                bar.accessibilityHidden(true)
            }
        } else {
        HStack(spacing: 8) {
            if style == .gauge { gauge.accessibilityHidden(true) }
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Label(label, systemImage: symbol)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(reading.displayValue)
                        .font(.caption.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(reading.effectiveFreshness == .current ? Color.primary : Color.secondary)
                        .fixedSize(horizontal: true, vertical: false)
                }
                if style == .bar { bar.accessibilityHidden(true) }
                HStack(spacing: 5) {
                    Label(reading.stateLabel, systemImage: stateSymbol)
                    if showsScale {
                        Spacer(minLength: 0)
                        Text(scale.caption(unit: reading.unit))
                            .monospacedDigit()
                    }
                }
                .font(.caption2).foregroundStyle(.secondary)
                .frame(height: 14, alignment: .leading)
                .lineLimit(1)
            }
        }
        }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(reading.accessibilityValue + " " + scale.accessibilityDescription(unit: reading.unit))
        .help(reading.accessibilityValue + " " + scale.accessibilityDescription(unit: reading.unit))
        .onAppear {
            synchronize(animated: false)
            hasAppeared = true
        }
        .onDisappear {
            hasAppeared = false
            synchronize(animated: false)
        }
        .onChange(of: motionInput) { previous, next in
            synchronize(animated: hasAppeared && next.reading.shouldAnimate(from: previous.reading,
                scale: next.scale, previousScale: previous.scale, isVisible: isVisible, reduceMotion: reduceMotion))
        }
        .onChange(of: isVisible) { _, _ in synchronize(animated: false) }
        .onChange(of: reduceMotion) { _, _ in synchronize(animated: false) }
    }

    private var stateSymbol: String {
        if reading.freshness == .current, reading.status == .idle { return "pause.circle" }
        if reading.freshness == .current, reading.status == .waiting { return "hourglass" }
        if reading.effectiveFreshness == .unavailable { return "questionmark.circle" }
        if reading.effectiveFreshness == .stale { return "clock" }
        switch reading.status {
        case .measured: return "circle.fill"
        case .estimated: return "diamond"
        case .idle: return "pause.circle"
        case .waiting: return "hourglass"
        }
    }

    private var bar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                if fraction != nil {
                    Capsule().fill(currentTint.opacity(reading.status == .estimated ? 0.45 : 0.8))
                        .frame(width: geometry.size.width * displayedFraction)
                    Image(systemName: reading.status == .estimated ? "diamond.fill"
                          : reading.effectiveFreshness == .stale ? "circle" : "circle.fill")
                        .font(.system(size: style == .inline ? 4 : 8, weight: .semibold))
                        .foregroundStyle(currentTint)
                        .frame(width: 8)
                        .offset(x: max(0, geometry.size.width - 8) * displayedFraction)
                } else {
                    Capsule().strokeBorder(Color.secondary.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                }
            }
        }
        .frame(height: style == .inline ? 4 : 8)
        .transaction { transaction in
            if !isVisible || reduceMotion || reading.effectiveFreshness != .current || reading.status != .measured {
                transaction.disablesAnimations = true
            }
        }
    }

    private var gauge: some View {
        ZStack {
            Circle().stroke(.quaternary, lineWidth: 4)
            if fraction != nil {
                Circle().trim(from: 0, to: displayedFraction)
                    .stroke(currentTint, style: StrokeStyle(lineWidth: 4, lineCap: .round,
                        dash: reading.status == .estimated ? [2, 3] : []))
                    .rotationEffect(.degrees(-90))
            }
            Image(systemName: stateSymbol)
                .font(.system(size: 10, weight: .medium)).foregroundStyle(currentTint)
        }
        .frame(width: 30, height: 30)
        .transaction { transaction in
            if !isVisible || reduceMotion || reading.effectiveFreshness != .current || reading.status != .measured {
                transaction.disablesAnimations = true
            }
        }
    }

    private func synchronize(animated: Bool) {
        let target = fraction ?? 0
        if animated {
            withAnimation(.easeOut(duration: 0.28)) { displayedFraction = target }
        } else {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { displayedFraction = target }
        }
    }
}
