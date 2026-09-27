import Foundation

public struct IntegerRange: Codable, Equatable, Sendable {
    public let minimum: Int
    public let maximum: Int
    public init(minimum: Int, maximum: Int) { self.minimum = minimum; self.maximum = maximum }
}

public struct ProviderSettingsValues: Codable, Equatable, Sendable {
    public let enabledModels: [String]
    public let preloadModels: [String]
    public let maximumConcurrentRequests: Int
    public let residentModelSlots: Int
    public let startupPreload: Bool

    public init(
        enabledModels: [String] = [], preloadModels: [String] = [],
        maximumConcurrentRequests: Int = 1, residentModelSlots: Int = 1,
        startupPreload: Bool = false
    ) {
        self.enabledModels = enabledModels
        self.preloadModels = preloadModels
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.residentModelSlots = residentModelSlots
        self.startupPreload = startupPreload
    }

    func validate() throws {
        guard enabledModels.count <= ProtocolLimits.maximumModels,
              preloadModels.count <= ProtocolLimits.maximumModels,
              (1...24).contains(maximumConcurrentRequests),
              (1...ProtocolLimits.maximumResidentModelSlots).contains(residentModelSlots) else {
            throw ProtocolError.invalidField("settings.values")
        }
        for value in enabledModels + preloadModels {
            try requireBounded(value, maximumBytes: ProtocolLimits.maximumIdentifierBytes, field: "settings.modelID")
        }
        guard Set(enabledModels).count == enabledModels.count,
              Set(preloadModels).count == preloadModels.count else {
            throw ProtocolError.invalidField("settings.duplicateModel")
        }
        guard Set(preloadModels).isSubset(of: Set(enabledModels)) else {
            throw ProtocolError.invalidField("settings.preloadNotEnabled")
        }
    }
}

public struct ProviderSettingsPatch: Codable, Equatable, Sendable {
    public let enabledModels: [String]?
    public let preloadModels: [String]?
    public let maximumConcurrentRequests: Int?
    public let residentModelSlots: Int?
    public let startupPreload: Bool?

    public init(
        enabledModels: [String]? = nil,
        preloadModels: [String]? = nil,
        maximumConcurrentRequests: Int? = nil,
        residentModelSlots: Int? = nil,
        startupPreload: Bool? = nil
    ) {
        self.enabledModels = enabledModels
        self.preloadModels = preloadModels
        self.maximumConcurrentRequests = maximumConcurrentRequests
        self.residentModelSlots = residentModelSlots
        self.startupPreload = startupPreload
    }

    func validate() throws {
        guard [enabledModels != nil, preloadModels != nil, maximumConcurrentRequests != nil,
               residentModelSlots != nil, startupPreload != nil].contains(true) else {
            throw ProtocolError.invalidField("settings.emptyPatch")
        }
        if let enabledModels {
            guard enabledModels.count <= ProtocolLimits.maximumModels else { throw ProtocolError.tooManyModels(enabledModels.count) }
            guard Set(enabledModels).count == enabledModels.count else { throw ProtocolError.invalidField("settings.duplicateModel") }
            for value in enabledModels { try requireBounded(value, maximumBytes: ProtocolLimits.maximumIdentifierBytes, field: "settings.enabledModel") }
        }
        if let preloadModels {
            guard preloadModels.count <= ProtocolLimits.maximumModels else { throw ProtocolError.tooManyModels(preloadModels.count) }
            guard Set(preloadModels).count == preloadModels.count else { throw ProtocolError.invalidField("settings.duplicateModel") }
            for value in preloadModels { try requireBounded(value, maximumBytes: ProtocolLimits.maximumIdentifierBytes, field: "settings.preloadModel") }
        }
        if let enabledModels, let preloadModels, !Set(preloadModels).isSubset(of: Set(enabledModels)) {
            throw ProtocolError.invalidField("settings.preloadNotEnabled")
        }
        if let maximumConcurrentRequests, !(1...24).contains(maximumConcurrentRequests) {
            throw ProtocolError.invalidField("settings.maximumConcurrentRequests")
        }
        if let residentModelSlots,
           !(1...ProtocolLimits.maximumResidentModelSlots).contains(residentModelSlots) {
            throw ProtocolError.invalidField("settings.residentModelSlots")
        }
    }
}

