import DarkbloomCompanionProtocol
import Foundation

public struct CompanionAuditEntry: Codable, Equatable, Sendable {
    public enum Event: String, Codable, Sendable {
        case paired, prepared, authorized, dispatched, succeeded, failed, revoked
    }
    public let at: Date
    public let event: Event
    public let deviceID: UUID
    public let requestID: UUID?
    public let commandID: UUID?
    public let actionType: String?
}

public actor CompanionAuditLog {
    private let maximumEntries: Int
    private var values: [CompanionAuditEntry] = []
    public init(maximumEntries: Int = 1_000) { self.maximumEntries = max(1, maximumEntries) }
    public func append(_ entry: CompanionAuditEntry) {
        values.append(entry)
        if values.count > maximumEntries { values.removeFirst(values.count - maximumEntries) }
    }
    public func entries() -> [CompanionAuditEntry] { values }
}
