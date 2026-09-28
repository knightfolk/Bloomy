import DarkbloomCompanionProtocol
import Foundation

public actor CompanionClientSession {
    private let connection: CompanionTLSConnection
    private let deviceID: UUID
    private var nextRequest: UInt64 = 0

    public static func connect(
        route: RouteCandidate,
        identity: CompanionIdentity,
        expectedHostSPKI: Data,
        deviceID: UUID
    ) async throws -> CompanionClientSession {
        let connection = try await CompanionTLSConnection.connect(
            host: route.host,
            port: route.port,
            identity: identity,
            expectedHostSPKI: expectedHostSPKI
        )
        let challengeEnvelope = try await connection.receiveEnvelope()
        guard case let .sessionChallenge(challenge) = challengeEnvelope.payload,
              Date() <= challenge.expiresAt else { throw CompanionTransportError.invalidTLS }
        let signature = try identity.sign(SessionAuthentication.transcript(
            deviceID: deviceID, nonce: challenge.nonce
        ))
        try await connection.sendEnvelope(.init(
            requestID: challengeEnvelope.requestID,
            payload: .sessionAuthenticate(.init(
                deviceID: deviceID, nonce: challenge.nonce, signature: signature
            ))
        ))
        return CompanionClientSession(connection: connection, deviceID: deviceID)
    }

    private init(connection: CompanionTLSConnection, deviceID: UUID) {
        self.connection = connection
        self.deviceID = deviceID
    }

    public func request(_ payload: EnvelopePayload, timeout: TimeInterval = 10) async throws -> Envelope {
        let requestID = UUID()
        let envelope = Envelope(requestID: requestID, payload: payload)
        try await connection.sendEnvelope(envelope, timeout: timeout)
        let response = try await connection.receiveEnvelope(timeout: timeout)
        guard response.requestID == requestID else { throw CompanionTransportError.invalidTLS }
        return response
    }

    public func close() { connection.cancel() }
}

public enum CompanionEnrollmentClient {
    public static func submit(
        invitation: PairingInvitation,
        identity: CompanionIdentity,
        proof: EnrollmentProof
    ) async throws -> PendingEnrollment {
        guard let route = invitation.routes.candidates.first else {
            throw CompanionTransportError.invalidEndpoint
        }
        let connection = try await CompanionTLSConnection.connect(
            host: route.host, port: route.port, identity: identity,
            expectedHostSPKI: invitation.hostSPKIPin
        )
        defer { connection.cancel() }
        let challenge = try await connection.receiveEnvelope()
        guard case .sessionChallenge = challenge.payload else { throw CompanionTransportError.invalidTLS }
        try await connection.sendEnvelope(.init(
            requestID: UUID(), payload: .enrollmentProof(proof)
        ))
        let response = try await connection.receiveEnvelope()
        guard case let .pendingEnrollment(value) = response.payload else {
            throw CompanionTransportError.invalidTLS
        }
        return value
    }
}
