import Foundation

public enum Capability: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case monitor
    case history
    case settingsRead
    case settingsWrite
    case providerLifecycle
    case providerLiveSwitch
    case appLifecycle
    case deviceManagement
}

public enum MetricID: String, Codable, CaseIterable, Equatable, Sendable {
    case providerUptimeSeconds
    case requestsServed
    case tokensGenerated
    case tokenRate
    case systemCPUPercent
    case systemGPUPercent
    case memoryUsedBytes
    case powerWatts
    case accountEarnings
    case accountEarningsRateEstimate
    case networkDemandPercent
}

public enum MetricUnit: String, Codable, Equatable, Sendable {
    case count
    case seconds
    case percent
    case bytes
    case watts
    case tokensPerSecond
    case currency
    case currencyPerHour
}

public enum MetricScope: String, Codable, Equatable, Sendable {
    case localProvider
    case wholeMac
    case account
    case network
}

public enum MetricProvenance: String, Codable, Equatable, Sendable {
    case direct
    case derived
}

public enum ObservationAvailability: String, Codable, Equatable, Sendable {
    case available
    case stale
    case unavailable
}

public enum SafeReason: String, Codable, Equatable, Sendable {
    case sourceMissing
    case sourceStale
    case sourceRefreshFailed
    case insufficientSamples
    case permissionDenied
    case providerStopped
    case unsupported
    case busy
    case conflict
    case expired
    case revoked
    case outcomeUncertain
    case internalFailure
}

public struct MetricObservation: Codable, Equatable, Sendable {
    public let metric: MetricID
    public let value: Double?
    public let unit: MetricUnit
    public let scope: MetricScope
    public let provenance: MetricProvenance
    public let capturedAt: Date?
    public let sourceAgeSeconds: Double?
    public let availability: ObservationAvailability
    public let reason: SafeReason?
    public let currencyCode: String?

    public init(
        metric: MetricID,
        value: Double?,
        unit: MetricUnit,
        scope: MetricScope,
        provenance: MetricProvenance,
        capturedAt: Date?,
        sourceAgeSeconds: Double?,
        availability: ObservationAvailability,
        reason: SafeReason?,
        currencyCode: String? = nil
    ) {
        self.metric = metric
        self.value = value
        self.unit = unit
        self.scope = scope
        self.provenance = provenance
        self.capturedAt = capturedAt
        self.sourceAgeSeconds = sourceAgeSeconds
        self.availability = availability
        self.reason = reason
        self.currencyCode = currencyCode
    }

    func validate() throws {
        try requireFinite(value, field: "observation.value")
        try requireFinite(sourceAgeSeconds, field: "observation.sourceAgeSeconds")
        if let sourceAgeSeconds, sourceAgeSeconds < 0 {
            throw ProtocolError.invalidField("observation.sourceAgeSeconds")
        }
        if availability == .available, value == nil {
            throw ProtocolError.invalidField("observation.availableValue")
        }
        if availability == .stale, capturedAt == nil {
            throw ProtocolError.invalidField("observation.staleCapturedAt")
        }
        if availability == .unavailable, value != nil {
            throw ProtocolError.invalidField("observation.unavailableValue")
        }
        let isCurrency = unit == .currency || unit == .currencyPerHour
        guard isCurrency == (currencyCode != nil) else {
            throw ProtocolError.invalidField("observation.currencyCode")
        }
        if let currencyCode,
           currencyCode.range(of: "^[A-Z]{3}$", options: .regularExpression) == nil {
            throw ProtocolError.invalidField("observation.currencyCode")
        }
    }
}

public enum RateWindow: String, Codable, Equatable, Sendable {
    case activeSample
    case trailingMinute
    case calendarDay
}

public struct ModelSummary: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let enabled: Bool
    public let advertised: Bool
    public let resident: Bool
    public let active: Bool
    public let tokenRate: Double?
    public let rateWindow: RateWindow?

    public init(
        id: String,
        name: String,
        enabled: Bool = false,
        advertised: Bool = false,
        resident: Bool = false,
        active: Bool = false,
        tokenRate: Double? = nil,
        rateWindow: RateWindow? = nil
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.advertised = advertised
        self.resident = resident
        self.active = active
        self.tokenRate = tokenRate
        self.rateWindow = rateWindow
    }

    func validate() throws {
        try requireBounded(id, maximumBytes: ProtocolLimits.maximumIdentifierBytes, field: "model.id")
        try requireBounded(name, maximumBytes: ProtocolLimits.maximumDisplayNameBytes, field: "model.name")
        try requireFinite(tokenRate, field: "model.tokenRate")
        if tokenRate != nil, rateWindow == nil { throw ProtocolError.invalidField("model.rateWindow") }
    }
}

