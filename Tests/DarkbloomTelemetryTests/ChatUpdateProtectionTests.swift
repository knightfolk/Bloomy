import AppKit
import DarkbloomTelemetry
import Testing
@testable import DarkbloomMonitor

/// Inert editor fixtures: no live endpoint, credentials, or sends are used.
@Suite("Chat update protection")
@MainActor
struct ChatUpdateProtectionTests {
    @Test("only meaningful text owned by the active conversation blocks an update")
    func activeDraftOwnership() {
        let active = UUID(), obsolete = UUID()
        let draft = ChatDraftState()
        #expect(!draft.hasUnsentText(in: active))
        draft.updateText(" \n\t", in: active)
        #expect(!draft.hasUnsentText(in: active))
        draft.updateText("Unsent prompt", in: active)
        #expect(draft.hasUnsentText(in: active))
        #expect(!draft.hasUnsentText(in: obsolete))
        #expect(!draft.hasUnsentText(in: nil))
        draft.reconcile(with: obsolete)
        #expect(draft.text.isEmpty)
        #expect(!draft.hasUnsentText(in: obsolete))
        draft.updateText("Unowned callback", in: nil)
        #expect(!draft.hasUnsentText(in: nil))
        #expect(!draft.hasUnsentText(in: active))
        draft.clear()
        #expect(draft.text.isEmpty)
        #expect(draft.conversationID == nil)
    }

    @Test("clearing or reconciling one composer preserves the other composer's protection")
    func independentDraftProtection() {
        let active = UUID(), next = UUID()
        let dashboard = ChatDraftState(), popOut = ChatDraftState()
        dashboard.updateText("Dashboard prompt", in: active)
        popOut.updateText("Pop-out prompt", in: active)
        #expect(dashboard.hasUnsentText(in: active))
        #expect(popOut.hasUnsentText(in: active))
        dashboard.clear()
        #expect(!dashboard.hasUnsentText(in: active))
        #expect(popOut.hasUnsentText(in: active))
        dashboard.updateText("New dashboard prompt", in: next)
        #expect(!popOut.hasUnsentText(in: next))
        popOut.reconcile(with: next)
        #expect(popOut.text.isEmpty)
        #expect(dashboard.hasUnsentText(in: next))
    }

    @Test("a pop-out retains its unsent text and update protection across minimize and close")
    func retainedPopOutDraft() async throws {
        let store = ChatStore(
            localClient: FakeChatRouteClient(), networkClient: FakeChatRouteClient(),
            balanceClient: FakeBalanceClient(), pricingClient: FakePricingClient(),
            keyStore: FakeConsumerKeyStore()
        )
        store.startConversation(route: .local)
        let active = try #require(store.conversation?.id)
        let controller = ChatWindowController(store: store, frameAutosaveName: nil)
        defer { controller.close() }
        controller.present(activate: false)
        try await settle(controller)
        let prompt = "Keep this unsent pop-out prompt."
        let editor = try composer(in: try #require(controller.window?.contentView))
        editor.insertText(prompt, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
        try await settle(controller)
        #expect(controller.chatDraft.text == prompt)
        #expect(controller.hasUnsavedChatEdits)

        controller.windowDidMiniaturize(Notification(name: NSWindow.didMiniaturizeNotification, object: controller.window))
        #expect(controller.hasUnsavedChatEdits)
        controller.close()
        try await settle(controller)
        #expect(controller.chatDraft.text == prompt)
        #expect(controller.chatDraft.conversationID == active)
        #expect(controller.hasUnsavedChatEdits)
        controller.present(activate: false)
        try await settle(controller)
        #expect(try composer(in: try #require(controller.window?.contentView)).string == prompt)
        #expect(controller.hasUnsavedChatEdits)
        controller.chatDraft.clear()
        #expect(!controller.hasUnsavedChatEdits)

        // A retained but obsolete draft must not indefinitely veto an update.
        controller.chatDraft.updateText("Obsolete prompt", in: active)
        controller.close()
        store.startConversation(route: .network)
        #expect(!controller.hasUnsavedChatEdits)
    }

    @Test("one key editor's close or clear cannot release another editor's owner")
    func independentCredentialOwners() {
        let protection = AppUpdateEditorProtection()
        let dashboardKeyEditor = UUID(), popOutKeyEditor = UUID()
        protection.setBlocked(true, owner: dashboardKeyEditor)
        protection.setBlocked(true, owner: popOutKeyEditor)
        protection.endEditing(owner: dashboardKeyEditor)
        #expect(protection.hasBlockingEditors)
        // Delayed cleanup from the first sheet is idempotent and scoped.
        protection.setBlocked(false, owner: dashboardKeyEditor)
        protection.endEditing(owner: dashboardKeyEditor)
        #expect(protection.hasBlockingEditors)
        protection.endEditing(owner: popOutKeyEditor)
        #expect(!protection.hasBlockingEditors)
    }

    private func settle(_ controller: ChatWindowController) async throws {
        try await Task.sleep(for: .milliseconds(150))
        controller.window?.contentView?.layoutSubtreeIfNeeded()
    }

    private func composer(in view: NSView) throws -> NSTextView {
        func find(in current: NSView) -> NSTextView? {
            if let editor = current as? NSTextView { return editor }
            for child in current.subviews {
                if let editor = find(in: child) { return editor }
            }
            return nil
        }
        return try #require(find(in: view), "Chat must mount its native message editor")
    }
}
