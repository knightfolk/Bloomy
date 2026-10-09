// Opt-in, finite proof in the inert fixture under normal NSApplication.run().
// Only this proof's window, named defaults suite, and synthetic controller are owned.
import AppKit
import Foundation
import SwiftUI
import DarkbloomTelemetry

@MainActor
enum ModelManageKeyboardProof {
    static func run(outputDirectory: URL) async -> Bool {
        let expected = ["forward_reveals_native_controls", "backward_reveals_native_controls", "footer_closes_sheet",
            "forecast_starts_collapsed_and_opens_without_mutation"]
        let deadline = ContinuousClock.now.advanced(by: .seconds(45))
        var cases: [[String: Any]] = [], events: [[String: Any]] = [], failures: [String] = []
        var fixture: ManageKeyboardFixture?
        weak var releasedHost: NSHostingController<AnyView>?
        var cleanupPassed = false
        func write(_ terminal: String) throws {
            let result: [String: Any] = ["proof": "model-manage-keyboard", "synthetic": true,
                "terminal": terminal, "sheetHeightPoints": 360, "maximumDurationSeconds": 45,
                "fullKeyboardAccessEnabled": NSApplication.shared.isFullKeyboardAccessEnabled,
                "expectedCaseCount": expected.count, "completedCaseCount": cases.count,
                "cases": cases, "focusEvidence": events, "failures": failures,
                "cleanupPassed": cleanupPassed,
                "passed": terminal == "success" && cases.count == expected.count && failures.isEmpty && cleanupPassed]
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: outputDirectory.appendingPathComponent("model-manage-keyboard-proof.json"), options: .atomic)
        }
        do {
            try write("running")
            try manageKeyboardRequire(NSApplication.shared.isRunning, "Normal NSApplication.run is required")
            let owned = ManageKeyboardFixture()
            fixture = owned; releasedHost = owned.host
            await owned.store.refresh()
            try manageKeyboardRequire(owned.store.draft != nil, "Synthetic provider draft did not load")
            owned.captureBaseline()
            try await owned.activateOwnedWindow(owned.window, stage: "host-activation",
                deadline: deadline, evidence: &events)
            try await manageKeyboardWait("Native Manage entry did not mount", deadline: deadline) {
                owned.layout()
                return owned.matching("Manage Keyboard fixture", roles: ["AXButton"], in: owned.window).count == 1
            }
            try manageKeyboardPress(owned.exact("Manage Keyboard fixture", roles: ["AXButton"], in: owned.window))
            try await manageKeyboardWait("Manage sheet did not mount", deadline: deadline) {
                owned.window.attachedSheet != nil
            }
            guard let sheet = owned.window.attachedSheet else { throw ManageKeyboardFailure("Manage sheet is absent") }
            try await owned.activateOwnedWindow(sheet, stage: "sheet-activation",
                deadline: deadline, evidence: &events)
            events.append(["stage": "sheet-mounted", "scrollDiscovery": owned.scrollDiagnostics(in: sheet)])
            try await manageKeyboardWait("Overflowing native Manage scroll view did not mount", deadline: deadline) {
                owned.layout(); return owned.scrollViews(in: sheet).count == 1
            }
            let scroll = try owned.scroll(in: sheet)
            try manageKeyboardRequire(abs(sheet.contentRect(forFrameRect: sheet.frame).height - 360) <= 2,
                "Manage sheet is not constrained to 360 points")
            try manageKeyboardRequire(scroll.documentView!.bounds.height > scroll.contentView.bounds.height + 40,
                "Fixture content does not actually overflow its viewport")
            try manageKeyboardRequire(owned.matching("What-if daily runtime for Keyboard fixture",
                roles: ["AXSlider"], in: sheet).isEmpty, "Optional forecast starts expanded")
            try await owned.seek("forecast", sheet: sheet, deadline: deadline, evidence: &events)
            try manageKeyboardPress(owned.control("forecast", in: sheet))
            try await manageKeyboardWait("Forecast disclosure did not reveal its runtime control", deadline: deadline) {
                owned.layout()
                return owned.matching("What-if daily runtime for Keyboard fixture", roles: ["AXSlider"], in: sheet).count == 1
            }
            try owned.assertUnchanged()
            cases.append(["name": expected[3], "passed": true])
            // Native disabled Delete is the only optional control; mandatory
            // runtime/switch/Details controls are never skipped for preferences.
            let delete = owned.matching("Delete Keyboard fixture", roles: ["AXButton"], in: sheet)
            events.append(["stage": "initial", "scrollOffset": scroll.contentView.bounds.origin.y,
                "viewportFrame": manageKeyboardRect(owned.viewport(scroll)),
                "deleteControlCount": delete.count,
                "deleteExplicitlyDisabled": delete.count == 1 && manageKeyboardAttribute("isAccessibilityEnabled", delete[0]) as? Bool == false,
                "nativeControls": owned.controlDiagnostics(in: sheet)])
            try write("running")

            for (index, forward) in [true, false].enumerated() {
                var result: [String: Any] = ["name": expected[index], "passed": false]
                do {
                    // Establish the first anchor through the real key loop,
                    // without setting AX focus or invoking a reveal callback.
                    if forward {
                        try await owned.seek("header", sheet: sheet, deadline: deadline, evidence: &events)
                    }
                    let observations = try await owned.traverse(forward: forward, sheet: sheet,
                        deadline: deadline, evidence: &events)
                    result["visitedControls"] = observations.visited.sorted()
                    result["scrollMovedInRequiredDirection"] = observations.moved
                    try manageKeyboardRequire(observations.moved,
                        "\(forward ? "Forward" : "Backward") focus did not move the actual scroll viewport \(forward ? "down" : "up")")
                    result["passed"] = true
                } catch {
                    let message = "\(expected[index]): \(error.localizedDescription)"
                    result["failure"] = message; failures.append(message)
                    result["nativeControls"] = owned.controlDiagnostics(in: sheet)
                }
                cases.append(result)
                try write("running")
            }
            var footerResult: [String: Any] = ["name": expected[2], "passed": false]
            do {
                try await owned.seek("footer", sheet: sheet, deadline: deadline, evidence: &events)
                let footer = try owned.control("footer", in: sheet)
                try owned.assertFocusedVisible("footer", node: footer, sheet: sheet)
                try manageKeyboardPress(footer)
                try await manageKeyboardWait("Focused footer Done did not close Manage", deadline: deadline) {
                    owned.window.attachedSheet == nil
                }
                try owned.assertUnchanged()
                footerResult["passed"] = true
            } catch {
                let message = "\(expected[2]): \(error.localizedDescription)"
                footerResult["failure"] = message; failures.append(message)
            }
            cases.append(footerResult)
            let calls = await owned.controller.calls()
            if calls.refreshes != 1 || !calls.mutations.isEmpty {
                failures.append("Focus caused unexpected controller calls: refreshes=\(calls.refreshes), mutations=\(calls.mutations)")
            }
            try write("running")
        } catch {
            failures.append(error is CancellationError ? "Proof cancelled" : error.localizedDescription)
        }
        // Removing the hosting tree cancels view-owned work, including sheet
        // presentation. These fixtures install no ongoing freshness deadline.
        if let owned = fixture {
            await owned.store.cancelCurrentOperationAndWait()
            owned.close()
            cleanupPassed = !owned.window.isVisible && owned.window.attachedSheet == nil
                && owned.host == nil && owned.store.operation == .idle
        }
        fixture = nil
        do {
            try await manageKeyboardWait("Owned hosting controller was not released", deadline: .now.advanced(by: .seconds(3))) {
                releasedHost == nil
            }
        } catch { cleanupPassed = false; failures.append("Cleanup: \(error.localizedDescription)") }
        if !cleanupPassed { failures.append("Owned sheet/window/store cleanup failed") }
        let passed = cases.count == expected.count && failures.isEmpty && cleanupPassed
        do { try write(passed ? "success" : "failure") }
        catch {
            failures.append("Terminal report write failed: \(error.localizedDescription)")
            print("ModelManageKeyboardProof report-write failure: \(error.localizedDescription)")
        }
        let success = passed && failures.isEmpty
        print("ModelManageKeyboardProof TERMINAL_\(success ? "SUCCESS" : "FAILURE") completed=\(cases.count) expected=\(expected.count) cleanup=\(cleanupPassed) failures=\(failures)")
        return success
    }
}

