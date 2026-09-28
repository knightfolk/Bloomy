import CryptoKit
import DarkbloomCompanionProtocol
import Foundation

public enum AuthorizationError: Error, Equatable, Sendable {
    case revoked
    case missingCapability(Capability)
    case revisionConflict
    case expired
    case unknownCommand
    case wrongDevice
    case signedPayloadMismatch
    case invalidSignature
    case replayed
    case policyChanged
    case tooManyPendingCommands
}

public struct AuthorizedCommand: Equatable, Sendable {
    public let commandID: UUID
    public let proposal: ControlProposal
    public let deviceID: UUID

    public init(commandID: UUID, proposal: ControlProposal, deviceID: UUID) {
        self.commandID = commandID
        self.proposal = proposal
        self.deviceID = deviceID
    }
}

public actor CommandAuthorizationCoordinator {
    private struct Stored: Sendable {
        let prepared: PreparedCommand
        let proposal: ControlProposal
    }

    private let hostID: UUID
    private var runtimeEpoch: UUID
    private let registry: any PairedDeviceRegistry
    private let revision: @Sendable () async -> String?
    private let now: @Sendable () -> Date
    private var prepared: [UUID: Stored] = [:]
    private var used: Set<UUID> = []
    private var usedOrder: [UUID] = []
    private let maximumPrepared = 128
    private let maximumRecentApprovals = 1_024

    public init(
        hostID: UUID,
        runtimeEpoch: UUID,
        registry: any PairedDeviceRegistry,
        revision: @escaping @Sendable () async -> String?,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hostID = hostID
        self.runtimeEpoch = runtimeEpoch
        self.registry = registry
        self.revision = revision
        self.now = now
    }

    public func prepare(_ proposal: ControlProposal, deviceID: UUID) async throws -> PreparedCommand {
        discardExpiredPreparedCommands()
        guard prepared.count < maximumPrepared else { throw AuthorizationError.tooManyPendingCommands }
        guard let record = await registry.record(for: deviceID) else { throw AuthorizationError.revoked }
        let capability = requiredCapability(for: proposal.action)
        guard record.device.capabilities.contains(capability) else {
            throw AuthorizationError.missingCapability(capability)
        }
        let currentRevision = await revision()
        if let expected = proposal.expectedRevision, expected != currentRevision {
            throw AuthorizationError.revisionConflict
        }
        let commandID = UUID()
        let epoch = await registry.policyEpoch
        let nonce = randomBytes(count: 32)
        let expiry = now().addingTimeInterval(60)
        let payload = try signedBytes(
            commandID: commandID, proposal: proposal, deviceID: deviceID,
            policyEpoch: epoch, nonce: nonce, expiresAt: expiry
        )
        let result = PreparedCommand(
            commandID: commandID,
            requestID: proposal.requestID,
            hostID: hostID,
            deviceID: deviceID,
            runtimeEpoch: runtimeEpoch,
            action: proposal.action,
            risk: risk(for: proposal.action),
            expectedRevision: proposal.expectedRevision,
            policyEpoch: epoch,
            nonce: nonce,
            expiresAt: expiry,
            signedPayload: payload
        )
        prepared[commandID] = Stored(prepared: result, proposal: proposal)
        return result
    }

    public func authorize(_ approval: SignedApproval, deviceID: UUID) async throws -> AuthorizedCommand {
        guard !used.contains(approval.commandID) else { throw AuthorizationError.replayed }
        guard let stored = prepared[approval.commandID] else { throw AuthorizationError.unknownCommand }
        guard stored.prepared.deviceID == deviceID else { throw AuthorizationError.wrongDevice }
        guard approval.signedPayload == stored.prepared.signedPayload else {
            throw AuthorizationError.signedPayloadMismatch
        }
        guard now() <= stored.prepared.expiresAt else {
            prepared[approval.commandID] = nil
            throw AuthorizationError.expired
        }
        guard let record = await registry.record(for: deviceID) else { throw AuthorizationError.revoked }
        guard await registry.policyEpoch == stored.prepared.policyEpoch else {
            throw AuthorizationError.policyChanged
        }
        let capability = requiredCapability(for: stored.proposal.action)
        guard record.device.capabilities.contains(capability) else {
            throw AuthorizationError.missingCapability(capability)
        }
        let currentRevision = await revision()
        if let expected = stored.proposal.expectedRevision, expected != currentRevision {
            throw AuthorizationError.revisionConflict
        }
        guard let key = try? P256.Signing.PublicKey(x963Representation: record.approvalPublicKey),
              let signature = try? P256.Signing.ECDSASignature(derRepresentation: approval.signature),
              key.isValidSignature(signature, for: approval.signedPayload) else {
            throw AuthorizationError.invalidSignature
        }
        prepared[approval.commandID] = nil
        used.insert(approval.commandID)
        usedOrder.append(approval.commandID)
        if usedOrder.count > maximumRecentApprovals {
            used.remove(usedOrder.removeFirst())
        }
        return AuthorizedCommand(
            commandID: approval.commandID,
            proposal: stored.proposal,
            deviceID: deviceID
        )
    }

    public func rotateRuntimeEpoch() {
        runtimeEpoch = UUID()
        prepared.removeAll()
        used.removeAll()
        usedOrder.removeAll()
    }

    private func discardExpiredPreparedCommands() {
        let current = now()
        prepared = prepared.filter { current <= $0.value.prepared.expiresAt }
    }

    private func signedBytes(
        commandID: UUID,
        proposal: ControlProposal,
        deviceID: UUID,
        policyEpoch: UInt64,
        nonce: Data,
        expiresAt: Date
    ) throws -> Data {
        struct Payload: Encodable {
            let domain: String
            let commandID: UUID
            let proposal: ControlProposal
            let hostID: UUID
            let deviceID: UUID
            let runtimeEpoch: UUID
            let policyEpoch: UInt64
            let nonce: Data
            let expiresAtMilliseconds: Int64
        }
        let milliseconds = Int64((expiresAt.timeIntervalSince1970 * 1_000).rounded(.down))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(Payload(
            domain: "darkbloom-companion-command-v1",
            commandID: commandID,
            proposal: proposal,
            hostID: hostID,
            deviceID: deviceID,
            runtimeEpoch: runtimeEpoch,
            policyEpoch: policyEpoch,
            nonce: nonce,
            expiresAtMilliseconds: milliseconds
        ))
    }

    private func requiredCapability(for action: ControlAction) -> Capability {
        switch action {
        case .providerLifecycle: .providerLifecycle
        case .applySavedModelsLive: .providerLiveSwitch
        case .applySettings, .saveSettings: .settingsWrite
        case .appLifecycle: .appLifecycle
        }
    }

    private func risk(for action: ControlAction) -> CommandRisk {
        switch action {
        case .providerLifecycle(.stop): .stopsProvider
        case .providerLifecycle(.restart): .restartsProvider
        case .providerLifecycle(.start): .configurationChange
        case .applySavedModelsLive: .interruptsActiveWork
        case .applySettings, .saveSettings: .configurationChange
        case .appLifecycle(.quit): .quitsMacApp
        case .appLifecycle(.open), .appLifecycle(.relaunch): .configurationChange
        }
    }

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
