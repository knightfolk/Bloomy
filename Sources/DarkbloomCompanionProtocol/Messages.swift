import Foundation

public enum SessionPhase: String, Codable, Equatable, Sendable { case bootstrap, authenticated }

public enum MessageType: String, Codable, CaseIterable, Equatable, Sendable {
    case pairingInvitation
    case enrollmentProof
    case pendingEnrollment
    case enrollmentResult
    case sessionChallenge
    case sessionAuthenticate
    case monitorSubscribe
    case companionSnapshot
    case historyQuery
    case historyPage
    case alertHistoryQuery
    case alertHistoryPage
    case settingsDraft
    case settingsSnapshot
    case settingsPatch
    case settingsSave
    case controlProposal
    case preparedCommand
    case signedApproval
    case operationQuery
    case operationStatus
    case deviceList
    case deviceRevoke
    case deviceRevokeResponse
    case safeError

    public var isBootstrapMessage: Bool {
        switch self {
        case .pairingInvitation, .enrollmentProof, .pendingEnrollment, .enrollmentResult, .safeError: true
        default: false
        }
    }

    var hasCommandSizeLimit: Bool {
        switch self {
        case .controlProposal, .preparedCommand, .signedApproval: true
        default: false
        }
    }
}

public enum RouteKind: String, Codable, Equatable, Sendable { case lan, tailnet }

public struct RouteCandidate: Codable, Equatable, Sendable {
    public let kind: RouteKind
    public let host: String
    public let port: UInt16
    public init(kind: RouteKind, host: String, port: UInt16) { self.kind = kind; self.host = host; self.port = port }

    func validate() throws {
        try requireBounded(host, maximumBytes: 255, field: "route.host")
        guard port > 0 else { throw ProtocolError.invalidField("route.port") }
    }
}

public struct PeerRouteHints: Codable, Equatable, Sendable {
    public let candidates: [RouteCandidate]
    public init(candidates: [RouteCandidate]) { self.candidates = candidates }
    func validate() throws {
        guard candidates.count <= ProtocolLimits.maximumRouteHints else { throw ProtocolError.invalidField("route.count") }
        for candidate in candidates { try candidate.validate() }
    }
}

public struct PairedHost: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let displayName: String
    public let routes: PeerRouteHints
    public let lastConnectedAt: Date?

    public init(hostID: UUID, displayName: String, routes: PeerRouteHints, lastConnectedAt: Date?) {
        self.hostID = hostID
        self.displayName = displayName
        self.routes = routes
        self.lastConnectedAt = lastConnectedAt
    }

    public func validate() throws {
        try requireBounded(displayName, maximumBytes: ProtocolLimits.maximumDisplayNameBytes, field: "host.displayName")
        try routes.validate()
    }
}

public struct PairingInvitation: Codable, Equatable, Sendable {
    public let hostID: UUID
    public let hostName: String
    public let invitationID: UUID
    public let invitationSecret: Data
    public let hostSPKIPin: Data
    public let expiresAt: Date
    public let routes: PeerRouteHints

    public init(
        hostID: UUID, hostName: String, invitationID: UUID, invitationSecret: Data,
        hostSPKIPin: Data, expiresAt: Date, routes: PeerRouteHints
    ) {
        self.hostID = hostID; self.hostName = hostName; self.invitationID = invitationID
        self.invitationSecret = invitationSecret; self.hostSPKIPin = hostSPKIPin
        self.expiresAt = expiresAt; self.routes = routes
    }

    func validate() throws {
        try requireBounded(hostName, maximumBytes: ProtocolLimits.maximumDisplayNameBytes, field: "invitation.hostName")
        guard (16...64).contains(invitationSecret.count), (32...128).contains(hostSPKIPin.count) else {
            throw ProtocolError.invalidField("invitation.keyMaterial")
        }
        try routes.validate()
    }
}

public struct EnrollmentProof: Codable, Equatable, Sendable {
    public let invitationID: UUID
    public let phoneID: UUID
    public let phoneName: String
    public let identityCertificate: Data
    public let approvalPublicKey: Data
    public let nonce: Data
    public let transcriptSignature: Data

