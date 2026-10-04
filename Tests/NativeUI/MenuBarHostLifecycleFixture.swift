// Diagnostic comparison with the standalone 15-case motion gate. This app
// hosts the unchanged production SwiftUI label and never contacts a provider.
import AppKit
import DarkbloomTelemetry
import QuartzCore
import SwiftUI

private struct HostLifecycleFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private final class HostLifecycleTarget {
    let host: NSHostingController<AnyView>
    let window: NSWindow
    var native: MenuBarActivityArc.ActivityArcView?
    var arc: CAShapeLayer?
    var evidence: [String: Any] = [:]
    var lifecycle: [[String: Any]] = []
    private var observers: [NSObjectProtocol] = []
    private let startedAt = CACurrentMediaTime()

    init() {
        let label = MenuBarLabel(
            presentation: .make(snapshot: .unavailable(now: Date(timeIntervalSince1970: 1_700_000_000)),
                thermal: .nominal, earnings: .unavailable(reason: "Inert host lifecycle diagnostic"), mode: .statusOnly),
            uptime: .available(percent: 100, observedSeconds: 600), family: .qwen,
            indicators: .init(modelIsActive: true, gpu: .init(value: 50, freshness: .current),
                fanSpeed: .init(value: 50, freshness: .current), temperature: .init(value: 75, freshness: .current)))
        host = NSHostingController(rootView: AnyView(label.frame(maxWidth: .infinity, maxHeight: .infinity)))
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        window = NSWindow(contentRect: NSRect(x: screen.midX - 150, y: screen.midY - 70, width: 300, height: 140),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Production SwiftUI Menu Label"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.isOpaque = true
        window.backgroundColor = .windowBackgroundColor
        window.collectionBehavior = [.moveToActiveSpace]
        window.contentViewController = host
        // Public notification observation only: no animation delegate, layer
        // subclass, synchronization callback or production modification.
        for name in [NSWindow.willCloseNotification, NSWindow.didChangeOcclusionStateNotification,
                     NSWindow.didExposeNotification, NSWindow.didMiniaturizeNotification,
                     NSWindow.didDeminiaturizeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) {
                [weak self] notification in
                let callbackName = notification.name.rawValue
                MainActor.assumeIsolated { self?.record(callbackName) }
            })
        }
    }

    func show() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func mount() async throws {
        show()
        try await waitVisible()
        try await waitUntil("Production host did not mount exactly one native activity view") {
            self.nativeViews.count == 1
        }
        guard let native = nativeViews.first, let arc = shapeLayers(in: native.layer).first else {
            throw HostLifecycleFailure("Production native arc has no public descendant CAShapeLayer")
        }
        try require(shapeLayers(in: native.layer).count == 1, "Native activity view has multiple shape layers")
        self.native = native
        self.arc = arc
        try retainedIdentity()
        record("mounted_production_label")
        evidence["initialNative"] = snapshot()
    }

    var nativeViews: [MenuBarActivityArc.ActivityArcView] {
        func visit(_ view: NSView) -> [MenuBarActivityArc.ActivityArcView] {
            if let arc = view as? MenuBarActivityArc.ActivityArcView { return [arc] }
            return view.subviews.flatMap { visit($0) }
        }
        return visit(host.view)
    }

    private func shapeLayers(in root: CALayer?) -> [CAShapeLayer] {
        guard let root else { return [] }
        return (root as? CAShapeLayer).map { [$0] } ?? (root.sublayers ?? []).flatMap { shapeLayers(in: $0) }
    }

    func retainedIdentity() throws {
        guard let native, let arc else { throw HostLifecycleFailure("Native view/layer was not captured") }
        try require(window.contentViewController === host && window.contentView === host.view,
                    "Close/reopen replaced the original SwiftUI host")
        try require(nativeViews.count == 1 && nativeViews.first === native && native.window === window,
                    "Close/reopen replaced or detached the original native activity view")
        try require(shapeLayers(in: native.layer).count == 1 && shapeLayers(in: native.layer).first === arc,
                    "Close/reopen replaced or multiplied the original native activity layer")
        try require(arc.superlayer === native.layer, "Activity layer lost production ownership")
    }

    func waitVisible() async throws {
        try await waitUntil("Owned host did not become genuinely visible: \(self.snapshot())") {
            self.visible
        }
    }

    var visible: Bool {
        window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible)
    }

    func clock() async throws {
        try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                    "System Reduce Motion prevents rotation proof; no setting is changed")
        guard let arc else { throw HostLifecycleFailure("Missing retained arc") }
        try await waitUntil("Eligible production host has no rotation key: \(self.snapshot())") {
            arc.animation(forKey: "inferenceRotation") != nil
        }
        try clockPolicy()
    }

    func clockPolicy() throws {
        guard let arc, let animation = arc.animation(forKey: "inferenceRotation") as? CABasicAnimation else {
            throw HostLifecycleFailure("Retained native layer has no basic rotation animation")
        }
        try require(arc.animationKeys() == ["inferenceRotation"], "Activity must have exactly one rotation key")
        try require(animation.keyPath == "transform.rotation.z" && animation.duration == 1.4
                    && animation.repeatCount == .infinity, "Production rotation policy changed")
        try require(arc.speed == 1 && !arc.isHidden && arc.path != nil, "Active arc is hidden, pathless or retimed")
    }

    func angle(differingFrom initial: Double? = nil) async throws -> Double {
        guard let arc else { throw HostLifecycleFailure("Missing retained arc") }
        let deadline = CACurrentMediaTime() + 4
        repeat {
            try require(visible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
                        "Angle observation lost genuine visibility or Reduce Motion eligibility")
            try retainedIdentity()
            try clockPolicy()
            if let presentation = arc.presentation() {
                let angle = atan2(presentation.transform.m12, presentation.transform.m11)
                if angle.isFinite, initial.map({ angularDistance($0, angle) > 0.1 }) ?? true { return angle }
            }
            // Observe only; no displayIfNeeded, transaction flush, configure,
            // rootView assignment or recovery callback during motion proof.
            try await Task.sleep(for: .milliseconds(20))
        } while CACurrentMediaTime() < deadline
        throw HostLifecycleFailure("Visible production compositor did not supply advancing rotation")
    }

    func stableClockEvidence() async throws -> [String: Any] {
        try retainedIdentity()
        try await clock()
        let beforeFirst = try await angle()
        let beforeSecond = try await angle(differingFrom: beforeFirst)
        evidence["beforeHoldAngles"] = [beforeFirst, beforeSecond]
        let holdStart = CACurrentMediaTime()
        try await Task.sleep(for: .milliseconds(1_600))
        let holdSeconds = CACurrentMediaTime() - holdStart
        evidence["holdSeconds"] = holdSeconds
        try require(holdSeconds > 1.4 && visible, "Post-recovery hold lost genuine visibility or lasted too little")
        try retainedIdentity()
        try clockPolicy() // Do not wait for a missing clock to restart after the hold.
        let afterFirst = try await angle()
        let afterSecond = try await angle(differingFrom: afterFirst)
        return ["beforeHoldAngles": [beforeFirst, beforeSecond], "afterHoldAngles": [afterFirst, afterSecond],
                "beforeHoldAngleAdvance": angularDistance(beforeFirst, beforeSecond),
                "afterHoldAngleAdvance": angularDistance(afterFirst, afterSecond), "holdSeconds": holdSeconds,
                "productionDurationSeconds": 1.4, "productionRepeatIsInfinite": true,
                "requestedNativeDisplay": false, "transactionFlush": false, "sameHostViewAndArc": true]
    }

    func record(_ event: String) {
        guard lifecycle.count < 100 else { return }
        lifecycle.append(["event": event, "seconds": CACurrentMediaTime() - startedAt, "state": snapshot()])
    }

    func snapshot() -> [String: Any] {
        var result: [String: Any] = ["windowNumber": window.windowNumber, "windowVisible": window.isVisible,
            "miniaturized": window.isMiniaturized, "compositorVisible": window.occlusionState.contains(.visible),
            "occlusionState": window.occlusionState.rawValue, "windowLevel": window.level.rawValue,
            "windowFrame": NSStringFromRect(window.frame), "hostIdentity": String(describing: ObjectIdentifier(host)),
            "hostViewIdentity": String(describing: ObjectIdentifier(host.view)), "nativeDescendantCount": nativeViews.count,
            "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
        if let native {
            result["nativeViewIdentity"] = String(describing: ObjectIdentifier(native))
            result["attachedToExpectedWindow"] = native.window === window
            result["hiddenOrHasHiddenAncestor"] = native.isHiddenOrHasHiddenAncestor
            result["viewBounds"] = NSStringFromRect(native.bounds)
        }
        if let arc {
            result["nativeLayerIdentity"] = String(describing: ObjectIdentifier(arc))
            result["layerStillOwnedByView"] = arc.superlayer === native?.layer
            result["animationKeys"] = arc.animationKeys() ?? []
            result["layerSpeed"] = arc.speed
            result["layerHidden"] = arc.isHidden
            result["hasPath"] = arc.path != nil
            if let presentation = arc.presentation() {
                let angle = atan2(presentation.transform.m12, presentation.transform.m11)
                result["presentationAngle"] = angle.isFinite ? angle as Any : "nonfinite"
            }
        }
        return result
    }

    func finish() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
        window.close()
        // Drive normal SwiftUI teardown for non-dismantle cases too.
        host.rootView = AnyView(EmptyView())
    }
}