public enum RuntimeState: String, Codable, CaseIterable, Equatable, Sendable {
    case running
    case stopped
    case starting
    case scheduledIdle
    case preloading
    case switching
    case stopping
    case draining
    case unavailable
    case connected
    case disconnected
    case disabled
    case unknown
}

public struct RuntimeStateObservation: Codable, Equatable, Sendable {
    public let state: RuntimeState
    public let observedAt: Date
    public let reason: SafeReason?

    public init(state: RuntimeState, observedAt: Date, reason: SafeReason? = nil) {
        self.state = state
        self.observedAt = observedAt
        self.reason = reason
    }
}

public struct RuntimeStates: Codable, Equatable, Sendable {
    public let provider: RuntimeStateObservation
    public let macApp: RuntimeStateObservation
    public let helper: RuntimeStateObservation
    public let connection: RuntimeStateObservation

    public init(
        provider: RuntimeStateObservation,
        macApp: RuntimeStateObservation,
        helper: RuntimeStateObservation,
        connection: RuntimeStateObservation
    ) {
        self.provider = provider
        self.macApp = macApp
        self.helper = helper
        self.connection = connection
    }
}

public struct CompanionSnapshot: Codable, Equatable, Sendable {
    public static let schemaVersion: UInt16 = 1

    public let schema: UInt16
    public let hostID: UUID
    public let runtimeEpoch: UUID
    public let sequence: UInt64
    public let generatedAt: Date
    public let observations: [MetricObservation]
    public let models: [ModelSummary]
    public let states: RuntimeStates
    public let capabilities: Set<Capability>

    public init(
        hostID: UUID,
        runtimeEpoch: UUID,
        sequence: UInt64,
        generatedAt: Date,
        observations: [MetricObservation],
        models: [ModelSummary],
        states: RuntimeStates,
        capabilities: Set<Capability> = []
    ) {
        self.schema = Self.schemaVersion
        self.hostID = hostID
        self.runtimeEpoch = runtimeEpoch
        self.sequence = sequence
        self.generatedAt = generatedAt
        self.observations = observations
        self.models = models
        self.states = states
        self.capabilities = capabilities
    }

    public static func validated(
        hostID: UUID,
        runtimeEpoch: UUID,
        sequence: UInt64,
        generatedAt: Date,
        observations: [MetricObservation],
        models: [ModelSummary],
        states: RuntimeStates,
        capabilities: Set<Capability> = []
    ) throws -> Self {
        let value = Self(
            hostID: hostID, runtimeEpoch: runtimeEpoch, sequence: sequence,
            generatedAt: generatedAt, observations: observations, models: models,
            states: states, capabilities: capabilities
        )
        try value.validate()
        return value
    }

    func validate() throws {
        guard schema == Self.schemaVersion else { throw ProtocolError.invalidField("snapshot.schema") }
        guard observations.count <= ProtocolLimits.maximumObservations else {
            throw ProtocolError.tooManyObservations(observations.count)
        }
        guard models.count <= ProtocolLimits.maximumModels else {
            throw ProtocolError.tooManyModels(models.count)
        }
        guard Set(models.map(\.id)).count == models.count else {
            throw ProtocolError.invalidField("snapshot.duplicateModel")
        }
        for observation in observations { try observation.validate() }
        for model in models { try model.validate() }
    }

