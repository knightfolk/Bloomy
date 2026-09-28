import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Monitor operational alert integration", .serialized)
@MainActor
struct MonitorStoreOperationalAlertsTests {
    @Test("alerts persist with denied notifications, restore dedupe, and build a frozen packet")
    func persistsRestoresAndExports() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("darkbloom-monitor-alerts-\(UUID().uuidString).sqlite3")
        let database = try AlertHistoryDatabase(url: url)
        let notificationClient = StoreNotificationClient()
        let notifier = OperationalNotificationCenter(client: notificationClient)
        let policy = OperationalAlertPolicy(
            sustainedOutageDuration: 2,
            coldStartGraceDuration: 0,
            maximumEvidenceGap: 10,
            maximumSnapshotAge: 5
        )
        let firstStore = makeStore(database: database, notifier: notifier, policy: policy, at: 100)

        await firstStore.accept(snapshot(at: 100, trust: "offline"))
        await firstStore.accept(snapshot(at: 102, trust: "offline"))
        await firstStore.accept(snapshot(at: 102, trust: "offline"))
        #expect(try await database.recentHistory(limit: 10).map(\.kind) == [.raised])
        #expect(try await database.activeAlertCodes() == [.providerOffline])
        #expect(notificationClient.authorizationChecks == 1)
        #expect(notificationClient.payloads.isEmpty)

        let restoredStore = makeStore(database: database, notifier: notifier, policy: policy, at: 103)
        await restoredStore.accept(snapshot(at: 103, trust: "offline"))
        #expect(try await database.recentHistory(limit: 10).map(\.kind) == [.raised])

        await restoredStore.accept(snapshot(at: 104, trust: "offline", scheduledIdle: true))
        let history = try await database.recentHistory(limit: 10)
        #expect(history.map(\.kind) == [.raised, .suppressed])
        #expect(try await database.activeAlertCodes().isEmpty)
        #expect(notificationClient.authorizationChecks == 1)

        let packet = try await restoredStore.makeSupportPacketPreview()
        #expect(packet.alertCount == 2)
        #expect(packet.data.count <= SupportPacketSnapshot.maximumBytes)
        #expect(packet.previewText.contains("provider_offline"))
        #expect(restoredStore.alertHistoryAvailable)
    }

    private func makeStore(
        database: AlertHistoryDatabase,
        notifier: OperationalAlertNotifying,
        policy: OperationalAlertPolicy,
        at seconds: Int
    ) -> MonitorStore {
        let now = Date(timeIntervalSince1970: TimeInterval(seconds))
        return MonitorStore(
            service: TelemetryService(source: EmptyAlertTelemetrySource()),
            initial: .unavailable(now: now),
            alertHistory: database,
            alertNotifier: notifier,
            alertPolicy: policy,
            now: { now }
        )
    }

    private func snapshot(at seconds: Int, trust: String, scheduledIdle: Bool = false) -> TelemetrySnapshot {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let daemon = DaemonState(
            schema: 1,
            version: "fixture",
            currentModel: "allowed/model",
            warmModels: [],
            stats: ProviderStats(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: TrustState(
                level: "fixture",
                status: trust,
                reason: "unused prose",
                receivedAt: date.timeIntervalSince1970
            ),
            capacity: nil,
            slots: [],
            inferenceActive: false,
            startedAt: 0,
            writtenAt: date.timeIntervalSince1970,
            pid: 123,
            processIdentity: ProcessIdentity(pid: 123, startTimeMicros: 1),
            availability: scheduledIdle ? ProviderAvailabilityState(phase: .waitingForSchedule) : nil
        )
        return TelemetrySnapshot(
            state: .available(value: daemon, capturedAt: date),
            loadedModels: .unavailable(reason: "unused"),
            status: .unavailable(reason: "unused"),
            eventFeed: .unavailable(reason: "unused"),
            tokenRate: .unavailable(reason: "unused"),
            diagnostics: [],
            capturedAt: date,
            menuStatus: trust == "offline" ? .offline : .online
        )
    }
}

@MainActor
private final class StoreNotificationClient: OperationalNotificationClient {
    private(set) var authorizationChecks = 0
    private(set) var payloads: [OperationalNotificationPayload] = []

    func authorizationGranted() async -> Bool {
        authorizationChecks += 1
        return false
    }

    func add(_ payload: OperationalNotificationPayload) async throws {
        payloads.append(payload)
    }
}

private struct EmptyAlertTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw AlertTelemetryFailure() }
    func readLoadedModels() async throws -> LoadedModelsState { throw AlertTelemetryFailure() }
    func readStatus() async throws -> StatusSnapshot { throw AlertTelemetryFailure() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw AlertTelemetryFailure() }
}

private struct AlertTelemetryFailure: Error {}
