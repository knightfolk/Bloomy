import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

/// These lookups deliberately suspend on a background thread. No Keychain,
/// credential, provider, or network access is involved.
@Suite("Nonblocking saved-key status")
@MainActor
struct KeyPresenceStartupTests {
    @Test("startup and repeated UI gates stay responsive while lookup is pending",
          arguments: KeyConsumerKind.allCases)
    func pendingLookup(kind: KeyConsumerKind) async {
        let key = SuspendedPresenceKey(result: .configured)
        defer { key.releaseFirstLookup() }
        let harness = makeHarness(kind: kind, key: key)
        let startup = Task { await harness.refresh() }
        await waitUntil { key.lookupCount == 1 }

        #expect(harness.presence == nil)
        #expect(harness.notice == "Checking saved key…")
        if case .nudge(let store) = harness {
            store.setEnabled(true)
            #expect(store.status == "Checking saved key…")
        }
        for _ in 0..<20 {
            #expect(!harness.canAct)
            #expect(harness.presence == nil)
        }
        #expect(key.lookupCount == 1)
        #expect(key.secretReadCount == 0)

        key.releaseFirstLookup()
        await startup.value
        #expect(harness.presence == .configured)
        #expect(harness.notice == nil)
        #expect(key.secretReadCount == 0)
    }

    @Test("successful save wins over an older missing-key lookup",
          arguments: KeyConsumerKind.allCases)
    func saveRejectsStaleLookup(kind: KeyConsumerKind) async {
        let key = SuspendedPresenceKey(result: .missing)
        defer { key.releaseFirstLookup() }
        let harness = makeHarness(kind: kind, key: key)
        let startup = Task { await harness.refresh() }
        await waitUntil { key.lookupCount == 1 }

        #expect(harness.save("synthetic-status-only") == nil)
        #expect(harness.presence == .configured)
        #expect(key.lookupCount == 1)
        key.releaseFirstLookup()
        await startup.value
        #expect(harness.presence == .configured)
        #expect(harness.notice == nil)
        #expect(key.secretReadCount == 0)
    }

    @Test("removal verification wins over an older configured-key lookup",
          arguments: KeyConsumerKind.allCases)
    func removalRejectsStaleLookup(kind: KeyConsumerKind) async {
        let key = SuspendedPresenceKey(result: .configured)
        defer { key.releaseFirstLookup() }
        let harness = makeHarness(kind: kind, key: key)
        let startup = Task { await harness.refresh() }
        await waitUntil { key.lookupCount == 1 }

        harness.remove()
        #expect(harness.presence == nil)
        #expect(!harness.canAct)
        await harness.refresh()
        #expect(harness.presence == .missing)
        key.releaseFirstLookup()
        await startup.value
        #expect(harness.presence == .missing)
        #expect(harness.notice == nil)
        #expect(key.secretReadCount == 0)
    }

    @Test("unavailable status stays distinct from setup and can be retried",
          arguments: KeyConsumerKind.allCases)
    func unavailableRetry(kind: KeyConsumerKind) async {
        let key = SuspendedPresenceKey(result: .unavailable, suspendFirst: false)
        let harness = makeHarness(kind: kind, key: key)
        await harness.refresh()
        #expect(harness.presence == .unavailable)
        #expect(harness.notice == "Keychain status is unavailable. Try again.")
        #expect(!harness.canAct)
        if case .nudge(let store) = harness {
            store.setEnabled(true)
            #expect(store.status == "Keychain status is unavailable. Try again.")
            store.setEnabled(false)
        }
        key.setResult(.configured)
        await harness.refresh()
        #expect(harness.presence == .configured)
        #expect(harness.notice == nil)
        #expect(key.secretReadCount == 0)
    }

    @Test("failed pre-send metadata check blocks Chat without claiming a missing key")
    func chatPreflightUnavailable() async {
        let key = SuspendedPresenceKey(result: .configured, suspendFirst: false)
        let harness = makeHarness(kind: .chat, key: key)
        await harness.refresh()
        guard case .chat(let store) = harness else { return }
        store.startConversation(route: .network)
        store.acknowledgePaidRoute()
        await waitUntil { store.canSend }
        key.setResult(.unavailable)
        #expect(store.send("synthetic preflight") == true)
        await waitUntil { store.conversation?.entries.last?.phase.isFailure == true }
        #expect(store.keyPresence == .unavailable)
        #expect(store.notice == "Keychain status could not be checked, so the send was stopped. Check key access in Chat settings.")
        #expect(key.secretReadCount == 0)
    }

