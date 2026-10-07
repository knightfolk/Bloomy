#if FIXTURE_SETTINGS_PREVIEW_PROOF
import AppKit
import DarkbloomTelemetry
import QuartzCore

/// Reads the preview in the production DashboardWindowController/RootView. No surrogate
/// host, layer mutation, forced display/layout or visibility notification.
@MainActor
enum SettingsPreviewProof {
    static func run(window: NSWindow, navigation: DashboardNavigation, store: MonitorStore,
                    publish: @MainActor (Bool) async -> Void,
                    reopen: @MainActor () -> Void, outputDirectory: URL) async -> [String: Any] {
        let session = Session(window: window, navigation: navigation, store: store, output: outputDirectory)
        func fresh(_ active: Bool = true) async throws {
            try Task.checkCancellation()
            session.active = active
            await publish(active)
            try session.requireSource()
        }
        func showPreview() {
            navigation.sidebarSelection = .settings(.menuBar)
            navigation.revealSelectedSection()
        }
        await session.check("actual_settings_baseline") {
            try await fresh()
            showPreview()
            let host = try await session.eligible()
            return try await session.motion(host, stage: "baseline")
        }
        await session.check("ten_fresh_updates") {
            try await fresh()
            let host = try await session.eligible()
            for _ in 1...10 {
                try await fresh()
                try await Task.sleep(for: .milliseconds(20))
                try session.requireIdentity(host)
                try session.requireClock(host.layer)
            }
            return try await session.motion(host, stage: "after_ten_updates")
        }
        await session.check("active_idle_active") {
            try await fresh()
            let host = try await session.eligible()
            try await fresh(false)
            try await session.wait("idle_clock_not_stopped") {
                try session.requireIdentity(host)
                return host.layer.isHidden && (host.layer.animationKeys() ?? []).isEmpty
            }
            let idle = host.json
            try await fresh()
            _ = try await session.eligible()
            var evidence = try await session.motion(host, stage: "after_idle")
            evidence["idle"] = idle
            return evidence
        }
        await session.check("navigate_away_return") {
            try await fresh()
            let old = try await session.eligible()
            navigation.sidebarSelection = .settings(.appearance)
            try await session.wait("departed_preview_not_dismantled") {
                session.nativeArcs().isEmpty && (old.layer.animationKeys() ?? []).isEmpty
            }
            let departed = old.json
            try await fresh()
            showPreview()
            let new = try await session.eligible()
            try require(new.view !== old.view && new.layer !== old.layer, "navigation_reused_dismantled_preview")
            try require((old.layer.animationKeys() ?? []).isEmpty, "departed_clock_restarted")
            var evidence = try await session.motion(new, stage: "returned_to_settings")
            evidence["departed"] = departed
            return evidence
        }
        await session.check("minimize_restore") {
            try await fresh()
            let host = try await session.eligible()
            window.performMiniaturize(nil)
            try await session.wait("minimized_clock_not_stopped") {
                window.isMiniaturized && !store.dashboardVisible && (host.layer.animationKeys() ?? []).isEmpty
            }
            let minimized = host.json
            reopen()
            _ = try await session.eligible()
            var evidence = try await session.motion(host, stage: "restored_from_minimize")
            evidence["minimized"] = minimized
            return evidence
        }
        await session.check("retained_close_reopen") {
            try await fresh()
            let host = try await session.eligible()
            window.performClose(nil)
            try await session.wait("closed_clock_not_stopped") {
                !window.isVisible && !store.dashboardVisible && (host.layer.animationKeys() ?? []).isEmpty
            }
            let closed = host.json
            reopen()
            _ = try await session.eligible()
            var evidence = try await session.motion(host, stage: "retained_window_reopened")
            evidence["closed"] = closed
            return evidence
        }
        await session.check("rapid_close_reopen") {
            try await fresh()
            let host = try await session.eligible()
            // Same supported close/presentation sequence without an artificial
            // yield between them, followed by an unchanged compositor hold.
            window.performClose(nil)
            reopen()
            _ = try await session.eligible()
            return try await session.motion(host, stage: "rapid_reopen")
        }
        // Leave the tested route through its normal navigation owner. Cleanup
        // observes retained old layers even after cancellation; it never edits them.
        navigation.sidebarSelection = .destination(.overview)
        let cleanup = Task { @MainActor in
            let started = CACurrentMediaTime()
            while session.hosts.contains(where: { !($0.layer.animationKeys() ?? []).isEmpty })
                    && CACurrentMediaTime() - started < 3 {
                try? await Task.sleep(for: .milliseconds(20))
            }
            session.cleanupVerified = session.hosts.allSatisfy { ($0.layer.animationKeys() ?? []).isEmpty }
        }
        await cleanup.value
        session.cancelled = session.cancelled || Task.isCancelled
        session.terminal = session.cancelled ? "cancelled" : "completed"
        session.write()
        return session.report
    }

