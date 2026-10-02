import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Chat controls and transcript presentation", .serialized)
@MainActor
struct ChatPresentationTests {
    @Test("identical message content retains distinct spoken speakers")
    func spokenSpeakers() {
        let text = "The same synthetic message."
        let user = ChatEntry(id: UUID(), author: .user, text: text, phase: .complete)
        let assistant = ChatEntry(id: UUID(), author: .assistant, text: text, phase: .complete)
        #expect(ChatEntryPresentation(entry: user).speaker == "You")
        #expect(ChatEntryPresentation(entry: assistant).speaker == "Assistant")
        #expect(ChatEntryPresentation(entry: user).messageAccessibilityLabel == "You: \(text)")
        #expect(ChatEntryPresentation(entry: assistant).messageAccessibilityLabel == "Assistant: \(text)")
        #expect(ChatEntryPresentation(entry: user).phaseAccessibilityLabel == nil)
        #expect(ChatEntryPresentation(entry: assistant).phaseAccessibilityLabel == nil)
    }

    @Test("response states identify the speaker and retain failure and delivery uncertainty")
    func spokenResponseStates() {
        var entry = ChatEntry(id: UUID(), author: .assistant, text: "", phase: .sending)
        #expect(ChatEntryPresentation(entry: entry).speaker == "Assistant")
        #expect(ChatEntryPresentation(entry: entry).phaseAccessibilityLabel == "Assistant: Waiting for the destination.")
        entry.phase = .failed("Synthetic endpoint unavailable.")
        #expect(ChatEntryPresentation(entry: entry).phaseAccessibilityLabel == "Assistant: Synthetic endpoint unavailable.")
        entry.phase = .cancelled
        #expect(ChatEntryPresentation(entry: entry).phaseAccessibilityLabel == "Assistant: Cancelled — the request may already have been delivered on this route.")
    }

    @Test("friendly model labels retain canonical identity even when aliases collide")
    func canonicalModelIdentity() {
        let first = ChatModelPresentation(id: "vendor-one/qwen3.8-27b")
        let second = ChatModelPresentation(id: "vendor-two/qwen3.8-27b")
        #expect(first.displayName == "Qwen 3.8 · 27B")
        #expect(second.displayName == first.displayName)
        #expect(first.id != second.id)
        #expect(first.accessibilityLabel != second.accessibilityLabel)
        #expect(first.accessibilityLabel.contains(first.id))
        #expect(second.accessibilityLabel.contains(second.id))
        let known = ChatModelPresentation(id: "gpt-oss-20b")
        #expect(known.displayName == "GPT-OSS · 20B")
        #expect(known.accessibilityLabel.contains("gpt-oss-20b"))
        let variant = ChatModelPresentation(id: "vendor/qwen3.8-27b-special-variant")
        #expect(variant.displayName.contains("special variant"))
        #expect(variant.accessibilityLabel.contains(variant.id))
    }

    @Test("a late route choice cannot replace a sending conversation until explicit cancellation", arguments: ChatRoute.allCases)
    func newChatRequiresCancellation(route: ChatRoute) async throws {
        let local = FakeChatRouteClient()
        let store = ChatStore(localClient: local, networkClient: FakeChatRouteClient(),
            balanceClient: FakeBalanceClient(), pricingClient: FakePricingClient(),
            keyStore: FakeConsumerKeyStore(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        #expect(ChatNewConversationPolicy.start(route: .local, using: store))
        let deadline = Date().addingTimeInterval(20)
        while !store.canSend, Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        try #require(store.canSend)
        let conversationID = try #require(store.conversation?.id)
        #expect(store.send("Queued synthetic turn."))
        defer { store.cancelSend() }
        // No actor yield: this also protects a send that is queued but has not
        // reached even the inert completion client yet.
        #expect(!ChatNewConversationPolicy.start(route: route, using: store))
        #expect(store.conversation?.id == conversationID)
        #expect(store.isSending)
        #expect(store.conversation?.entries.last?.phase == .sending)
        #expect(local.completeCalls.isEmpty)
        store.cancelSend()
        #expect(store.conversation?.entries.last?.phase == .cancelled)
        #expect(store.notice?.contains("may already have been delivered") == true)
        #expect(ChatNewConversationPolicy.start(route: route, using: store))
        #expect(store.conversation?.id != conversationID)
        #expect(store.conversation?.route == route)
        #expect(store.conversation?.entries.isEmpty == true)
    }
}