    public init(
        invitationID: UUID, phoneID: UUID, phoneName: String, identityCertificate: Data,
        approvalPublicKey: Data, nonce: Data, transcriptSignature: Data
    ) {
        self.invitationID = invitationID; self.phoneID = phoneID; self.phoneName = phoneName
        self.identityCertificate = identityCertificate; self.approvalPublicKey = approvalPublicKey
        self.nonce = nonce; self.transcriptSignature = transcriptSignature
    }

    func validate() throws {
        try requireBounded(phoneName, maximumBytes: ProtocolLimits.maximumDisplayNameBytes, field: "enrollment.phoneName")
        for (value, field) in [
            (identityCertificate, "enrollment.identityCertificate"),
            (approvalPublicKey, "enrollment.approvalPublicKey"),
            (nonce, "enrollment.nonce"),
            (transcriptSignature, "enrollment.transcriptSignature"),
        ] {
            guard !value.isEmpty, value.count <= ProtocolLimits.maximumBinaryFieldBytes else {
                throw ProtocolError.invalidField(field)
            }
        }
    }
}

public struct PendingEnrollment: Codable, Equatable, Sendable {
    public let enrollmentID: UUID
    public let phoneID: UUID
    public let comparisonCode: String
    public let expiresAt: Date
    public init(enrollmentID: UUID, phoneID: UUID, comparisonCode: String, expiresAt: Date) {
        self.enrollmentID = enrollmentID; self.phoneID = phoneID
        self.comparisonCode = comparisonCode; self.expiresAt = expiresAt
    }
    func validate() throws {
        guard comparisonCode.range(of: "^[0-9]{6}$", options: .regularExpression) != nil else {
            throw ProtocolError.invalidField("enrollment.comparisonCode")
        }
    }
}

public struct PairedDevice: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let displayName: String
    public let capabilities: Set<Capability>
    public let enrolledAt: Date
    public init(deviceID: UUID, displayName: String, capabilities: Set<Capability>, enrolledAt: Date) {
        self.deviceID = deviceID; self.displayName = displayName
        self.capabilities = capabilities; self.enrolledAt = enrolledAt
    }
    func validate() throws {
        try requireBounded(displayName, maximumBytes: ProtocolLimits.maximumDisplayNameBytes, field: "device.displayName")
    }


    private enum CodingKeys: String, CodingKey { case deviceID, displayName, capabilities, enrolledAt }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceID = try container.decode(UUID.self, forKey: .deviceID)
        displayName = try container.decode(String.self, forKey: .displayName)
        capabilities = Set(try container.decode([Capability].self, forKey: .capabilities))
        enrolledAt = try container.decode(Date.self, forKey: .enrolledAt)
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(deviceID, forKey: .deviceID)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(capabilities.sorted { $0.rawValue < $1.rawValue }, forKey: .capabilities)
        try container.encode(enrolledAt, forKey: .enrolledAt)
    }
}

public struct EnrollmentResult: Codable, Equatable, Sendable {
    public let device: PairedDevice
    public let policyEpoch: UInt64
    public init(device: PairedDevice, policyEpoch: UInt64) { self.device = device; self.policyEpoch = policyEpoch }
}

public struct SessionChallenge: Codable, Equatable, Sendable {
    public let nonce: Data
    public let expiresAt: Date
    public init(nonce: Data, expiresAt: Date) { self.nonce = nonce; self.expiresAt = expiresAt }
    func validate() throws {
        guard (16...128).contains(nonce.count) else { throw ProtocolError.invalidField("session.nonce") }
    }
}

public struct SessionAuthentication: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public let nonce: Data
    public let signature: Data
    public init(deviceID: UUID, nonce: Data, signature: Data) {
        self.deviceID = deviceID; self.nonce = nonce; self.signature = signature
    }
    func validate() throws {
        guard (16...128).contains(nonce.count),
              !signature.isEmpty,
              signature.count <= ProtocolLimits.maximumBinaryFieldBytes else {
            throw ProtocolError.invalidField("session.authentication")
        }
    }

    public static func transcript(deviceID: UUID, nonce: Data) -> Data {
        var data = Data("darkbloom-companion-session-v1\0".utf8)
        data.append(Data(deviceID.uuidString.lowercased().utf8))
        data.append(0)
        data.append(nonce)
        return data
    }
}

