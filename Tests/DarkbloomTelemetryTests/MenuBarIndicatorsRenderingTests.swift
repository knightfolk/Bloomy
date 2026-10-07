import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Three native menu-bar indicators", .serialized)
@MainActor
struct MenuBarIndicatorsRenderingTests {
    @Test("three indicators keep exactly the same native footprint in every state")
    func footprintAndEvidence() throws {
        let states: [(String, MenuBarIndicators)] = [
            ("Idle · 0% GPU · 20% fan · 61°C", fixture(gpu: 0, fan: 20, temperature: 61)),
            ("Working · 50% GPU · 50% fan · 75°C", fixture(active: true, gpu: 50, fan: 50, temperature: 75)),
            ("Working · 100% GPU · 100% fan · 90°C", fixture(active: true, gpu: 100, fan: 100, temperature: 90)),
            ("Stale · held samples · no animation", fixture(gpu: 42, fan: 60, temperature: 90, freshness: .stale)),
            ("Offline · missing readings", .init()),
        ]
        let exporting = ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1"
        for dark in [false, true] {
            for (index, entry) in states.enumerated() {
                let view = label(entry.1, alert: index == 0).environment(\.colorScheme, dark ? .dark : .light)
                let host = NSHostingController(rootView: view)
                #expect(host.sizeThatFits(in: NSSize(width: 500, height: 100)) == NSSize(width: 72, height: 18))
                let bitmap = try render(view, size: NSSize(width: 72, height: 18), dark: dark)
                #expect(bitmap.pixelsWide == 72)
                #expect(bitmap.pixelsHigh == 18)
                // Each third contains rendered icon/ring pixels, including
                // unavailable hardware. Missing data never removes an item.
                for startX in [0, 27, 54] {
                    #expect(hasVisiblePixels(bitmap, x: startX, width: 18))
                }
                if exporting {
                    try #require(bitmap.representation(using: .png, properties: [:]))
                        .write(to: URL(fileURLWithPath: "/tmp/bloomy-three-rings-\(dark ? "dark" : "light")-\(index).png"))
                }
            }
            if exporting {
                let strip = VStack(alignment: .leading, spacing: 16) {
                    ForEach(Array(states.enumerated()), id: \.offset) { item in
                        HStack(spacing: 14) {
                            label(item.element.1, alert: item.offset == 0)
                            Text(item.element.0).font(.system(size: 11))
                        }
                    }
                }
                .padding(16)
                .frame(width: 390, height: 186, alignment: .topLeading)
                .background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)
                let bitmap = try render(strip, size: NSSize(width: 390, height: 186), dark: dark)
                try #require(bitmap.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: "/tmp/bloomy-three-rings-\(dark ? "dark" : "light").png"))
            }
        }
    }

    @Test("detached native activity evidence remains static and preserves the arc geometry")
    func detachedArcStateAndGeometry() throws {
        let view = MenuBarActivityArc.ActivityArcView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let arc = try #require(view.layer?.sublayers?.first as? CAShapeLayer)
        #expect(arc.path != nil)
        #expect(arc.lineWidth == 1.4)
        #expect(arc.strokeStart == 0.08)
        #expect(arc.strokeEnd == 0.34)
        view.configure(active: false, tint: .systemGreen)
        #expect(arc.isHidden)
        #expect(arc.animation(forKey: "inferenceRotation") == nil)
        view.configure(active: true, tint: .systemYellow)
        #expect(!arc.isHidden)
        #expect(arc.animation(forKey: "inferenceRotation") == nil)
        view.configure(active: true, tint: .systemYellow, reduceMotion: true)
        #expect(!arc.isHidden)
        #expect(arc.animation(forKey: "inferenceRotation") == nil)
        #expect(view.window == nil)
    }

    @Test("dismantling immediately releases a compositor clock on a retained native view")
    func dismantleRemovesRetainedClock() throws {
        let view = MenuBarActivityArc.ActivityArcView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        let arc = try #require(view.layer?.sublayers?.first as? CAShapeLayer)
        view.configure(active: true, tint: .systemYellow)
        // A synthetic installed clock isolates cleanup from WindowServer
        // lifecycle proof, which runs in the native app fixture.
        let animation = CABasicAnimation(keyPath: "transform.rotation.z")
        animation.repeatCount = .infinity
        arc.add(animation, forKey: "inferenceRotation")
        #expect(arc.animation(forKey: "inferenceRotation") != nil)
        MenuBarActivityArc.dismantleNSView(view, coordinator: ())
        #expect(arc.animation(forKey: "inferenceRotation") == nil)
        #expect(!arc.isHidden)
    }

    @Test("activity colors resolve in the native view appearance, not an unrelated drawing context")
    func activityColorUsesViewAppearance() throws {
        let view = MenuBarActivityArc.ActivityArcView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        defer { view.stopObserving() }
        let arc = try #require(view.layer?.sublayers?.first as? CAShapeLayer)
        for name in [NSAppearance.Name.aqua, .darkAqua, .vibrantLight, .vibrantDark] {
            let local = try #require(NSAppearance(named: name))
            let other = try #require(NSAppearance(named: name == .aqua || name == .vibrantLight ? .darkAqua : .aqua))
            view.appearance = local
            for tint in [NSColor.systemGreen, .systemYellow, .systemRed, .secondaryLabelColor] {
                other.performAsCurrentDrawingAppearance {
                    view.configure(active: true, tint: tint)
                }
                let actual = try components(arc.strokeColor)
                var resolved: CGColor?
                local.performAsCurrentDrawingAppearance { resolved = tint.cgColor }
                let expected = try components(resolved)
                #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.005 })
                #expect(!arc.isHidden)
                #expect(arc.animationKeys() == nil)
            }
        }
    }

    private func components(_ color: CGColor?) throws -> [CGFloat] {
        let rgb = try #require(color.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB) })
        return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
    }

    private func fixture(active: Bool = false, gpu: Double, fan: Double, temperature: Double,
                         freshness: MenuBarIndicators.Freshness = .current) -> MenuBarIndicators {
        .init(modelIsActive: active, gpu: .init(value: gpu, freshness: freshness),
              fanSpeed: .init(value: fan, freshness: freshness), temperature: .init(value: temperature, freshness: freshness))
    }

    private func label(_ indicators: MenuBarIndicators, alert: Bool,
                       forceStationaryActivity: Bool = false) -> some View {
        MenuBarLabel(presentation: .make(snapshot: .unavailable(now: .now), thermal: .nominal,
            earnings: .unavailable(reason: "fixture"), mode: .statusOnly),
            uptime: .available(percent: 100, observedSeconds: 600), family: .qwen,
            attention: alert ? .init(title: "Provider idle", detail: "No provider work observed for at least 5 minutes.",
                                     shortText: "Idle 5m", idleStartedAt: .now.addingTimeInterval(-300)) : nil,
            indicators: indicators, forceStationaryActivity: forceStationaryActivity)
    }

    private func render<Content: View>(_ view: Content, size: NSSize, dark: Bool) throws -> NSBitmapImageRep {
        let host = NSHostingController(rootView: view)
        host.view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.orderBack(nil)
        defer { window.close() }
        host.view.layoutSubtreeIfNeeded()
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        bitmap.size = size
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        return bitmap
    }

    private func hasVisiblePixels(_ bitmap: NSBitmapImageRep, x: Int, width: Int) -> Bool {
        for column in x..<min(x + width, bitmap.pixelsWide) {
            for row in 0..<bitmap.pixelsHigh {
                if let color = bitmap.colorAt(x: column, y: row), color.alphaComponent > 0.1 { return true }
            }
        }
        return false
    }
}