@MainActor
private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw HostLifecycleFailure(message) }
}

@MainActor
private func waitUntil(_ message: @autoclosure () -> String, predicate: () -> Bool) async throws {
    let deadline = CACurrentMediaTime() + 4
    repeat {
        if predicate() { return }
        try await Task.sleep(for: .milliseconds(20))
    } while CACurrentMediaTime() < deadline
    try require(predicate(), message())
}

private func angularDistance(_ first: Double, _ second: Double) -> Double {
    abs(atan2(sin(second - first), cos(second - first)))
}

@MainActor
private final class HostLifecycleReport {
    static let requiredCases = ["visible_active_compositor_advances", "same_window_close_and_reopen",
                                "rapid_same_window_close_and_reopen", "swiftui_dismantle_retained_view"]
    let outputURL: URL
    private let startedAt = Date()
    private(set) var cases: [[String: Any]] = []
    private(set) var failures: [String] = []
    private(set) var terminal = false

    init() {
        outputURL = FileManager.default.temporaryDirectory.appendingPathComponent(
            "BloomyMenuHostLifecycle-\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("host-lifecycle-proof.json")
    }

    func check(_ name: String, body: (HostLifecycleTarget) async throws -> [String: Any]) async {
        let start = Date()
        let target = HostLifecycleTarget()
        var status = "passed"
        var errorText: String?
        do {
            try await target.mount()
            target.evidence.merge(try await body(target)) { _, new in new }
        } catch {
            status = "failed"
            errorText = error.localizedDescription
            failures.append("\(name): \(error.localizedDescription)")
        }
        target.record("case_terminal")
        var record: [String: Any] = ["name": name, "status": status, "seconds": Date().timeIntervalSince(start),
            "evidence": target.evidence, "finalNative": target.snapshot(), "lifecycle": target.lifecycle]
        if let errorText { record["error"] = errorText }
        cases.append(record) // Retain failed cases and partial evidence; never replace with later success.
        print("MenuHostLifecycle \(name): \(status)\(errorText.map { ": \($0)" } ?? "")")
        target.finish()
        persist(terminal: false)
    }

    func persist(terminal: Bool) {
        self.terminal = terminal
        let missing = Self.requiredCases.filter { name in !cases.contains { $0["name"] as? String == name } }
        let passed = terminal && failures.isEmpty && missing.isEmpty
        let payload: [String: Any] = ["proof": "production-swiftui-menu-host-lifecycle-diagnostic",
            "diagnosticComparisonOnly": true, "replacesStandalone15CaseGate": false, "synthetic": true,
            "providerConnected": false, "terminal": terminal, "passed": passed,
            "status": terminal ? (passed ? "passed" : "failed") : "running",
            "processID": ProcessInfo.processInfo.processIdentifier, "bundleID": Bundle.main.bundleIdentifier ?? "nil",
            "startedAt": startedAt.timeIntervalSince1970, "elapsedSeconds": Date().timeIntervalSince(startedAt),
            "requiredCases": Self.requiredCases, "cases": cases, "failures": failures, "missingCases": missing,
            "systemReduceMotion": NSWorkspace.shared.accessibilityDisplayShouldReduceMotion]
        do {
            try FileManager.default.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
                .write(to: outputURL, options: .atomic)
        } catch {
            failures.append("Report persistence failed: \(error.localizedDescription)")
            print("MenuHostLifecycle report persistence failed: \(error.localizedDescription)")
        }
    }

    func interrupted() {
        guard !terminal else { return }
        failures.append("Fixture quit before all diagnostic cases reached terminal status")
        persist(terminal: true)
    }

    func run() async -> Bool {
        persist(terminal: false)
        await check(Self.requiredCases[0]) { target in
            try await target.stableClockEvidence()
        }
        await check(Self.requiredCases[1]) { target in
            try await target.clock()
            target.record("before_close")
            target.window.close()
            target.record("after_close")
            try require(!target.window.isVisible && target.arc?.animation(forKey: "inferenceRotation") == nil,
                        "Close must immediately stop the retained production arc")
            try target.retainedIdentity()
            try await waitUntil("Closed host remained compositor-visible") {
                !target.window.occlusionState.contains(.visible)
            }
            target.show()
            try await target.waitVisible()
            target.record("visibility_regained")
            return try await target.stableClockEvidence()
        }
        await check(Self.requiredCases[2]) { target in
            try await target.clock()
            target.record("before_rapid_close")
            target.window.close()
            target.record("after_rapid_close")
            try require(!target.window.isVisible && target.arc?.animation(forKey: "inferenceRotation") == nil,
                        "Rapid close must immediately stop before any yield")
            try target.retainedIdentity()
            // No await/yield between close and reopen, preserving notification coalescing.
            target.show()
            try await target.waitVisible()
            target.record("rapid_visibility_regained")
            return try await target.stableClockEvidence()
        }
        await check(Self.requiredCases[3]) { target in
            try await target.clock()
            guard let native = target.native, let arc = target.arc else {
                throw HostLifecycleFailure("Dismantle has no retained native view/layer")
            }
            target.record("before_swiftui_root_removal")
            target.host.rootView = AnyView(Text("Production label dismantled"))
            try await waitUntil("SwiftUI did not dismantle and remove its production representable") {
                target.nativeViews.isEmpty && arc.animation(forKey: "inferenceRotation") == nil
            }
            target.record("swiftui_dismantle_observed")
            // Exercise late lifecycle delivery while retaining the actual removed
            // view and layer. Reattach it to an eligible owned native container:
            // checking a detached view alone would pass even without dismantle.
            // Teardown itself is exclusively SwiftUI-driven.
            let retainedContainer = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 140))
            target.window.contentViewController = nil
            native.frame = NSRect(x: 141, y: 61, width: 18, height: 18)
            retainedContainer.addSubview(native)
            target.window.contentView = retainedContainer
            target.record("retained_dismantled_view_reattached")
            native.configure(active: true, tint: .systemYellow)
            native.isHidden = true
            native.isHidden = false
            target.window.close()
            target.show()
            try await target.waitVisible()
            let settleStart = CACurrentMediaTime()
            try await Task.sleep(for: .milliseconds(1_600))
            try require(target.visible && native.window === target.window && !native.isHiddenOrHasHiddenAncestor,
                        "Retained dismantle stress did not preserve real visible-window eligibility")
            try require(!NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && !arc.isHidden,
                        "Retained dismantle stress lost active non-reduced-motion eligibility")
            try require(target.nativeViews.isEmpty && arc.animation(forKey: "inferenceRotation") == nil,
                        "Late native/window delivery resurrected a dismantled production clock")
            return ["swiftuiDismantled": true, "didNotRestart": true,
                    "retainedNativeViewAndArc": true, "retainedViewReattachedToVisibleWindow": true,
                    "lateCallbackSettleSeconds": CACurrentMediaTime() - settleStart]
        }
        persist(terminal: true)
        let passed = failures.isEmpty && cases.count == Self.requiredCases.count
        print("MenuHostLifecycle terminal: \(passed ? "passed" : "failed") cases=\(cases.count)/4 output=\(outputURL.path)")
        return passed
    }
}

