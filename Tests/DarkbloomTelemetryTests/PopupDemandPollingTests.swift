import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Popup model demand polling", .serialized)
@MainActor
struct PopupDemandPollingTests {
    @Test("fresh popup open shortens hidden sleep without fetching; owners share one loop")
    func freshOpenAndOwners() async throws {
        let clock = PopupDemandClock()
        let sleeper = PopupDemandSleeper()
        let client = PopupDemandClient()
        let store = makeStore(clock: clock, sleeper: sleeper, client: client)
        let first = UUID(), second = UUID()
        do {
            store.start()
            try await expectDelay(300, request: 1, sleeper: sleeper)
            #expect(await client.calls == 1)
            clock.advance(10)
            store.setModelControlsVisible(true, owner: first)
            try await expectDelay(60, request: 2, sleeper: sleeper)
            #expect(await client.calls == 1)
            #expect(!store.dashboardVisible)
            store.setModelControlsVisible(true, owner: second)
            store.setModelControlsVisible(false, owner: first)
            #expect(await sleeper.requestCount == 2)
            #expect(await sleeper.pendingCount == 1)
            store.setModelControlsVisible(false, owner: second)
            try await expectDelay(300, request: 3, sleeper: sleeper)
            #expect(await client.calls == 1)
            #expect(await sleeper.pendingCount == 1)
            store.setDashboardVisible(true)
            try await expectDelay(60, request: 4, sleeper: sleeper)
            store.setModelControlsVisible(true, owner: first)
            store.setDashboardVisible(false)
            #expect(await sleeper.requestCount == 4)
            store.setModelControlsVisible(false, owner: first)
            try await expectDelay(300, request: 5, sleeper: sleeper)
            await store.stop()
            #expect(await sleeper.pendingCount == 0)
            #expect(await sleeper.cancellations == 5)
            store.setModelControlsVisible(true, owner: second)
            #expect(await sleeper.requestCount == 5)
            #expect(await client.calls == 1)
        } catch {
            await store.stop()
            throw error
        }
    }

    @Test("stale popup open wakes the existing demand loop immediately")
    func staleOpen() async throws {
        let clock = PopupDemandClock()
        let sleeper = PopupDemandSleeper()
        let client = PopupDemandClient()
        let store = makeStore(clock: clock, sleeper: sleeper, client: client)
        let owner = UUID()
        do {
            store.start()
            try await expectDelay(300, request: 1, sleeper: sleeper)
            clock.advance(NetworkCapacitySnapshot.maximumAge + 1)
            store.setModelControlsVisible(true, owner: owner)
            try await expectDelay(60, request: 2, sleeper: sleeper)
            #expect(await client.calls == 2)
            #expect(await sleeper.cancellations == 1)
            #expect(await sleeper.pendingCount == 1)
            #expect(store.networkCapacity.value?.isFresh(at: clock.now()) == true)
            clock.advance(60)
            await sleeper.wake()
            try await expectDelay(60, request: 3, sleeper: sleeper)
            #expect(await client.calls == 3)
            store.setModelControlsVisible(false, owner: owner)
            try await expectDelay(300, request: 4, sleeper: sleeper)
            await store.stop()
            #expect(await sleeper.pendingCount == 0)
        } catch {
            await store.stop()
            throw error
        }
    }

