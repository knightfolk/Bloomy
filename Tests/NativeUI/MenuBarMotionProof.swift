import AppKit
import CoreGraphics
import DarkbloomTelemetry
import Darwin
import QuartzCore
import SwiftUI

/// Finite WindowServer/compositor proof. Call only from the inert fixture's
/// normal NSApplication.run loop, keeping its dashboard anchor window alive.
@MainActor
enum MenuBarMotionProof {
    static func run(outputDirectory: URL) async -> Bool {
        let report = MotionProofReport(outputDirectory: outputDirectory)
        let fixture: MotionArcFixture
        do {
            fixture = try MotionArcFixture()
            try report.write(terminal: false)
        } catch {
            report.failures.append("Native motion fixture preparation failed: \(error.localizedDescription)")
            return report.finish()
        }
        defer { fixture.window.close() }
        let view = fixture.view
        let window = fixture.window
        let arc = fixture.arc

        await report.check("native_window_visible") {
            try require(NSApplication.shared.isRunning, "The native fixture must own a running NSApplication loop")
            view.configure(active: false, tint: .systemGreen)
            window.orderFront(nil)
            try await waitForVisible(window)
            try require(arc.isHidden && arc.animation(forKey: "inferenceRotation") == nil,
                        "Inactive native evidence must have no compositor clock")
            return diagnostics(window)
        }
        await report.check("active_compositor_advances") {
            try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                        "System Reduce Motion is enabled; actual rotation cannot be proved without changing that preference")
            view.configure(active: true, tint: .systemYellow)
            try await waitForVisible(window)
            try await waitForClock(arc)
            let first = try await presentationAngle(arc, in: window)
            let second = try await presentationAngle(arc, in: window, differingFrom: first)
            try require(angularDistance(first, second) > 0.1, "The visible compositor angle must advance")
            return ["firstAngle": first, "secondAngle": second, "duration": arc.animation(forKey: "inferenceRotation")?.duration ?? -1]
        }
        await report.check("repeated_updates_keep_one_clock") {
            try await fixture.restoreActive()
            for _ in 0..<10 { view.configure(active: true, tint: .systemGreen) }
            let keys = arc.animationKeys() ?? []
            try require(keys == ["inferenceRotation"], "Repeated eligible updates must retain exactly one rotation clock")
            let first = try await presentationAngle(arc, in: window)
            let second = try await presentationAngle(arc, in: window, differingFrom: first)
            return ["animationKeys": keys, "angleAdvance": angularDistance(first, second)]
        }
        await report.check("self_hide_and_restore") {
            try await fixture.restoreActive()
            view.isHidden = true
            try await waitUntil("Self-hidden view retained rotation") { arc.animation(forKey: "inferenceRotation") == nil }
            view.isHidden = false
            try await waitForClock(arc)
            return ["restored": true]
        }
        await report.check("ancestor_hide_and_restore") {
            try await fixture.restoreActive()
            fixture.container.isHidden = true
            try await waitUntil("Ancestor-hidden view retained rotation") { arc.animation(forKey: "inferenceRotation") == nil }
            fixture.container.isHidden = false
            try await waitForClock(arc)
            return ["restored": true]
        }
        await report.check("window_order_out_and_restore") {
            try await fixture.restoreActive()
            window.orderOut(nil)
            try await waitUntil("Ordered-out window retained rotation") {
                !window.isVisible && arc.animation(forKey: "inferenceRotation") == nil
            }
            window.orderFront(nil)
            try await waitForVisible(window)
            try await waitForClock(arc)
            return ["restored": true]
        }
        await report.check("opaque_cover_occlusion_and_restore") {
            try await fixture.restoreActive()
            let coverFrame = window.frame.insetBy(dx: -32, dy: -32)
            // The measured same-process opaque cover did not change actual
            // occlusion. Test process ownership as a distinct variable, using
            // only this staged executable's bounded inert cover mode.
            let cover = OwnedMotionCover(frame: coverFrame)
            var occluded = [String: Any]()
            var coverEvidence = [String: Any]()
            var serverEvidence = [[String: Any]]()
            do {
                try await cover.start()
                coverEvidence = cover.readyEvidence ?? [:]
                try await waitUntil("The child cover did not establish opaque coverage above the target in WindowServer") {
                    let entries = windowServerDiagnostics(windowNumbers: [window.windowNumber, cover.windowNumber])
                    guard let target = entries.first(where: { $0["windowNumber"] as? Int == window.windowNumber }),
                          let front = entries.first(where: { $0["windowNumber"] as? Int == cover.windowNumber }),
                          target["ownerPID"] as? Int == Int(getpid()),
                          front["ownerPID"] as? Int == Int(cover.process.processIdentifier),
                          let targetIndex = target["frontToBackIndex"] as? Int,
                          let frontIndex = front["frontToBackIndex"] as? Int, frontIndex < targetIndex,
                          front["alpha"] as? Double == 1,
                          let targetBounds = target["bounds"] as? [String: Any],
                          let frontBounds = front["bounds"] as? [String: Any],
                          let targetRect = CGRect(dictionaryRepresentation: targetBounds as CFDictionary),
                          let frontRect = CGRect(dictionaryRepresentation: frontBounds as CFDictionary) else { return false }
                    return frontRect.contains(targetRect)
                }
                try await waitUntil("A distinct-process opaque cover did not genuinely occlude the entire arc window") {
                    cover.process.isRunning && window.isVisible && !window.occlusionState.contains(.visible)
                }
                try await waitUntil("Occluded window retained rotation") { arc.animation(forKey: "inferenceRotation") == nil }
                occluded = diagnostics(window)
                serverEvidence = windowServerDiagnostics(windowNumbers: [window.windowNumber, cover.windowNumber])
            } catch {
                let server = windowServerDiagnostics(windowNumbers: [window.windowNumber, cover.windowNumber])
                let cleanup = await cover.stop()
                throw MotionProofFailure("\(error.localizedDescription); target=\(diagnostics(window)); cover=\(cover.readyEvidence ?? [:]); "
                    + "ownedWindowServerEntries=\(server); childCleanup=\(cleanup)")
            }
            let cleanup = await cover.stop()
            try require(cleanup["exited"] as? Bool == true && cleanup["exitStatus"] as? Int == 0
                && cleanup["childTerminalReason"] as? String == "parent-request"
                && cleanup["childWindowClosed"] as? Bool == true,
                "The owned cover must close and exit normally after the parent request: \(cleanup)")
            try await waitForVisible(window)
            try await waitForClock(arc)
            return ["occludedWindow": occluded, "coverWindow": coverEvidence,
                    "ownedWindowServerEntries": serverEvidence, "childCleanup": cleanup, "restored": true]
        }
        await report.check("detach_and_restore") {
            try await fixture.restoreActive()
            view.removeFromSuperview()
            try require(view.window == nil && arc.animation(forKey: "inferenceRotation") == nil,
                        "Detaching the native view must immediately remove rotation")
            fixture.container.addSubview(view)
            try await waitForClock(arc)
            return ["restoredIntoSameWindow": view.window === window]
        }
        await report.check("same_window_close_and_reopen") {
            try await fixture.restoreActive()
            window.close()
            try require(!window.isVisible && arc.animation(forKey: "inferenceRotation") == nil,
                        "Closing the window must immediately stop rotation")
            try require(window.contentView === fixture.container && view.window === window,
                        "Close/reopen proof must retain the same window and native view")
            try await waitUntil("Closed window remained compositor-visible") { !window.occlusionState.contains(.visible) }
            window.orderFront(nil)
            try await waitForVisible(window)
            try await waitForClock(arc)
            return ["sameWindowAndView": view.window === window]
        }
        await report.check("rapid_same_window_close_and_reopen") {
            try await fixture.restoreActive()
            window.close()
            try require(!window.isVisible && arc.animation(forKey: "inferenceRotation") == nil,
                        "Rapid close must stop before any yield")
            // Deliberately do not yield before reopening. Native notifications
            // may be coalesced within this single MainActor run-loop pass.
            window.orderFront(nil)
            try await waitForVisible(window)
            try await waitForClock(arc)
            try require(window.contentView === fixture.container && view.window === window,
                        "Rapid reopen must retain the same window and native view")
            view.configure(active: true, tint: .systemYellow, reduceMotion: true)
            window.close()
            try require(arc.animation(forKey: "inferenceRotation") == nil,
                        "Stationary rapid close must stop immediately")
            window.orderFront(nil)
            try await waitForVisible(window)
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                DispatchQueue.main.async { continuation.resume() }
            }
            try require(!arc.isHidden && arc.animation(forKey: "inferenceRotation") == nil,
                        "Deferred close reevaluation must preserve stationary active evidence")
            return ["sameWindowAndView": true, "stationaryReopenStayedStatic": true]
        }
        await report.check("native_stationary_true_false_true") {
            try await fixture.restoreActive()
            view.configure(active: true, tint: .systemYellow, reduceMotion: true)
            try require(!arc.isHidden && arc.animation(forKey: "inferenceRotation") == nil,
                        "Stationary active evidence must remain visible without rotation")
            view.configure(active: true, tint: .systemYellow, reduceMotion: false)
            try await waitForClock(arc)
            view.configure(active: true, tint: .systemYellow, reduceMotion: true)
            try require(!arc.isHidden && arc.animation(forKey: "inferenceRotation") == nil,
                        "Returning to stationary input must stop immediately")
            return ["staticActivityArcRetained": true]
        }
        await report.check("inactive_evidence_stops_immediately") {
            try await fixture.restoreActive()
            view.configure(active: false, tint: .secondaryLabelColor)
            try require(arc.isHidden && arc.animation(forKey: "inferenceRotation") == nil,
                        "Inactive evidence must hide the activity cue and remove its clock")
            view.configure(active: true, tint: .systemYellow)
            try await waitForClock(arc)
            return ["restored": true]
        }
        await report.check("dismantle_retained_view") {
            try await fixture.restoreActive()
            MenuBarActivityArc.dismantleNSView(view, coordinator: ())
            try require(!arc.isHidden && arc.animation(forKey: "inferenceRotation") == nil,
                        "Dismantling must immediately remove rotation while retaining static evidence")
            view.configure(active: true, tint: .systemGreen)
            view.isHidden = true
            view.isHidden = false
            window.orderOut(nil)
            try await waitUntil("Dismantled test window did not hide") { !window.occlusionState.contains(.visible) }
            window.orderFront(nil)
            try await waitForVisible(window)
            try require(arc.animation(forKey: "inferenceRotation") == nil,
                        "Later view/window updates must not restart a dismantled clock")
            return ["didNotRestart": true]
        }
        await report.check("parent_stationary_activity_bridge") {
            let host = NSHostingController(rootView: AnyView(label(forceStationary: true)))
            let parentWindow = makeWindow(content: host.view)
            parentWindow.orderFront(nil)
            defer { parentWindow.close() }
            try await waitForVisible(parentWindow)
            try await waitUntil("Parent label did not mount its native activity arc") { findArc(in: host.view) != nil }
            var native = try currentArc(in: host.view)
            try require(!native.isHidden && native.animation(forKey: "inferenceRotation") == nil,
                        "The parent's stationary preference must reach the native active arc")
            host.rootView = AnyView(label(forceStationary: false))
            try await waitUntil("Removing the parent preference did not resume native rotation") {
                (try? currentArc(in: host.view).animation(forKey: "inferenceRotation")) != nil
            }
            native = try currentArc(in: host.view)
            let first = try await presentationAngle(native, in: parentWindow)
            let second = try await presentationAngle(native, in: parentWindow, differingFrom: first)
            host.rootView = AnyView(label(forceStationary: true))
            try await waitUntil("Restoring the parent preference did not stop native rotation") {
                guard let current = try? currentArc(in: host.view) else { return false }
                return current.animation(forKey: "inferenceRotation") == nil && !current.isHidden
            }
            return ["staticActivityArcRetained": true, "normalAngleAdvance": angularDistance(first, second)]
        }
        return report.finish()
    }

    private static func label(forceStationary: Bool) -> MenuBarLabel {
        MenuBarLabel(presentation: .make(snapshot: .unavailable(now: Date()), thermal: .nominal,
            earnings: .unavailable(reason: "Synthetic motion fixture"), mode: .statusOnly),
            uptime: .available(percent: 100, observedSeconds: 600), family: .qwen,
            indicators: .init(modelIsActive: true, gpu: .init(value: 50, freshness: .current),
                fanSpeed: .init(value: 50, freshness: .current), temperature: .init(value: 75, freshness: .current)),
            forceStationaryActivity: forceStationary)
    }

    private static func findArc(in view: NSView) -> MenuBarActivityArc.ActivityArcView? {
        if let arc = view as? MenuBarActivityArc.ActivityArcView { return arc }
        return view.subviews.lazy.compactMap { findArc(in: $0) }.first
    }

    private static func currentArc(in view: NSView) throws -> CAShapeLayer {
        guard let native = findArc(in: view), let arc = native.layer?.sublayers?.first as? CAShapeLayer else {
            throw MotionProofFailure("The parent label has no native activity layer")
        }
        return arc
    }

    private static func makeWindow(content: NSView) -> NSWindow {
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let rect = NSRect(x: screen.minX + 32, y: screen.minY + 32, width: 96, height: 96)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.isOpaque = true
        window.hasShadow = true
        window.backgroundColor = .windowBackgroundColor
        window.ignoresMouseEvents = false
        window.contentView = content
        return window
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        guard condition else { throw MotionProofFailure(message) }
    }

    private static func waitUntil(_ message: String, timeout: TimeInterval = 4, predicate: () -> Bool) async throws {
        let deadline = CACurrentMediaTime() + timeout
        repeat {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        try require(predicate(), message)
    }

    private static func waitForVisible(_ window: NSWindow) async throws {
        try await waitUntil("The owned native window did not become genuinely visible: \(diagnostics(window))") {
            window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
        }
    }

    private static func waitForClock(_ arc: CAShapeLayer) async throws {
        try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    "System Reduce Motion prevents the required rotation proof; the fixture never overrides it")
        try await waitUntil("Eligible native activity did not start rotation") { arc.animation(forKey: "inferenceRotation") != nil }
        try require(arc.animation(forKey: "inferenceRotation")?.duration == 1.4
            && arc.animation(forKey: "inferenceRotation")?.repeatCount == .infinity,
            "Native rotation must retain the production duration and repeat policy")
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        abs(atan2(sin(second - first), cos(second - first)))
    }

    private static func presentationAngle(_ arc: CAShapeLayer, in window: NSWindow,
                                          differingFrom initial: Double? = nil) async throws -> Double {
        let deadline = CACurrentMediaTime() + 4
        repeat {
            window.displayIfNeeded()
            CATransaction.flush()
            if let presentation = arc.presentation() {
                let transform = presentation.transform
                let angle = atan2(transform.m12, transform.m11)
                if angle.isFinite, initial.map({ angularDistance($0, angle) > 0.1 }) ?? true { return angle }
            }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        throw MotionProofFailure("A genuinely visible native compositor did not supply an advancing rotation angle")
    }

    private static func diagnostics(_ window: NSWindow) -> [String: Any] {
        ["windowNumber": window.windowNumber, "visible": window.isVisible,
         "occlusionState": window.occlusionState.rawValue, "onActiveSpace": window.isOnActiveSpace,
         "frame": NSStringFromRect(window.frame), "appRunning": NSApplication.shared.isRunning,
         "class": NSStringFromClass(type(of: window)), "level": window.level.rawValue,
         "opaque": window.isOpaque, "alpha": window.alphaValue, "shadow": window.hasShadow,
         "ignoresMouseEvents": window.ignoresMouseEvents, "contentOpaque": window.contentView?.isOpaque ?? false,
         "screenFrame": window.screen.map { NSStringFromRect($0.frame) } ?? "nil"]
    }

    /// Inspect ordering/opacity for only the two owned proof windows. Do not
    /// retain names, titles or metadata for any other application's windows.
    private static func windowServerDiagnostics(windowNumbers: Set<Int>) -> [[String: Any]] {
        let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] ?? []
        return entries.enumerated().compactMap { index, entry in
            guard let number = entry[kCGWindowNumber as String] as? Int, windowNumbers.contains(number), number > 0 else { return nil }
            return ["windowNumber": number, "frontToBackIndex": index,
                    "ownerPID": entry[kCGWindowOwnerPID as String] ?? -1,
                    "layer": entry[kCGWindowLayer as String] ?? -1,
                    "alpha": entry[kCGWindowAlpha as String] ?? -1,
                    "bounds": entry[kCGWindowBounds as String] ?? [String: Any](),
                    "onScreen": entry[kCGWindowIsOnscreen as String] ?? false]
        }
    }

    @MainActor
    private final class OwnedMotionCover {
        let process = Process()
        private let input = Pipe()
        private let output = Pipe()
        private let frame: NSRect
        private var outputBuffer = Data()
        private var launched = false
        private var outputClosed = false
        private var childTerminalReason: String?
        private var childWindowClosed = false
        private var cleanupEvidence = [String: Any]()
        private(set) var readyEvidence: [String: Any]?
        var windowNumber: Int { readyEvidence?["windowNumber"] as? Int ?? -1 }

        init(frame: NSRect) { self.frame = frame }

        func start() async throws {
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["--motion-cover", String(Double(frame.minX)), String(Double(frame.minY)),
                                 String(Double(frame.width)), String(Double(frame.height))]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            output.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil }
                Task { @MainActor [weak self] in self?.receive(data) }
            }
            try process.run()
            launched = true
            // Release the parent's copies of child-side endpoints. EOF on
            // stdin is the graceful stop request; stdout EOF proves draining.
            try input.fileHandleForReading.close()
            try output.fileHandleForWriting.close()
            try await MenuBarMotionProof.waitUntil("The owned cover process did not report its native window") {
                self.readyEvidence != nil || !self.process.isRunning
            }
            guard process.isRunning, let readyEvidence else {
                throw MotionProofFailure("The owned cover exited before readiness")
            }
            try MenuBarMotionProof.require(readyEvidence["processID"] as? Int == Int(process.processIdentifier)
                && process.processIdentifier != getpid() && windowNumber > 0
                && readyEvidence["opaque"] as? Bool == true && readyEvidence["contentOpaque"] as? Bool == true
                && readyEvidence["visible"] as? Bool == true
                && readyEvidence["level"] as? Int == NSWindow.Level.normal.rawValue + 1,
                "The distinct-process cover must report its own visible opaque native window")
            let dimensions = readyEvidence["frameValues"] as? [Double]
            try MenuBarMotionProof.require(dimensions == [Double(frame.minX), Double(frame.minY), Double(frame.width), Double(frame.height)],
                        "The child cover geometry must exactly match the requested frame")
        }

        private func receive(_ data: Data) {
            if data.isEmpty { outputClosed = true; return }
            guard outputBuffer.count + data.count <= 65_536 else { return }
            outputBuffer.append(data)
            while let newline = outputBuffer.firstIndex(of: 10) {
                let line = outputBuffer.prefix(upTo: newline)
                outputBuffer.removeSubrange(...newline)
                guard let event = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
                if event["event"] as? String == "ready" { readyEvidence = event }
                if event["event"] as? String == "terminal" {
                    childTerminalReason = event["reason"] as? String
                    childWindowClosed = event["windowClosed"] as? Bool == true
                }
            }
        }

        /// Await only this Process, never blocking AppKit's running main loop.
        /// A hung child is signaled only through its tracked live Process/PID.
        func stop() async -> [String: Any] {
            // Cleanup must finish even if the caller's proof task was canceled.
            await Task { @MainActor in
                self.cleanupEvidence = await self.stopUncancelled()
            }.value
            return cleanupEvidence
        }

        private func stopUncancelled() async -> [String: Any] {
            try? input.fileHandleForWriting.close()
            if launched {
                do { try await MenuBarMotionProof.waitUntil("Cover did not exit after EOF", timeout: 2) { !self.process.isRunning } }
                catch {
                    if process.isRunning { process.terminate() }
                    do { try await MenuBarMotionProof.waitUntil("Cover did not exit after termination", timeout: 1) { !self.process.isRunning } }
                    catch {
                        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
                        try? await MenuBarMotionProof.waitUntil("Owned cover did not exit after kill", timeout: 1) { !self.process.isRunning }
                    }
                }
                // Drain the small bounded terminal record, including the
                // child's actual reason, after the process has exited.
                if !process.isRunning {
                    try? await MenuBarMotionProof.waitUntil("Cover stdout did not reach EOF", timeout: 1) { self.outputClosed }
                }
            }
            output.fileHandleForReading.readabilityHandler = nil
            try? input.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? output.fileHandleForReading.close()
            return ["processID": launched ? Int(process.processIdentifier) : -1,
                    "exited": launched && !process.isRunning,
                    "exitStatus": launched && !process.isRunning ? Int(process.terminationStatus) : -1,
                    "terminationReason": launched && !process.isRunning
                        ? (process.terminationReason == .exit ? "exit" : "signal") : "not-exited",
                    "childTerminalReason": childTerminalReason ?? "not-reported",
                    "childWindowClosed": childWindowClosed]
        }
    }

    @MainActor
    private struct MotionArcFixture {
        let container: NSView
        let view: MenuBarActivityArc.ActivityArcView
        let window: NSWindow
        let arc: CAShapeLayer

        init() throws {
            container = MotionOpaqueTargetView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
            view = MenuBarActivityArc.ActivityArcView(frame: NSRect(x: 39, y: 39, width: 18, height: 18))
            container.addSubview(view)
            window = makeWindow(content: container)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            guard let layer = view.layer?.sublayers?.first as? CAShapeLayer else {
                throw MotionProofFailure("The native fixture could not create the production activity layer")
            }
            arc = layer
        }

        func restoreActive() async throws {
            if view.superview !== container { container.addSubview(view) }
            view.isHidden = false
            container.isHidden = false
            view.configure(active: true, tint: .systemYellow, reduceMotion: false)
            window.orderFront(nil)
            try await waitForVisible(window)
            try await waitForClock(arc)
        }
    }
}