    private static func require(_ value: Bool, _ code: String) throws {
        if !value { throw Failure(code: code) }
    }
    private struct Failure: LocalizedError {
        let code: String
        var errorDescription: String? { code }
    }
    private static func identity(_ object: AnyObject) -> String { String(describing: ObjectIdentifier(object)) }
    private static func distance(_ a: Double, _ b: Double) -> Double {
        abs(atan2(sin(a - b), cos(a - b)))
    }

    @MainActor
    private struct Host {
        let view: MenuBarActivityArc.ActivityArcView
        let layer: CAShapeLayer
        var geometry: [String] {
            [NSStringFromRect(view.bounds), NSStringFromRect(layer.frame), NSStringFromRect(layer.bounds),
             layer.path.map { NSStringFromRect($0.boundingBoxOfPath) } ?? "nil",
             String(Double(layer.lineWidth)), String(Double(layer.strokeStart)), String(Double(layer.strokeEnd))]
        }
        var json: [String: Any] {
            let clock = layer.animation(forKey: "inferenceRotation") as? CABasicAnimation
            return ["viewIdentity": identity(view), "layerIdentity": identity(layer),
                    "windowIdentity": view.window.map(identity) ?? "nil", "geometry": geometry,
                    "viewVisibleRect": NSStringFromRect(view.visibleRect),
                    "hiddenAncestor": view.isHiddenOrHasHiddenAncestor, "layerHidden": layer.isHidden,
                    "animationKeys": layer.animationKeys() ?? [], "clockDuration": clock?.duration ?? -1,
                    "presentationAngle": layer.presentation().map { atan2($0.transform.m12, $0.transform.m11) } ?? 0]
        }
    }