    @Test("closing and reopening panels cannot bypass a failed demand retry")
    func failureBackoffSurvivesReopen() async throws {
        let clock = PopupDemandClock()
        let sleeper = PopupDemandSleeper()
        let client = PopupDemandClient(failingCalls: [2])
        let store = makeStore(clock: clock, sleeper: sleeper, client: client)
        let first = UUID(), second = UUID()
        do {
            store.setModelControlsVisible(true, owner: first)
            store.start()
            try await expectDelay(60, request: 1, sleeper: sleeper)
            clock.advance(60)
            await sleeper.wake()
            try await expectDelay(120, request: 2, sleeper: sleeper)
            #expect(await client.calls == 2)
            if case .stale = store.networkCapacity {} else { Issue.record("Failed read lost the last demand sample") }
            store.setModelControlsVisible(false, owner: first)
            clock.advance(30)
            store.setModelControlsVisible(true, owner: second)
            store.setModelControlsVisible(false, owner: second)
            store.setDashboardVisible(true)
            store.setDashboardVisible(false)
            #expect(await sleeper.requestCount == 2)
            #expect(await sleeper.cancellations == 0)
            #expect(await client.calls == 2)
            #expect(await sleeper.pendingCount == 1)
            clock.advance(90)
            await sleeper.wake()
            try await expectDelay(300, request: 3, sleeper: sleeper)
            #expect(await client.calls == 3)
            if case .available = store.networkCapacity {} else { Issue.record("Scheduled retry did not recover") }
            await store.stop()
            #expect(await sleeper.pendingCount == 0)
            #expect(await sleeper.cancellations == 1)
        } catch {
            await store.stop()
            throw error
        }
    }

    private func makeStore(clock: PopupDemandClock, sleeper: PopupDemandSleeper,
                           client: PopupDemandClient) -> MonitorStore {
        MonitorStore(service: TelemetryService(source: PopupDemandUnusedSource()),
            initial: .unavailable(now: clock.now()), earningsClient: PopupDemandUnusedEarnings(),
            networkCapacityClient: client, now: { clock.now() },
            publicPollingSleep: { try await sleeper.sleep($0) }, publicPollingJitter: { 0 })
    }

    private func expectDelay(_ expected: TimeInterval, request: Int,
                             sleeper: PopupDemandSleeper) async throws {
        let deadline = Date().addingTimeInterval(10)
        while await sleeper.requestCount < request {
            guard Date() < deadline else { throw PopupDemandTestError.timerMissing }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await sleeper.delay(at: request - 1) == expected)
    }
}

private enum PopupDemandTestError: Error { case timerMissing, unused, failedRead }

private final class PopupDemandClock: @unchecked Sendable {
    private let lock = NSLock()
    private var date = Date(timeIntervalSince1970: 1_788_566_400)
    func now() -> Date { lock.withLock { date } }
    func advance(_ seconds: TimeInterval) { lock.withLock { date.addTimeInterval(seconds) } }
}

private actor PopupDemandSleeper {
    private var delays: [TimeInterval] = []
    private var pending: [UUID: CheckedContinuation<Void, any Error>] = [:]
    private(set) var cancellations = 0
    var requestCount: Int { delays.count }
    var pendingCount: Int { pending.count }
    func delay(at index: Int) -> TimeInterval { delays[index] }

    func sleep(_ seconds: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
                pending[id] = waiter
                delays.append(seconds)
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    func wake() {
        let waiters = Array(pending.values)
        pending.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    private func cancel(_ id: UUID) {
        guard let waiter = pending.removeValue(forKey: id) else { return }
        cancellations += 1
        waiter.resume(throwing: CancellationError())
    }
}

private actor PopupDemandClient: NetworkCapacityFetching {
    private(set) var calls = 0
    private let failingCalls: Set<Int>
    init(failingCalls: Set<Int> = []) { self.failingCalls = failingCalls }
    func fetch(at capturedAt: Date) async throws -> NetworkCapacitySnapshot {
        calls += 1
        if failingCalls.contains(calls) { throw PopupDemandTestError.failedRead }
        return NetworkCapacitySnapshot(models: [], capturedAt: capturedAt)
    }
}

private struct PopupDemandUnusedEarnings: AccountEarningsFetching {
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "unused") }
}

private struct PopupDemandUnusedSource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw PopupDemandTestError.unused }
    func readLoadedModels() async throws -> LoadedModelsState { throw PopupDemandTestError.unused }
    func readStatus() async throws -> StatusSnapshot { throw PopupDemandTestError.unused }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}
