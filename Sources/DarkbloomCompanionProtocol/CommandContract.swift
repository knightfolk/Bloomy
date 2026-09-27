import Foundation

public enum ProviderLifecycleAction: String, Codable, Equatable, Sendable { case start, stop, restart }
public enum AppLifecycleAction: String, Codable, Equatable, Sendable { case open, quit, relaunch }

public enum ControlAction: Equatable, Sendable {
    case providerLifecycle(ProviderLifecycleAction)
    case applySavedModelsLive
    case applySettings(draftID: UUID, patch: SettingsPatch)
    case saveSettings(draftID: UUID)
    case appLifecycle(AppLifecycleAction)
}

extension ControlAction: Codable {
    private enum CodingKeys: String, CodingKey { case type, action, draftID, patch }
    private enum Kind: String, Codable {
        case providerLifecycle, applySavedModelsLive, applySettings, saveSettings, appLifecycle
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .type)
        guard let kind = Kind(rawValue: raw) else { throw ProtocolError.unknownCommand(raw) }
        switch kind {
        case .providerLifecycle:
            self = .providerLifecycle(try container.decode(ProviderLifecycleAction.self, forKey: .action))
        case .applySavedModelsLive:
            self = .applySavedModelsLive
        case .applySettings:
            self = .applySettings(
                draftID: try container.decode(UUID.self, forKey: .draftID),
                patch: try container.decode(SettingsPatch.self, forKey: .patch)
            )
        case .saveSettings:
            self = .saveSettings(draftID: try container.decode(UUID.self, forKey: .draftID))
        case .appLifecycle:
            self = .appLifecycle(try container.decode(AppLifecycleAction.self, forKey: .action))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .providerLifecycle(action):
            try container.encode(Kind.providerLifecycle, forKey: .type)
            try container.encode(action, forKey: .action)
        case .applySavedModelsLive:
            try container.encode(Kind.applySavedModelsLive, forKey: .type)
        case let .applySettings(draftID, patch):
            try container.encode(Kind.applySettings, forKey: .type)
            try container.encode(draftID, forKey: .draftID)
            try container.encode(patch, forKey: .patch)
        case let .saveSettings(draftID):
            try container.encode(Kind.saveSettings, forKey: .type)
            try container.encode(draftID, forKey: .draftID)
        case let .appLifecycle(action):
            try container.encode(Kind.appLifecycle, forKey: .type)
            try container.encode(action, forKey: .action)
        }
    }

    func validate() throws {
        if case let .applySettings(_, patch) = self { try patch.validate() }
    }
}

public struct ControlProposal: Codable, Equatable, Sendable {
    public let requestID: UUID
    public let expectedRevision: String?
    public let action: ControlAction

    public init(requestID: UUID, expectedRevision: String? = nil, action: ControlAction) {
        self.requestID = requestID
        self.expectedRevision = expectedRevision
        self.action = action
    }

    func validate() throws {
        if let expectedRevision {
            try requireBounded(expectedRevision, maximumBytes: ProtocolLimits.maximumOpaqueRevisionBytes, field: "command.expectedRevision")
        }
        try action.validate()
    }
}

public enum CommandRisk: String, Codable, Equatable, Sendable {
    case configurationChange
    case restartsProvider
    case interruptsActiveWork
    case stopsProvider
    case quitsMacApp
}

public struct PreparedCommand: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let requestID: UUID
    public let hostID: UUID
    public let deviceID: UUID
    public let runtimeEpoch: UUID
    public let action: ControlAction
    public let risk: CommandRisk
    public let expectedRevision: String?
    public let policyEpoch: UInt64
    public let nonce: Data
    public let expiresAt: Date
    public let signedPayload: Data

    public init(
        commandID: UUID, requestID: UUID, hostID: UUID, deviceID: UUID, runtimeEpoch: UUID,
        action: ControlAction, risk: CommandRisk, expectedRevision: String?, policyEpoch: UInt64,
        nonce: Data, expiresAt: Date, signedPayload: Data
    ) {
        self.commandID = commandID; self.requestID = requestID; self.hostID = hostID
        self.deviceID = deviceID; self.runtimeEpoch = runtimeEpoch; self.action = action
        self.risk = risk; self.expectedRevision = expectedRevision; self.policyEpoch = policyEpoch
        self.nonce = nonce; self.expiresAt = expiresAt; self.signedPayload = signedPayload
    }

    func validate() throws {
        try action.validate()
        guard (16...128).contains(nonce.count) else { throw ProtocolError.invalidField("command.nonce") }
        guard !signedPayload.isEmpty, signedPayload.count <= ProtocolLimits.maximumSignedPayloadBytes else {
            throw ProtocolError.invalidField("command.signedPayload")
        }
        if let expectedRevision {
            try requireBounded(expectedRevision, maximumBytes: ProtocolLimits.maximumOpaqueRevisionBytes, field: "command.expectedRevision")
        }
    }
}

public struct SignedApproval: Codable, Equatable, Sendable {
    public let commandID: UUID
    public let signedPayload: Data
    public let signature: Data
    public init(commandID: UUID, signedPayload: Data, signature: Data) {
        self.commandID = commandID; self.signedPayload = signedPayload; self.signature = signature
    }

    func validate() throws {
        guard !signedPayload.isEmpty, signedPayload.count <= ProtocolLimits.maximumSignedPayloadBytes,
              !signature.isEmpty, signature.count <= ProtocolLimits.maximumBinaryFieldBytes else {
            throw ProtocolError.invalidField("approval.bytes")
        }
    }
}

public enum OperationState: String, Codable, Equatable, Sendable {
    case accepted
    case mutating
    case reconciling
    case draining
    case succeeded
    case failed
    case outcomeUncertain
}

public struct OperationStatus: Codable, Equatable, Sendable {
    public let operationID: UUID
    public let requestID: UUID
    public let commandID: UUID
    public let state: OperationState
    public let progress: Double?
    public let error: SafeErrorResponse?
    public let updatedAt: Date

    public init(
        operationID: UUID, requestID: UUID, commandID: UUID, state: OperationState,
        progress: Double?, error: SafeErrorResponse?, updatedAt: Date
    ) {
        self.operationID = operationID; self.requestID = requestID; self.commandID = commandID
        self.state = state; self.progress = progress; self.error = error; self.updatedAt = updatedAt
    }

    func validate() throws {
        if let progress, (!progress.isFinite || !(0...1).contains(progress)) {
            throw ProtocolError.invalidField("operation.progress")
        }
    }
}

public struct OperationQuery: Codable, Equatable, Sendable {
    public let operationID: UUID
    public init(operationID: UUID) { self.operationID = operationID }
}
