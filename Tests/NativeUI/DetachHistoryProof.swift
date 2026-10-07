#if FIXTURE_DETACH_HISTORY_PROOF
import AppKit
import QuartzCore

/// A separate, counterbalanced diagnostic. The original fifteen-case gate and
/// production callbacks remain unchanged. No recovery, display or flush calls.
@MainActor
enum DetachHistoryProof {
    static func run(output: URL) async -> [String: Any] {
        let session = Session(output: output)
        do {
            for round in 0..<2 {
                try Task.checkCancellation()
                let roles = round == 0 ? [false, true] : [true, false]
                var pair = [Target]()
                for (position, detached) in roles.enumerated() {
                    let target = try Target(round: round, position: position, detached: detached)
                    session.targets.append(target)
                    pair.append(target)
                }
                for target in pair {
                    await session.check(target, "baseline") {
                        try await target.prepare()
                        return try await target.motion()
                    }
                }
                for target in pair {
                    await session.check(target, "history") {
                        try await target.prepare()
                        if target.detached {
                            target.view.removeFromSuperview()
                            try require(target.view.window == nil && target.arc.animationKeys() == nil,
                                        "detach_did_not_stop_clock")
                            target.container.addSubview(target.view)
                        } else {
                            try require(target.view.superview === target.container,
                                        "control_unexpectedly_detached")
                        }
                        // Observe automatic recovery. No fresh configure,
                        // presentation, display or flush can rescue either arm.
                        try await target.eligible()
                        return try await target.motion()
                    }
                }
                for phase in ["normal_reopen", "rapid_reopen"] {
                    for target in pair {
                        await session.check(target, phase) {
                            try await target.prepare()
                            target.window.close()
                            try require(!target.window.isVisible && (target.arc.animationKeys() ?? []).isEmpty,
                                        "close_did_not_stop_clock")
                            try target.identity()
                            if phase == "normal_reopen" {
                                try await wait("closed_window_still_compositor_visible") {
                                    !target.window.occlusionState.contains(.visible)
                                }
                            }
                            target.present()
                            // Nothing reconfigures or redraws after close/reopen.
                            try await target.eligible()
                            return try await target.motion()
                        }
                    }
                }
                for target in pair { target.window.close() }
            }
        } catch {
            session.preparationError = error.localizedDescription
        }
        // Owned cleanup must also finish when Quit cancels the parent task.
        await Task { @MainActor in
            for target in session.targets {
                MenuBarActivityArc.dismantleNSView(target.view, coordinator: ())
                target.window.close()
            }
            session.cleanupVerified = session.targets.allSatisfy {
                !$0.window.isVisible && ($0.arc.animationKeys() ?? []).isEmpty
            }
        }.value
        session.cancelled = session.cancelled || Task.isCancelled
        session.recordUnexecutedCases()
        session.terminal = session.cancelled ? "cancelled" : "completed"
        session.write()
        return session.report
    }

