import Combine
import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Energy earnings query efficiency")
@MainActor
struct MonitorStoreEnergyEfficiencyTests {
    @Test func disabledEnergySkipsSessionReadsAndUnchangedPublications() async {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let client = CountedEnergyActivityClient()
        let store = MonitorStore(service: TelemetryService(source: EnergyCacheTelemetrySource()),
                                 initial: .unavailable(now: date), earningsClient: client, now: { date })
        var publications = 0
        let subscription = store.$energyEarnings.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        let result = EnergyRecordingSnapshot(reading: nil, intervals: [], issue: nil)
        for offset in 0..<360 {
            await store.updateEnergyEarnings(using: result, enabled: false,
                                            at: date.addingTimeInterval(Double(offset * 10)))
        }
        #expect(await client.sessionReads == 0)
        #expect(await client.activityReads == 0)
        #expect(publications == 0)
        #expect(store.energyEarnings == nil)
    }

    @Test func disablingClearsOnceAndReenablingValidatesTheCurrentAccount() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let day = try #require(Calendar.current.dateInterval(of: .day, for: date))
        let client = CountedEnergyActivityClient()
        let store = MonitorStore(service: TelemetryService(source: EnergyCacheTelemetrySource()),
                                 initial: .unavailable(now: date), earningsClient: client, now: { date })
        let result = EnergyRecordingSnapshot(reading: nil, intervals: intervals(from: day.start, count: 360), issue: nil)
        await store.updateEnergyEarnings(using: result, enabled: true, at: date)
        #expect(store.energyEarnings?.earningsUSD == 1)
        let readsBeforeDisabling = await client.sessionReads
        var publications = 0
        let subscription = store.$energyEarnings.dropFirst().sink { _ in publications += 1 }
        defer { subscription.cancel() }
        for _ in 0..<360 {
            await store.updateEnergyEarnings(using: result, enabled: false, at: date)
        }
        #expect(await client.sessionReads == readsBeforeDisabling)
        #expect(publications == 1)
        #expect(store.energyEarnings == nil)
        await client.changeAccount()
        await store.updateEnergyEarnings(using: result, enabled: true, at: date)
        #expect(await client.sessionReads > readsBeforeDisabling)
        #expect(await client.activityReads == 2)
        #expect(store.energyEarnings?.earningsUSD == 2)
    }

    @Test func repeatedFreshEnergyCachesHourlyActivityUntilAccountRevisionOrNewDay() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let day = try #require(Calendar.current.dateInterval(of: .day, for: date))
        let client = CountedEnergyActivityClient()
        let store = MonitorStore(service: TelemetryService(source: EnergyCacheTelemetrySource()),
                                 initial: .unavailable(now: date), earningsClient: client, now: { date })
        let result = EnergyRecordingSnapshot(reading: nil, intervals: intervals(from: day.start, count: 360), issue: nil)
        for offset in 0..<360 {
            await store.updateEnergyEarnings(using: result, enabled: true, at: day.start.addingTimeInterval(3600 + Double(offset * 10)))
        }
        #expect(await client.activityReads == 1)
        #expect(store.energyEarnings?.earningsUSD == 1)
        await store.refreshEarnings()
        await store.updateEnergyEarnings(using: result, enabled: true, at: date)
        #expect(await client.activityReads == 2)
        let tomorrow = try #require(Calendar.current.date(byAdding: .day, value: 1, to: date))
        await store.updateEnergyEarnings(using: result, enabled: true, at: tomorrow)
        #expect(await client.activityReads == 3)
        #expect(store.energyEarnings == nil)
    }

    @Test func activityFailureRetriesAndFreshEnergyRecomputesCoverageWithoutQuery() async throws {
        let date = Date(timeIntervalSince1970: 2_000_000)
        let day = try #require(Calendar.current.dateInterval(of: .day, for: date))
        let client = CountedEnergyActivityClient()
        let store = MonitorStore(service: TelemetryService(source: EnergyCacheTelemetrySource()),
                                 initial: .unavailable(now: date), earningsClient: client, now: { date })
        await client.failNextActivity()
        let incomplete = EnergyRecordingSnapshot(reading: nil, intervals: intervals(from: day.start, count: 359), issue: nil)
        await store.updateEnergyEarnings(using: incomplete, enabled: true, at: date)
        await store.updateEnergyEarnings(using: incomplete, enabled: true, at: date)
        #expect(await client.activityReads == 2)
        #expect(store.energyEarnings == nil)
        let complete = EnergyRecordingSnapshot(reading: nil, intervals: intervals(from: day.start, count: 360), issue: nil)
        await store.updateEnergyEarnings(using: complete, enabled: true, at: date)
        #expect(await client.activityReads == 2)
        #expect(store.energyEarnings?.earningsUSD == 1)
        await store.updateEnergyEarnings(using: complete, enabled: false, at: date)
        #expect(store.energyEarnings == nil)
    }

    @Test func boundedDaySlicePreservesBoundaryFragmentsAndMatchesFullHistory() throws {
        let day = DateInterval(start: Date(timeIntervalSince1970: 1005), duration: 3600)
        let history = intervals(from: Date(timeIntervalSince1970: 0), count: 60_000)
        let selected = EnergyHistory.overlapping(history, with: day)
        #expect(selected == history.filter { $0.end > day.start && $0.start < day.end })
        #expect(selected.count == 361)
        let bucket = ActivityBucket(interval: day, totals: .init(workMicroUSD: 1_000_000, rewardMicroUSD: 0, jobs: 1, promptTokens: 0, completionTokens: 0), coverage: .recorded)
        #expect(EnergyEarnings.matching(buckets: [bucket], energy: selected, day: day, now: day.end)
                == EnergyEarnings.matching(buckets: [bucket], energy: history, day: day, now: day.end))
    }

    private func intervals(from start: Date, count: Int) -> [EnergyInterval] {
        (0..<count).map { index in
            .init(start: start.addingTimeInterval(Double(index * 10)), end: start.addingTimeInterval(Double(index * 10 + 10)),
                  kWh: 0.001, usdPerKWh: 0.1, source: "fixture", estimated: true)
        }
    }
}