public enum DeviceListMode: String, Codable, Equatable, Sendable { case request, response }
public struct DeviceListMessage: Codable, Equatable, Sendable {
    public let mode: DeviceListMode
    public let devices: [PairedDevice]
    public init(mode: DeviceListMode, devices: [PairedDevice] = []) { self.mode = mode; self.devices = devices }
    func validate() throws {
        guard devices.count <= ProtocolLimits.maximumDevices else { throw ProtocolError.invalidField("device.count") }
        guard mode == .response || devices.isEmpty else { throw ProtocolError.invalidField("device.requestList") }
        for device in devices { try device.validate() }
    }
}

public struct DeviceRevokeRequest: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public init(deviceID: UUID) { self.deviceID = deviceID }
}

public struct DeviceRevokeResponse: Codable, Equatable, Sendable {
    public let deviceID: UUID
    public init(deviceID: UUID) { self.deviceID = deviceID }
}

public enum SafeErrorCode: String, Codable, Equatable, Sendable {
    case malformedRequest
    case unsupportedVersion
    case unauthorized
    case forbidden
    case notFound
    case busy
    case conflict
    case expired
    case rateLimited
    case unavailable
    case internalFailure
}

public struct SafeErrorResponse: Codable, Equatable, Sendable {
    public let code: SafeErrorCode
    public let reason: SafeReason?
    public let retryAfterSeconds: UInt16?
    public init(code: SafeErrorCode, reason: SafeReason? = nil, retryAfterSeconds: UInt16? = nil) {
        self.code = code; self.reason = reason; self.retryAfterSeconds = retryAfterSeconds
    }
}

public enum EnvelopePayload: Equatable, Sendable {
    case pairingInvitation(PairingInvitation)
    case enrollmentProof(EnrollmentProof)
    case pendingEnrollment(PendingEnrollment)
    case enrollmentResult(EnrollmentResult)
    case sessionChallenge(SessionChallenge)
    case sessionAuthenticate(SessionAuthentication)
    case monitorSubscribe(MonitorSubscription)
    case companionSnapshot(CompanionSnapshot)
    case historyQuery(HistoryQuery)
    case historyPage(HistoryPage)
    case alertHistoryQuery(AlertHistoryQuery)
    case alertHistoryPage(AlertHistoryPage)
    case settingsDraft(SettingsDraftRequest)
    case settingsSnapshot(SettingsSnapshot)
    case settingsPatch(SettingsPatchRequest)
    case settingsSave(SettingsSaveRequest)
    case controlProposal(ControlProposal)
    case preparedCommand(PreparedCommand)
    case signedApproval(SignedApproval)
    case operationQuery(OperationQuery)
    case operationStatus(OperationStatus)
    case deviceList(DeviceListMessage)
    case deviceRevoke(DeviceRevokeRequest)
    case deviceRevokeResponse(DeviceRevokeResponse)
    case safeError(SafeErrorResponse)

    public var messageType: MessageType {
        switch self {
        case .pairingInvitation: .pairingInvitation
        case .enrollmentProof: .enrollmentProof
        case .pendingEnrollment: .pendingEnrollment
        case .enrollmentResult: .enrollmentResult
        case .sessionChallenge: .sessionChallenge
        case .sessionAuthenticate: .sessionAuthenticate
        case .monitorSubscribe: .monitorSubscribe
        case .companionSnapshot: .companionSnapshot
        case .historyQuery: .historyQuery
        case .historyPage: .historyPage
        case .alertHistoryQuery: .alertHistoryQuery
        case .alertHistoryPage: .alertHistoryPage
        case .settingsDraft: .settingsDraft
        case .settingsSnapshot: .settingsSnapshot
        case .settingsPatch: .settingsPatch
        case .settingsSave: .settingsSave
        case .controlProposal: .controlProposal
        case .preparedCommand: .preparedCommand
        case .signedApproval: .signedApproval
        case .operationQuery: .operationQuery
        case .operationStatus: .operationStatus
        case .deviceList: .deviceList
        case .deviceRevoke: .deviceRevoke
        case .deviceRevokeResponse: .deviceRevokeResponse
        case .safeError: .safeError
        }
    }

