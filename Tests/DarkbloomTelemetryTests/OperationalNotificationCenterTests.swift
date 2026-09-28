import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Operational notifications", .serialized)
@MainActor
struct OperationalNotificationCenterTests {
    @Test("only newly raised transitions become notifications")
    func onlyRaisesAreDelivered() async {
        let client = NotificationClient(granted: true)
        let center = OperationalNotificationCenter(client: client)
        await center.deliver([
            transition(.providerOffline, .raised, at: 100),
            transition(.providerOffline, .recovered, at: 200),
            transition(.providerOffline, .suppressed, at: 300),
        ])

        #expect(client.authorizationChecks == 1)
        #expect(client.payloads.count == 1)
        #expect(client.payloads.first?.title == OperationalAlertCode.providerOffline.title)
        #expect(client.payloads.first?.body.contains("offline") == true)
        #expect(client.payloads.first?.identifier == "darkbloom.alert.provider_offline.100000")
    }

    @Test("denied authorization preserves a no-prompt notification path")
    func deniedAuthorizationAddsNothing() async {
        let client = NotificationClient(granted: false)
        let center = OperationalNotificationCenter(client: client)
        await center.deliver([transition(.modelUnknown, .raised, at: 1)])

        #expect(client.authorizationChecks == 1)
        #expect(client.payloads.isEmpty)
    }

    private func transition(
        _ code: OperationalAlertCode,
        _ kind: AlertTransitionKind,
        at seconds: Int
    ) -> AlertTransition {
        AlertTransition(
            code: code,
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: TimeInterval(seconds)),
            observationCount: 3
        )
    }
}

@MainActor
private final class NotificationClient: OperationalNotificationClient {
    let granted: Bool
    private(set) var authorizationChecks = 0
    private(set) var payloads: [OperationalNotificationPayload] = []

    init(granted: Bool) { self.granted = granted }

    func authorizationGranted() async -> Bool {
        authorizationChecks += 1
        return granted
    }

    func add(_ payload: OperationalNotificationPayload) async throws {
        payloads.append(payload)
    }
}
