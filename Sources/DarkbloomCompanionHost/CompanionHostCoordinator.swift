import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import DarkbloomTelemetry
import Foundation

public protocol CompanionSnapshotProviding: Sendable {
    func snapshot(for deviceID: UUID, capabilities: Set<Capability>) async throws -> CompanionSnapshot
}

public actor FixtureSnapshotProvider: CompanionSnapshotProviding {
    private var value: CompanionSnapshot
    public init(_ value: CompanionSnapshot) { self.value = value }
    public func update(_ value: CompanionSnapshot) { self.value = value }
    public func snapshot(for deviceID: UUID, capabilities: Set<Capability>) -> CompanionSnapshot { value }
}

public actor CompanionHostCoordinator {
    public let hostID: UUID
    public let runtimeEpoch: UUID
    private let registry: any PairedDeviceRegistry
    private let pairing: PairingCoordinator
    private let authorization: CommandAuthorizationCoordinator
    private let dispatcher: any HostOperationDispatching
    private let settings: CompanionSettingsCoordinator
    private let snapshots: any CompanionSnapshotProviding
    private let audit: any CompanionAuditRecording
    private let alertHistory: (any AlertHistoryRecording)?

    public init(
        hostID: UUID,
        runtimeEpoch: UUID = UUID(),
        pairing: PairingCoordinator,
        registry: any PairedDeviceRegistry,
        authorization: CommandAuthorizationCoordinator,
        dispatcher: any HostOperationDispatching,
        settings: CompanionSettingsCoordinator,
        snapshots: any CompanionSnapshotProviding,
        audit: any CompanionAuditRecording = CompanionAuditLog(),
        alertHistory: (any AlertHistoryRecording)? = nil
    ) {
        self.hostID = hostID
        self.runtimeEpoch = runtimeEpoch
        self.pairing = pairing
        self.registry = registry
        self.authorization = authorization
        self.dispatcher = dispatcher
        self.settings = settings
        self.snapshots = snapshots
        self.audit = audit
        self.alertHistory = alertHistory
    }

    public func authenticate(_ value: SessionAuthentication, challenge: SessionChallenge) async -> Bool {
        guard value.nonce == challenge.nonce,
              let record = await registry.record(for: value.deviceID) else { return false }
        let transcript = SessionAuthentication.transcript(deviceID: value.deviceID, nonce: value.nonce)
        return CompanionTrust.verify(
            value.signature,
            message: transcript,
            certificateDER: record.identityCertificate
        )
    }

    public func handle(deviceID: UUID, envelope: Envelope) async -> Envelope {
        do {
            guard let record = await registry.record(for: deviceID) else {
                return failure(requestID: envelope.requestID, code: .unauthorized, reason: .revoked)
            }
            switch envelope.payload {
            case .monitorSubscribe:
                try require(.monitor, in: record)
                return Envelope(
                    requestID: envelope.requestID,
                    payload: .companionSnapshot(try await snapshots.snapshot(
                        for: deviceID, capabilities: record.device.capabilities
                    ))
                )
            case let .alertHistoryQuery(query):
                try require(.history, in: record)
                guard let alertHistory else {
                    return failure(requestID: envelope.requestID, code: .unavailable, reason: .sourceMissing)
                }
                let retained = try await alertHistory.recentHistory(limit: 2_000)
                let matching = retained
                    .filter { value in query.cursor.map { value.id < $0 } ?? true }
                    .sorted { $0.id > $1.id }
                let candidates = Array(matching.prefix(query.maximumRecords + 1))
                let hasOlder = candidates.count > query.maximumRecords
                let selected = Array(candidates.prefix(query.maximumRecords))
                let rows = selected.compactMap { value -> CompanionAlertRecord? in
                    guard let code = CompanionAlertCode(rawValue: value.code.rawValue),
                          let transition = CompanionAlertTransition(rawValue: value.kind.rawValue) else { return nil }
                    return CompanionAlertRecord(
                        id: value.id, code: code, transition: transition,
                        occurredAt: value.occurredAt,
                        observedDurationSeconds: value.observedDurationSeconds,
                        observationCount: value.observationCount
                    )
                }
                let cursor = hasOlder ? rows.last?.id : nil
                let page = try AlertHistoryPage.validated(hostID: hostID, records: rows, nextCursor: cursor)
                return Envelope(requestID: envelope.requestID, payload: .alertHistoryPage(page))
            case .settingsDraft:
                try require(.settingsRead, in: record)
                return Envelope(
                    requestID: envelope.requestID,
                    payload: .settingsSnapshot(try await settings.makeDraft())
                )
            case let .controlProposal(proposal):
                guard proposal.requestID == envelope.requestID else {
                    return failure(requestID: envelope.requestID, code: .malformedRequest, reason: nil)
                }
                let prepared = try await authorization.prepare(proposal, deviceID: deviceID)
                try await audit.append(.init(
                    at: .now, event: .prepared, deviceID: deviceID,
                    requestID: proposal.requestID, commandID: prepared.commandID,
                    actionType: Self.actionType(proposal.action)
                ))
                return Envelope(requestID: envelope.requestID, payload: .preparedCommand(prepared))
            case let .signedApproval(approval):
                let command = try await authorization.authorize(approval, deviceID: deviceID)
                try await audit.append(.init(
                    at: .now, event: .authorized, deviceID: deviceID,
                    requestID: command.proposal.requestID, commandID: command.commandID,
                    actionType: Self.actionType(command.proposal.action)
                ))
                let status = try await dispatcher.dispatch(command)
                try await audit.append(.init(
                    at: .now, event: status.state == .succeeded ? .succeeded : .failed,
                    deviceID: deviceID, requestID: command.proposal.requestID,
                    commandID: command.commandID, actionType: Self.actionType(command.proposal.action)
                ))
                return Envelope(requestID: envelope.requestID, payload: .operationStatus(status))
            case let .operationQuery(query):
                guard let status = await dispatcher.operation(query.operationID, deviceID: deviceID) else {
                    return failure(requestID: envelope.requestID, code: .notFound, reason: nil)
                }
                return Envelope(requestID: envelope.requestID, payload: .operationStatus(status))
            case let .deviceList(message) where message.mode == .request:
                try require(.deviceManagement, in: record)
                let devices = try await registry.records().map(\.device)
                return Envelope(
                    requestID: envelope.requestID,
                    payload: .deviceList(.init(mode: .response, devices: devices))
                )
            case let .deviceRevoke(request):
                guard request.deviceID == deviceID else {
                    return failure(requestID: envelope.requestID, code: .forbidden, reason: nil)
                }
                try await registry.revoke(deviceID)
                return Envelope(
                    requestID: envelope.requestID,
                    payload: .deviceRevokeResponse(.init(deviceID: deviceID))
                )
            case .settingsPatch, .settingsSave:
                return failure(requestID: envelope.requestID, code: .forbidden, reason: nil)
            default:
                return failure(requestID: envelope.requestID, code: .malformedRequest, reason: nil)
            }
        } catch let error as AuthorizationError {
            return failure(
                requestID: envelope.requestID,
                code: error == .revisionConflict ? .conflict :
                    (error == .tooManyPendingCommands ? .busy : .forbidden),
                reason: error == .expired ? .expired : nil
            )
        } catch let error as HostDispatchError where error == .busy {
            return failure(requestID: envelope.requestID, code: .busy, reason: .busy)
        } catch {
            return failure(requestID: envelope.requestID, code: .internalFailure, reason: .internalFailure)
        }
    }

    public func makeInvitation() async throws -> PairingInvitation { try await pairing.makeInvitation() }
    public func beginEnrollment(_ proof: EnrollmentProof) async throws -> PendingEnrollment {
        try await pairing.beginEnrollment(proof)
    }
    public func approveEnrollment(
        _ enrollmentID: UUID,
        capabilities: Set<Capability>
    ) async throws -> EnrollmentResult {
        try await pairing.approve(enrollmentID: enrollmentID, capabilities: capabilities)
    }

    public static func sessionTranscript(deviceID: UUID, nonce: Data) -> Data {
        SessionAuthentication.transcript(deviceID: deviceID, nonce: nonce)
    }

    private func require(_ capability: Capability, in record: PairedDeviceRecord) throws {
        guard record.device.capabilities.contains(capability) else {
            throw AuthorizationError.missingCapability(capability)
        }
    }

    private func failure(
        requestID: UUID,
        code: SafeErrorCode,
        reason: SafeReason?
    ) -> Envelope {
        Envelope(requestID: requestID, payload: .safeError(.init(code: code, reason: reason)))
    }

    private static func actionType(_ action: ControlAction) -> String {
        switch action {
        case let .providerLifecycle(value): "provider.\(value.rawValue)"
        case .applySavedModelsLive: "provider.applyLive"
        case .applySettings: "settings.patch"
        case .saveSettings: "settings.save"
        case let .appLifecycle(value): "app.\(value.rawValue)"
        }
    }
}
