#if FIXTURE_PRODUCTION_STATUS_ITEM_PROOF
import AppKit
import DarkbloomTelemetry
import QuartzCore

/// Opt-in diagnostic of the actual production status-item host. This requires
/// an already-running fixture application and a never-started, inert store.
/// It does not replace the normal native motion or human visual acceptance gate.
@MainActor
enum StatusItemHostProof {
    static func run(
        store: MonitorStore,
        snapshot: @MainActor (Bool) -> TelemetrySnapshot,
        defaults: UserDefaults,
        outputDirectory: URL
    ) async -> [String: Any] {
        let session = Session(store: store, defaults: defaults, outputDirectory: outputDirectory)
        defer { session.cleanup() }
        session.write()

        await session.check("actual_host_baseline") {
            try await accept(session, snapshot: snapshot, active: true)
            session.createController()
            let host = try await eligibleHost(session)
            session.baseline = host
            return try await motion(session, host: host, stage: "baseline")
        }
        await session.check("ten_fresh_store_updates_keep_one_clock") {
            try await accept(session, snapshot: snapshot, active: true)
            let host = try await eligibleHost(session)
            try session.requireBaseline(host)
            var updates = [[String: Any]]()
            for index in 1...10 {
                try await accept(session, snapshot: snapshot, active: true)
                // Give SwiftUI a separate run-loop opportunity for each
                // publication instead of coalescing all ten into one update.
                try await Task.sleep(for: .milliseconds(20))
                try session.requireSource()
                try requireSameHost(session, host: host)
                try requireClock(host.layer)
                updates.append(["update": index, "source": session.sourceDiagnostics(),
                                "animationKeys": host.layer.animationKeys() ?? []])
            }
            var evidence = try await motion(session, host: host, stage: "after_ten_updates")
            evidence["updates"] = updates
            return evidence
        }
        await session.check("active_idle_active") {
            try await accept(session, snapshot: snapshot, active: true)
            let host = try await eligibleHost(session)
            try session.requireBaseline(host)
            let before = try await motion(session, host: host, stage: "before_idle")
            try await accept(session, snapshot: snapshot, active: false)
            try await wait(session, code: "idle_clock_did_not_stop", message: "Idle telemetry did not hide the arc and remove its clock") {
                try requireSameHost(session, host: host)
                return host.layer.isHidden && (host.layer.animationKeys() ?? []).isEmpty
            }
            let idle = host.diagnostics()
            session.observe("idle_clock_stopped", host: host)
            try await accept(session, snapshot: snapshot, active: true)
            _ = try await eligibleHost(session)
            let after = try await motion(session, host: host, stage: "after_idle")
            return ["beforeIdle": before, "idle": idle, "afterIdle": after]
        }
        await session.check("production_popover_open_close") {
            try await accept(session, snapshot: snapshot, active: true)
            let host = try await eligibleHost(session)
            try session.requireBaseline(host)
            let before = try await motion(session, host: host, stage: "before_popover")
            try await accept(session, snapshot: snapshot, active: true)
            guard let controller = session.controller else { throw Failure("missing_controller", "The owned controller is missing") }
            defer { controller.popover.performClose(nil) }
            controller.showPopover()
            try await wait(session, code: "popover_did_not_open", message: "Production showPopover did not show its popover") {
                controller.popover.isShown && controller.popoverVisibility.isVisible
            }
            let shown = try await motion(session, host: host, stage: "popover_shown")
            try await accept(session, snapshot: snapshot, active: true)
            controller.popover.performClose(nil)
            try await wait(session, code: "popover_did_not_close", message: "Production performClose did not close its popover") {
                !controller.popover.isShown && !controller.popoverVisibility.isVisible
            }
            let closed = try await motion(session, host: host, stage: "popover_closed")
            return ["beforePopover": before, "shown": shown, "closed": closed,
                    "usedProductionShowPopover": true, "usedProductionPerformClose": true]
        }
        await session.check("invalidate_release_recreate") {
            try await accept(session, snapshot: snapshot, active: true)
            let oldHost = try await eligibleHost(session)
            try session.requireBaseline(oldHost)
            let before = try await motion(session, host: oldHost, stage: "before_invalidate")
            weak var oldController = session.controller
            let oldControllerIdentity = session.controller.map(identity) ?? "nil"
            session.invalidateController()
            try await wait(session, code: "invalidated_clock_did_not_stop", message: "Supported controller invalidation retained the old rotation clock") {
                (oldHost.layer.animationKeys() ?? []).isEmpty
            }
            session.observe("old_clock_stopped", host: oldHost)
            try require(oldController == nil, "old_controller_retained", "The invalidated controller did not release")
            // Retain the old native objects as evidence so pointer reuse cannot
            // make a replacement appear to have the same native identities.
            try await accept(session, snapshot: snapshot, active: true)
            session.createController()
            let newHost = try await eligibleHost(session)
            try require(newHost.button !== oldHost.button && newHost.view !== oldHost.view && newHost.layer !== oldHost.layer,
                        "native_host_not_replaced", "A recreated controller must own a new button, native view, and layer")
            session.baseline = newHost
            let after = try await motion(session, host: newHost, stage: "recreated_host")
            try session.requireSource()
            try require((oldHost.layer.animationKeys() ?? []).isEmpty,
                        "old_clock_restarted", "The retained old layer restarted after recreation")
            return ["beforeInvalidation": before, "oldControllerIdentity": oldControllerIdentity,
                    "oldControllerReleased": oldController == nil, "oldHost": oldHost.diagnostics(),
                    "newControllerIdentity": session.controller.map(identity) ?? "nil", "newHost": after]
        }
        if Task.isCancelled { session.cancelled = true }
        session.cleanup()
        // Teardown must be verified even when the proof was cancelled. This
        // bounded owned task is joined; it observes clocks without needing
        // fresh serving input and never changes the native layer.
        let cleanupVerification = Task { @MainActor in await session.verifyCleanup() }
        await cleanupVerification.value
        session.terminal = session.cancelled ? "cancelled" : "completed"
        session.write()
        return session.report()
    }

