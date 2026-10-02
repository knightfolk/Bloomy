import AppKit
import DarkbloomTelemetry
import QuartzCore
import SwiftUI

enum DarkbloomLogoAsset {
    static let sourceImage = load(named: "bloomy-mark")
    private static let menuBarMask = load(named: "bloomy-menubar")
    private static let modelMasks: [ModelFamilyIcon: NSImage] = {
        var masks: [ModelFamilyIcon: NSImage] = [:]
        for family in ModelFamilyIcon.allCases where family != .darkbloom {
            masks[family] = load(named: "model-\(family.rawValue)")
        }
        return masks
    }()

    static func modelImage(family: ModelFamilyIcon) -> NSImage? {
        guard let source = modelMasks[family] ?? sourceImage else { return nil }
        var bounds = NSRect(x: 0, y: 0, width: 96, height: 96)
        guard let bitmap = source.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else { return source }
        return NSImage(cgImage: bitmap, size: NSSize(width: 96, height: 96))
    }

    static func menuBarImage(tint: NSColor, family: ModelFamilyIcon = .darkbloom) -> NSImage? {
        guard let mask = modelMasks[family] ?? menuBarMask else { return nil }

        let image = NSImage(size: mask.size, flipped: false) { rect in
            mask.draw(in: rect)
            tint.setFill()
            rect.fill(using: .sourceAtop)
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func load(named name: String) -> NSImage? {
        guard
            let url = AppResources.url(named: name, extension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            return nil
        }
        image.isTemplate = true
        return image
    }
}

struct DarkbloomLogo: View {
    let image: NSImage?
    let tint: Color

    var body: some View {
        if let image {
            Image(nsImage: image)
                .renderingMode(image.isTemplate ? .template : .original)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(tint)
        }
    }
}

struct MenuBarMetric: View {
    static let width: CGFloat = 72
    static let height: CGFloat = 18

    let text: String?

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
            if let text {
                Text(text)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .lineLimit(1)
            }
        }
        .frame(width: Self.width, height: Self.height, alignment: .leading)
    }
}

/// The GPU utilization ring drawn around the menu-bar model logo. The inner
/// logo keeps its provider-health tint; the arc is whole-Mac GPU use, tinted
/// by GPU die temperature when a fresh reading exists. The parent
/// `MenuBarLabel` owns accessibility text for the whole unit.
struct MenuBarGPURingView: View {
    static let diameter: CGFloat = 18
    static let lineWidth: CGFloat = 1

    let ring: MenuBarGPURing
    let family: ModelFamilyIcon
    let statusNSColor: NSColor