    private struct Failure: LocalizedError {
        let code: String
        var errorDescription: String? { code }
    }
    private static func require(_ condition: Bool, _ code: String) throws {
        if !condition { throw Failure(code: code) }
    }
    private static func wait(_ code: String, _ condition: () throws -> Bool) async throws {
        let start = CACurrentMediaTime()
        repeat {
            try Task.checkCancellation()
            if try condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() - start < 4
        throw Failure(code: code)
    }
    private static func id(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
    private static func distance(_ a: Double, _ b: Double) -> Double { abs(atan2(sin(a - b), cos(a - b))) }

    @MainActor
    private final class OpaqueTargetView: NSView {
        override var isOpaque: Bool { true }
        override func draw(_ dirtyRect: NSRect) {
            NSColor.windowBackgroundColor.setFill()
            bounds.fill()
        }
    }

    @MainActor
    private final class Target {
        let round: Int
        let detached: Bool
        let position: Int
        let container: NSView
        let view: MenuBarActivityArc.ActivityArcView
        let window: NSWindow
        let arc: CAShapeLayer
        let originalGeometry: [String]

        init(round: Int, position: Int, detached: Bool) throws {
            self.round = round; self.position = position; self.detached = detached
            container = OpaqueTargetView(frame: NSRect(x: 0, y: 0, width: 96, height: 96))
            view = MenuBarActivityArc.ActivityArcView(frame: NSRect(x: 39, y: 39, width: 18, height: 18))
            container.addSubview(view)
            let screen = (NSApplication.shared.mainWindow?.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 800, height: 600)
            let frame = NSRect(x: screen.midX + (position == 0 ? -128 : 32), y: screen.midY - 48,
                               width: 96, height: 96)
            window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
            window.level = .normal; window.isOpaque = true; window.hasShadow = true
            window.backgroundColor = .windowBackgroundColor
            window.collectionBehavior = [.moveToActiveSpace]
            window.contentView = container
            view.needsLayout = true; view.layoutSubtreeIfNeeded()
            guard let shape = view.layer?.sublayers?.first as? CAShapeLayer else {
                window.close(); throw Failure(code: "native_arc_missing")
            }
            arc = shape
            originalGeometry = Self.geometry(view: view, arc: shape)
        }
        static func geometry(view: NSView, arc: CAShapeLayer) -> [String] {
            [NSStringFromRect(view.frame), NSStringFromRect(view.bounds), NSStringFromRect(arc.frame),
             arc.path.map { NSStringFromRect($0.boundingBoxOfPath) } ?? "nil",
             String(Double(arc.lineWidth)), String(Double(arc.strokeStart)), String(Double(arc.strokeEnd))]
        }
        func identity() throws {
            try require(window.contentView === container && view.superview === container && view.window === window
                        && arc.superlayer === view.layer && view.layer?.sublayers?.first === arc,
                        "native_identity_or_attachment_changed")
            try require(Self.geometry(view: view, arc: arc) == originalGeometry, "native_geometry_changed")
        }
        func clock() throws {
            let animation = arc.animation(forKey: "inferenceRotation") as? CABasicAnimation
            try require(arc.animationKeys() == ["inferenceRotation"] && animation?.keyPath == "transform.rotation.z"
                        && animation?.duration == 1.4 && animation?.repeatCount == .infinity, "clock_missing_or_changed")
        }
        func present() {
            NSApplication.shared.activate(ignoringOtherApps: true)
            window.orderFrontRegardless()
        }
        func prepare() async throws {
            try identity()
            view.configure(active: true, tint: .systemYellow, reduceMotion: false)
            present()
            try await eligible()
        }
        func eligible() async throws {
            try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "system_reduce_motion_enabled")
            try await wait("native_host_not_eligible") {
                try self.isEligible()
            }
            try await wait("eligible_host_clock_missing") { self.arc.animationKeys() == ["inferenceRotation"] }
            try clock()
        }
        func isEligible() throws -> Bool {
            try identity()
            return window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
                && !view.isHiddenOrHasHiddenAncestor && view.visibleRect.intersects(view.bounds) && !arc.isHidden
                && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        }
        func angle(after first: Double? = nil) async throws -> Double {
            var result = 0.0
            try await wait("visible_compositor_not_advancing") {
                try self.clock()
                try require(self.isEligible(), "host_lost_native_eligibility")
                guard let layer = self.arc.presentation() else { return false }
                let angle = atan2(layer.transform.m12, layer.transform.m11)
                guard angle.isFinite, first.map({ distance($0, angle) > 0.1 }) ?? true else { return false }
                result = angle; return true
            }
            return result
        }
        func motion() async throws -> [String: Any] {
            let first = try await angle(); let second = try await angle(after: first)
            let start = CACurrentMediaTime()
            try await Task.sleep(for: .milliseconds(1_600))
            let hold = CACurrentMediaTime() - start
            try require(hold > 1.4, "hold_shorter_than_rotation")
            let third = try await angle(); let fourth = try await angle(after: third)
            return ["holdSeconds": hold, "beforeAngles": [first, second], "afterAngles": [third, fourth],
                    "afterAdvance": distance(third, fourth), "forcedDisplay": false, "state": state]
        }
        var state: [String: Any] {
            ["round": round, "position": position, "detached": detached,
             "viewIdentity": id(view), "arcIdentity": id(arc), "windowIdentity": id(window),
             "geometry": Self.geometry(view: view, arc: arc), "visible": window.isVisible,
             "occlusionVisible": window.occlusionState.contains(.visible), "onActiveSpace": window.isOnActiveSpace,
             "appActive": NSApplication.shared.isActive, "windowNumber": window.windowNumber,
             "frame": NSStringFromRect(window.frame), "animationKeys": arc.animationKeys() ?? [],
             "attached": view.window === window && view.superview === container]
        }
    }
    @MainActor
    private final class Session {
        let output: URL
        var targets = [Target]()
        var cases = [[String: Any]]()
        var currentCase = "none"
        var terminal = "running"
        var cancelled = false
        var cleanupVerified = false
        var preparationError: String?
        var writeErrors = [String]()
        init(output: URL) { self.output = output }
        func recordUnexecutedCases() {
            let completed = Set(cases.compactMap { $0["case"] as? String })
            for round in 0..<2 {
                for role in ["attached", "detached"] {
                    for phase in ["baseline", "history", "normal_reopen", "rapid_reopen"] {
                        let name = "round_\(round)_\(role)_\(phase)"
                        if !completed.contains(name) {
                            cases.append(["case": name, "passed": false, "cancelled": cancelled,
                                "error": cancelled ? "cancelled_before_execution" : "not_executed_after_preparation_failure"])
                        }
                    }
                }
            }
        }
        func check(_ target: Target, _ phase: String, _ body: () async throws -> [String: Any]) async {
            currentCase = "round_\(target.round)_\(target.detached ? "detached" : "attached")_\(phase)"
            write()
            do {
                try Task.checkCancellation()
                let evidence = try await body()
                cases.append(["case": currentCase, "passed": true, "evidence": evidence])
            } catch {
                cancelled = cancelled || Task.isCancelled || error is CancellationError
                cases.append(["case": currentCase, "passed": false, "cancelled": Task.isCancelled,
                              "error": error.localizedDescription, "state": target.state])
            }
            write()
        }
        var report: [String: Any] {
            ["proof": "manual_host_detach_history", "synthetic": true, "replacesNormalNativeGate": false,
             "terminal": terminal, "passed": terminal == "completed" && cases.count == 16
                && cases.allSatisfy { $0["passed"] as? Bool == true } && cleanupVerified && writeErrors.isEmpty,
             "currentCase": currentCase, "cases": cases, "targets": targets.map(\.state),
             "cleanupVerified": cleanupVerified, "preparationError": preparationError ?? "none", "writeErrors": writeErrors]
        }
        func write() {
            do {
                let bytes = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try bytes.write(to: output.appendingPathComponent("detach-history-result.json"), options: .atomic)
            } catch { writeErrors.append(error.localizedDescription) }
        }
    }
}
#endif
