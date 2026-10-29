import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Add-on settings coordination")
@MainActor struct ProviderAddonSettingsTests {
    @Test("requires a fresh check and reflects a confirmed hold and release")
    func confirmedActions() async throws {
        let client = FixtureAddonSettingsClient()
        let store = ProviderExtrasStore(client: client)
        await #expect(throws: ProviderExtrasMutationError.commandFailed) { try await store.changeAddonHold(leaseSeconds: 60) }
        await store.refreshAddon()
        try await store.changeAddonHold(leaseSeconds: 60)
        guard case .available(let held) = store.addonStatus else { Issue.record("Missing hold state"); return }
        #expect(held.operatorHoldPresent && held.hold == .draining)
        try await store.changeAddonHold(force: true)
        guard case .available(let released) = store.addonStatus else { Issue.record("Missing released state"); return }
        #expect(released.hold == .none)
        #expect(await client.forceWasUsed)
    }

    @Test("an uncertain command is never shown as confirmed")
    func uncertain() async {
        let client = FixtureAddonSettingsClient()
        await client.makeNextUncertain()
        let store = ProviderExtrasStore(client: client)
        await store.refreshAddon()
        await #expect(throws: ProviderExtrasMutationError.commandFailed) { try await store.changeAddonHold(leaseSeconds: 60) }
        #expect(store.errorMessage?.contains("could not be confirmed") == true)
        #expect(store.addonCheckedAt == nil)
        guard case .available(let status) = store.addonStatus else { Issue.record("Missing reconciled status"); return }
        #expect(status.operatorHoldPresent)
    }
}

private actor FixtureAddonSettingsClient: ProviderExtrasProviding {
    private var current = ProviderAddonControlSnapshot(hold: .none, machineLockHeld: false, operatorHoldPresent: false)
    private var uncertain = false
    private(set) var forceWasUsed = false
    func makeNextUncertain() { uncertain = true }
    func addonStatus() async -> ProviderAddonControlStatus { .available(current) }
    func holdAddon(leaseSeconds: Int) async -> ProviderAddonMutationResult {
        current = .init(hold: .draining, machineLockHeld: false, operatorHoldPresent: true)
        return uncertain ? .outcomeUncertain(.available(current)) : .confirmed(current)
    }
    func releaseAddon(force: Bool) async -> ProviderAddonMutationResult {
        forceWasUsed = force
        current = .init(hold: .none, machineLockHeld: false, operatorHoldPresent: false)
        return .confirmed(current)
    }
    func refresh() async -> ProviderExtrasSnapshot {
        .init(capturedAt: Date(), idlePolicy: .unavailable(reason: "fixture"),
              betaFeatures: .unavailable(reason: "fixture"), fanStatus: .unavailable(reason: "fixture"))
    }
    func saveIdle(minutes: Int) async throws {}
    func setBeta(id: String, enabled: Bool) async throws {}
}
