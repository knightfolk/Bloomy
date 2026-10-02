import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Provider extras polling", .serialized)
@MainActor
struct ProviderExtrasPollingTests {
    @Test("background fan checks preserve static settings until periodic verification")
    func backgroundCadence() async {
        let clock = ExtrasPollingClock()
        let client = ExtrasPollingClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refreshBackground()
        let initial = store.snapshot
        for tick in 1...9 {
            clock.advance(to: TimeInterval(tick * 30))
            await store.refreshBackground()
        }
        #expect(await client.fullReads == 1)
        #expect(await client.fanReads == 9)
        #expect(store.snapshot?.idlePolicy == initial?.idlePolicy)
        #expect(store.snapshot?.capturedAt == initial?.capturedAt)
        #expect(store.snapshot?.fanStatus != initial?.fanStatus)
        clock.advance(to: 300)
        await store.refreshBackground()
        #expect(await client.fullReads == 2)
        #expect(await client.fanReads == 9)
        await store.stop()
    }

    @Test("explicit refresh always checks static sources and restarts verification age")
    func explicitRefresh() async throws {
        let clock = ExtrasPollingClock()
        let client = ExtrasPollingClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refreshBackground()
        clock.advance(to: 100)
        await store.refresh()
        #expect(await client.fullReads == 2)
        #expect(store.snapshot?.capturedAt == clock.now())
        clock.advance(to: 300)
        await store.refreshBackground()
        #expect(await client.fullReads == 2)
        #expect(await client.fanReads == 1)
        try await store.setBeta(id: "fixture", enabled: true)
        #expect(await client.mutations == 1)
        #expect(await client.fullReads == 3)
        await store.stop()
    }

    @Test("failed static reads retry and preserve their last good timestamps", arguments: ["idle", "beta", "auto"])
    func failedStaticRetry(source: String) async {
        let clock = ExtrasPollingClock()
        let client = ExtrasPollingClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refresh()
        let initial = store.snapshot
        await client.setFailure(source)
        clock.advance(to: 300)
        await store.refreshBackground()
        switch source {
        case "idle": #expect(staleTimestamp(store.snapshot?.idlePolicy) == initial?.capturedAt)
        case "beta": #expect(staleTimestamp(store.snapshot?.betaFeatures) == initial?.capturedAt)
        default: #expect(staleTimestamp(store.snapshot?.autoUpdateStatus) == initial?.capturedAt)
        }
        await client.setFailure(nil)
        clock.advance(to: 330)
        await store.refreshBackground()
        #expect(await client.fullReads == 3)
        #expect(store.snapshot?.capturedAt == clock.now())
        await store.stop()
    }

    @Test("visible surfaces share one cadence and the last cancellation stops reads")
    func sharedVisibleCadence() async throws {
        let clock = ExtrasPollingClock()
        let client = ExtrasPollingClient(clock: clock)
        let store = ProviderExtrasStore(
            client: client, visibleFanPollingInterval: .milliseconds(120), now: clock.now
        )
        await store.refresh()
        let first = Task { await store.observeVisibleFan() }
        defer { first.cancel() }
        try await waitForFanReads(1, client: client)
        let second = Task { await store.observeVisibleFan() }
        defer { second.cancel() }
        try await Task.sleep(for: .milliseconds(30))
        #expect(await client.fanReads == 1)
        // The background cadence uses the active visible poller, too.
        await store.refreshBackground()
        #expect(await client.fanReads == 1)
        try await waitForFanReads(2, client: client)
        #expect(await client.fanReads == 2)
        first.cancel()
        await first.value
        try await waitForFanReads(3, client: client)
        #expect(await client.fanReads == 3)
        second.cancel()
        await second.value
        let finalReads = await client.fanReads
        try await Task.sleep(for: .milliseconds(260))
        #expect(await client.fanReads == finalReads)
        // Explicit refresh still works with no visible subscriber.
        await store.refreshFan()
        #expect(await client.fanReads == finalReads + 1)
        await store.stop()
    }