    @MainActor
    private final class Session {
        let window: NSWindow
        let navigation: DashboardNavigation
        let store: MonitorStore
        let output: URL
        var active = true
        var results = [[String: Any]]()
        var hosts = [Host]()
        var angleSamples = [[String: Any]]()
        var terminal = "running"
        var currentCase = "none"
        var cancelled = false
        var cleanupVerified = false
        var writeErrors = [String]()
        init(window: NSWindow, navigation: DashboardNavigation, store: MonitorStore, output: URL) {
            self.window = window; self.navigation = navigation; self.store = store; self.output = output
        }
        func host() -> Host? {
            let views = nativeArcs()
            guard views.count == 1, let view = views.first, view.window === window,
                  let shapes = view.layer?.sublayers?.compactMap({ $0 as? CAShapeLayer }), shapes.count == 1 else { return nil }
            return Host(view: view, layer: shapes[0])
        }
        func nativeArcs() -> [MenuBarActivityArc.ActivityArcView] {
            func arcs(_ root: NSView) -> [MenuBarActivityArc.ActivityArcView] {
                if let arc = root as? MenuBarActivityArc.ActivityArcView { return [arc] }
                return root.subviews.flatMap(arcs)
            }
            return window.contentView.map(arcs) ?? []
        }
        func requireSource() throws {
            guard case .available(let state, _) = store.snapshot.state else { throw Failure(code: "source_unavailable") }
            let age = Date().timeIntervalSince1970 - state.writtenAt
            try require(store.snapshot.menuStatus == .online && state.inferenceActive == active
                        && age.isFinite && (0...10).contains(age), "source_not_fresh_or_expected")
        }
        var source: [String: Any] {
            ["storeIdentity": identity(store), "writtenAt": store.snapshot.state.value?.writtenAt ?? -1,
             "ageSeconds": store.snapshot.state.value.map { Date().timeIntervalSince1970 - $0.writtenAt } ?? -1,
             "expectedActive": active, "observedActive": store.snapshot.state.value?.inferenceActive ?? false,
             "dashboardVisible": store.dashboardVisible]
        }
        var windowState: [String: Any] {
            ["identity": identity(window), "visible": window.isVisible, "miniaturized": window.isMiniaturized,
             "occlusionVisible": window.occlusionState.contains(.visible), "onActiveSpace": window.isOnActiveSpace,
             "number": window.windowNumber, "frame": NSStringFromRect(window.frame),
             "class": NSStringFromClass(type(of: window)), "keyWindow": window.isKeyWindow,
             "applicationActive": NSApplication.shared.isActive, "nativeArcCount": nativeArcs().count,
             "ownedWindowServerEntries": ownedWindowServerEntries,
             "route": navigation.selected.rawValue, "settingsPage": navigation.settingsPage.rawValue]
        }
        var ownedWindowServerEntries: [[String: Any]] {
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            return entries.enumerated().compactMap { index, entry in
                guard entry[kCGWindowNumber as String] as? Int == window.windowNumber,
                      entry[kCGWindowOwnerPID as String] as? Int == Int(ProcessInfo.processInfo.processIdentifier) else { return nil }
                return ["number": window.windowNumber, "frontToBackIndex": index,
                        "ownerPID": entry[kCGWindowOwnerPID as String] ?? -1,
                        "layer": entry[kCGWindowLayer as String] ?? -1,
                        "alpha": entry[kCGWindowAlpha as String] ?? -1,
                        "bounds": entry[kCGWindowBounds as String] ?? [:],
                        "onScreen": entry[kCGWindowIsOnscreen as String] ?? false]
            }
        }
        func wait(_ code: String, _ predicate: () throws -> Bool) async throws {
            let start = CACurrentMediaTime()
            repeat {
                try Task.checkCancellation()
                try requireSource()
                if try predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            } while CACurrentMediaTime() - start < 3
            throw Failure(code: code)
        }
        func eligible() async throws -> Host {
            try await wait("settings_preview_not_eligible") {
                guard navigation.sidebarSelection == .settings(.menuBar), let host = host(),
                      window.isVisible, !window.isMiniaturized, window.occlusionState.contains(.visible), store.dashboardVisible,
                      !host.view.isHiddenOrHasHiddenAncestor, host.view.visibleRect.intersects(host.view.bounds), !host.layer.isHidden,
                      host.view.bounds.size == NSSize(width: 18, height: 18),
                      host.layer.bounds.size == NSSize(width: 18, height: 18), host.layer.path != nil,
                      host.layer.animation(forKey: "inferenceRotation") != nil else { return false }
                try requireClock(host.layer)
                return true
            }
            guard let host = host() else { throw Failure(code: "preview_missing") }
            if !hosts.contains(where: { $0.view === host.view }) { hosts.append(host) }
            return host
        }
        func requireIdentity(_ old: Host) throws {
            guard let host = host() else { throw Failure(code: "preview_missing") }
            try require(host.view === old.view && host.layer === old.layer && host.view.window === window,
                        "preview_identity_changed")
        }
        func requireClock(_ layer: CAShapeLayer) throws {
            try require(layer.animationKeys() == ["inferenceRotation"], "preview_clock_keys")
            guard let clock = layer.animation(forKey: "inferenceRotation") as? CABasicAnimation else { throw Failure(code: "preview_clock_type") }
            try require(clock.keyPath == "transform.rotation.z" && abs(clock.duration - 1.4) < 0.000001
                        && clock.repeatCount == .infinity, "preview_clock_parameters")
        }
        func angle(_ host: Host, geometry: [String], after: Double? = nil) async throws -> Double {
            var result: Double?
            try await wait(after == nil ? "presentation_missing" : "presentation_stalled") {
                try requireIdentity(host)
                try require(host.geometry == geometry, "preview_geometry_changed")
                try require(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible) && store.dashboardVisible
                            && !host.view.isHiddenOrHasHiddenAncestor && host.view.visibleRect.intersects(host.view.bounds) && !host.layer.isHidden,
                            "preview_visibility_lost")
                try requireClock(host.layer)
                guard let layer = host.layer.presentation() else { return false }
                let value = atan2(layer.transform.m12, layer.transform.m11)
                guard value.isFinite, after.map({ distance($0, value) > 0.1 }) ?? true else { return false }
                result = value
                angleSamples.append(["case": currentCase, "angle": value, "source": source,
                                     "window": windowState, "native": host.json])
                return true
            }
            guard let result else { throw Failure(code: "presentation_missing") }
            return result
        }
        func motion(_ host: Host, stage: String) async throws -> [String: Any] {
            let geometry = host.geometry
            let first = try await angle(host, geometry: geometry)
            let second = try await angle(host, geometry: geometry, after: first)
            let before = host.json
            let started = CACurrentMediaTime()
            try await Task.sleep(for: .milliseconds(1_700))
            let held = CACurrentMediaTime() - started
            try require(held > 1.6, "hold_too_short")
            let third = try await angle(host, geometry: geometry)
            let fourth = try await angle(host, geometry: geometry, after: third)
            return ["stage": stage, "beforeHold": before, "afterHold": host.json,
                    "beforeHoldAngles": [first, second], "afterHoldAngles": [third, fourth],
                    "holdSeconds": held, "source": source, "window": windowState,
                    "compositorOnly": true, "forcedLayoutDisplayFlush": false]
        }
        func check(_ name: String, body: () async throws -> [String: Any]) async {
            currentCase = name
            write()
            var result: [String: Any] = ["case": name]
            do {
                try Task.checkCancellation()
                try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, "system_reduce_motion")
                result["evidence"] = try await body()
                try Task.checkCancellation()
                try requireSource()
                result["passed"] = true
            } catch is CancellationError {
                cancelled = true
                result["passed"] = false; result["failure"] = "cancelled"
            } catch {
                result["passed"] = false; result["failure"] = error.localizedDescription
            }
            result["sourceAtEnd"] = source; result["windowAtEnd"] = windowState
            result["nativeAtEnd"] = host()?.json ?? [:]
            results.append(result)
            write()
        }
        var report: [String: Any] {
            ["schemaVersion": 1, "proof": "actual_dashboard_settings_preview", "synthetic": true,
             "pid": ProcessInfo.processInfo.processIdentifier, "diagnosticOnly": true,
             "replacesNormalNativeGate": false, "terminal": terminal, "currentCase": currentCase,
             "passed": terminal == "completed" && !cancelled && results.count == 7
                && results.allSatisfy { $0["passed"] as? Bool == true } && cleanupVerified && writeErrors.isEmpty,
             "results": results, "cleanupVerified": cleanupVerified, "retainedHosts": hosts.map(\.json),
             "angleSamples": angleSamples,
             "window": windowState, "source": source, "reportWriteErrors": writeErrors]
        }
        func write() {
            do {
                try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                try data.write(to: output.appendingPathComponent("settings-preview-progress.json"), options: .atomic)
            } catch { writeErrors.append(error.localizedDescription) }
        }
    }
}
#endif