    private static func accept(_ session: Session, snapshot: @MainActor (Bool) -> TelemetrySnapshot, active: Bool) async throws {
        try Task.checkCancellation()
        let fresh = snapshot(active)
        session.expectedActive = active
        await session.store.accept(fresh)
        try Task.checkCancellation()
        try session.requireSource()
        session.observe(active ? "fresh_active_snapshot" : "fresh_idle_snapshot")
    }

    private static func eligibleHost(_ session: Session) async throws -> Host {
        // A failure in an earlier case may leave no controller. Later cases can
        // still independently diagnose a newly constructed production host.
        if session.controller == nil { session.createController() }
        try await wait(session, code: "native_host_not_mounted", message: "The production button did not mount exactly one native arc") {
            session.host() != nil
        }
        guard let host = session.host() else { throw Failure("native_host_not_mounted", "The production native arc is missing") }
        try await wait(session, code: "actual_host_not_visible", message: "The AppKit status-item host did not become compositor-visible") {
            try requireSameIdentity(session, host: host)
            return host.window.isVisible && !host.window.isMiniaturized && host.window.occlusionState.contains(.visible)
                && !host.view.isHiddenOrHasHiddenAncestor && !host.layer.isHidden
                && host.view.bounds.width > 0 && host.view.bounds.height > 0 && host.layer.path != nil
        }
        try await wait(session, code: "rotation_clock_missing", message: "The eligible production host did not acquire inferenceRotation") {
            try requireSameIdentity(session, host: host)
            return host.layer.animation(forKey: "inferenceRotation") != nil
        }
        try requireClock(host.layer)
        // Capture stable geometry after AppKit/SwiftUI's ordinary layout has
        // completed, rather than freezing the just-mounted zero-size view.
        guard let settled = session.host() else { throw Failure("native_host_missing", "The settled production host disappeared") }
        return settled
    }

