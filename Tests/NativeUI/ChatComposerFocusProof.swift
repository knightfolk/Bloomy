// Opt-in, finite proof under normal NSApplication.run(); no endpoint or key access.
import AppKit
import Foundation
import SwiftUI
import DarkbloomTelemetry

@MainActor
enum ChatComposerFocusProof {
    static func run(outputDirectory: URL) async -> Bool {
        let names = ["explicit_cancel_restores_existing_composer", "cancel_elsewhere_preserves_key_window",
                     "normal_completion_preserves_focus", "external_cancel_preserves_focus"]
        var cases: [[String: Any]] = [], failures: [String] = []
        var contexts: [[String: Any]] = []
        var fixture: ChatFocusFixture?
        weak var firstHost: NSHostingController<ChatView>?
        weak var secondHost: NSHostingController<ChatView>?
        var cleanupPassed = false
        func write(_ terminal: String) throws {
            let result: [String: Any] = ["proof": "chat-composer-focus", "synthetic": true,
                "terminal": terminal, "expectedCaseCount": names.count, "completedCaseCount": cases.count,
                "completedcases": cases.map { $0["name"] as? String ?? "" }, "cases": cases,
                "failures": failures, "windowContexts": contexts, "cleanupPassed": cleanupPassed,
                "passed": terminal == "completed" && cases.count == names.count && failures.isEmpty && cleanupPassed]
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
                .write(to: outputDirectory.appendingPathComponent("chat-composer-focus-proof.json"), options: .atomic)
        }
        do {
            try write("running")
            try chatFocusRequire(NSApplication.shared.isRunning, "Normal NSApplication.run is required")
            let owned = ChatFocusFixture()
            fixture = owned
            firstHost = owned.first.host
            secondHost = owned.second.host
            owned.store.startConversation(route: .local)
            contexts.append(owned.context("initial-before-presentation"))
            owned.first.window.makeKeyAndOrderFront(nil)
            owned.second.window.orderBack(nil)
            contexts.append(owned.context("initial-after-presentation"))
            try await chatFocusWait("Inert model verification did not become ready") { owned.store.canSend }
            let firstEditor = try await owned.first.readyEditor()
            let secondEditor = try await owned.second.readyEditor()
            contexts.append(owned.context("initial-after-readiness-yields"))
            owned.second.draft.updateText("Independent synthetic draft", in: owned.store.conversation?.id)
            try await chatFocusWait("Second composer did not render its independent draft") {
                secondEditor.string == "Independent synthetic draft"
            }
            for name in names {
                var result: [String: Any] = ["name": name, "passed": false]
                do {
                    contexts += try await owned.sentinels(stage: name)
                    try await owned.beginSend()
                    let cancel = try await owned.first.cancelButton()
                    if name == names[0] {
                        contexts.append(owned.context("\(name)-before-make-key"))
                        owned.first.window.makeKeyAndOrderFront(nil)
                        contexts.append(owned.context("\(name)-after-make-key"))
                        try chatFocusRequire(owned.first.window.makeFirstResponder(firstEditor), "Composer rejected native focus")
                        owned.first.window.selectNextKeyView(nil)
                        try await chatFocusWait("Native key loop did not focus the actual Cancel control") {
                            let focus = chatFocusObservedFocus(cancel)
                            result["cancelFocusedGetter"] = focus.getter ?? "unavailable"
                            result["cancelAXFocused"] = focus.value.map { $0 as Any } ?? NSNull()
                            result["cancelKeyWindowMatched"] = NSApplication.shared.keyWindow === owned.first.window
                            result["cancelResponderClass"] = owned.first.window.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"
                            result["cancelFocusContext"] = owned.context("\(name)-after-focus-yields")
                            return owned.first.cancelHasNativeFocus(cancel)
                        }
                        try chatFocusPress(cancel)
                        await owned.client.release(success: false)
                        try await chatFocusWait("Explicit Cancel did not restore its existing TextEditor") {
                            NSApplication.shared.keyWindow === owned.first.window
                                && owned.first.window.firstResponder === firstEditor
                        }
                        try chatFocusRequire(try owned.first.editor() === firstEditor, "Cancel replaced the TextEditor")
                        firstEditor.insertText("Follow-up after cancel", replacementRange: NSRange(location: 0, length: 0))
                        try await chatFocusWait("Follow-up did not reach the initiating draft") {
                            owned.first.draft.text == "Follow-up after cancel"
                        }
                        try chatFocusRequire(owned.second.draft.text == "Independent synthetic draft",
                            "Cancel or follow-up altered the independent composer")
                        result["existingComposerFocused"] = true
                        result["followUpDraftMatched"] = true
                    } else {
                        contexts.append(owned.context("\(name)-before-make-key"))
                        owned.second.window.makeKeyAndOrderFront(nil)
                        contexts.append(owned.context("\(name)-after-make-key"))
                        try chatFocusRequire(owned.second.window.makeFirstResponder(owned.second.sentinel), "Sentinel rejected focus")
                        if name == names[1] { try chatFocusPress(cancel) }
                        else if name == names[3] { owned.store.cancelSend() }
                        await owned.client.release(success: name == names[2])
                        try await owned.joinSend()
                        // Observe identities throughout a finite post-publication settling interval.
                        for _ in 0..<5 {
                            try await Task.sleep(for: .milliseconds(40))
                            owned.first.layout(); owned.second.layout()
                            result["postPublicationContext"] = owned.context("\(name)-after-publication-yields")
                            try chatFocusRequire(NSApplication.shared.keyWindow === owned.second.window,
                                "Background publication changed the key window")
                            try chatFocusRequire(owned.second.window.firstResponder === owned.second.sentinel,
                                "Background publication stole the other window's responder")
                            if name != names[1] {
                                try chatFocusRequire(owned.first.window.firstResponder === owned.first.sentinel,
                                    "Completion/external cancellation moved the initiating window's responder")
                            }
                        }
                        result["keyWindowPreserved"] = true
                        result["otherResponderPreserved"] = true
                        result["initiatingResponderPreserved"] = name != names[1]
                    }
                    try await owned.joinSend()
                    try chatFocusRequire(!owned.store.isSending, "Send did not reach terminal state")
                    let phase = owned.store.conversation?.entries.last?.phase
                    try chatFocusRequire(phase == (name == names[2] ? .complete : .cancelled), "Unexpected terminal send phase")
                    result["passed"] = true
                } catch {
                    let message = "\(name): \(error.localizedDescription)"
                    result["failure"] = message; failures.append(message)
                }
                owned.store.cancelSend()
                await owned.client.release(success: false)
                do { try await owned.joinSend() }
                catch { failures.append("\(name) send cleanup: \(error.localizedDescription)") }
                cases.append(result)
                do { try write("running") }
                catch { failures.append("Progress report write failed: \(error.localizedDescription)") }
            }
        } catch { failures.append(error is CancellationError ? "Proof cancelled" : error.localizedDescription) }

        // An unstructured cleanup task does not inherit caller cancellation.
        let cleanupStore = fixture?.store
        if let owned = fixture {
            let cleanup = Task { @MainActor in await owned.close() }
            cleanupPassed = await cleanup.value
        }
        fixture = nil
        let releaseCheck = Task { @MainActor in
            do {
                try await chatFocusWait("Owned hosting controllers were not released") {
                    firstHost == nil && secondHost == nil && cleanupStore?.hasScheduledModelExpiry != true
                }
                return true
            } catch { return false }
        }
        let hostsReleased = await releaseCheck.value
        cleanupPassed = cleanupPassed && hostsReleased
        if !cleanupPassed { failures.append("Owned window/host/send/deadline cleanup failed") }
        do { try write("completed") }
        catch { failures.append("Terminal report write failed: \(error.localizedDescription)") }
        let passed = cases.count == names.count && failures.isEmpty && cleanupPassed
        print("ChatComposerFocusProof TERMINAL_\(passed ? "SUCCESS" : "FAILURE") completed=\(cases.count) expected=\(names.count) cleanup=\(cleanupPassed)")
        return passed
    }
}

