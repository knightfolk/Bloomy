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

    @Test("native inference arc animates only active evidence and stops immediately")
    func nativeArcLifecycle() async throws {
        let view = MenuBarActivityArc.ActivityArcView(frame: NSRect(x: 0, y: 0, width: 18, height: 18))
        // Other native suites render windows concurrently. A nonactivating
        // fixture panel keeps this tiny compositor surface visible without
        // changing the application's key window or relying on orderBack.
        let window = NSPanel(contentRect: NSRect(x: 20, y: 20, width: 18, height: 18),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.contentView = view
        window.orderFront(nil)
        defer { window.close() }
        #expect(window.isVisible)
        #expect(view.window === window)
        view.needsLayout = true
        view.layoutSubtreeIfNeeded()
        let arc = try #require(view.layer?.sublayers?.first as? CAShapeLayer)
        #expect(arc.path != nil)
        view.configure(active: false, tint: .systemGreen)
        #expect(arc.isHidden)
        #expect(arc.animation(forKey: "inferenceRotation") == nil)
        view.configure(active: true, tint: .systemYellow)
        #expect(!arc.isHidden)
        let animation = arc.animation(forKey: "inferenceRotation")
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            #expect(animation == nil)
        } else {
            #expect(animation?.duration == 1.4)
            #expect(animation?.repeatCount == .infinity)
            // Swift Testing can run other MainActor rendering tasks while a
            // sleep yields. Explicitly commit instead of assuming the normal
            // AppKit run-loop transaction has flushed after a fixed delay.
            window.displayIfNeeded()
            CATransaction.flush()
            let initialAngle = try await presentationAngle(arc, in: window)
            let first = try #require(initialAngle, "Visible fixture must acquire a compositor presentation layer")
            let changedAngle = try await presentationAngle(arc, in: window, differingFrom: first)
            let second = try #require(changedAngle, "Active compositor rotation must advance within three seconds")
            #expect(abs(second - first) > 0.1)
        }
        view.configure(active: false, tint: .secondaryLabelColor)
        #expect(arc.animation(forKey: "inferenceRotation") == nil)
        #expect(arc.isHidden)
    }

    /// A finite proof wait, used only by this test. Missing compositor state
    /// remains a failure; it is never treated as permission to skip motion.
    private func presentationAngle(_ arc: CAShapeLayer, in window: NSWindow,
                                   differingFrom initial: Double? = nil) async throws -> Double? {
        let deadline = CACurrentMediaTime() + 3
        repeat {
            if let presentation = arc.presentation() {
                let transform = presentation.transform
                let angle = atan2(transform.m12, transform.m11)
                if angle.isFinite, initial.map({ abs(angle - $0) > 0.1 }) ?? true { return angle }
            }
            window.displayIfNeeded()
            CATransaction.flush()
            try await Task.sleep(for: .milliseconds(30))
        } while CACurrentMediaTime() < deadline
        return nil
    }

    private func fixture(active: Bool = false, gpu: Double, fan: Double, temperature: Double,
                         freshness: MenuBarIndicators.Freshness = .current) -> MenuBarIndicators {
        .init(modelIsActive: active, gpu: .init(value: gpu, freshness: freshness),
              fanSpeed: .init(value: fan, freshness: freshness), temperature: .init(value: temperature, freshness: freshness))
    }

    private func label(_ indicators: MenuBarIndicators, alert: Bool) -> some View {
        MenuBarLabel(presentation: .make(snapshot: .unavailable(now: .now), thermal: .nominal,
            earnings: .unavailable(reason: "fixture"), mode: .statusOnly),
            uptime: .available(percent: 100, observedSeconds: 600), family: .qwen,
            attention: alert ? .init(title: "Provider idle", detail: "No provider work observed for at least 5 minutes.",
                                     shortText: "Idle 5m", idleStartedAt: .now.addingTimeInterval(-300)) : nil,
            indicators: indicators)
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