    private static func motion(_ session: Session, host: Host, stage: String) async throws -> [String: Any] {
        let geometry = host.geometry
        let first = try await angle(session, host: host, geometry: geometry)
        let second = try await angle(session, host: host, geometry: geometry, differingFrom: first)
        session.observe(stage + "_before_hold", host: host)
        let started = CACurrentMediaTime()
        // Compositor-only hold: no display/layout/flush, source updates,
        // configuration, animation mutation, or production recovery callbacks.
        try await Task.sleep(for: .milliseconds(1_700))
        try Task.checkCancellation()
        let held = CACurrentMediaTime() - started
        try session.requireSource()
        try require(held > 1.6, "hold_too_short", "The compositor-only hold must exceed 1.6 seconds")
        let third = try await angle(session, host: host, geometry: geometry)
        let fourth = try await angle(session, host: host, geometry: geometry, differingFrom: third)
        session.observe(stage + "_after_hold", host: host)
        return ["native": host.diagnostics(), "source": session.sourceDiagnostics(),
                "beforeHoldAngles": [first, second], "beforeHoldAdvance": angularDistance(first, second),
                "holdSeconds": held, "afterHoldAngles": [third, fourth], "afterHoldAdvance": angularDistance(third, fourth),
                "compositorOnly": true, "forcedDisplayLayoutOrFlush": false]
    }

    private static func angle(_ session: Session, host: Host, geometry: Geometry, differingFrom initial: Double? = nil) async throws -> Double {
        var result: Double?
        try await wait(session, code: initial == nil ? "presentation_layer_missing" : "presentation_angle_stalled",
                       message: initial == nil ? "The actual host supplied no finite compositor angle" : "The actual host compositor angle did not advance") {
            try requireSameHost(session, host: host, geometry: geometry)
            try require(host.window.isVisible && !host.window.isMiniaturized && host.window.occlusionState.contains(.visible)
                        && !host.view.isHiddenOrHasHiddenAncestor && !host.layer.isHidden,
                        "host_visibility_lost", "The production arc lost genuine compositor visibility")
            try requireClock(host.layer)
            guard let presentation = host.layer.presentation() else { return false }
            let value = atan2(presentation.transform.m12, presentation.transform.m11)
            guard value.isFinite, initial.map({ angularDistance($0, value) > 0.1 }) ?? true else { return false }
            result = value
            return true
        }
        guard let result else { throw Failure("presentation_layer_missing", "No angle was recorded") }
        return result
    }

    private static func wait(_ session: Session, code: String, message: String, predicate: () throws -> Bool) async throws {
        let deadline = CACurrentMediaTime() + 3
        repeat {
            try Task.checkCancellation()
            try session.requireSource()
            if try predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        try Task.checkCancellation()
        try session.requireSource()
        if try predicate() { return }
        throw Failure(code, message)
    }

    private static func requireClock(_ layer: CAShapeLayer) throws {
        try require(layer.animationKeys() == ["inferenceRotation"], "rotation_clock_keys_invalid", "Expected exactly one inferenceRotation clock")
        guard let clock = layer.animation(forKey: "inferenceRotation") as? CABasicAnimation else {
            throw Failure("rotation_clock_type_invalid", "inferenceRotation must be a CABasicAnimation")
        }
        try require(clock.keyPath == "transform.rotation.z", "rotation_clock_keypath_invalid", "Rotation keyPath differs from production")
        try require(abs(clock.duration - 1.4) < 0.000001, "rotation_clock_duration_invalid", "Rotation duration must remain 1.4 seconds")
        try require(clock.repeatCount == .infinity, "rotation_clock_repeat_invalid", "Rotation must repeat infinitely")
    }

    private static func requireSameIdentity(_ session: Session, host: Host) throws {
        guard let current = session.host() else { throw Failure("native_host_missing", "The production native host disappeared") }
        try require(current.button === host.button && current.view === host.view && current.layer === host.layer && current.window === host.window,
                    "native_identity_changed", "The same controller must retain its button, native view, layer, and AppKit host window")
    }

    private static func requireSameHost(_ session: Session, host: Host, geometry: Geometry? = nil) throws {
        try requireSameIdentity(session, host: host)
        try require(host.geometry == (geometry ?? host.initialGeometry), "native_geometry_changed", "The production activity geometry changed")
    }

    private static func require(_ condition: Bool, _ code: String, _ message: String) throws {
        if !condition { throw Failure(code, message) }
    }

    private static func angularDistance(_ first: Double, _ second: Double) -> Double {
        abs(atan2(sin(second - first), cos(second - first)))
    }

    private static func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }

    private struct Failure: LocalizedError {
        let code: String
        let message: String
        init(_ code: String, _ message: String) { self.code = code; self.message = message }
        var errorDescription: String? { message }
    }

    private struct Geometry: Equatable {
        let buttonBounds: NSRect
        let viewFrame: NSRect
        let viewBounds: NSRect
        let layerFrame: NSRect
        let layerBounds: NSRect
        let pathBounds: CGRect?
        let lineWidth: CGFloat
        let strokeStart: CGFloat
        let strokeEnd: CGFloat
        var json: [String: Any] {
            ["buttonBounds": NSStringFromRect(buttonBounds), "viewFrame": NSStringFromRect(viewFrame),
             "viewBounds": NSStringFromRect(viewBounds), "layerFrame": NSStringFromRect(layerFrame),
             "layerBounds": NSStringFromRect(layerBounds), "pathBounds": pathBounds.map(NSStringFromRect) ?? "nil",
             "lineWidth": lineWidth, "strokeStart": strokeStart, "strokeEnd": strokeEnd]
        }
    }

    @MainActor
    private struct Host {
        let button: NSStatusBarButton
        let view: MenuBarActivityArc.ActivityArcView
        let layer: CAShapeLayer
        let window: NSWindow
        let initialGeometry: Geometry
        var geometry: Geometry {
            Geometry(buttonBounds: button.bounds, viewFrame: view.frame, viewBounds: view.bounds,
                     layerFrame: layer.frame, layerBounds: layer.bounds, pathBounds: layer.path?.boundingBoxOfPath,
                     lineWidth: layer.lineWidth, strokeStart: layer.strokeStart, strokeEnd: layer.strokeEnd)
        }
        init(button: NSStatusBarButton, view: MenuBarActivityArc.ActivityArcView, layer: CAShapeLayer, window: NSWindow) {
            self.button = button; self.view = view; self.layer = layer; self.window = window
            initialGeometry = Geometry(buttonBounds: button.bounds, viewFrame: view.frame, viewBounds: view.bounds,
                                       layerFrame: layer.frame, layerBounds: layer.bounds, pathBounds: layer.path?.boundingBoxOfPath,
                                       lineWidth: layer.lineWidth, strokeStart: layer.strokeStart, strokeEnd: layer.strokeEnd)
        }
        func diagnostics() -> [String: Any] {
            let clock = layer.animation(forKey: "inferenceRotation") as? CABasicAnimation
            let angle = layer.presentation().map { atan2($0.transform.m12, $0.transform.m11) }
            return ["buttonIdentity": identity(button), "viewIdentity": identity(view), "layerIdentity": identity(layer),
                    "windowIdentity": identity(window), "windowClass": NSStringFromClass(type(of: window)),
                    "windowNumber": window.windowNumber, "windowVisible": window.isVisible,
                    "windowOcclusionState": window.occlusionState.rawValue,
                    "compositorVisible": window.occlusionState.contains(.visible), "windowMiniaturized": window.isMiniaturized,
                    "windowOnActiveSpace": window.isOnActiveSpace, "windowFrame": NSStringFromRect(window.frame),
                    "attachedToExpectedWindow": view.window === window, "layerOwnedByView": layer.superlayer === view.layer,
                    "viewHiddenOrHasHiddenAncestor": view.isHiddenOrHasHiddenAncestor, "layerHidden": layer.isHidden,
                    "animationKeys": layer.animationKeys() ?? [], "clockKeyPath": clock?.keyPath ?? "nil",
                    "clockDuration": clock?.duration ?? -1, "clockRepeatInfinite": clock?.repeatCount == .infinity,
                    "presentationAngle": angle.flatMap { $0.isFinite ? $0 : nil }.map { $0 as Any } ?? NSNull(),
                    "geometry": geometry.json]
        }
    }