    private func makeHarness(kind: KeyConsumerKind, key: SuspendedPresenceKey) -> KeyConsumerHarness {
        switch kind {
        case .chat:
            return .chat(ChatStore(localClient: FakeChatRouteClient(), networkClient: FakeChatRouteClient(),
                balanceClient: FakeBalanceClient(), pricingClient: FakePricingClient(), keyStore: key,
                now: { Date(timeIntervalSince1970: 1_800_000_000) }))
        case .nudge:
            // Volatile preferences avoid the user's opt-in or attempt ledger.
            let defaults = UserDefaults(suiteName: "KeyPresenceStartup-\(UUID().uuidString)")!
            return .nudge(InactivityNudgeStore(keyStore: key, defaults: defaults,
                evidence: { _ in .unavailable }, canAct: { false }, send: { _, _ in nil }))
        }
    }

    private func waitUntil(_ predicate: () -> Bool) async {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        Issue.record("Background presence lookup did not start.")
    }
}

enum KeyConsumerKind: CaseIterable, Sendable { case chat, nudge }

@MainActor
private enum KeyConsumerHarness {
    case chat(ChatStore)
    case nudge(InactivityNudgeStore)

    var presence: ConsumerKeyPresence? {
        switch self {
        case .chat(let store): store.keyPresence
        case .nudge(let store): store.keyPresence
        }
    }
    var notice: String? {
        switch self {
        case .chat(let store): store.keyStatusNotice
        case .nudge(let store): store.keyStatusNotice
        }
    }
    var canAct: Bool {
        switch self {
        case .chat(let store): store.canSend
        case .nudge(let store): store.manualUnavailableReason == nil
        }
    }
    func refresh() async {
        switch self {
        case .chat(let store): await store.refreshKeyStatus()
        case .nudge(let store): await store.refreshKeyStatus()
        }
    }
    func save(_ value: String) -> String? {
        switch self {
        case .chat(let store): store.storeConsumerKey(value)
        case .nudge(let store): store.saveKey(value)
        }
    }
    func remove() {
        switch self {
        case .chat(let store): store.removeConsumerKey()
        case .nudge(let store): store.removeKey()
        }
    }
}

private final class SuspendedPresenceKey: ConsumerKeyManaging, @unchecked Sendable {
    private let condition = NSCondition()
    private var result: ConsumerKeyPresence
    private var released: Bool
    private var lookups = 0
    private var secretReads = 0

    init(result: ConsumerKeyPresence, suspendFirst: Bool = true) {
        self.result = result
        released = !suspendFirst
    }
    var lookupCount: Int {
        condition.lock(); defer { condition.unlock() }
        return lookups
    }
    var secretReadCount: Int {
        condition.lock(); defer { condition.unlock() }
        return secretReads
    }
    var hasKey: Bool {
        Issue.record("UI status must use presence metadata, not validated secret access.")
        return false
    }
    func keyPresence() -> ConsumerKeyPresence {
        condition.lock(); defer { condition.unlock() }
        lookups += 1
        let captured = result
        if lookups == 1 {
            let deadline = Date().addingTimeInterval(20)
            while !released {
                if !condition.wait(until: deadline) {
                    Issue.record("Presence lookup was not released; startup may be blocking the main actor.")
                    break
                }
            }
        }
        return captured
    }
    func releaseFirstLookup() {
        condition.lock()
        released = true
        condition.broadcast()
        condition.unlock()
    }
    func setResult(_ value: ConsumerKeyPresence) {
        condition.lock()
        result = value
        condition.unlock()
    }
    func store(_ key: String) throws { setResult(.configured) }
    func remove() { setResult(.missing) }
    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? {
        condition.lock()
        secretReads += 1
        condition.unlock()
        Issue.record("Configuration checks must not read secret data.")
        return nil
    }
}
