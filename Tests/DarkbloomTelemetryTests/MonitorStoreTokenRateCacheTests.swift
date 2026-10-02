import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Accepted telemetry token-rate query efficiency")
@MainActor
struct MonitorStoreTokenRateCacheTests {
    private let base = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 2_000_000)).addingTimeInterval(3600)

    @Test("one hour of duplicate snapshots queries once and keeps the observed daily average current")
    func duplicateLifecycle() async {
        let recorder = CountedTokenRateRecorder()
        let store = makeStore(recorder)
        var accepted = 0
        for second in 0..<3600 {
            let date = base.addingTimeInterval(Double(second))
            let snapshot = sample(at: date, writtenAt: base.timeIntervalSince1970)
            let ticks = (second.isMultiple(of: 2) ? 2 : 0)
                + (second.isMultiple(of: 5) ? 1 : 0)
                + (second.isMultiple(of: 30) ? 1 : 0)
            for _ in 0..<ticks { await store.accept(snapshot); accepted += 1 }
        }
        #expect(accepted == 4440)
        #expect(await recorder.counts == [1, 1])
        #expect(store.modelTokenRateAverages.first?.sampleCount == 1)
        #expect(CalendarTokenRates.current(store.modelTokenRateAverages, at: base.addingTimeInterval(3598), calendar: .current).first?.tokensPerSecond == 20)
        #expect(store.snapshot.capturedAt == base.addingTimeInterval(3598))
        #expect(store.averageTokenRate == .available(tokensPerSecond: 20, label: "today's average"))
    }

    @Test("active source advances query once per new sample across all accepted source ticks")
    func activeLifecycle() async {
        let recorder = CountedTokenRateRecorder()
        let store = makeStore(recorder)
        var accepted = 0
        for second in 0..<3600 {
            let snapshot = sample(at: base.addingTimeInterval(Double(second)),
                                  writtenAt: base.timeIntervalSince1970 + Double(second / 2 * 2))
            let ticks = (second.isMultiple(of: 2) ? 2 : 0)
                + (second.isMultiple(of: 5) ? 1 : 0)
                + (second.isMultiple(of: 30) ? 1 : 0)
            for _ in 0..<ticks { await store.accept(snapshot); accepted += 1 }
        }
        #expect(accepted == 4440)
        #expect(await recorder.counts == [1800, 1800])
        #expect(store.modelTokenRateAverages.first?.sampleCount == 1800)
    }

    @Test("a revised derived rate retries recording without counting an already persisted observation")
    func revisedRateAndProviderRestart() async {
        let recorder = CountedTokenRateRecorder()
        let store = makeStore(recorder)
        await store.accept(sample(at: base, rate: nil))
        #expect(await recorder.counts == [0, 1])
        await store.accept(sample(at: base, rate: 20))
        await store.accept(sample(at: base, rate: 40))
        #expect(await recorder.counts == [2, 2])
        #expect(store.modelTokenRateAverages.first?.tokensPerSecond == 20)
        await store.accept(sample(at: base, rate: 40, startTimeMicros: 2))
        #expect(await recorder.counts == [3, 3])
        #expect(store.modelTokenRateAverages.first?.tokensPerSecond == 30)
        #expect(store.modelTokenRateAverages.first?.sampleCount == 2)
    }

    @Test("relaunch reads persisted values and day rollover clears them even without daemon state")
    func appRestartAndDayRollover() async {
        let recorder = CountedTokenRateRecorder()
        let first = makeStore(recorder)
        await first.accept(sample(at: base))
        let restarted = makeStore(recorder)
        await restarted.accept(sample(at: base))
        #expect(await recorder.counts == [2, 2])
        #expect(restarted.modelTokenRateAverages.first?.sampleCount == 1)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: base)!
        await restarted.accept(.unavailable(now: tomorrow))
        #expect(await recorder.counts == [2, 3])
        #expect(restarted.modelTokenRateAverages.isEmpty)
        #expect(restarted.averageTokenRate == .unavailable(reason: "No measured token rates today"))
        await restarted.accept(sample(at: tomorrow))
        #expect(await recorder.counts == [2, 3])
        #expect(restarted.modelTokenRateAverages.isEmpty)
    }

    @Test("failed writes and failed aggregates retry on identical telemetry")
    func failureRetry() async {
        let recorder = CountedTokenRateRecorder()
        let store = makeStore(recorder)
        await recorder.failNextWrite()
        await store.accept(sample(at: base))
        #expect(await recorder.counts == [1, 1])
        #expect(store.modelTokenRateAverages.isEmpty)
        await recorder.failNextQuery()
        await store.accept(sample(at: base))
        #expect(await recorder.counts == [2, 2])
        #expect(store.modelTokenRateAverages.isEmpty)
        await store.accept(sample(at: base))
        #expect(await recorder.counts == [2, 3])
        #expect(store.modelTokenRateAverages.first?.sampleCount == 1)
        await store.accept(sample(at: base))
        #expect(await recorder.counts == [2, 3])
    }

    @Test("a failed aggregate does not extend the freshness of the last successful measurements")
    func failedRefreshPreservesOldPeriod() async {
        let recorder = CountedTokenRateRecorder()
        let store = makeStore(recorder)
        await store.accept(sample(at: base))
        await recorder.failNextQuery()
        let later = base.addingTimeInterval(601)
        let updated = sample(at: later, writtenAt: later.timeIntervalSince1970, rate: 40)
        await store.accept(updated)
        #expect(store.modelTokenRateAverages.first?.tokensPerSecond == 20)
        #expect(store.modelTokenRateAverages.first?.queryPeriod?.end == base)
        #expect(CalendarTokenRates.current(store.modelTokenRateAverages, at: later, calendar: .current).isEmpty)
        await store.accept(updated)
        #expect(await recorder.counts == [2, 3])
        #expect(store.modelTokenRateAverages.first?.tokensPerSecond == 30)
        #expect(store.modelTokenRateAverages.first?.queryPeriod?.end == later)
    }

    private func makeStore(_ recorder: CountedTokenRateRecorder) -> MonitorStore {
        MonitorStore(service: TelemetryService(source: CacheUnusedTelemetrySource()),
                     initial: .unavailable(now: base), earningsClient: CacheUnusedEarningsClient(),
                     tokenRateRecorder: recorder, now: { Date(timeIntervalSince1970: 2_000_000) })
    }

    private func sample(at date: Date, writtenAt: TimeInterval? = nil, rate: Double? = 20,
                        startTimeMicros: Int64 = 1) -> TelemetrySnapshot {
        let state = DaemonState(schema: 1, version: "fixture", currentModel: "gemma", warmModels: [],
                                stats: .init(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
                                trust: nil, capacity: nil, slots: [], inferenceActive: true,
                                startedAt: 0, writtenAt: writtenAt ?? base.timeIntervalSince1970, pid: 42,
                                processIdentity: .init(pid: 42, startTimeMicros: startTimeMicros))
        return TelemetrySnapshot(state: .available(value: state, capturedAt: date),
                                 loadedModels: .unavailable(reason: "fixture"), status: .unavailable(reason: "fixture"),
                                 eventFeed: .unavailable(reason: "fixture"),
                                 tokenRate: rate.map { .available(tokensPerSecond: $0, label: "fixture") }
                                    ?? .unavailable(reason: "warming"),
                                 diagnostics: [], capturedAt: date, menuStatus: .online)
    }
}