    @MainActor
    private final class Session {
        let store: MonitorStore
        let defaults: UserDefaults
        let outputURL: URL
        var controller: StatusItemController?
        var baseline: Host?
        var expectedActive = true
        var expectedModel: String?
        var results = [[String: Any]]()
        var observations = [[String: Any]]()
        var currentCase: String?
        var terminal = "running"
        var cancelled = false
        var created = 0
        var invalidated = 0
        var cleanupEvidence = [[String: Any]]()
        var invalidatedHosts = [(host: Host, eventIndex: Int)]()
        var cleanupVerificationComplete = false
        var writeErrors = [String]()

        init(store: MonitorStore, defaults: UserDefaults, outputDirectory: URL) {
            self.store = store; self.defaults = defaults
            outputURL = outputDirectory.appendingPathComponent("status-item-host-progress.json")
        }

        func createController() {
            guard controller == nil else { return }
            controller = StatusItemController(store: store, defaults: defaults)
            created += 1
        }

        func invalidateController() {
            guard let controller else { return }
            let before = host()
            controller.invalidate()
            invalidated += 1
            cleanupEvidence.append(["controllerIdentity": identity(controller), "supportedInvalidateCalled": true,
                                    "remainingAnimationKeysImmediately": before?.layer.animationKeys() ?? [],
                                    "clockStoppedImmediately": (before?.layer.animationKeys() ?? []).isEmpty,
                                    "nativeHostWasAvailable": before != nil])
            if let before { invalidatedHosts.append((before, cleanupEvidence.count - 1)) }
            self.controller = nil
        }

        func cleanup() { invalidateController() }

        func verifyCleanup() async {
            for entry in invalidatedHosts {
                let started = CACurrentMediaTime()
                while !(entry.host.layer.animationKeys() ?? []).isEmpty && CACurrentMediaTime() - started < 3 {
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                }
                let keys = entry.host.layer.animationKeys() ?? []
                cleanupEvidence[entry.eventIndex]["remainingAnimationKeysAfterSettle"] = keys
                cleanupEvidence[entry.eventIndex]["clockVerifiedStopped"] = keys.isEmpty
                cleanupEvidence[entry.eventIndex]["verificationSeconds"] = CACurrentMediaTime() - started
            }
            cleanupVerificationComplete = true
        }

        var allOwnedClocksVerifiedStopped: Bool {
            cleanupVerificationComplete && invalidatedHosts.count == invalidated
                && cleanupEvidence.allSatisfy { $0["clockVerifiedStopped"] as? Bool == true }
        }

        func requireSource() throws {
            try require(store.providerExtras == nil, "store_not_inert", "This proof requires providerExtras:nil")
            guard store.snapshot.menuStatus == .online, case .available(let state, _) = store.snapshot.state else {
                throw Failure("source_not_current", "The synthetic source must be online and available")
            }
            let age = Date().timeIntervalSince1970 - state.writtenAt
            try require(age.isFinite && (0...10).contains(age), "source_expired", "The production activity source is outside its 10-second freshness window (age \(age))")
            try require(state.inferenceActive == expectedActive, "source_activity_mismatch", "Synthetic activity does not match this check")
            try require(!state.currentModel.isEmpty, "source_model_missing", "The synthetic snapshot must identify the same model")
            if let expectedModel {
                try require(state.currentModel == expectedModel, "source_model_changed", "Synthetic snapshots changed model identity")
            } else { expectedModel = state.currentModel }
        }

        func sourceDiagnostics() -> [String: Any] {
            let state = store.snapshot.state.value
            let age = state.map { Date().timeIntervalSince1970 - $0.writtenAt }
            let available: Bool
            if case .available = store.snapshot.state { available = true } else { available = false }
            return ["capturedAt": store.snapshot.capturedAt.timeIntervalSince1970,
                    "writtenAt": state?.writtenAt ?? -1, "activityAgeSeconds": age ?? -1,
                    "sourceAvailable": available,
                    "freshAtObservation": available && store.snapshot.menuStatus == .online
                        && (age.map { $0.isFinite && (0...10).contains($0) } ?? false),
                    "freshnessLimitSeconds": 10, "model": state?.currentModel ?? "nil",
                    "inferenceActive": state?.inferenceActive ?? false, "expectedActive": expectedActive,
                    "menuStatus": String(describing: store.snapshot.menuStatus)]
        }