@MainActor
private final class ChatFocusFixture {
    let client: ChatFocusClient
    let store: ChatStore
    let first: ChatFocusWindow
    let second: ChatFocusWindow
    weak var sendToken: ChatFocusTaskToken?

    init() {
        let client = ChatFocusClient()
        self.client = client
        store = ChatStore(localClient: client, networkClient: client, balanceClient: ChatFocusUnusedServices(),
            pricingClient: ChatFocusUnusedServices(), keyStore: ChatFocusNoKeys())
        first = ChatFocusWindow(store: store, title: "Chat focus proof — first synthetic surface")
        second = ChatFocusWindow(store: store, title: "Chat focus proof — second synthetic surface")
    }
    func context(_ stage: String) -> [String: Any] {
        func window(_ value: NSWindow) -> [String: Any] {
            ["title": value.title, "number": value.windowNumber, "class": String(describing: type(of: value)),
             "isKeyWindow": value.isKeyWindow, "canBecomeKeyWindow": value.canBecomeKey,
             "isVisible": value.isVisible,
             "firstResponderClass": value.firstResponder.map { String(describing: type(of: $0)) } ?? "nil"]
        }
        let application = NSApplication.shared
        return ["stage": stage, "isActive": application.isActive,
                "keyWindowTitle": application.keyWindow?.title ?? "nil",
                "keyWindowNumber": application.keyWindow?.windowNumber ?? -1,
                "first": window(first.window), "second": window(second.window)]
    }
    func sentinels(stage: String) async throws -> [[String: Any]] {
        var contexts = [context("\(stage)-sentinels-before-make-key")]
        first.draft.clear()
        first.window.makeKeyAndOrderFront(nil)
        contexts.append(context("\(stage)-sentinels-after-make-key"))
        try chatFocusRequire(first.window.makeFirstResponder(first.sentinel), "First sentinel rejected focus")
        try chatFocusRequire(second.window.makeFirstResponder(second.sentinel), "Second sentinel rejected focus")
        try await Task.sleep(for: .milliseconds(40))
        try await chatFocusWait("Sentinels did not settle") {
            self.first.window.firstResponder === self.first.sentinel
                && self.second.window.firstResponder === self.second.sentinel
        }
        contexts.append(context("\(stage)-sentinels-after-yield"))
        return contexts
    }
    func beginSend() async throws {
        var token: ChatFocusTaskToken? = ChatFocusTaskToken()
        sendToken = token
        let accepted = ChatFocusTaskScope.$token.withValue(token) { store.send("Synthetic held prompt") }
        token = nil
        try chatFocusRequire(accepted && sendToken != nil, "Send was rejected or its task context did not retain the lifetime token")
        try await chatFocusWait("Injected completion was not actually in flight") {
            await self.client.activeCount == 1 && self.store.isSending
        }
    }
    func joinSend() async throws {
        try await chatFocusWait("Held completion/send task context did not finish") {
            await self.client.activeCount == 0 && self.sendToken == nil && !self.store.isSending
        }
    }
    func close() async -> Bool {
        store.cancelSend()
        await client.shutdown()
        var joined = false
        do { try await joinSend(); joined = true } catch {}
        first.close(store: store); second.close(store: store)
        // Deadline teardown is checked after releasing these hosting controllers.
        return joined && !first.window.isVisible && !second.window.isVisible && !store.isSending
    }
}