private actor CountedTokenRateRecorder: ModelTokenRateRecording {
    private struct Row {
        let model: String
        let rate: Double
        let date: Date
        let identity: ProcessIdentity
        let writtenAt: TimeInterval
    }
    private var rows: [Row] = []
    private var writes = 0
    private var queries = 0
    private var failWrite = false
    private var failQuery = false
    var counts: [Int] { [writes, queries] }
    func failNextWrite() { failWrite = true }
    func failNextQuery() { failQuery = true }
    func record(model: String, tokensPerSecond: Double, capturedAt: Date,
                processIdentity: ProcessIdentity, writtenAt: TimeInterval) throws {
        _ = try recordIfNew(model: model, tokensPerSecond: tokensPerSecond, capturedAt: capturedAt,
                            processIdentity: processIdentity, writtenAt: writtenAt)
    }
    func recordIfNew(model: String, tokensPerSecond: Double, capturedAt: Date,
                     processIdentity: ProcessIdentity, writtenAt: TimeInterval) throws -> Bool {
        writes += 1
        if failWrite { failWrite = false; throw CacheFixtureFailure() }
        guard !rows.contains(where: { $0.identity == processIdentity && $0.writtenAt == writtenAt }) else { return false }
        rows.append(Row(model: model, rate: tokensPerSecond, date: capturedAt,
                        identity: processIdentity, writtenAt: writtenAt))
        return true
    }
    func averages(from start: Date, through end: Date) throws -> [ModelTokenRateAverage] {
        queries += 1
        if failQuery { failQuery = false; throw CacheFixtureFailure() }
        let valid = rows.filter { (start...end).contains($0.date) }
        return Dictionary(grouping: valid, by: \.model).map { model, values in
            ModelTokenRateAverage(model: model, tokensPerSecond: values.reduce(0) { $0 + $1.rate } / Double(values.count),
                                  sampleCount: values.count, queryPeriod: .init(start: start, end: end))
        }.sorted { $0.model < $1.model }
    }
}
private struct CacheFixtureFailure: Error {}
private struct CacheUnusedTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw CacheFixtureFailure() }
    func readLoadedModels() async throws -> LoadedModelsState { throw CacheFixtureFailure() }
    func readStatus() async throws -> StatusSnapshot { throw CacheFixtureFailure() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}
private struct CacheUnusedEarningsClient: AccountEarningsFetching {
    func fetch(now: Date) async throws -> EarningsPresentationValue { .unavailable(reason: "fixture") }
}