/// Dispatched before the dashboard creates its model, defaults or dependencies.
/// This separate process owns exactly one opaque window and no app services.
@MainActor
enum MotionCoverHost {
    static func runIfRequested(arguments: [String]) -> Bool {
        guard arguments.contains("--motion-cover") else { return false }
        guard arguments.count == 6, arguments[1] == "--motion-cover" else {
            Darwin.exit(64)
        }
        let values = arguments.dropFirst(2).compactMap(Double.init)
        guard values.count == 4, values.allSatisfy(\.isFinite),
              abs(values[0]) <= 100_000, abs(values[1]) <= 100_000,
              (32...1_024).contains(values[2]), (32...1_024).contains(values[3]) else {
            Darwin.exit(64)
        }
        let frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard NSScreen.screens.contains(where: { $0.frame.contains(frame) }) else { Darwin.exit(64) }
        let application = NSApplication.shared
        let delegate = MotionCoverApplicationDelegate(frame: frame)
        application.setActivationPolicy(.accessory)
        application.delegate = delegate
        // One finite timeout, started before the native run loop. No polling,
        // provider setup, defaults suite, status item or dashboard is created.
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak delegate] in
            delegate?.finish(reason: "self-timeout")
        }
        application.run()
        withExtendedLifetime(delegate) {}
        return true
    }
}

