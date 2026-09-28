import Foundation

#if os(macOS)
import ServiceManagement

public enum HelperRegistrationStatus: String, Sendable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound
}

/// The identifier must be fixed by the signed app bundle. Creating this
/// object only reads status; registration requires an explicit local call.
public struct HelperRegistration: Sendable {
    public let loginItemIdentifier: String

    public init(loginItemIdentifier: String) {
        self.loginItemIdentifier = loginItemIdentifier
    }

    public func status() -> HelperRegistrationStatus {
        let service = SMAppService.loginItem(identifier: loginItemIdentifier)
        switch service.status {
        case .enabled: return .enabled
        case .requiresApproval: return .requiresApproval
        case .notRegistered: return .notRegistered
        case .notFound: return .notFound
        @unknown default: return .notFound
        }
    }

    public func registerAfterLocalApproval() throws {
        try SMAppService.loginItem(identifier: loginItemIdentifier).register()
    }

    public func unregisterAfterLocalApproval() throws {
        try SMAppService.loginItem(identifier: loginItemIdentifier).unregister()
    }
}
#endif