@MainActor
private final class ManageKeyboardFixture {
    let namespace = "ModelManageKeyboard-\(UUID().uuidString)"
    let defaults: UserDefaults
    let controller = ManageKeyboardController()
    let store: ProviderControlStore
    var host: NSHostingController<AnyView>?
    let window: NSWindow
    private var baselineDraft: ProviderConfigDraft?
    private var baselineDefaults: [String: Any] = [:]
    private let required: Set<String> = ["header", "footer", "runtime", "enabled", "preload", "details", "forecast"]

    init() {
        defaults = UserDefaults(suiteName: namespace)!
        store = ProviderControlStore(controller: controller, hostingOptions: { .default })
        host = NSHostingController(rootView: AnyView(ModelManagerView(store: store, isVisible: false)
            .defaultAppStorage(defaults).environment(\.modelManagerSheetMaximumHeight, 360)))
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 1_040, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Manage keyboard proof — synthetic"
        window.isReleasedWhenClosed = false
        window.contentViewController = host
        // Attaching SwiftUI's host can replace the constructor's content size.
        // Match the working native ModelAccessibilityFixture after attachment.
        window.setContentSize(NSSize(width: 1_040, height: 760))
    }
    func captureBaseline() {
        baselineDraft = store.draft
        baselineDefaults = defaults.persistentDomain(forName: namespace) ?? [:]
    }
    func activateOwnedWindow(_ target: NSWindow, stage: String, deadline: ContinuousClock.Instant,
                             evidence: inout [[String: Any]]) async throws {
        try manageKeyboardRequire(target === window || target === window.attachedSheet,
            "Activation target is not a proof-owned window")
        func context(_ suffix: String) -> [String: Any] {
            ["stage": "\(stage)-\(suffix)", "applicationIsActive": NSApplication.shared.isActive,
             "keyWindowIsTarget": NSApplication.shared.keyWindow === target,
             "targetIsKeyWindow": target.isKeyWindow, "targetCanBecomeKeyWindow": target.canBecomeKey,
             "targetIsOwnedSheet": target === window.attachedSheet]
        }
        evidence.append(context("before"))
        // Normal macOS activation is scoped to this already-running inert
        // fixture. Do not change activation policy or operate another app.
        NSApplication.shared.activate()
        target.makeKeyAndOrderFront(nil)
        defer { evidence.append(context("after")) }
        do {
            try await manageKeyboardWait("Owned fixture window did not become active and key",
                deadline: min(deadline, .now.advanced(by: .seconds(5)))) {
                self.layout()
                return NSApplication.shared.isActive && NSApplication.shared.keyWindow === target
            }
        } catch {
            if error is CancellationError { throw error }
            throw ManageKeyboardFailure("Owned fixture activation failed: \(context("failure"))")
        }
    }
    func assertUnchanged() throws {
        try manageKeyboardRequire(store.draft == baselineDraft && store.draft?.hasChanges == false,
            "Focus changed the staged provider settings")
        let current = defaults.persistentDomain(forName: namespace) ?? [:]
        try manageKeyboardRequire(NSDictionary(dictionary: current).isEqual(to: baselineDefaults),
            "Focus changed saved runtime or other fixture settings")
        try manageKeyboardRequire(store.operation == .idle && store.pendingConfirmation == nil,
            "Focus initiated a provider operation or confirmation")
    }
    func layout() {
        for candidate in [window, window.attachedSheet].compactMap({ $0 }) {
            candidate.contentView?.layoutSubtreeIfNeeded(); candidate.displayIfNeeded()
        }
    }
    func matching(_ label: String, roles: [String], in root: NSObject) -> [NSObject] {
        manageKeyboardNodes(root).filter { roles.contains(manageKeyboardRole($0)) && manageKeyboardName($0) == label }
    }
    func exact(_ label: String, roles: [String], in root: NSObject) throws -> NSObject {
        let found = matching(label, roles: roles, in: root)
        try manageKeyboardRequire(found.count == 1, "Expected one native \(label); found \(found.count)")
        return found[0]
    }
    func control(_ target: String, in sheet: NSWindow) throws -> NSObject {
        switch target {
        case "forecast":
            let found = manageKeyboardNodes(sheet).filter {
                ["AXButton", "AXDisclosureTriangle"].contains(manageKeyboardRole($0))
                    && manageKeyboardName($0).hasPrefix("What-if forecast")
            }
            try manageKeyboardRequire(found.count == 1, "Expected one forecast disclosure; found \(found.count)")
            return found[0]
        case "runtime": return try exact("What-if daily runtime for Keyboard fixture", roles: ["AXSlider"], in: sheet)
        case "enabled": return try exact("Disable Keyboard fixture", roles: ["AXSwitch", "AXCheckBox"], in: sheet)
        case "preload": return try exact("Preload Keyboard fixture", roles: ["AXSwitch", "AXCheckBox"], in: sheet)
        case "details": return try exact("Details", roles: ["AXButton", "AXDisclosureTriangle"], in: sheet)
        case "delete": return try exact("Delete Keyboard fixture", roles: ["AXButton"], in: sheet)
        default:
            let identifier = target == "header" ? "models.manage.done" : "models.manage.footerDone"
            let found = manageKeyboardNodes(sheet).filter {
                manageKeyboardRole($0) == "AXButton" && manageKeyboardName($0) == "Done"
                    && manageKeyboardAttribute("accessibilityIdentifier", $0) as? String == identifier
            }
            try manageKeyboardRequire(found.count == 1, "Expected one native \(target) Done; found \(found.count)")
            return found[0]
        }
    }
    func focused(in sheet: NSWindow) -> String? {
        let found = (required.union(["delete"])).filter { target in
            guard let node = try? control(target, in: sheet) else { return false }
            return manageKeyboardFocus(node) == true
        }
        return found.count == 1 ? found.first : nil
    }
    func scrollViews(in sheet: NSWindow) -> [NSScrollView] {
        manageKeyboardNodes(sheet).compactMap { $0 as? NSScrollView }.filter {
            guard let document = $0.documentView else { return false }
            return $0.contentView.bounds.height > 100 && document.bounds.height > $0.contentView.bounds.height + 40
        }
    }
    func scroll(in sheet: NSWindow) throws -> NSScrollView {
        let found = scrollViews(in: sheet)
        try manageKeyboardRequire(found.count == 1, "Expected one overflowing native scroll view; found \(found.count)")
        return found[0]
    }
    func viewport(_ scroll: NSScrollView) -> NSRect {
        guard let window = scroll.window else { return .zero }
        return window.convertToScreen(scroll.contentView.convert(scroll.contentView.bounds, to: nil))
    }
    func assertFocusedVisible(_ target: String, node: NSObject, sheet: NSWindow) throws {
        try manageKeyboardRequire(NSApplication.shared.keyWindow === sheet && manageKeyboardFocus(node) == true,
            "Actual \(target) AX control does not own native keyboard focus")
        let owned = responderChain(in: sheet).contains {
            $0["isOwnedSheet"] as? Bool == true || $0["viewWindowIsOwnedSheet"] as? Bool == true
        }
        try manageKeyboardRequire(owned, "Focused \(target) responder does not belong to the owned sheet")
        guard let frame = manageKeyboardFrame(node), frame.width > 0, frame.height > 0 else {
            throw ManageKeyboardFailure("Actual \(target) AX frame is missing or empty")
        }
        let visible: NSRect
        if target == "footer", let content = sheet.contentView {
            visible = sheet.convertToScreen(content.convert(content.bounds, to: nil))
        } else { visible = viewport(try scroll(in: sheet)) }
        try manageKeyboardRequire(visible.insetBy(dx: -1, dy: -1).contains(frame),
            "Focused \(target) frame \(frame) is outside visible viewport \(visible)")
        try assertUnchanged()
    }
    func responderChain(in sheet: NSWindow) -> [[String: Any]] {
        var result: [[String: Any]] = [], seen = Set<ObjectIdentifier>()
        var responder = sheet.firstResponder
        for _ in 0..<32 {
            guard let current = responder, seen.insert(ObjectIdentifier(current)).inserted else { break }
            var entry: [String: Any] = ["class": String(describing: type(of: current)),
                "isOwnedSheet": current === sheet, "isOwnedHostWindow": current === window]
            if let view = current as? NSView { entry["viewWindowIsOwnedSheet"] = view.window === sheet }
            result.append(entry)
            // Once our window is reached, ownership is proven without walking
            // application or unrelated-window responder chains.
            if current === sheet || current === window { break }
            responder = current.nextResponder
        }
        return result
    }
    func evidence(_ target: String, sheet: NSWindow, stage: String) throws -> [String: Any] {
        let node = try control(target, in: sheet), scroll = try scroll(in: sheet)
        var result: [String: Any] = ["stage": stage, "control": target, "role": manageKeyboardRole(node),
            "label": manageKeyboardName(node), "AXFocused": manageKeyboardFocus(node) as Any? ?? NSNull(),
            "frame": manageKeyboardFrame(node).map(manageKeyboardRect) as Any? ?? NSNull(),
            "viewportFrame": manageKeyboardRect(viewport(scroll)), "scrollOffset": scroll.contentView.bounds.origin.y,
            "firstResponderClass": sheet.firstResponder.map { String(describing: type(of: $0)) } ?? "nil",
            "applicationIsActive": NSApplication.shared.isActive,
            "keyWindowIsOwnedSheet": NSApplication.shared.keyWindow === sheet,
            "responderChain": responderChain(in: sheet)]
        do { try assertFocusedVisible(target, node: node, sheet: sheet) }
        catch { result["assertionFailure"] = error.localizedDescription }
        return result
    }
    func awaitFocusedVisible(_ target: String, sheet: NSWindow, deadline: ContinuousClock.Instant) async throws {
        var lastFailure = "No visibility assertion observed"
        do {
            try await manageKeyboardWait("Focused \(target) was not revealed",
                deadline: min(deadline, .now.advanced(by: .seconds(2)))) {
                self.layout()
                do {
                    try self.assertFocusedVisible(target, node: self.control(target, in: sheet), sheet: sheet)
                    return true
                } catch { lastFailure = error.localizedDescription; return false }
            }
        } catch {
            if error is CancellationError { throw error }
            throw ManageKeyboardFailure("Focused \(target) was not revealed: \(lastFailure)")
        }
    }
    func advance(forward: Bool, sheet: NSWindow, deadline: ContinuousClock.Instant) async throws -> String {
        let before = focused(in: sheet)
        if forward { sheet.selectNextKeyView(nil) } else { sheet.selectPreviousKeyView(nil) }
        var target: String?
        try await manageKeyboardWait("Native key loop did not move to a distinct known control; previous=\(before ?? "unobserved")",
            deadline: min(deadline, .now.advanced(by: .seconds(2)))) {
            self.layout(); target = self.focused(in: sheet)
            return target != nil && target != before
        }
        return target!
    }
    func seek(_ target: String, sheet: NSWindow, deadline: ContinuousClock.Instant,
              evidence: inout [[String: Any]]) async throws {
        for _ in 0..<16 {
            if focused(in: sheet) == target {
                evidence.append(try self.evidence(target, sheet: sheet, stage: "seek-\(target)-before-reveal"))
                try await awaitFocusedVisible(target, sheet: sheet, deadline: deadline)
                try assertFocusedVisible(target, node: control(target, in: sheet), sheet: sheet)
                return
            }
            let next = try await advance(forward: true, sheet: sheet, deadline: deadline)
            evidence.append(try self.evidence(next, sheet: sheet, stage: "seek-\(target)"))
        }
        throw ManageKeyboardFailure("Native key loop could not reach \(target) in 16 steps")
    }
    func traverse(forward: Bool, sheet: NSWindow, deadline: ContinuousClock.Instant,
                  evidence: inout [[String: Any]]) async throws -> (visited: Set<String>, moved: Bool) {
        var visited = Set<String>(), offsets: [CGFloat] = []
        var target = focused(in: sheet)
        for step in 0..<18 {
            guard let current = target else { throw ManageKeyboardFailure("Native focus is not on an identifiable sheet control") }
            let node = try control(current, in: sheet)
            evidence.append(try self.evidence(current, sheet: sheet,
                stage: "\(forward ? "forward" : "backward")-\(step)-before-reveal"))
            try await awaitFocusedVisible(current, sheet: sheet, deadline: deadline)
            try assertFocusedVisible(current, node: node, sheet: sheet)
            evidence.append(try self.evidence(current, sheet: sheet, stage: "\(forward ? "forward" : "backward")-\(step)"))
            visited.insert(current); offsets.append(try scroll(in: sheet).contentView.bounds.origin.y)
            if required.isSubset(of: visited) {
                let moved = zip(offsets, offsets.dropFirst()).contains { a, b in forward ? b > a + 2 : b < a - 2 }
                return (visited, moved)
            }
            target = try await advance(forward: forward, sheet: sheet, deadline: deadline)
        }
        throw ManageKeyboardFailure("Native \(forward ? "forward" : "backward") loop missed required controls: \(required.subtracting(visited).sorted()); visited=\(visited.sorted()); Full Keyboard Access=\(NSApplication.shared.isFullKeyboardAccessEnabled)")
    }
    func controlDiagnostics(in sheet: NSWindow) -> [[String: Any]] {
        manageKeyboardNodes(sheet).filter { ["AXButton", "AXSlider", "AXSwitch", "AXCheckBox", "AXDisclosureTriangle"].contains(manageKeyboardRole($0)) }.map {
            ["role": manageKeyboardRole($0), "label": manageKeyboardName($0),
             "class": String(describing: type(of: $0)), "focused": manageKeyboardFocus($0) as Any? ?? NSNull(),
             "frame": manageKeyboardFrame($0).map(manageKeyboardRect) as Any? ?? NSNull()]
        }
    }
    func scrollDiagnostics(in sheet: NSWindow) -> [[String: Any]] {
        manageKeyboardNodes(sheet).filter { $0 is NSScrollView || manageKeyboardRole($0) == "AXScrollArea" }.map {
            var result: [String: Any] = ["class": String(describing: type(of: $0)),
                "role": manageKeyboardRole($0), "isNativeNSScrollView": $0 is NSScrollView,
                "frame": manageKeyboardFrame($0).map(manageKeyboardRect) as Any? ?? NSNull()]
            if let scroll = $0 as? NSScrollView {
                result["viewportHeight"] = scroll.contentView.bounds.height
                result["documentHeight"] = scroll.documentView?.bounds.height as Any? ?? NSNull()
            }
            return result
        }
    }
    func close() {
        if let sheet = window.attachedSheet { window.endSheet(sheet); sheet.close(); sheet.contentView = nil }
        host?.rootView = AnyView(EmptyView())
        host?.view.removeFromSuperview(); window.contentViewController = nil; window.contentView = nil
        window.close(); host = nil
        defaults.removePersistentDomain(forName: namespace)
    }
}