@MainActor
private final class MotionCoverApplicationDelegate: NSObject, NSApplicationDelegate {
    private let frame: NSRect
    private var window: NSWindow?
    private var finished = false

    init(frame: NSRect) { self.frame = frame }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hasShadow = false
        window.backgroundColor = .black
        window.isOpaque = true
        window.alphaValue = 1
        window.level = NSWindow.Level(rawValue: NSWindow.Level.normal.rawValue + 1)
        window.contentView = MotionOpaqueCoverView(frame: NSRect(origin: .zero, size: frame.size))
        self.window = window
        window.orderFront(nil)
        window.contentView?.needsDisplay = true
        window.displayIfNeeded()
        CATransaction.flush()
        emit(["event": "ready", "processID": Int(getpid()), "windowNumber": window.windowNumber,
              "frameValues": [Double(window.frame.minX), Double(window.frame.minY),
                              Double(window.frame.width), Double(window.frame.height)],
              "frame": NSStringFromRect(window.frame), "opaque": window.isOpaque,
              "contentOpaque": window.contentView?.isOpaque ?? false, "visible": window.isVisible,
              "level": window.level.rawValue, "alpha": window.alphaValue])
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in self?.finish(reason: "parent-request") }
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func finish(reason: String) {
        guard !finished else { return }
        finished = true
        FileHandle.standardInput.readabilityHandler = nil
        window?.close()
        emit(["event": "terminal", "processID": Int(getpid()), "reason": reason,
              "windowClosed": window?.isVisible == false])
        NSApplication.shared.terminate(nil)
    }

    private func emit(_ event: [String: Any]) {
        guard var data = try? JSONSerialization.data(withJSONObject: event, options: [.sortedKeys]) else { return }
        data.append(10)
        try? FileHandle.standardOutput.write(contentsOf: data)
    }
}