    var body: some View {
        ZStack {
            Circle()
                .stroke(Self.trackColor, lineWidth: Self.lineWidth)
            Circle()
                .trim(from: 0, to: ring.progress)
                .stroke(arcColor, style: StrokeStyle(lineWidth: Self.lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            DarkbloomLogo(
                image: DarkbloomLogoAsset.menuBarImage(tint: statusNSColor, family: family),
                tint: Color(nsColor: statusNSColor)
            )
            .frame(width: 11, height: 11)
        }
        .frame(width: Self.diameter, height: Self.diameter)
        .accessibilityHidden(true)
    }

    private static var trackColor: Color {
        Color(nsColor: .labelColor).opacity(0.2)
    }

    private var arcColor: Color {
        if ring.lastSampledAt != nil {
            return Color(nsColor: .secondaryLabelColor).opacity(0.45)
        }
        return switch ring.tint {
        case .green: Color(nsColor: .systemGreen)
        case .yellow: Color(nsColor: .systemYellow)
        case .red: Color(nsColor: .systemRed)
        case .neutral: Color(nsColor: .labelColor).opacity(0.55)
        }
    }
}

/// Three stable, native-size indicators. Numeric details live in the tooltip
/// and accessibility label, leaving the menu-bar geometry unchanged.
struct MenuBarLabel: View {
    static let width: CGFloat = 72
    static let height: CGFloat = 18

    let presentation: MenuBarPresentation
    let uptime: ObservedUptimeValue
    var family: ModelFamilyIcon = .darkbloom
    // Retained so existing callers can migrate independently.
    var ring: MenuBarGPURing? = nil
    var attention: MenuBarAttention? = nil
    var indicators: MenuBarIndicators? = nil
    /// Hosts may request a stationary activity cue without changing Mac preferences.
    var forceStationaryActivity = false

    var body: some View {
        HStack(spacing: 9) {
            modelIndicator
            MenuBarValueRing(reading: values.gpu, tint: .neutral) {
                Image(systemName: "cpu")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.primary)
            }
            MenuBarValueRing(reading: values.fanSpeed, tint: values.temperatureTint) {
                Image(systemName: "thermometer.medium")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(thermalColor)
                    .opacity(values.temperature.freshness == .stale ? 0.45 : 1)
            }
        }
        .frame(width: Self.width, height: Self.height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .help(helpText)
    }

    private var modelIndicator: some View {
        ZStack {
            Circle().stroke(thermalColor.opacity(values.temperature.freshness == .current ? 0.55 : 0.2), lineWidth: 1)
                .padding(0.75)
            MenuBarActivityArc(isActive: values.modelIsActive, tint: thermalNSColor,
                               forceStationary: forceStationaryActivity)
            DarkbloomLogo(
                image: DarkbloomLogoAsset.menuBarImage(tint: statusNSColor, family: family),
                tint: Color(nsColor: statusNSColor)
            )
            .frame(width: 11, height: 11)
            if attention != nil {
                Text("!")
                    .font(.system(size: 6, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(width: 7, height: 7)
                    .background(Circle().fill(Color(nsColor: .systemOrange)))
                    .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 0.7))
                    .offset(x: 6, y: -5)
            }
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    private var values: MenuBarIndicators {
        if let indicators { return indicators }
        return MenuBarIndicators(
            gpu: ring.map { .init(value: $0.utilization, freshness: $0.lastSampledAt == nil ? .current : .stale,
                                  sampledAt: $0.lastSampledAt) } ?? .unavailable,
            temperature: ring?.temperatureCelsius.map { .init(value: $0, freshness: .current) } ?? .unavailable
        )
    }

    private var statusNSColor: NSColor {
        if attention != nil { return .systemOrange }
        return switch presentation.health.color {
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .orange: .systemOrange
        case .red: .systemRed
        }
    }

    private var thermalColor: Color { MenuBarValueRing<EmptyView>.color(for: values.temperatureTint) }

    private var thermalNSColor: NSColor {
        switch values.temperatureTint {
        case .green: .systemGreen
        case .yellow: .systemYellow
        case .red: .systemRed
        case .neutral: .secondaryLabelColor
        }
    }

    private var accessibilityText: String {
        var text = "\(presentation.accessibilityLabel) \(uptime.accessibilityDescription) \(values.accessibilityDetail)"
        if let attention { text += " Attention: \(attention.title). \(attention.detail)" }
        return text
    }

    private var helpText: String {
        var text = "\(presentation.health.reason) · \(uptime.accessibilityDescription) · \(values.accessibilityDetail)"
        if let attention { text = "\(attention.title): \(attention.detail) · \(text)" }
        return text
    }
}

private struct MenuBarValueRing<Content: View>: View {
    let reading: MenuBarIndicators.Reading
    let tint: MenuBarGPURing.Tint
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.2), style: StrokeStyle(
                lineWidth: 1, dash: reading.freshness == .unavailable ? [1.5, 2] : []))
                .padding(0.75)
            if reading.value != nil {
                Circle().trim(from: 0, to: reading.progress)
                    .stroke(reading.freshness == .stale ? Color.secondary.opacity(0.4) : Self.color(for: tint),
                            style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(0.75)
            }
            content()
        }
        .frame(width: 18, height: 18)
        .accessibilityHidden(true)
    }

    static func color(for tint: MenuBarGPURing.Tint) -> Color {
        switch tint {
        case .green: Color(nsColor: .systemGreen)
        case .yellow: Color(nsColor: .systemYellow)
        case .red: Color(nsColor: .systemRed)
        case .neutral: Color.primary.opacity(0.75)
        }
    }
}

/// Core Animation rotates only the small active arc. Idle labels have no
/// display timer, and Reduced Motion leaves a stationary activity arc.
struct MenuBarActivityArc: NSViewRepresentable {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isActive: Bool
    let tint: NSColor
    var forceStationary = false

