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
                    reopen: @MainActor () -> Void, extrasClient: SettingsProofExtras,
                    outputDirectory: URL) async -> [String: Any] {
        let session = Session(window: window, navigation: navigation, store: store, output: outputDirectory)
        let occlusionObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeOcclusionStateNotification, object: window, queue: .main
        ) { [weak session] _ in
            MainActor.assumeIsolated {
                session?.recordOcclusionNotification()
            }
        }
        defer { NotificationCenter.default.removeObserver(occlusionObserver) }
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
        await session.check("independent_fan_temperature_updates") {
            try await fresh()
            let host = try await session.eligible()
            let geometry = host.geometry
            var readings = [[String: Any]]()
            for (temperature, percent, color) in [(54.0, 25.0, NSColor.systemGreen),
                                                   (70.0, 50.0, NSColor.systemYellow),
                                                   (85.0, 100.0, NSColor.systemRed)] {
                try await fresh()
                let beforeReads = await extrasClient.readCount
                await extrasClient.set(temperature: temperature, fanPercent: percent)
                await store.providerExtras?.refresh()
                let afterReads = await extrasClient.readCount
                try require(afterReads == beforeReads + 1, "unexpected_extras_read_count")
                try session.requireReadings(temperature: temperature, fanPercent: percent, stale: false)
                try await session.wait("fan_temperature_color_not_rendered") {
                    try session.requireIdentity(host)
                    try require(host.geometry == geometry, "fan_update_changed_geometry")
                    return session.colorMatches(host, expected: color)
                }
                var evidence = try await session.motion(host, stage: "fan_\(temperature)")
                evidence["temperature"] = temperature; evidence["fanPercent"] = percent
                evidence["clientReads"] = afterReads
                readings.append(evidence)
            }
            return ["readings": readings, "sameHost": true]
        }
        await session.check("failed_fan_read_and_recovery") {
            try await fresh()
            let host = try await session.eligible()
            let geometry = host.geometry
            // Establish this case independently of the preceding color ramp.
            await extrasClient.set(temperature: 85, fanPercent: 100)
            await store.providerExtras?.refresh()
            try session.requireReadings(temperature: 85, fanPercent: 100, stale: false)
            try await session.wait("fresh_fan_baseline_not_rendered") {
                try session.requireIdentity(host)
                try require(host.geometry == geometry, "fresh_fan_baseline_changed_geometry")
                try session.requireClock(host.layer)
                return session.colorMatches(host, expected: .systemRed)
            }
            let freshBaseline = host.json
            guard case .available(let previous, let date) = store.providerExtras?.snapshot?.fanStatus else {
                throw Failure(code: "fan_baseline_missing")
            }
            let beforeReads = await extrasClient.readCount
            await extrasClient.failRead()
            await store.providerExtras?.refresh()
            try require(await extrasClient.readCount == beforeReads + 1, "unexpected_extras_read_count")
            guard case .stale(let retained, let retainedDate, _) = store.providerExtras?.snapshot?.fanStatus else {
                throw Failure(code: "failed_fan_read_not_stale")
            }
            try require(retained == previous && retainedDate == date, "failed_fan_read_lost_evidence")
            try session.requireReadings(temperature: 85, fanPercent: 100, stale: true)
            try await session.wait("stale_temperature_not_neutral") {
                try session.requireIdentity(host)
                try require(host.geometry == geometry, "stale_fan_changed_geometry")
                return session.colorMatches(host, expected: .secondaryLabelColor)
            }
            let stale = try await session.motion(host, stage: "stale_fan_active_model")
            try await fresh()
            await extrasClient.set(temperature: 54, fanPercent: 75)
            await store.providerExtras?.refresh()
            try require(await extrasClient.readCount == beforeReads + 2, "unexpected_extras_read_count")
            try session.requireReadings(temperature: 54, fanPercent: 75, stale: false)
            try await session.wait("fan_recovery_color_not_rendered") {
                try session.requireIdentity(host)
                try require(host.geometry == geometry, "recovered_fan_changed_geometry")
                return session.colorMatches(host, expected: .systemGreen)
            }
            let recovered = try await session.motion(host, stage: "recovered_fan")
            return ["freshBaseline": freshBaseline, "stale": stale, "recovered": recovered,
                    "retainedCaptureDate": date.timeIntervalSince1970]
        }
        await session.check("window_appearance_changes_without_reading") {
            try await fresh()
            let host = try await session.eligible()
            let geometry = host.geometry
            let originalAppearance = window.appearance
            defer { window.appearance = originalAppearance }
            let sourceWrittenAt = store.snapshot.state.value?.writtenAt
            let extrasReads = await extrasClient.readCount
            var transitions = [[String: Any]]()
            for name in [NSAppearance.Name.darkAqua, .aqua] {
                window.appearance = NSAppearance(named: name)
                try await session.wait("appearance_color_not_rendered") {
                    try session.requireIdentity(host)
                    try require(host.geometry == geometry, "appearance_changed_geometry")
                    try session.requireClock(host.layer)
                    return host.view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == name
                        && session.colorMatches(host, expected: .systemGreen)
                }
                var evidence = try await session.motion(host, stage: "appearance_\(name.rawValue)")
                try require(store.snapshot.state.value?.writtenAt == sourceWrittenAt,
                            "appearance_published_daemon_input")
                try require(await extrasClient.readCount == extrasReads,
                            "appearance_refreshed_fan_input")
                evidence["requestedAppearance"] = name.rawValue
                evidence["unchangedDaemonPublication"] = true
                evidence["extrasReads"] = extrasReads
                transitions.append(evidence)
            }
            window.appearance = originalAppearance
            try await session.wait("original_appearance_not_restored") {
                try session.requireIdentity(host)
                try require(host.geometry == geometry, "appearance_restore_changed_geometry")
                try session.requireClock(host.layer)
                return window.appearance === originalAppearance
                    && session.colorMatches(host, expected: .systemGreen)
            }
            try require(store.snapshot.state.value?.writtenAt == sourceWrittenAt,
                        "appearance_restore_published_daemon_input")
            try require(await extrasClient.readCount == extrasReads,
                        "appearance_restore_refreshed_fan_input")
            return ["transitions": transitions, "originalWindowAppearance": originalAppearance?.name.rawValue ?? "nil",
                    "restoresOriginalAppearance": true]
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
        await session.check("navigate_return_immediate_close_reopen") {
            var cycles = [[String: Any]]()
            for cycle in 0..<3 {
                try await fresh()
                let old = try await session.eligible()
                navigation.sidebarSelection = .settings(.appearance)
                try await session.wait("immediate_departure_not_dismantled") {
                    session.nativeArcs().isEmpty && (old.layer.animationKeys() ?? []).isEmpty
                }
                showPreview()
                let returned = try await session.eligible()
                try require(returned.view !== old.view && returned.layer !== old.layer,
                            "immediate_navigation_reused_dismantled_preview")
                let geometry = returned.geometry
                // Read the model attachment only. No presentation sampling,
                // compositor hold or yield precedes this supported close/reopen.
                let beforeClose = returned.attachment
                window.performClose(nil)
                reopen()
                _ = try await session.eligible()
                try session.requireIdentity(returned)
                try require(returned.geometry == geometry, "immediate_reopening_changed_geometry")
                try require((old.layer.animationKeys() ?? []).isEmpty,
                            "immediate_departed_clock_restarted")
                var evidence = try await session.motion(returned, stage: "immediate_navigation_reopen_\(cycle)")
                evidence["beforeCloseAttachment"] = beforeClose
                evidence["afterReopenAttachment"] = returned.attachment
                evidence["cycle"] = cycle
                cycles.append(evidence)
            }
            return ["cycles": cycles, "presentationObservedBeforeClose": false,
                    "supportedNavigationAndWindowController": true]
        }
        await session.check("supported_opaque_cover_and_restore") {
            try await fresh()
            let originalFrame = window.frame
            defer { window.setFrame(originalFrame, display: false) }
            guard let screen = window.screen else { throw Failure(code: "cover_screen_missing") }
            let available = screen.visibleFrame.insetBy(dx: 32, dy: 32)
            let width = min(800, available.width), height = min(560, available.height)
            try require(width >= 640 && height >= 480, "cover_screen_too_small")
            window.setFrame(NSRect(x: available.midX - width / 2, y: available.midY - height / 2,
                                   width: width, height: height), display: false)
            let host = try await session.eligible()
            let geometry = host.geometry
            let coverFrame = window.frame.insetBy(dx: -32, dy: -32)
            try require(screen.frame.contains(coverFrame)
                        && (32...1_024).contains(coverFrame.width)
                        && (32...1_024).contains(coverFrame.height), "cover_actual_frame_out_of_bounds")
            let probe = await MenuBarMotionProof.settingsCoverProbe(frame: coverFrame) { number, process, ready in
                var server = [[String: Any]]()
                var stages = [[String: Any]]()
                do {
                    // Split delivery from product response without extending
                    // the original total three-second prerequisite budget.
                    let prerequisiteDeadline = CACurrentMediaTime() + 3
                    @MainActor func covered() throws -> Bool {
                        try session.requireIdentity(host)
                        try require(host.geometry == geometry, "covered_geometry_changed")
                        server = session.windowServerEntries(numbers: [window.windowNumber, number])
                        return process.isRunning && window.isVisible && !window.isMiniaturized
                            && session.opaqueCoverage(server, coverNumber: number, coverPID: Int(process.processIdentifier))
                    }
                    @MainActor func record(_ stage: String) {
                        let evidence: [String: Any] = ["stage": stage, "window": session.windowState,
                            "dashboardVisible": store.dashboardVisible, "animationKeys": host.layer.animationKeys() ?? [],
                            "server": server, "uptime": CACurrentMediaTime()]
                        stages.append(evidence)
                        session.coverStages.append(evidence)
                        session.write()
                    }
                    try await session.wait("supported_cover_missing_opaque_coverage", deadline: prerequisiteDeadline) {
                        try covered()
                    }
                    record("opaque_coverage")
                    try await session.wait("supported_cover_native_occlusion_not_delivered", deadline: prerequisiteDeadline) {
                        try covered() && !window.occlusionState.contains(.visible)
                    }
                    record("native_occlusion")
                    try await session.wait("supported_cover_clocks_not_stopped", deadline: prerequisiteDeadline) {
                        try covered() && !window.occlusionState.contains(.visible)
                            && !store.dashboardVisible && (host.layer.animationKeys() ?? []).isEmpty
                    }
                    record("product_response")
                    let before = session.windowState
                    let started = CACurrentMediaTime()
                    try await Task.sleep(for: .milliseconds(1_700))
                    try session.requireIdentity(host)
                    try require(process.isRunning && window.isVisible && !window.occlusionState.contains(.visible)
                                && !store.dashboardVisible && host.geometry == geometry
                                && (host.layer.animationKeys() ?? []).isEmpty, "covered_state_not_sustained")
                    server = session.windowServerEntries(numbers: [window.windowNumber, number])
                    try require(session.opaqueCoverage(server, coverNumber: number, coverPID: Int(process.processIdentifier)),
                                "covered_order_or_geometry_lost")
                    return ["beforeHold": before, "afterHold": session.windowState,
                            "holdSeconds": CACurrentMediaTime() - started, "server": server, "ready": ready,
                            "stages": stages]
                } catch {
                    session.coverFailures.append(["window": session.windowState, "native": host.json,
                                                  "server": server, "ready": ready, "stages": stages])
                    throw error
                }
            }
            session.coverProbes.append(probe)
            if probe["cancelled"] as? Bool == true { throw CancellationError() }
            guard let cleanup = probe["cleanup"] as? [String: Any] else { throw Failure(code: "cover_cleanup_missing") }
            try require(cleanup["exited"] as? Bool == true && cleanup["exitStatus"] as? Int == 0
                        && cleanup["childTerminalReason"] as? String == "parent-request"
                        && cleanup["childWindowClosed"] as? Bool == true, "cover_graceful_cleanup_failed")
            try require(probe["passed"] as? Bool == true, "supported_cover_prerequisite_failed")
            _ = try await session.eligible()
            try session.requireIdentity(host)
            try require(host.geometry == geometry, "uncovered_geometry_changed")
            var evidence = try await session.motion(host, stage: "supported_cover_restored")
            evidence["cover"] = probe
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
        var attachment: [String: Any] {
            let content = view.window?.contentView
            var ancestors = [[String: Any]]()
            var cursor = view.layer
            while let current = cursor, ancestors.count < 32 {
                ancestors.append(["identity": identity(current),
                                  "isContentViewLayer": current === content?.layer,
                                  "parentIdentity": current.superlayer.map(identity) ?? "nil"])
                cursor = current.superlayer
            }
            return ["viewIdentity": identity(view), "layerIdentity": identity(layer),
                    "windowIdentity": view.window.map(identity) ?? "nil",
                    "contentViewWantsLayer": content?.wantsLayer ?? false,
                    "contentViewLayerIdentity": content?.layer.map(identity) ?? "nil",
                    "backingLayerParentIdentity": view.layer?.superlayer.map(identity) ?? "nil",
                    "ancestors": ancestors, "ancestryTruncated": cursor != nil]
        }
        var geometry: [String] {
            [NSStringFromRect(view.bounds), NSStringFromRect(layer.frame), NSStringFromRect(layer.bounds),
             layer.path.map { NSStringFromRect($0.boundingBoxOfPath) } ?? "nil",
             String(Double(layer.lineWidth)), String(Double(layer.strokeStart)), String(Double(layer.strokeEnd))]
        }
        var json: [String: Any] {
            let clock = layer.animation(forKey: "inferenceRotation") as? CABasicAnimation
            return ["viewIdentity": identity(view), "layerIdentity": identity(layer),
                    "viewAppearance": view.effectiveAppearance.name.rawValue,
                    "windowAppearance": view.window?.effectiveAppearance.name.rawValue ?? "nil",
                    "expectedGreenComponents": colorComponents(.systemGreen),
                    "expectedYellowComponents": colorComponents(.systemYellow),
                    "expectedRedComponents": colorComponents(.systemRed),
                    "expectedNeutralComponents": colorComponents(.secondaryLabelColor),
                    "windowIdentity": view.window.map(identity) ?? "nil", "geometry": geometry,
                    "viewVisibleRect": NSStringFromRect(view.visibleRect),
                    "hiddenAncestor": view.isHiddenOrHasHiddenAncestor, "layerHidden": layer.isHidden,
                    "animationKeys": layer.animationKeys() ?? [], "clockDuration": clock?.duration ?? -1,
                    "strokeColorComponents": layer.strokeColor.flatMap { NSColor(cgColor: $0)?.usingColorSpace(.deviceRGB) }
                        .map { [$0.redComponent, $0.greenComponent, $0.blueComponent, $0.alphaComponent] } ?? [],
                    "presentationAngle": layer.presentation().map { atan2($0.transform.m12, $0.transform.m11) } ?? 0,
                    "attachment": attachment]
        }
        func colorComponents(_ color: NSColor) -> [CGFloat] {
            var resolved: CGColor?
            view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
            guard let resolved, let rgb = NSColor(cgColor: resolved)?.usingColorSpace(.deviceRGB) else { return [] }
            return [rgb.redComponent, rgb.greenComponent, rgb.blueComponent, rgb.alphaComponent]
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
        var coverProbes = [[String: Any]]()
        var coverFailures = [[String: Any]]()
        var coverStages = [[String: Any]]()
        var occlusionNotifications = [[String: Any]]()
        var droppedOcclusionNotifications = 0
        init(window: NSWindow, navigation: DashboardNavigation, store: MonitorStore, output: URL) {
            self.window = window; self.navigation = navigation; self.store = store; self.output = output
        }
        func recordOcclusionNotification() {
            occlusionNotifications.append(["uptime": CACurrentMediaTime(), "currentCase": currentCase,
                "window": windowState, "dashboardVisible": store.dashboardVisible])
            if occlusionNotifications.count > 64 {
                let dropped = occlusionNotifications.count - 64
                droppedOcclusionNotifications += dropped
                occlusionNotifications.removeFirst(dropped)
            }
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
            windowServerEntries(numbers: [window.windowNumber])
        }
        func windowServerEntries(numbers: Set<Int>) -> [[String: Any]] {
            let entries = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]] ?? []
            return entries.enumerated().compactMap { index, entry in
                guard let number = entry[kCGWindowNumber as String] as? Int, numbers.contains(number) else { return nil }
                return ["number": number, "frontToBackIndex": index,
                        "ownerPID": entry[kCGWindowOwnerPID as String] ?? -1,
                        "layer": entry[kCGWindowLayer as String] ?? -1,
                        "alpha": entry[kCGWindowAlpha as String] ?? -1,
                        "bounds": entry[kCGWindowBounds as String] ?? [:],
                        "onScreen": entry[kCGWindowIsOnscreen as String] ?? false]
            }
        }
        func opaqueCoverage(_ entries: [[String: Any]], coverNumber: Int, coverPID: Int) -> Bool {
            guard let target = entries.first(where: { $0["number"] as? Int == window.windowNumber }),
                  let cover = entries.first(where: { $0["number"] as? Int == coverNumber }),
                  target["ownerPID"] as? Int == Int(ProcessInfo.processInfo.processIdentifier),
                  cover["ownerPID"] as? Int == coverPID,
                  let targetIndex = target["frontToBackIndex"] as? Int,
                  let coverIndex = cover["frontToBackIndex"] as? Int, coverIndex < targetIndex,
                  cover["alpha"] as? Double == 1,
                  let targetBounds = target["bounds"] as? [String: Any],
                  let coverBounds = cover["bounds"] as? [String: Any],
                  let targetRect = CGRect(dictionaryRepresentation: targetBounds as CFDictionary),
                  let coverRect = CGRect(dictionaryRepresentation: coverBounds as CFDictionary) else { return false }
            return coverRect.contains(targetRect)
        }
        func wait(_ code: String, deadline: TimeInterval? = nil, _ predicate: () throws -> Bool) async throws {
            let end = deadline ?? CACurrentMediaTime() + 3
            repeat {
                try Task.checkCancellation()
                try requireSource()
                guard CACurrentMediaTime() < end else { throw Failure(code: code) }
                if try predicate() { return }
                try await Task.sleep(for: .milliseconds(20))
            } while CACurrentMediaTime() < end
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
        func requireReadings(temperature: Double, fanPercent: Double, stale: Bool) throws {
            let values = MenuBarIndicators.make(snapshot: store.snapshot, utilization: nil, sampledAt: nil,
                fanStatus: store.providerExtras?.snapshot?.fanStatus, now: Date())
            try require(values.temperature.value == temperature && values.fanSpeed.value == fanPercent
                        && values.modelIsActive && values.temperature.freshness == (stale ? .stale : .current)
                        && values.fanSpeed.freshness == (stale ? .stale : .current), "unexpected_fan_evidence")
        }
        func colorMatches(_ host: Host, expected: NSColor) -> Bool {
            guard let color = host.layer.strokeColor,
                  let actual = NSColor(cgColor: color)?.usingColorSpace(.deviceRGB) else { return false }
            var expectedColor: CGColor?
            host.view.effectiveAppearance.performAsCurrentDrawingAppearance { expectedColor = expected.cgColor }
            guard let expectedColor, let target = NSColor(cgColor: expectedColor)?.usingColorSpace(.deviceRGB) else { return false }
            return zip([actual.redComponent, actual.greenComponent, actual.blueComponent, actual.alphaComponent],
                       [target.redComponent, target.greenComponent, target.blueComponent, target.alphaComponent])
                .allSatisfy { abs($0 - $1) < 0.005 }
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
             "passed": terminal == "completed" && !cancelled && results.count == 12
                && results.allSatisfy { $0["passed"] as? Bool == true } && cleanupVerified && writeErrors.isEmpty,
             "results": results, "cleanupVerified": cleanupVerified, "retainedHosts": hosts.map(\.json),
             "angleSamples": angleSamples,
             "window": windowState, "source": source, "reportWriteErrors": writeErrors,
             "coverProbes": coverProbes, "coverFailures": coverFailures, "coverStages": coverStages,
             "occlusionNotifications": occlusionNotifications,
             "occlusionNotificationCapacity": 64,
             "droppedOcclusionNotifications": droppedOcclusionNotifications]
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