private actor ManageKeyboardController: ProviderControlling {
    static let modelID = "google/keyboard-fixture"
    private var refreshCount = 0
    private var mutationNames: [String] = []
    func refresh() async throws -> ProviderControlSnapshot {
        refreshCount += 1
        let catalog = [CatalogModel(id: Self.modelID, displayName: "Keyboard fixture", family: "gemma", modelType: "llm",
            capabilities: ["chat"], sizeGB: 4, minimumRAMGB: 8, active: true)]
        let local = [LocalModel(id: Self.modelID, modelType: "llm", sizeBytes: 4_000_000_000, estimatedMemoryGB: nil)]
        let selection = ProviderModelSelection(enabled: [Self.modelID], preloaded: [])
        let now = Date()
        return ProviderControlSnapshot(inventory: ModelInventoryBuilder.build(catalog: catalog, local: local,
            selection: selection, daemon: nil, loadedModels: []),
            draft: ProviderConfigDraft(sourceRevision: "manage-keyboard-fixture", original: selection, selection: selection),
            capturedAt: now, sources: ProviderControlSourceStates(catalog: .fresh(evidenceAt: now),
                localModels: .fresh(evidenceAt: now), daemon: .fresh(evidenceAt: now), loadedModels: .fresh(evidenceAt: now)))
    }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        mutationNames.append("save"); throw ManageKeyboardFailure("Unexpected synthetic save")
    }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {
        mutationNames.append("download"); throw ManageKeyboardFailure("Unexpected synthetic download")
    }
    func delete(_ localModelID: String) async throws {
        mutationNames.append("delete"); throw ManageKeyboardFailure("Unexpected synthetic delete")
    }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        mutationNames.append("lifecycle"); throw ManageKeyboardFailure("Unexpected synthetic lifecycle")
    }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func calls() -> (refreshes: Int, mutations: [String]) { (refreshCount, mutationNames) }
}