    private enum CodingKeys: String, CodingKey {
        case schema, hostID, runtimeEpoch, sequence, generatedAt, observations, models, states, capabilities
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = try container.decode(UInt16.self, forKey: .schema)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        runtimeEpoch = try container.decode(UUID.self, forKey: .runtimeEpoch)
        sequence = try container.decode(UInt64.self, forKey: .sequence)
        generatedAt = try container.decode(Date.self, forKey: .generatedAt)
        observations = try container.decode([MetricObservation].self, forKey: .observations)
        models = try container.decode([ModelSummary].self, forKey: .models)
        states = try container.decode(RuntimeStates.self, forKey: .states)
        capabilities = try container.decodeIfPresent(Set<Capability>.self, forKey: .capabilities) ?? []
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schema, forKey: .schema)
        try container.encode(hostID, forKey: .hostID)
        try container.encode(runtimeEpoch, forKey: .runtimeEpoch)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(generatedAt, forKey: .generatedAt)
        try container.encode(observations, forKey: .observations)
        try container.encode(models, forKey: .models)
        try container.encode(states, forKey: .states)
        try container.encode(capabilities.sorted { $0.rawValue < $1.rawValue }, forKey: .capabilities)
    }
}

public struct MonitorSubscription: Codable, Equatable, Sendable {
    public let minimumIntervalSeconds: UInt16
    public init(minimumIntervalSeconds: UInt16 = 2) { self.minimumIntervalSeconds = minimumIntervalSeconds }
}

public struct HistoryQuery: Codable, Equatable, Sendable {
    public let periodStart: Date
    public let periodEnd: Date
    public let cursor: String?
    public let modelID: String?
    public let maximumBuckets: UInt16

    public init(periodStart: Date, periodEnd: Date, cursor: String? = nil, modelID: String? = nil, maximumBuckets: UInt16 = 168) {
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.cursor = cursor
        self.modelID = modelID
        self.maximumBuckets = maximumBuckets
    }

    func validate() throws {
        guard periodStart < periodEnd, maximumBuckets > 0,
              maximumBuckets <= ProtocolLimits.maximumHistoryBuckets else {
            throw ProtocolError.invalidField("history.query")
        }
        if let cursor { try requireBounded(cursor, maximumBytes: 256, field: "history.cursor") }
        if let modelID { try requireBounded(modelID, maximumBytes: ProtocolLimits.maximumIdentifierBytes, field: "history.modelID") }
    }
}

public struct HistoryBucket: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let observations: [MetricObservation]
    public init(start: Date, end: Date, observations: [MetricObservation]) {
        self.start = start
        self.end = end
        self.observations = observations
    }

    func validate() throws {
        guard start < end else { throw ProtocolError.invalidField("history.bucketPeriod") }
        for observation in observations { try observation.validate() }
    }
}

public struct HistoryPage: Codable, Equatable, Sendable {
    public let buckets: [HistoryBucket]
    public let hostTimeZoneID: String
    public let coverage: Double
    public let nextCursor: String?

    public init(buckets: [HistoryBucket], hostTimeZoneID: String, coverage: Double, nextCursor: String?) {
        self.buckets = buckets
        self.hostTimeZoneID = hostTimeZoneID
        self.coverage = coverage
        self.nextCursor = nextCursor
    }

    public static func validated(
        buckets: [HistoryBucket], hostTimeZoneID: String, coverage: Double, nextCursor: String?
    ) throws -> Self {
        let value = Self(buckets: buckets, hostTimeZoneID: hostTimeZoneID, coverage: coverage, nextCursor: nextCursor)
        try value.validate()
        return value
    }

    func validate() throws {
        guard buckets.count <= ProtocolLimits.maximumHistoryBuckets else {
            throw ProtocolError.tooManyHistoryBuckets(buckets.count)
        }
        try requireBounded(hostTimeZoneID, maximumBytes: 64, field: "history.hostTimeZoneID")
        guard coverage.isFinite, (0...1).contains(coverage) else { throw ProtocolError.invalidField("history.coverage") }
        if let nextCursor { try requireBounded(nextCursor, maximumBytes: 256, field: "history.nextCursor") }
        for bucket in buckets { try bucket.validate() }
    }

    private enum CodingKeys: String, CodingKey { case buckets, hostTimeZoneID, coverage, nextCursor }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        buckets = try container.decode([HistoryBucket].self, forKey: .buckets)
        hostTimeZoneID = try container.decode(String.self, forKey: .hostTimeZoneID)
        coverage = try container.decode(Double.self, forKey: .coverage)
        nextCursor = try container.decodeIfPresent(String.self, forKey: .nextCursor)
        try validate()
    }
}