    func validate() throws {
        switch self {
        case let .pairingInvitation(value): try value.validate()
        case let .enrollmentProof(value): try value.validate()
        case let .pendingEnrollment(value): try value.validate()
        case let .enrollmentResult(value): try value.device.validate()
        case let .sessionChallenge(value): try value.validate()
        case let .sessionAuthenticate(value): try value.validate()
        case let .monitorSubscribe(value):
            guard (1...300).contains(value.minimumIntervalSeconds) else { throw ProtocolError.invalidField("subscription.interval") }
        case let .companionSnapshot(value): try value.validate()
        case let .historyQuery(value): try value.validate()
        case let .historyPage(value): try value.validate()
        case let .alertHistoryQuery(value): try value.validate()
        case let .alertHistoryPage(value): try value.validate()
        case .settingsDraft: break
        case let .settingsSnapshot(value): try value.validate()
        case let .settingsPatch(value):
            try requireBounded(value.expectedRevision, maximumBytes: ProtocolLimits.maximumOpaqueRevisionBytes, field: "settings.expectedRevision")
            try value.patch.validate()
        case let .settingsSave(value):
            try requireBounded(value.expectedRevision, maximumBytes: ProtocolLimits.maximumOpaqueRevisionBytes, field: "settings.expectedRevision")
        case let .controlProposal(value): try value.validate()
        case let .preparedCommand(value): try value.validate()
        case let .signedApproval(value): try value.validate()
        case .operationQuery: break
        case let .operationStatus(value): try value.validate()
        case let .deviceList(value): try value.validate()
        case .deviceRevoke, .deviceRevokeResponse, .safeError: break
        }
    }
}

public struct Envelope: Codable, Equatable, Sendable {
    public let protocolMajor: UInt16
    public let messageType: MessageType
    public let requestID: UUID
    public let payload: EnvelopePayload

    public init(
        protocolMajor: UInt16 = ProtocolLimits.currentMajor,
        requestID: UUID,
        payload: EnvelopePayload
    ) {
        self.protocolMajor = protocolMajor
        self.messageType = payload.messageType
        self.requestID = requestID
        self.payload = payload
    }

    public func validate(for phase: SessionPhase? = nil) throws {
        guard protocolMajor == ProtocolLimits.currentMajor else { throw ProtocolError.unsupportedMajor(protocolMajor) }
        guard messageType == payload.messageType else { throw ProtocolError.payloadTypeMismatch(messageType) }
        if case let .controlProposal(proposal) = payload, proposal.requestID != requestID {
            throw ProtocolError.invalidField("command.requestID")
        }
        if let phase {
            switch phase {
            case .bootstrap:
                guard messageType.isBootstrapMessage else { throw ProtocolError.messageNotAllowed(messageType, phase) }
            case .authenticated:
                guard !messageType.isBootstrapMessage || messageType == .safeError else {
                    throw ProtocolError.messageNotAllowed(messageType, phase)
                }
            }
        }
        try payload.validate()
    }

