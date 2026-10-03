// Runs only in the opt-in synthetic app fixture under NSApplication.run().
// Native accessibility roles/names/actions are inspected directly; there is
// no provider, account, credential, privacy-setting, or process-lifecycle work.
import AppKit
import SwiftUI
import DarkbloomTelemetry

@MainActor
enum ModelManagerAccessibilityProof {
    private static let caseNames = ["cards-first-downloaded", "cards-both-downloaded", "manage-sheet"]

    /// Writes progress and an explicit terminal result. Missing AX controls
    /// fail a case; they are never skipped or replaced with emulated roles.
    static func run(outputDirectory: URL) async -> [String: Any] {
        var cases: [[String: Any]] = []
        var writeFailures: [String] = []
        func report(terminal: String) -> [String: Any] {
            let passed = cases.filter { $0["success"] as? Bool == true }.count
            return ["proof": "model-manager-accessibility", "synthetic": true,
                "terminal": terminal, "expectedCaseCount": caseNames.count,
                "completedCaseCount": cases.count, "passedCaseCount": passed,
                "failedCaseCount": cases.count - passed, "cases": cases,
                "reportWriteFailures": writeFailures,
                "success": terminal == "success" && cases.count == caseNames.count && passed == caseNames.count && writeFailures.isEmpty]
        }
        func write(_ value: [String: Any]) throws {
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputDirectory.appendingPathComponent("model-manager-accessibility-proof.json"), options: .atomic)
        }
        do { try write(report(terminal: "running")) }
        catch { writeFailures.append("Initial result could not be written: \(error.localizedDescription)") }

        for caseName in caseNames {
            var failures: [String] = []
            let fixture = ModelAccessibilityFixture(secondDownloaded: caseName != "cards-first-downloaded")
            await fixture.store.refresh()
            do {
                if caseName == "manage-sheet" { try await manageSheetSwitches(fixture) }
                else { try await contextualCardActions(fixture, secondDownloaded: caseName == "cards-both-downloaded") }
            } catch { failures.append(error.localizedDescription) }
            let mutations = await fixture.controller.mutationAttempts()
            if !mutations.isEmpty { failures.append("Unexpected provider mutation attempts: \(mutations.joined(separator: ", "))") }
            fixture.close()
            cases.append(["name": caseName, "success": failures.isEmpty, "failures": failures])
            do { try write(report(terminal: "running")) }
            catch { writeFailures.append("Case result could not be written: \(error.localizedDescription)") }
        }

