import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Shared readiness observation efficiency")
@MainActor
struct MonitorStoreReadinessTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let identity = ProcessIdentity(pid: 42, startTimeMicros: 900_000_000)

    @Test("screen redraws reuse identity but clock expiry still invalidates readiness")
    func redrawAndExpiry() async {
        let reader = ReadinessIdentityReader(identity)
        let store = makeStore(snapshot(), reader: reader)
        for _ in 0..<100 {
            #expect(store.providerReadiness(at: now).state == .ready)
        }
        #expect(reader.count == 1)
        #expect(store.providerReadiness(at: now.addingTimeInterval(11)).state == .stale)
        #expect(reader.count == 1)
        await store.stop()
    }

    @Test("non-daemon publications reuse identity and a new daemon observation rechecks it")
    func publicationBoundaries() async {
        let reader = ReadinessIdentityReader(identity)
        let sample = snapshot()
        let store = makeStore(sample, reader: reader)
        #expect(store.providerReadiness(at: now).state == .ready)
        let unrelated = replacing(sample, capturedAt: now.addingTimeInterval(1))
        await store.accept(unrelated)
        #expect(store.providerReadiness(at: now.addingTimeInterval(1)).state == .ready)
        #expect(reader.count == 1)
        let newDate = now.addingTimeInterval(2)
        reader.set(nil)
        await store.accept(snapshot(at: newDate))
        #expect(store.providerReadiness(at: newDate).state == .unconfirmed)
        #expect(reader.count == 2)
        reader.set(identity)
        // Changing the reader alone cannot revise an already-observed process.
        #expect(store.providerReadiness(at: newDate).state == .unconfirmed)
        #expect(reader.count == 2)
        await store.accept(snapshot(at: now.addingTimeInterval(3)))
        #expect(store.providerReadiness(at: now.addingTimeInterval(3)).state == .ready)
        #expect(reader.count == 3)
        await store.stop()
    }

    @Test("unavailable and stale sources discard cached identity without probing")
    func unavailableSources() async {
        let reader = ReadinessIdentityReader(identity)
        let sample = snapshot()
        let store = makeStore(sample, reader: reader)
        #expect(store.providerReadiness(at: now).state == .ready)
        let stale = replacing(sample, state: .stale(value: sample.state.value!, capturedAt: now, reason: "Fixture retained data"))
        await store.accept(stale)
        #expect(store.providerReadiness(at: now).state == .stale)
        await store.accept(.unavailable(now: now))
        #expect(store.providerReadiness(at: now).state == .unavailable)
        #expect(reader.count == 1)
        await store.accept(sample)
        #expect(store.providerReadiness(at: now).state == .ready)
        #expect(reader.count == 2)
        await store.stop()
    }

    @Test("explicit missing identity never falls back to a real kernel process")
    func noFallback() async throws {
        let live = try #require(ProcessIdentity.current())
        let reader = ReadinessIdentityReader(nil)
        let store = makeStore(snapshot(identity: live), reader: reader)
        #expect(store.providerReadiness(at: now).state == .unconfirmed)
        #expect(reader.count == 1)
        await store.stop()
    }

    private func replacing(_ sample: TelemetrySnapshot, state: SourceAvailability<DaemonState>? = nil,
                           capturedAt: Date? = nil) -> TelemetrySnapshot {
        TelemetrySnapshot(state: state ?? sample.state, loadedModels: sample.loadedModels,
            status: sample.status, eventFeed: sample.eventFeed, tokenRate: sample.tokenRate,
            diagnostics: sample.diagnostics, capturedAt: capturedAt ?? sample.capturedAt,
            menuStatus: sample.menuStatus)
    }

    private func makeStore(_ initial: TelemetrySnapshot, reader: ReadinessIdentityReader) -> MonitorStore {
        MonitorStore(service: TelemetryService(source: ReadinessUnusedSource()), initial: initial,
                     earningsClient: ReadinessUnusedEarnings(), now: { Date(timeIntervalSince1970: 1_000) },
                     gpuUsage: SystemGPUUsageStore(read: { nil }),
                     readinessProcessIdentityReader: { reader.read($0) })
    }

    private func snapshot(at date: Date? = nil, identity suppliedIdentity: ProcessIdentity? = nil) -> TelemetrySnapshot {
        let date = date ?? now
        let process = suppliedIdentity ?? identity
        let state = DaemonState(schema: 1, version: "fixture", currentModel: "gemma", warmModels: ["gemma"],
            stats: .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: .init(level: "hardware", status: "online", reason: "fixture", receivedAt: date.timeIntervalSince1970),
            capacity: nil, slots: [], inferenceActive: false, startedAt: 900,
            writtenAt: date.timeIntervalSince1970, pid: process.pid, processIdentity: process,
            advertisedModels: ["gemma"], coordinatorURL: "wss://coordinator.example/ws/provider")
        var status = StatusSnapshot()
        status.coordinator = "https://coordinator.example"
        return TelemetrySnapshot(state: .available(value: state, capturedAt: date),
            loadedModels: .unavailable(reason: "fixture"), status: .available(value: status, capturedAt: date),
            eventFeed: .unavailable(reason: "fixture"), tokenRate: .unavailable(reason: "fixture"),
            diagnostics: [], capturedAt: date, menuStatus: .online)
    }
}

private final class ReadinessIdentityReader: @unchecked Sendable {
    private let lock = NSLock()
    private var identity: ProcessIdentity?
    private var reads = 0
    init(_ identity: ProcessIdentity?) { self.identity = identity }
    var count: Int { lock.withLock { reads } }
    func set(_ value: ProcessIdentity?) { lock.withLock { identity = value } }
    func read(_ pid: Int32) -> ProcessIdentity? {
        lock.withLock { reads += 1; return identity?.pid == pid ? identity : nil }
    }
}
private struct ReadinessUnusedSource: TelemetrySource {
    struct Unused: Error {}
    func readDaemonState() async throws -> DaemonState { throw Unused() }
    func readLoadedModels() async throws -> LoadedModelsState { throw Unused() }
    func readStatus() async throws -> StatusSnapshot { throw Unused() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}
private struct ReadinessUnusedEarnings: AccountEarningsFetching {
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "fixture") }
}