private struct MotionProofFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private final class MotionProofReport {
    private let outputURL: URL
    private let startedAt = Date()
    private var cases: [[String: Any]] = []
    var failures: [String] = []
    private let requiredCases = ["native_window_visible", "active_compositor_advances", "repeated_updates_keep_one_clock",
        "self_hide_and_restore", "ancestor_hide_and_restore", "window_order_out_and_restore",
        "opaque_cover_occlusion_and_restore", "detach_and_restore", "same_window_close_and_reopen",
        "rapid_same_window_close_and_reopen", "native_stationary_true_false_true", "inactive_evidence_stops_immediately",
        "dismantle_retained_view", "parent_stationary_activity_bridge"]

    init(outputDirectory: URL) {
        outputURL = outputDirectory.appendingPathComponent("motion-lifecycle-proof.json")
    }

    func check(_ name: String, body: () async throws -> [String: Any]) async {
        let start = Date()
        do {
            let evidence = try await body()
            cases.append(["name": name, "status": "passed", "evidence": evidence, "seconds": Date().timeIntervalSince(start)])
            print("MotionProof \(name): passed")
        } catch {
            let failure = "\(name): \(error.localizedDescription)"
            failures.append(failure)
            cases.append(["name": name, "status": "failed", "error": error.localizedDescription, "seconds": Date().timeIntervalSince(start)])
            print("MotionProof \(failure)")
        }
        do { try write(terminal: false) }
        catch { failures.append("Progress manifest write failed: \(error.localizedDescription)") }
    }