        let passed = cases.filter { $0["success"] as? Bool == true }.count
        let terminal = passed == caseNames.count && writeFailures.isEmpty ? "success" : "failure"
        var result = report(terminal: terminal)
        do { try write(result) }
        catch {
            writeFailures.append("Terminal result could not be written: \(error.localizedDescription)")
            result = report(terminal: "failure")
        }
        let success = result["success"] as? Bool == true
        print("ModelManagerAccessibilityProof TERMINAL_\(success ? "SUCCESS" : "FAILURE") completed=\(cases.count) expected=\(caseNames.count) passed=\(passed) failed=\(cases.count - passed) reportWriteFailures=\(writeFailures.count)")
        return result
    }

    private static func contextualCardActions(_ fixture: ModelAccessibilityFixture, secondDownloaded: Bool) async throws {
        let nodes = try await readyDescendants(of: fixture.window, named: "Manage Gemma fixture", roles: ["AXButton"])
        let firstAction = try node(named: "Manage Gemma fixture", roles: ["AXButton"], in: nodes)
        let secondAction = try node(named: secondDownloaded ? "Manage Qwen fixture" : "Details for Qwen fixture", roles: ["AXButton"], in: nodes)
        try require(firstAction !== secondAction, "Each card must expose its own distinct native action")
        try require(!nodes.contains { role($0) == "AXButton" && ["Manage", "Details"].contains(name($0)) }, "Generic card action remains")
        let enabled = try node(named: "Disable Gemma fixture", roles: ["AXCheckBox"], in: nodes)
        let preload = try node(named: "Preload Gemma fixture", roles: ["AXCheckBox"], in: nodes)
        try require(state(enabled) == true && state(preload) == false, "Card checkbox states do not match the synthetic selection")
        try require(nodes.filter { name($0) == "Disable Gemma fixture" }.count == 1, "Enabled checkbox name has duplicate AX nodes")
        try require(nodes.filter { name($0) == "Preload Gemma fixture" }.count == 1, "Preload checkbox name has duplicate AX nodes")
        try press(enabled)
        try await settle(fixture.window)
        guard let draft = fixture.store.draft else { throw ModelAccessibilityFailure("Draft is absent after checkbox press") }
        try require(!draft.selection.enabled.contains(ModelAccessibilityController.firstID), "Gemma checkbox did not edit Gemma's draft")
        try require(draft.selection.enabled.contains(ModelAccessibilityController.secondID) == secondDownloaded, "Gemma checkbox altered Qwen's draft selection")
        try require(draft.selection.preloaded.isEmpty && draft.hasChanges, "Checkbox press did not retain only the intended staged change")
        let updated = try node(named: "Enable Gemma fixture", roles: ["AXCheckBox"], in: descendants(of: fixture.window))
        try require(state(updated) == false, "Gemma checkbox state did not reflect the draft change")
    }

    private static func manageSheetSwitches(_ fixture: ModelAccessibilityFixture) async throws {
        let initial = try await readyDescendants(of: fixture.window, named: "Manage Qwen fixture", roles: ["AXButton"])
        _ = try node(named: "Manage Gemma fixture", roles: ["AXButton"], in: initial)
        let manage = try node(named: "Manage Qwen fixture", roles: ["AXButton"], in: initial)
        try press(manage)
        try await waitUntil { fixture.window.attachedSheet != nil }
        guard let sheet = fixture.window.attachedSheet else { throw ModelAccessibilityFailure("Manage sheet is absent") }
        let nodes = try await readyDescendants(of: sheet, named: "Disable Qwen fixture", roles: ["AXCheckBox", "AXSwitch"])
        let enabled = try node(named: "Disable Qwen fixture", roles: ["AXCheckBox", "AXSwitch"], in: nodes)
        let preload = try node(named: "Preload Qwen fixture", roles: ["AXCheckBox", "AXSwitch"], in: nodes)
        try require(state(enabled) == true && state(preload) == false, "Sheet switch states do not match the synthetic selection")
        try require(nodes.filter { name($0) == "Disable Qwen fixture" }.count == 1, "Sheet enable switch name has duplicate AX nodes")
        try require(nodes.filter { name($0) == "Preload Qwen fixture" }.count == 1, "Sheet preload switch name has duplicate AX nodes")
        try require(!nodes.contains { role($0) == "AXStaticText" && ["Enabled", "Load at startup"].contains(name($0)) }, "Decorative sheet caption remains separately accessible")
        try press(preload)
        try await settle(sheet)
        guard let draft = fixture.store.draft else { throw ModelAccessibilityFailure("Draft is absent after sheet switch press") }
        try require(draft.selection.preloaded == [ModelAccessibilityController.secondID], "Qwen switch did not edit only Qwen's preload draft")
        try require(draft.selection.enabled == [ModelAccessibilityController.firstID, ModelAccessibilityController.secondID], "Preload switch changed unrelated enabled models")
        try require(draft.hasChanges, "Sheet switch did not retain a staged edit")
        let updated = try node(named: "Remove preload Qwen fixture", roles: ["AXCheckBox", "AXSwitch"], in: descendants(of: sheet))
        try require(state(updated) == true, "Sheet preload switch state did not reflect the draft change")
        let sheetNodes = descendants(of: sheet)
        let headerDone = try node(identifier: "models.manage.done", named: "Done", roles: ["AXButton"], in: sheetNodes)
        let footerDone = try node(identifier: "models.manage.footerDone", named: "Done", roles: ["AXButton"], in: sheetNodes)
        try require(headerDone !== footerDone, "Header and footer Done identifiers resolved to the same native control")
        try press(footerDone)
        try await waitUntil { fixture.window.attachedSheet == nil }
        try require(fixture.store.draft?.selection.preloaded == [ModelAccessibilityController.secondID], "Closing Manage did not retain the staged Qwen draft")
    }

    private static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw ModelAccessibilityFailure(message) }
    }

    private static func settle(_ window: NSWindow) async throws {
        try await Task.sleep(for: .milliseconds(100))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    private static func readyDescendants(of window: NSWindow, named expectedName: String, roles: [String]) async throws -> [NSObject] {
        let deadline = Date().addingTimeInterval(8)
        var nodes: [NSObject] = []
        repeat {
            try await settle(window)
            nodes = descendants(of: window)
            if nodes.contains(where: { roles.contains(role($0)) && name($0) == expectedName }) { return nodes }
        } while Date() < deadline
        print("ModelAXDiagnostics expected=\(expectedName) visible=\(window.isVisible) nodes=\(nodes.count): \(summary(nodes))")
        return nodes // Exact-one assertion below fails missing native controls.
    }

    private static func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(10)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try require(condition(), "The fixture sheet did not finish its transition")
    }

    private static func node(named expectedName: String, roles: [String], in nodes: [NSObject]) throws -> NSObject {
        // Enclosing card identifiers propagate to children on this macOS.
        // Real native roles and contextual names must each match exactly once.
        let matches = nodes.filter { roles.contains(role($0)) && name($0) == expectedName }
        if matches.count != 1 {
            print("ModelAXDiagnostics expected=\(expectedName) matches=\(matches.count): \(summary(nodes))")
        }
        try require(matches.count == 1, "Expected exactly one native \(roles.joined(separator: "/")) named \(expectedName); found \(matches.count)")
        return matches[0]
    }

    private static func node(identifier expectedIdentifier: String, named expectedName: String,
        roles: [String], in nodes: [NSObject]) throws -> NSObject {
        let identified = nodes.filter {
            attribute("accessibilityIdentifier", of: $0) as? String == expectedIdentifier
        }
        if identified.count != 1 {
            print("ModelAXDiagnostics expectedIdentifier=\(expectedIdentifier) matches=\(identified.count): \(summary(nodes))")
        }
        try require(identified.count == 1,
            "Expected exactly one native node with accessibility identifier \(expectedIdentifier); found \(identified.count)")

        let control = identified[0]
        try require(roles.contains(role(control)),
            "Native control \(expectedIdentifier) has role \(role(control)); expected \(roles.joined(separator: "/"))")
        try require(name(control) == expectedName,
            "Native control \(expectedIdentifier) is named \(name(control)); expected \(expectedName)")
        return control
    }

    private static func role(_ node: NSObject) -> String { attribute("accessibilityRole", of: node) as? String ?? "" }
    private static func name(_ node: NSObject) -> String {
        for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
            if let value = attribute(key, of: node) as? String, !value.isEmpty { return value }
        }
        return ""
    }
    private static func state(_ node: NSObject) -> Bool? {
        let value = attribute("accessibilityValue", of: node)
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            if ["1", "on"].contains(text.lowercased()) { return true }
            if ["0", "off"].contains(text.lowercased()) { return false }
        }
        return nil
    }
    private static func attribute(_ getter: String, of object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
        return object.value(forKey: getter)
    }
    private static func descendants(of root: NSObject) -> [NSObject] {
        var result: [NSObject] = [], seen: Set<ObjectIdentifier> = []
        func visit(_ object: NSObject) {
            guard seen.insert(ObjectIdentifier(object)).inserted, result.count < 2_000 else { return }
            result.append(object)
            for child in attribute("accessibilityChildren", of: object) as? [Any] ?? [] {
                if let child = child as? NSObject { visit(child) }
            }
            if let window = object as? NSWindow, let content = window.contentView { visit(content) }
            if let view = object as? NSView {
                if let descendant = NSAccessibility.unignoredDescendant(of: view) as? NSObject { visit(descendant) }
                for child in view.subviews { visit(child) }
            }
        }
        visit(root)
        return result
    }
    private static func summary(_ nodes: [NSObject]) -> String {
        nodes.prefix(80).map { node in
            let identifier = attribute("accessibilityIdentifier", of: node) as? String ?? "nil"
            return "\(type(of: node))[role=\(role(node)); name=\(name(node)); id=\(identifier)]"
        }.joined(separator: " | ")
    }
    private static func press(_ object: NSObject) throws {
        let selector = NSSelectorFromString("accessibilityPerformPress")
        try require(object.responds(to: selector), "The native control does not expose a press action")
        typealias Press = @convention(c) (AnyObject, Selector) -> Bool
        let invoke = unsafeBitCast(object.method(for: selector), to: Press.self)
        try require(invoke(object, selector), "The native accessibility press was rejected")
    }
}

