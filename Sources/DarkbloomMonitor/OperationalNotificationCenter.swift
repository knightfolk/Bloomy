import Foundation
import DarkbloomTelemetry
import UserNotifications

struct OperationalNotificationPayload: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
}

@MainActor
protocol OperationalNotificationClient: AnyObject {
    func authorizationGranted() async -> Bool
    func add(_ payload: OperationalNotificationPayload) async throws
}

@MainActor
protocol OperationalAlertNotifying: AnyObject {
    func deliver(_ transitions: [AlertTransition]) async
}

/// Delivers only fixed-code, newly raised transitions. It checks existing
/// notification authorization and never prompts during monitoring startup.
@MainActor
final class OperationalNotificationCenter: OperationalAlertNotifying {
    private let client: any OperationalNotificationClient

    init(client: (any OperationalNotificationClient)? = nil) {
        self.client = client ?? UserNotificationClient()
    }

    func deliver(_ transitions: [AlertTransition]) async {
        let openings = transitions.filter {
            $0.kind == .raised && Self.isValid($0)
        }
        guard !openings.isEmpty, await client.authorizationGranted() else { return }

        for transition in openings {
            let milliseconds = Int64((transition.occurredAt.timeIntervalSince1970 * 1_000).rounded(.towardZero))
            let payload = OperationalNotificationPayload(
                identifier: "darkbloom.alert.\(transition.code.rawValue).\(milliseconds)",
                title: transition.code.title,
                body: Self.body(for: transition)
            )
            try? await client.add(payload)
        }
    }

    private static func body(for transition: AlertTransition) -> String {
        switch transition.code {
        case .providerOffline:
            let seconds = transition.observedDurationSeconds ?? 0
            return "Fresh provider status stayed offline for \(seconds) seconds across \(transition.observationCount) observations."
        case .lifecycleTimedOut, .lifecycleForced:
            return "Darkbloom reported a provider lifecycle failure."
        case .modelInsufficientMemory, .modelUnavailable, .modelUnsupported,
             .modelIntegrityFailure, .modelTimedOut, .modelBackendUnavailable, .modelUnknown:
            return "Darkbloom reported a model load failure."
        }
    }

    private static func isValid(_ transition: AlertTransition) -> Bool {
        let timestamp = transition.occurredAt.timeIntervalSince1970
        guard timestamp.isFinite,
              (-62_135_596_800...253_402_300_799).contains(timestamp),
              (1...1_000_000).contains(transition.observationCount) else { return false }
        return transition.observedDurationSeconds.map { (0...86_400).contains($0) } ?? true
    }
}

@MainActor
private final class UserNotificationClient: OperationalNotificationClient {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func authorizationGranted() async -> Bool {
        let status = await center.notificationSettings().authorizationStatus
        return status == .authorized || status == .provisional
    }

    func add(_ payload: OperationalNotificationPayload) async throws {
        let content = UNMutableNotificationContent()
        content.title = payload.title
        content.body = payload.body
        content.sound = .default
        try await center.add(UNNotificationRequest(
            identifier: payload.identifier,
            content: content,
            trigger: nil
        ))
    }
}