    func write(terminal: Bool) throws {
        try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let missing = requiredCases.filter { required in !cases.contains { $0["name"] as? String == required } }
        let passed = terminal && failures.isEmpty && missing.isEmpty
        let payload: [String: Any] = ["proof": "native-menu-bar-motion", "synthetic": true,
            "terminal": terminal, "status": terminal ? (passed ? "passed" : "failed") : "running", "passed": passed,
            "processID": ProcessInfo.processInfo.processIdentifier, "startedAt": startedAt.timeIntervalSince1970,
            "elapsedSeconds": Date().timeIntervalSince(startedAt), "requiredCases": requiredCases,
            "cases": cases, "failures": failures, "missingCases": missing,
            "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: outputURL, options: .atomic)
    }

    func finish() -> Bool {
        do { try write(terminal: true) }
        catch { print("MotionProof terminal manifest write failed: \(error.localizedDescription)"); return false }
        let completed = cases.count == requiredCases.count
        let passed = completed && failures.isEmpty
        print("MotionProof terminal: \(passed ? "passed" : "failed") cases=\(cases.count)/\(requiredCases.count) output=\(outputURL.path)")
        return passed
    }
}

@MainActor
private final class MotionOpaqueTargetView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
    }
}

@MainActor
private final class MotionOpaqueCoverView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.setFill()
        bounds.fill()
    }
}