    private func staleTimestamp<Value>(_ source: SourceAvailability<Value>?) -> Date? where Value: Equatable & Sendable {
        guard case .stale(_, let date, _) = source else { return nil }
        return date
    }

    @Test("full manual refresh follows a fan-only read already in flight")
    func fullRefreshAfterFanRead() async throws {
        let clock = ExtrasPollingClock()
        let client = ExtrasPollingClient(clock: clock)
        let store = ProviderExtrasStore(client: client, now: clock.now)
        await store.refresh()
        await client.blockNextFanRead()
        let fan = Task { await store.refreshFan() }
        try await waitForFanReads(1, client: client)
        let full = Task { await store.refresh() }
        // Let the full request join the in-flight fan read.
        try await Task.sleep(for: .milliseconds(20))
        #expect(await client.fullReads == 1)
        clock.advance(to: 30)
        await client.releaseFanRead()
        await fan.value
        await full.value
        #expect(await client.fullReads == 2)
        #expect(store.snapshot?.capturedAt == clock.now())
        await store.stop()
    }

    private func waitForFanReads(_ count: Int, client: ExtrasPollingClient) async throws {
        for _ in 0..<200 {
            if await client.fanReads >= count { return }
            try await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Expected fan cadence did not run")
    }
}

private final class ExtrasPollingClock: @unchecked Sendable {
    private let lock = NSLock()
    private var elapsed: TimeInterval = 0
    func advance(to elapsed: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        self.elapsed = elapsed
    }
    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return Date(timeIntervalSince1970: 1_000 + elapsed)
    }
}

private actor ExtrasPollingClient: ProviderExtrasProviding {
    let clock: ExtrasPollingClock
    private var failure: String?
    private var shouldBlockFan = false
    private var fanContinuation: CheckedContinuation<Void, Never>?
    private(set) var fullReads = 0
    private(set) var fanReads = 0
    private(set) var mutations = 0
    init(clock: ExtrasPollingClock) { self.clock = clock }
    func setFailure(_ failure: String?) { self.failure = failure }
    func blockNextFanRead() { shouldBlockFan = true }
    func releaseFanRead() {
        fanContinuation?.resume()
        fanContinuation = nil
    }
    func refresh() async -> ProviderExtrasSnapshot {
        fullReads += 1
        let date = clock.now()
        return ProviderExtrasSnapshot(
            capturedAt: date,
            idlePolicy: failure == "idle" ? .unavailable(reason: "fixture") : .available(
                value: ProviderIdlePolicy(idleTimeoutMinutes: 0, policy: "always_ready", summary: "fixture", pinned: true),
                capturedAt: date
            ),
            betaFeatures: failure == "beta" ? .unavailable(reason: "fixture") : .available(value: [], capturedAt: date),
            fanStatus: fanStatus(),
            autoUpdateStatus: failure == "auto" ? .unavailable(reason: "fixture") : .available(value: ProviderAutoUpdateStatus(enabled: true), capturedAt: date)
        )
    }
    func refreshFan() async -> SourceAvailability<ProviderFanStatus> {
        fanReads += 1
        if shouldBlockFan {
            shouldBlockFan = false
            await withCheckedContinuation { fanContinuation = $0 }
        }
        return fanStatus()
    }
    private func fanStatus() -> SourceAvailability<ProviderFanStatus> {
        .available(value: ProviderFanStatus(
            capability: ProviderFanStatus.controlCapability,
            installed: false, loaded: false, helper: nil,
            diagnostic: ProviderFanDiagnostic(chip: "fixture", supported: true, gpuTemperatures: [], fans: []),
            helperErrorPresent: false, diagnosticErrorPresent: false
        ), capturedAt: clock.now())
    }
    func saveIdle(minutes: Int) async throws { mutations += 1 }
    func setBeta(id: String, enabled: Bool) async throws { mutations += 1 }
}
