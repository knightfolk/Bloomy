import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Frozen support report alert-history availability", .serialized)
@MainActor
struct SupportPacketAlertHistoryAvailabilityTests {
    @Test("presentation metadata leaves exported bytes and schema unchanged")
    func metadataDoesNotChangeExport() throws {
        let date = Date(timeIntervalSince1970: 100)
        let unspecified = try SupportPacketSnapshot.make(
            snapshot: .unavailable(now: date), alerts: [],
            allowlistedModelIDs: [], createdAt: date
        )
        #expect(unspecified.alertHistoryAvailable == nil)
        for available in [false, true] {
            let packet = try SupportPacketSnapshot.make(
                snapshot: .unavailable(now: date), alerts: [],
                allowlistedModelIDs: [], createdAt: date,
                alertHistoryAvailable: available
            )
            #expect(packet.alertHistoryAvailable == available)
            #expect(packet.data == unspecified.data)
            #expect(packet.alertCount == 0)
            #expect(packet.omittedAlertCount == 0)
        }
    }

    @Test("a report with saved alerts stays available after a later persistence failure")
    func laterFailureDoesNotChangeReport() async throws {
        let alert = AlertRecord(
            id: 1, code: .providerOffline, kind: .raised,
            occurredAt: Date(timeIntervalSince1970: 90),
            observedDurationSeconds: 2, observationCount: 2
        )
        let history = SupportAvailabilityHistory(rows: [alert])
        let store = makeStore(history: history)
        let packet = try await store.makeSupportPacketPreview()
        let originalBytes = packet.data
        #expect(store.alertHistoryAvailable)
        #expect(packet.alertHistoryAvailable == true)
        #expect(packet.alertCount == 1)

        await history.failWrites()
        await store.accept(offlineSnapshot(at: 100))
        await store.accept(offlineSnapshot(at: 102))
        #expect(await history.writeAttempts == 1)
        #expect(!store.alertHistoryAvailable)
        #expect(packet.alertHistoryAvailable == true)
        #expect(packet.alertCount == 1)
        #expect(packet.data == originalBytes)
    }

    @Test("an unavailable report stays unavailable after recovery to known-empty history")
    func laterRecoveryDistinguishesEmptyFromUnavailable() async throws {
        let history = SupportAvailabilityHistory(rows: [], readsFail: true)
        let store = makeStore(history: history)
        let unavailable = try await store.makeSupportPacketPreview()
        let originalBytes = unavailable.data
        #expect(!store.alertHistoryAvailable)
        #expect(unavailable.alertHistoryAvailable == false)
        #expect(unavailable.alertCount == 0)

        await history.recoverReads()
        let empty = try await store.makeSupportPacketPreview()
        #expect(store.alertHistoryAvailable)
        #expect(empty.alertHistoryAvailable == true)
        #expect(empty.alertCount == 0)
        #expect(empty.omittedAlertCount == 0)
        #expect(unavailable.alertHistoryAvailable == false)
        #expect(unavailable.data == originalBytes)
        #expect(empty.data == unavailable.data)
    }

    private func makeStore(history: SupportAvailabilityHistory) -> MonitorStore {
        let date = Date(timeIntervalSince1970: 99)
        return MonitorStore(
            service: TelemetryService(source: SupportAvailabilityTelemetrySource()),
            initial: .unavailable(now: date), alertHistory: history,
            alertPolicy: .init(
                sustainedOutageDuration: 2, coldStartGraceDuration: 0,
                maximumEvidenceGap: 10, maximumSnapshotAge: 5
            ),
            now: { date }
        )
    }

    private func offlineSnapshot(at seconds: TimeInterval) -> TelemetrySnapshot {
        let date = Date(timeIntervalSince1970: seconds)
        let daemon = DaemonState(
            schema: 1, version: "fixture", currentModel: "fixture/model", warmModels: [],
            stats: ProviderStats(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: TrustState(level: "fixture", status: "offline", reason: "fixture",
                              receivedAt: seconds),
            capacity: nil, slots: [], inferenceActive: false, startedAt: 0,
            writtenAt: seconds, pid: 123,
            processIdentity: ProcessIdentity(pid: 123, startTimeMicros: 1)
        )
        return TelemetrySnapshot(
            state: .available(value: daemon, capturedAt: date),
            loadedModels: .unavailable(reason: "fixture"),
            status: .unavailable(reason: "fixture"),
            eventFeed: .unavailable(reason: "fixture"),
            tokenRate: .unavailable(reason: "fixture"),
            diagnostics: [], capturedAt: date, menuStatus: .offline
        )
    }
}

private actor SupportAvailabilityHistory: AlertHistoryRecording {
    let rows: [AlertRecord]
    private var readsFail: Bool
    private var writesFail = false
    private(set) var writeAttempts = 0

    init(rows: [AlertRecord], readsFail: Bool = false) {
        self.rows = rows
        self.readsFail = readsFail
    }

    func failWrites() { writesFail = true }
    func recoverReads() { readsFail = false }

    func record(_ transitions: [AlertTransition]) async throws {
        writeAttempts += 1
        if writesFail { throw SupportAvailabilityFailure() }
    }

    func recentHistory(limit: Int) async throws -> [AlertRecord] {
        if readsFail { throw SupportAvailabilityFailure() }
        return Array(rows.suffix(limit))
    }

    func activeAlertCodes() async throws -> Set<OperationalAlertCode> {
        if readsFail { throw SupportAvailabilityFailure() }
        return []
    }
}

private struct SupportAvailabilityTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw SupportAvailabilityFailure() }
    func readLoadedModels() async throws -> LoadedModelsState { throw SupportAvailabilityFailure() }
    func readStatus() async throws -> StatusSnapshot { throw SupportAvailabilityFailure() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw SupportAvailabilityFailure() }
}

private struct SupportAvailabilityFailure: Error {}