        func host() -> Host? {
            guard let button = controller?.fixtureProofButton else { return nil }
            func arcs(in view: NSView) -> [MenuBarActivityArc.ActivityArcView] {
                if let arc = view as? MenuBarActivityArc.ActivityArcView { return [arc] }
                return view.subviews.flatMap { arcs(in: $0) }
            }
            let views = arcs(in: button)
            guard views.count == 1, let view = views.first, let window = view.window,
                  window === button.window else { return nil }
            let shapes = view.layer?.sublayers?.compactMap { $0 as? CAShapeLayer } ?? []
            guard shapes.count == 1, let layer = shapes.first else { return nil }
            return Host(button: button, view: view, layer: layer, window: window)
        }

        func requireBaseline(_ host: Host) throws {
            if let baseline { try requireSameHost(self, host: baseline) }
            else { baseline = host }
        }

        func observe(_ stage: String, host explicitHost: Host? = nil) {
            observations.append(["case": currentCase ?? "none", "stage": stage,
                                 "at": Date().timeIntervalSince1970, "source": sourceDiagnostics(),
                                 "native": (explicitHost ?? host())?.diagnostics() ?? [:]])
            write()
        }

        func check(_ name: String, body: () async throws -> [String: Any]) async {
            if cancelled || Task.isCancelled {
                cancelled = true
                results.append(["case": name, "passed": false, "status": "cancelled", "failureCode": "cancelled"])
                write()
                return
            }
            currentCase = name
            write()
            let started = CACurrentMediaTime()
            var result: [String: Any] = ["case": name]
            do {
                try require(store.providerExtras == nil, "store_not_inert", "This proof requires providerExtras:nil")
                try require(NSApplication.shared.isRunning, "app_loop_not_running", "This diagnostic requires the fixture's normal NSApplication loop")
                try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                            "system_reduce_motion", "System Reduce Motion prevents rotation proof; the preference is preserved")
                result["evidence"] = try await body()
                try Task.checkCancellation()
                try requireSource()
                result["passed"] = true
                result["status"] = "passed"
            } catch is CancellationError {
                cancelled = true
                result["passed"] = false
                result["status"] = "cancelled"
                result["failureCode"] = "cancelled"
            } catch {
                result["passed"] = false
                result["status"] = "failed"
                result["failureCode"] = (error as? Failure)?.code ?? "unexpected_error"
                result["failure"] = error.localizedDescription
            }
            result["elapsedSeconds"] = CACurrentMediaTime() - started
            result["sourceAtEnd"] = sourceDiagnostics()
            result["nativeAtEnd"] = host()?.diagnostics() ?? [:]
            results.append(result)
            currentCase = nil
            write()
        }

        func report() -> [String: Any] {
            ["schemaVersion": 1, "proof": "production_status_item_host", "pid": ProcessInfo.processInfo.processIdentifier,
             "diagnosticOnly": true, "replacesNormalNativeGate": false, "terminal": terminal,
             "passed": !cancelled && terminal == "completed" && results.count == 5
                && results.allSatisfy { $0["passed"] as? Bool == true } && writeErrors.isEmpty
                && controller == nil && created == invalidated && allOwnedClocksVerifiedStopped,
             "currentCase": currentCase ?? "none", "results": results, "observations": observations,
             "finalSource": sourceDiagnostics(), "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
             "ownedCleanup": ["controllersCreated": created, "controllersInvalidated": invalidated,
                              "allOwnedStatusItemsInvalidated": created == invalidated,
                              "allOwnedClocksVerifiedStopped": allOwnedClocksVerifiedStopped,
                              "cleanupVerificationComplete": cleanupVerificationComplete,
                              "remainingOwnedController": controller != nil, "events": cleanupEvidence],
             "reportWriteErrors": writeErrors]
        }

        func write() {
            do {
                try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: report(), options: [.prettyPrinted, .sortedKeys])
                try data.write(to: outputURL, options: .atomic)
            } catch {
                let message = error.localizedDescription
                if !writeErrors.contains(message) { writeErrors.append(message) }
            }
        }
    }
}
#endif