private actor CountedEnergyActivityClient: SyntheticAuthenticatedEarningsFixture {
    private(set) var activityReads = 0
    private(set) var sessionReads = 0
    private var failActivity = false
    private var context = AccountEarningsContext(accountScope: "synthetic-energy-account-A", generation: UUID())
    private var amount: Int64 = 1_000_000
    func changeAccount() {
        context = .init(accountScope: "synthetic-energy-account-B", generation: UUID())
        amount = 2_000_000
    }
    func financialSessionState() async -> AccountEarningsSessionState {
        sessionReads += 1
        return .init(context: context, ledgerReady: true, revision: context.generation)
    }
    // No asynchronous account-change delivery: re-enabling must discover the
    // replacement through its own authoritative read, not a fixture callback.
    func financialSessionChanges() async -> AsyncStream<AccountEarningsSessionState> {
        AsyncStream { $0.finish() }
    }
    func failNextActivity() { failActivity = true }
    func fetch(now: Date) async throws -> EarningsPresentationValue { .available(microUSD: 1_000_000) }
    func activity(in interval: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        activityReads += 1
        if failActivity { failActivity = false; throw EnergyCacheFailure() }
        return [.init(interval: .init(start: interval.start, duration: 3600),
                      totals: .init(workMicroUSD: amount, rewardMicroUSD: 0, jobs: 1, promptTokens: 0, completionTokens: 0), coverage: .recorded)]
    }
}
private struct EnergyCacheFailure: Error {}
private struct EnergyCacheTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw EnergyCacheFailure() }
    func readLoadedModels() async throws -> LoadedModelsState { throw EnergyCacheFailure() }
    func readStatus() async throws -> StatusSnapshot { throw EnergyCacheFailure() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { [] }
}