private struct ManageKeyboardFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
private func manageKeyboardRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw ManageKeyboardFailure(message) }
}
@MainActor
private func manageKeyboardWait(_ message: String, deadline: ContinuousClock.Instant,
                                condition: @MainActor () -> Bool) async throws {
    repeat {
        try Task.checkCancellation()
        guard ContinuousClock.now < deadline else { throw ManageKeyboardFailure(message) }
        if condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    } while ContinuousClock.now < deadline
    throw ManageKeyboardFailure(message)
}
@MainActor
private func manageKeyboardAttribute(_ getter: String, _ object: NSObject) -> Any? {
    guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
    return object.value(forKey: getter)
}
@MainActor
private func manageKeyboardRole(_ object: NSObject) -> String {
    manageKeyboardAttribute("accessibilityRole", object) as? String ?? ""
}
@MainActor
private func manageKeyboardName(_ object: NSObject) -> String {
    for getter in ["accessibilityLabel", "accessibilityTitle"] {
        if let text = manageKeyboardAttribute(getter, object) as? String, !text.isEmpty { return text }
    }
    return ""
}
@MainActor
private func manageKeyboardFocus(_ object: NSObject) -> Bool? {
    for getter in ["isAccessibilityFocused", "accessibilityFocused"] {
        if let number = manageKeyboardAttribute(getter, object) as? NSNumber { return number.boolValue }
    }
    return nil
}
@MainActor
private func manageKeyboardFrame(_ object: NSObject) -> NSRect? {
    (manageKeyboardAttribute("accessibilityFrame", object) as? NSValue)?.rectValue
}
private func manageKeyboardRect(_ rect: NSRect) -> [String: Double] {
    ["x": rect.origin.x, "y": rect.origin.y, "width": rect.width, "height": rect.height]
}
@MainActor
private func manageKeyboardNodes(_ root: NSObject) -> [NSObject] {
    var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
    func visit(_ object: NSObject) {
        guard seen.insert(ObjectIdentifier(object)).inserted, result.count < 2_000 else { return }
        result.append(object)
        for child in manageKeyboardAttribute("accessibilityChildren", object) as? [Any] ?? [] {
            if let child = child as? NSObject { visit(child) }
        }
        if let window = object as? NSWindow, let content = window.contentView { visit(content) }
        if let view = object as? NSView {
            if let descendant = NSAccessibility.unignoredDescendant(of: view) as? NSObject { visit(descendant) }
            for child in view.subviews { visit(child) }
        }
    }
    visit(root); return result
}
@MainActor
private func manageKeyboardPress(_ object: NSObject) throws {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    try manageKeyboardRequire(object.responds(to: selector), "Native control exposes no press action")
    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
    let invoke = unsafeBitCast(object.method(for: selector), to: Press.self)
    try manageKeyboardRequire(invoke(object, selector), "Native control rejected press")
}
