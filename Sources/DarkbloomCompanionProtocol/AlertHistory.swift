import Foundation

/// Fixed alert identifiers mirrored from the Mac's operational alert engine.
/// This deliberately excludes provider errors, model paths, and caller text.
public enum CompanionAlertCode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case providerOffline = "provider_offline"
    case lifecycleTimedOut = "lifecycle_timed_out"
    case lifecycleForced = "lifecycle_forced"
    case modelInsufficientMemory = "model_insufficient_memory"
    case modelUnavailable = "model_unavailable"
    case modelUnsupported = "model_unsupported"
    case modelIntegrityFailure = "model_integrity_failure"
    case modelTimedOut = "model_timed_out"
    case modelBackendUnavailable = "model_backend_unavailable"
    case modelUnknown = "model_unknown"
}

public enum CompanionAlertTransition: String, Codable, CaseIterable, Equatable, Sendable {
    case raised
    case recovered
    case suppressed
}

/// One sanitized history row. The schema has no field for diagnostics or prose.
public struct CompanionAlertRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: Int64
    public let code: CompanionAlertCode
    public let transition: CompanionAlertTransition
    public let occurredAt: Date
    public let observedDurationSeconds: Int?
    public let observationCount: Int

    public init(
        id: Int64,
        code: CompanionAlertCode,
        transition: CompanionAlertTransition,
        occurredAt: Date,
        observedDurationSeconds: Int?,
        observationCount: Int
    ) {
        self.id = id
        self.code = code
        self.transition = transition
        self.occurredAt = occurredAt
        self.observedDurationSeconds = observedDurationSeconds
        self.observationCount = observationCount
    }

    func validate() throws {
        guard id > 0,
              occurredAt.timeIntervalSince1970.isFinite,
              (-62_135_596_800...253_402_300_799).contains(occurredAt.timeIntervalSince1970),
              (observedDurationSeconds.map { (0...86_400).contains($0) } ?? true),
              (1...1_000_000).contains(observationCount) else {
            throw ProtocolError.invalidField("alert.record")
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, transition, occurredAt, observedDurationSeconds, observationCount
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        code = try container.decode(CompanionAlertCode.self, forKey: .code)
        transition = try container.decode(CompanionAlertTransition.self, forKey: .transition)
        occurredAt = try container.decode(Date.self, forKey: .occurredAt)
        observedDurationSeconds = try container.decodeIfPresent(Int.self, forKey: .observedDurationSeconds)
        observationCount = try container.decode(Int.self, forKey: .observationCount)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(transition, forKey: .transition)
        try container.encode(occurredAt, forKey: .occurredAt)
        try container.encodeIfPresent(observedDurationSeconds, forKey: .observedDurationSeconds)
        try container.encode(observationCount, forKey: .observationCount)
    }
}

/// `cursor` is the last row ID from the preceding page; the next page returns
/// only older records. A nil cursor starts at the newest retained row.
public struct AlertHistoryQuery: Codable, Equatable, Sendable {
    public let cursor: Int64?
    public let maximumRecords: Int

    public init(cursor: Int64? = nil, maximumRecords: Int = 50) {
        self.cursor = cursor
        self.maximumRecords = maximumRecords
    }

    public func validated() throws -> Self {
        try validate()
        return self
    }

    func validate() throws {
        guard (cursor.map { $0 > 0 } ?? true),
              (1...ProtocolLimits.maximumAlertHistoryRecordsPerPage).contains(maximumRecords) else {
            throw ProtocolError.invalidField("alertHistory.query")
        }
    }

    private enum CodingKeys: String, CodingKey { case cursor, maximumRecords }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        cursor = try container.decodeIfPresent(Int64.self, forKey: .cursor)
        maximumRecords = try container.decode(Int.self, forKey: .maximumRecords)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(cursor, forKey: .cursor)
        try container.encode(maximumRecords, forKey: .maximumRecords)
    }
}

public struct AlertHistoryPage: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let records: [CompanionAlertRecord]
    public let nextCursor: Int64?

    public init(hostID: UUID, records: [CompanionAlertRecord], nextCursor: Int64?) {
        self.hostID = hostID
        self.records = records
        self.nextCursor = nextCursor
    }

    public static func validated(
        hostID: UUID,
        records: [CompanionAlertRecord],
        nextCursor: Int64?
    ) throws -> Self {
        let value = Self(hostID: hostID, records: records, nextCursor: nextCursor)
        try value.validate()
        return value
    }

    func validate() throws {
        guard records.count <= ProtocolLimits.maximumAlertHistoryRecordsPerPage else {
            throw ProtocolError.invalidField("alertHistory.recordCount")
        }
        guard Set(records.map(\.id)).count == records.count,
              records.allSatisfy({ $0.id > 0 }),
              zip(records, records.dropFirst()).allSatisfy({ $0.0.id > $0.1.id }) else {
            throw ProtocolError.invalidField("alertHistory.recordOrder")
        }
        if let nextCursor {
            guard nextCursor > 0,
                  let oldestRecordID = records.last?.id,
                  nextCursor <= oldestRecordID else {
                throw ProtocolError.invalidField("alertHistory.nextCursor")
            }
        }
        for record in records { try record.validate() }
    }

    private enum CodingKeys: String, CodingKey { case hostID, records, nextCursor }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        records = try container.decode([CompanionAlertRecord].self, forKey: .records)
        nextCursor = try container.decodeIfPresent(Int64.self, forKey: .nextCursor)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostID, forKey: .hostID)
        try container.encode(records, forKey: .records)
        try container.encodeIfPresent(nextCursor, forKey: .nextCursor)
    }
}