@MainActor
private final class HostLifecycleApplicationDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var runButton: NSButton?
    private var statusField: NSTextField?
    private var report: HostLifecycleReport?
    private var task: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let report = HostLifecycleReport()
        self.report = report
        let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 640, height: 230),
            styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Bloomy Menu Host Lifecycle Fixture"
        window.isReleasedWhenClosed = false
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 230))
        window.contentView = content
        let explanation = NSTextField(wrappingLabelWithString:
            "Diagnostic comparison: real production SwiftUI host. Four finite cases. The standalone 15-case release gate remains separate.")
        explanation.frame = NSRect(x: 24, y: 164, width: 592, height: 44)
        content.addSubview(explanation)
        let button = NSButton(title: "Run lifecycle diagnostic", target: self, action: #selector(runDiagnostic))
        button.bezelStyle = .rounded
        button.frame = NSRect(x: 24, y: 110, width: 230, height: 32)
        button.setAccessibilityIdentifier("fixture.menu-host-lifecycle.run")
        button.setAccessibilityLabel("Run lifecycle diagnostic")
        content.addSubview(button)
        runButton = button
        let status = NSTextField(wrappingLabelWithString: "Ready. No provider connection.\nReport: \(report.outputURL.path)")
        status.frame = NSRect(x: 24, y: 16, width: 592, height: 78)
        status.setAccessibilityIdentifier("fixture.menu-host-lifecycle.status")
        content.addSubview(status)
        statusField = status
        self.window = window
        installMenus()
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        print("MenuHostLifecycle ready: \(report.outputURL.path)")
    }

    @objc private func runDiagnostic() {
        guard task == nil, let report else { return }
        runButton?.isEnabled = false
        statusField?.stringValue = "Running four finite native cases…\nReport: \(report.outputURL.path)"
        task = Task { @MainActor [weak self] in
            let passed = await report.run()
            self?.statusField?.stringValue = "Terminal: \(passed ? "passed" : "failed"). Diagnostic comparison only.\nReport: \(report.outputURL.path)"
            self?.window?.makeKeyAndOrderFront(nil)
        }
    }

    private func installMenus() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        let quit = NSMenuItem(title: "Quit Bloomy Menu Host Lifecycle Fixture",
            action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApplication.shared
        appMenu.addItem(quit)
        appItem.submenu = appMenu
        menu.addItem(appItem)
        NSApplication.shared.mainMenu = menu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        task?.cancel()
        if task != nil { report?.interrupted() }
        return .terminateNow
    }
}

@main
private enum MenuBarHostLifecycleFixtureApplication {
    @MainActor static func main() {
        let application = NSApplication.shared
        let delegate = HostLifecycleApplicationDelegate()
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