private struct ModelAccessibilityFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

@MainActor
private struct ModelAccessibilityFixture {
    let namespace = "ModelAccessibility-\(UUID().uuidString)"
    let defaults: UserDefaults
    let controller: ModelAccessibilityController
    let store: ProviderControlStore
    let window: NSWindow

    init(secondDownloaded: Bool) {
        // A named in-memory fixture suite never reads real provider defaults.
        defaults = UserDefaults(suiteName: namespace)!
        controller = ModelAccessibilityController(secondDownloaded: secondDownloaded)
        store = ProviderControlStore(controller: controller)
        let host = NSHostingController(rootView: ModelManagerView(store: store).defaultAppStorage(defaults))
        window = NSWindow(contentViewController: host)
        window.title = "Model accessibility proof — synthetic"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 1_040, height: 760))
        window.makeKeyAndOrderFront(nil)
    }

    func close() {
        if let sheet = window.attachedSheet {
            window.endSheet(sheet)
            sheet.close()
        }
        window.close()
        defaults.removePersistentDomain(forName: namespace)
    }
}

private actor ModelAccessibilityController: ProviderControlling {
    static let firstID = "google/gemma-fixture"
    static let secondID = "qwen/qwen-fixture"
    private var unexpectedMutations: [String] = []
    let secondDownloaded: Bool

    init(secondDownloaded: Bool) { self.secondDownloaded = secondDownloaded }

    func refresh() async throws -> ProviderControlSnapshot {
        let now = Date()
        let catalog = [
            CatalogModel(id: Self.firstID, displayName: "Gemma fixture", family: "gemma", modelType: "llm",
                capabilities: ["chat"], sizeGB: 4, minimumRAMGB: 8, active: true),
            CatalogModel(id: Self.secondID, displayName: "Qwen fixture", family: "qwen", modelType: "llm",
                capabilities: ["chat"], sizeGB: 4, minimumRAMGB: 8, active: true)
        ]
        let downloaded = secondDownloaded ? [Self.firstID, Self.secondID] : [Self.firstID]
        let local = downloaded.map { LocalModel(id: $0, modelType: "llm", sizeBytes: 4_000_000_000, estimatedMemoryGB: nil) }
        let selection = ProviderModelSelection(enabled: downloaded, preloaded: [])
        return ProviderControlSnapshot(inventory: ModelInventoryBuilder.build(catalog: catalog, local: local,
            selection: selection, daemon: nil, loadedModels: []),
            draft: ProviderConfigDraft(sourceRevision: "model-accessibility-fixture", original: selection, selection: selection),
            capturedAt: now, sources: ProviderControlSourceStates(catalog: .fresh(evidenceAt: now),
                localModels: .fresh(evidenceAt: now), daemon: .fresh(evidenceAt: now), loadedModels: .fresh(evidenceAt: now)))
    }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        unexpectedMutations.append("save provider settings")
        throw ModelAccessibilityUnexpectedMutation()
    }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {
        unexpectedMutations.append("download model")
        throw ModelAccessibilityUnexpectedMutation()
    }
    func delete(_ localModelID: String) async throws {
        unexpectedMutations.append("delete model")
        throw ModelAccessibilityUnexpectedMutation()
    }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func mutationAttempts() -> [String] { unexpectedMutations }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        unexpectedMutations.append("dispatch provider operation")
        throw ModelAccessibilityUnexpectedMutation()
    }
}

private struct ModelAccessibilityUnexpectedMutation: Error {}