public struct AppSettingsPatch: Codable, Equatable, Sendable {
    public let electricityRatePerKWh: Double?
    public let currencyCode: String?
    public init(electricityRatePerKWh: Double? = nil, currencyCode: String? = nil) {
        self.electricityRatePerKWh = electricityRatePerKWh
        self.currencyCode = currencyCode
    }

    func validate() throws {
        guard electricityRatePerKWh != nil || currencyCode != nil else {
            throw ProtocolError.invalidField("appSettings.emptyPatch")
        }
        if let electricityRatePerKWh, (!electricityRatePerKWh.isFinite || electricityRatePerKWh < 0) {
            throw ProtocolError.invalidField("appSettings.electricityRatePerKWh")
        }
        if let currencyCode {
            guard currencyCode.range(of: "^[A-Z]{3}$", options: .regularExpression) != nil else {
                throw ProtocolError.invalidField("appSettings.currencyCode")
            }
        }
    }
}

public struct SettingsPatch: Codable, Equatable, Sendable {
    public let provider: ProviderSettingsPatch?
    public let app: AppSettingsPatch?

    public init(provider: ProviderSettingsPatch? = nil, app: AppSettingsPatch? = nil) {
        self.provider = provider
        self.app = app
    }

    func validate() throws {
        guard provider != nil || app != nil else { throw ProtocolError.invalidField("settings.emptyPatch") }
        try provider?.validate(); try app?.validate()
    }
}

public struct SettingsSnapshot: Codable, Equatable, Sendable {
    public let draftID: UUID
    public let revision: String
    public let saved: ProviderSettingsValues
    public let applied: ProviderSettingsValues?
    public let concurrentRequestRange: IntegerRange
    public let residentSlotRange: IntegerRange
    public let restartRequired: Bool

    public init(
        draftID: UUID, revision: String, saved: ProviderSettingsValues,
        applied: ProviderSettingsValues?, concurrentRequestRange: IntegerRange = .init(minimum: 1, maximum: 24),
        residentSlotRange: IntegerRange = .init(minimum: 1, maximum: 2), restartRequired: Bool = false
    ) {
        self.draftID = draftID
        self.revision = revision
        self.saved = saved
        self.applied = applied
        self.concurrentRequestRange = concurrentRequestRange
        self.residentSlotRange = residentSlotRange
        self.restartRequired = restartRequired
    }

    func validate() throws {
        try requireBounded(revision, maximumBytes: ProtocolLimits.maximumOpaqueRevisionBytes, field: "settings.revision")
        try saved.validate(); try applied?.validate()
        guard concurrentRequestRange.minimum >= 1,
              concurrentRequestRange.maximum <= 24,
              concurrentRequestRange.minimum <= concurrentRequestRange.maximum,
              residentSlotRange.minimum >= 1,
              residentSlotRange.maximum <= ProtocolLimits.maximumResidentModelSlots,
              residentSlotRange.minimum <= residentSlotRange.maximum else {
            throw ProtocolError.invalidField("settings.range")
        }
    }
}

public struct SettingsDraftRequest: Codable, Equatable, Sendable {
    public init() {}
}

public struct SettingsPatchRequest: Codable, Equatable, Sendable {
    public let draftID: UUID
    public let expectedRevision: String
    public let patch: SettingsPatch
    public init(draftID: UUID, expectedRevision: String, patch: SettingsPatch) {
        self.draftID = draftID; self.expectedRevision = expectedRevision; self.patch = patch
    }
}

public struct SettingsSaveRequest: Codable, Equatable, Sendable {
    public let draftID: UUID
    public let expectedRevision: String
    public init(draftID: UUID, expectedRevision: String) {
        self.draftID = draftID; self.expectedRevision = expectedRevision
    }
}