@MainActor
private final class ChatFocusWindow {
    let draft = ChatDraftState()
    let host: NSHostingController<ChatView>
    let window: NSWindow
    let sentinel = NSButton(title: "Synthetic focus sentinel", target: nil, action: nil)

    init(store: ChatStore, title: String) {
        host = NSHostingController(rootView: ChatView(store: store, draft: draft))
        window = NSWindow(contentRect: NSRect(x: 80, y: 80, width: 760, height: 660),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = title; window.isReleasedWhenClosed = false
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 660))
        host.view.frame = NSRect(x: 0, y: 40, width: 760, height: 620)
        host.view.autoresizingMask = [.width, .height]
        sentinel.frame = NSRect(x: 16, y: 8, width: 200, height: 24)
        root.addSubview(host.view); root.addSubview(sentinel); window.contentView = root
    }
    func layout() { window.contentView?.layoutSubtreeIfNeeded(); window.displayIfNeeded() }
    func editor() throws -> NSTextView {
        let editors = chatFocusNativeViews(host.view).compactMap { $0 as? NSTextView }.filter(\.isEditable)
        try chatFocusRequire(editors.count == 1, "Expected exactly one existing native editable TextEditor; found \(editors.count)")
        return editors[0]
    }
    func readyEditor() async throws -> NSTextView {
        try await chatFocusWait("Native TextEditor did not mount") { self.layout(); return (try? self.editor()) != nil }
        return try editor()
    }
    func cancelButton() async throws -> NSObject {
        try await chatFocusWait("Expected exactly one native AXButton named Cancel") { self.layout(); return self.cancelNodes().count == 1 }
        return cancelNodes()[0]
    }
    private func cancelNodes() -> [NSObject] {
        chatFocusAXNodes(window).filter { node in
            chatFocusAttribute("accessibilityRole", node) as? String == "AXButton"
                && ["accessibilityLabel", "accessibilityTitle"].contains { key in
                    chatFocusAttribute(key, node) as? String == "Cancel"
                }
        }
    }
    func cancelHasNativeFocus(_ node: NSObject) -> Bool {
        guard NSApplication.shared.keyWindow === window,
              let responder = window.firstResponder,
              let composer = try? editor(), responder !== composer,
              chatFocusObservedFocus(node).value == true
        else { return false }
        // SwiftUI can focus a native KeyViewProxy rather than NSButton. Require
        // the exact Cancel AX element to be focused and its real responder to
        // belong to this window; never substitute a fabricated AX/control tree.
        var current: NSResponder? = responder
        for _ in 0..<32 {
            if let view = current as? NSView, view.window === window,
               view === host.view || view.isDescendant(of: host.view) { return true }
            current = current?.nextResponder
        }
        return false
    }
    func close(store: ChatStore) {
        host.rootView = ChatView(store: store, draft: draft, isVisible: false)
        window.close(); host.view.removeFromSuperview(); window.contentView = nil
    }
}