    private enum CodingKeys: String, CodingKey { case protocolMajor, messageType, requestID, payload }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        protocolMajor = try container.decode(UInt16.self, forKey: .protocolMajor)
        guard protocolMajor == ProtocolLimits.currentMajor else { throw ProtocolError.unsupportedMajor(protocolMajor) }
        let rawType = try container.decode(String.self, forKey: .messageType)
        guard let type = MessageType(rawValue: rawType) else { throw ProtocolError.unknownMessageType(rawType) }
        messageType = type
        requestID = try container.decode(UUID.self, forKey: .requestID)
        switch type {
        case .pairingInvitation: payload = .pairingInvitation(try container.decode(PairingInvitation.self, forKey: .payload))
        case .enrollmentProof: payload = .enrollmentProof(try container.decode(EnrollmentProof.self, forKey: .payload))
        case .pendingEnrollment: payload = .pendingEnrollment(try container.decode(PendingEnrollment.self, forKey: .payload))
        case .enrollmentResult: payload = .enrollmentResult(try container.decode(EnrollmentResult.self, forKey: .payload))
        case .sessionChallenge: payload = .sessionChallenge(try container.decode(SessionChallenge.self, forKey: .payload))
        case .sessionAuthenticate: payload = .sessionAuthenticate(try container.decode(SessionAuthentication.self, forKey: .payload))
        case .monitorSubscribe: payload = .monitorSubscribe(try container.decode(MonitorSubscription.self, forKey: .payload))
        case .companionSnapshot: payload = .companionSnapshot(try container.decode(CompanionSnapshot.self, forKey: .payload))
        case .historyQuery: payload = .historyQuery(try container.decode(HistoryQuery.self, forKey: .payload))
        case .historyPage: payload = .historyPage(try container.decode(HistoryPage.self, forKey: .payload))
        case .alertHistoryQuery: payload = .alertHistoryQuery(try container.decode(AlertHistoryQuery.self, forKey: .payload))
        case .alertHistoryPage: payload = .alertHistoryPage(try container.decode(AlertHistoryPage.self, forKey: .payload))
        case .settingsDraft: payload = .settingsDraft(try container.decode(SettingsDraftRequest.self, forKey: .payload))
        case .settingsSnapshot: payload = .settingsSnapshot(try container.decode(SettingsSnapshot.self, forKey: .payload))
        case .settingsPatch: payload = .settingsPatch(try container.decode(SettingsPatchRequest.self, forKey: .payload))
        case .settingsSave: payload = .settingsSave(try container.decode(SettingsSaveRequest.self, forKey: .payload))
        case .controlProposal: payload = .controlProposal(try container.decode(ControlProposal.self, forKey: .payload))
        case .preparedCommand: payload = .preparedCommand(try container.decode(PreparedCommand.self, forKey: .payload))
        case .signedApproval: payload = .signedApproval(try container.decode(SignedApproval.self, forKey: .payload))
        case .operationQuery: payload = .operationQuery(try container.decode(OperationQuery.self, forKey: .payload))
        case .operationStatus: payload = .operationStatus(try container.decode(OperationStatus.self, forKey: .payload))
        case .deviceList: payload = .deviceList(try container.decode(DeviceListMessage.self, forKey: .payload))
        case .deviceRevoke: payload = .deviceRevoke(try container.decode(DeviceRevokeRequest.self, forKey: .payload))
        case .deviceRevokeResponse: payload = .deviceRevokeResponse(try container.decode(DeviceRevokeResponse.self, forKey: .payload))
        case .safeError: payload = .safeError(try container.decode(SafeErrorResponse.self, forKey: .payload))
        }
        try validate()
    }

    public func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(protocolMajor, forKey: .protocolMajor)
        try container.encode(messageType.rawValue, forKey: .messageType)
        try container.encode(requestID, forKey: .requestID)
        switch payload {
        case let .pairingInvitation(value): try container.encode(value, forKey: .payload)
        case let .enrollmentProof(value): try container.encode(value, forKey: .payload)
        case let .pendingEnrollment(value): try container.encode(value, forKey: .payload)
        case let .enrollmentResult(value): try container.encode(value, forKey: .payload)
        case let .sessionChallenge(value): try container.encode(value, forKey: .payload)
        case let .sessionAuthenticate(value): try container.encode(value, forKey: .payload)
        case let .monitorSubscribe(value): try container.encode(value, forKey: .payload)
        case let .companionSnapshot(value): try container.encode(value, forKey: .payload)
        case let .historyQuery(value): try container.encode(value, forKey: .payload)
        case let .historyPage(value): try container.encode(value, forKey: .payload)
        case let .alertHistoryQuery(value): try container.encode(value, forKey: .payload)
        case let .alertHistoryPage(value): try container.encode(value, forKey: .payload)
        case let .settingsDraft(value): try container.encode(value, forKey: .payload)
        case let .settingsSnapshot(value): try container.encode(value, forKey: .payload)
        case let .settingsPatch(value): try container.encode(value, forKey: .payload)
        case let .settingsSave(value): try container.encode(value, forKey: .payload)
        case let .controlProposal(value): try container.encode(value, forKey: .payload)
        case let .preparedCommand(value): try container.encode(value, forKey: .payload)
        case let .signedApproval(value): try container.encode(value, forKey: .payload)
        case let .operationQuery(value): try container.encode(value, forKey: .payload)
        case let .operationStatus(value): try container.encode(value, forKey: .payload)
        case let .deviceList(value): try container.encode(value, forKey: .payload)
        case let .deviceRevoke(value): try container.encode(value, forKey: .payload)
        case let .deviceRevokeResponse(value): try container.encode(value, forKey: .payload)
        case let .safeError(value): try container.encode(value, forKey: .payload)
        }
    }
}