    func makeNSView(context: Context) -> ActivityArcView { ActivityArcView() }
    func updateNSView(_ nsView: ActivityArcView, context: Context) {
        nsView.configure(active: isActive, tint: tint, reduceMotion: reduceMotion || forceStationary)
    }

    static func dismantleNSView(_ nsView: ActivityArcView, coordinator: ()) {
        nsView.stopObserving()
    }

    final class ActivityArcView: NSView {
        private let arc = CAShapeLayer()
        private var active = false
        private var reduceMotion = false
        private var dismantled = false
        private var closeReevaluationScheduled = false
        private weak var closedWindowAwaitingReevaluation: NSWindow?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            arc.fillColor = nil
            arc.lineWidth = 1.4
            arc.lineCap = .round
            layer?.addSublayer(arc)
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(motionPreferenceChanged),
                name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        deinit {
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            NotificationCenter.default.removeObserver(self)
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            arc.removeAnimation(forKey: "inferenceRotation")
            NotificationCenter.default.removeObserver(self)
            super.viewWillMove(toWindow: newWindow)
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window, !dismantled {
                let center = NotificationCenter.default
                for name in [NSWindow.didChangeOcclusionStateNotification,
                             NSWindow.didExposeNotification,
                             NSWindow.didMiniaturizeNotification,
                             NSWindow.didDeminiaturizeNotification] {
                    center.addObserver(self, selector: #selector(windowVisibilityChanged), name: name, object: window)
                }
                center.addObserver(self, selector: #selector(windowWillClose),
                                   name: NSWindow.willCloseNotification, object: window)
            }
            synchronizeAnimation()
        }

        override func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            synchronizeAnimation()
        }

        override func viewDidHide() {
            super.viewDidHide()
            synchronizeAnimation()
        }

        override func viewDidUnhide() {
            super.viewDidUnhide()
            synchronizeAnimation()
        }

        /// A dismantled representable can briefly retain its native view.
        /// Release both observers and its compositor clock immediately.
        func stopObserving() {
            dismantled = true
            arc.removeAnimation(forKey: "inferenceRotation")
            NSWorkspace.shared.notificationCenter.removeObserver(self)
            NotificationCenter.default.removeObserver(self)
        }

        override func layout() {
            super.layout()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.frame = bounds
            arc.path = CGPath(ellipseIn: bounds.insetBy(dx: 0.8, dy: 0.8), transform: nil)
            arc.strokeStart = 0.08
            arc.strokeEnd = 0.34
            CATransaction.commit()
        }

        func configure(active: Bool, tint: NSColor, reduceMotion: Bool = false) {
            self.active = active
            self.reduceMotion = reduceMotion
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arc.strokeColor = tint.cgColor
            arc.isHidden = !active
            CATransaction.commit()
            synchronizeAnimation()
        }

        @objc private func motionPreferenceChanged() { synchronizeAnimation() }
        @objc private func windowVisibilityChanged() { synchronizeAnimation() }
        @objc private func windowWillClose() {
            // Stop before AppKit orders the window out. A synchronous reopen
            // can retain the visible occlusion bit without another notification,
            // so reevaluate once after this close completes.
            arc.removeAnimation(forKey: "inferenceRotation")
            closedWindowAwaitingReevaluation = window
            guard !closeReevaluationScheduled else { return }
            closeReevaluationScheduled = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.closeReevaluationScheduled = false
                let closedWindow = self.closedWindowAwaitingReevaluation
                self.closedWindowAwaitingReevaluation = nil
                guard !self.dismantled, let closedWindow,
                      self.window === closedWindow else { return }
                self.synchronizeAnimation()
            }
        }

        private func synchronizeAnimation() {
            guard active, !dismantled,
                  !isHiddenOrHasHiddenAncestor,
                  let window, window.isVisible, !window.isMiniaturized,
                  window.occlusionState.contains(.visible),
                  !reduceMotion, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
                arc.removeAnimation(forKey: "inferenceRotation")
                return
            }
            guard arc.animation(forKey: "inferenceRotation") == nil else { return }
            let animation = CABasicAnimation(keyPath: "transform.rotation.z")
            animation.fromValue = 0
            animation.toValue = -Double.pi * 2
            animation.duration = 1.4
            animation.repeatCount = .infinity
            arc.add(animation, forKey: "inferenceRotation")
        }
    }
}