private final class ChatFocusTaskToken: Sendable {}
private enum ChatFocusTaskScope { @TaskLocal static var token: ChatFocusTaskToken? }

private actor ChatFocusClient: LocalChatRouteClient, NetworkChatRouteClient {
    private var pending: [UUID: CheckedContinuation<ChatCompletionOutcome, any Error>] = [:]
    private var liveIDs = Set<UUID>()
    private var cancelledBeforeRegistration = Set<UUID>()
    private var isClosed = false
    private(set) var activeCount = 0
    func models(now: Date) async throws -> ChatModelListSnapshot { .init(modelIDs: ["fixture/model"], capturedAt: now) }
    func complete(model: String, messages: [ChatMessagePayload]) async throws -> ChatCompletionOutcome {
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        let id = UUID()
        liveIDs.insert(id)
        activeCount += 1
        defer {
            activeCount -= 1
            liveIDs.remove(id)
            cancelledBeforeRegistration.remove(id)
        }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                // Cancellation can win before this continuation is registered.
                // Terminal shutdown also rejects any queued late registration.
                if Task.isCancelled || isClosed || cancelledBeforeRegistration.remove(id) != nil {
                    continuation.resume(throwing: CancellationError())
                } else {
                    pending[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }
    private func cancel(_ id: UUID) {
        guard liveIDs.contains(id) else { return }
        if let continuation = pending.removeValue(forKey: id) {
            continuation.resume(throwing: CancellationError())
        } else {
            cancelledBeforeRegistration.insert(id)
        }
    }
    func shutdown() {
        isClosed = true
        release(success: false)
    }
    func release(success: Bool) {
        let held = pending; pending.removeAll()
        for continuation in held.values {
            if success {
                continuation.resume(returning: .init(content: "Synthetic reply", model: "fixture/model", finishReason: "stop",
                    promptTokens: 1, completionTokens: 1))
            } else { continuation.resume(throwing: CancellationError()) }
        }
    }
}
private struct ChatFocusNoKeys: ConsumerKeyManaging {
    var hasKey: Bool { false }
    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? { nil }
    func store(_ key: String) throws { throw ChatFocusFailure("Unexpected key write") }
    func remove() {}
}
private struct ChatFocusUnusedServices: ConsumerBalanceFetching, PublicPricingFetching {
    func fetch(now: Date) async throws -> ConsumerBalanceSnapshot { throw ChatFocusFailure("Unexpected balance read") }
    func fetch(at capturedAt: Date) async throws -> PublicPricingSnapshot { throw ChatFocusFailure("Unexpected pricing read") }
}
private struct ChatFocusFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}
private func chatFocusRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw ChatFocusFailure(message) }
}
@MainActor
private func chatFocusWait(_ message: String, condition: @MainActor () async -> Bool) async throws {
    let clock = ContinuousClock(), deadline = ContinuousClock.now.advanced(by: .seconds(5))
    repeat {
        try Task.checkCancellation()
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(20))
    } while clock.now < deadline
    throw ChatFocusFailure(message)
}
@MainActor
private func chatFocusNativeViews(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(chatFocusNativeViews) }
@MainActor
private func chatFocusAttribute(_ getter: String, _ object: NSObject) -> Any? {
    guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
    return object.value(forKey: getter)
}
@MainActor
private func chatFocusObservedFocus(_ object: NSObject) -> (getter: String?, value: Bool?) {
    for getter in ["isAccessibilityFocused", "accessibilityFocused"] {
        guard object.responds(to: NSSelectorFromString(getter)) else { continue }
        if let value = chatFocusAttribute(getter, object) as? NSNumber { return (getter, value.boolValue) }
    }
    return (nil, nil)
}
@MainActor
private func chatFocusAXNodes(_ root: NSObject) -> [NSObject] {
    var result: [NSObject] = [], seen = Set<ObjectIdentifier>()
    func visit(_ object: NSObject) {
        guard seen.insert(ObjectIdentifier(object)).inserted, result.count < 2_000 else { return }
        result.append(object)
        for child in chatFocusAttribute("accessibilityChildren", object) as? [Any] ?? [] {
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
private func chatFocusPress(_ object: NSObject) throws {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    try chatFocusRequire(object.responds(to: selector), "Native Cancel has no press action")
    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
    let invoke = unsafeBitCast(object.method(for: selector), to: Press.self)
    try chatFocusRequire(invoke(object, selector), "Native Cancel press rejected")
}
