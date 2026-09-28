import CryptoKit
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import Foundation

public enum PairingError: Error, Equatable, Sendable {
    case invitationUnavailable
    case invitationExpired
    case invalidProof
    case tooManyAttempts
    case enrollmentUnavailable
    case enrollmentExpired
    case malformedQRCode
    case qrCodeTooLarge
}

public actor PairingCoordinator {
    private struct InvitationState {
        let invitation: PairingInvitation
        var failures = 0
        var enrollmentID: UUID?
    }
    private struct PendingState {
        let pending: PendingEnrollment
        let proof: EnrollmentProof
        let invitationID: UUID
    }

    private let hostID: UUID
    private let hostName: String
    private let hostSPKIPin: Data
    private let routes: PeerRouteHints
    private let registry: any PairedDeviceRegistry
    private let now: @Sendable () -> Date
    private var activeInvitation: InvitationState?
    private var pending: [UUID: PendingState] = [:]

    public init(
        hostID: UUID,
        hostName: String,
        hostSPKIPin: Data,
        routes: PeerRouteHints,
        registry: any PairedDeviceRegistry,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hostID = hostID
        self.hostName = hostName
        self.hostSPKIPin = hostSPKIPin
        self.routes = routes
        self.registry = registry
        self.now = now
    }

    public func makeInvitation() throws -> PairingInvitation {
        let invitation = PairingInvitation(
            hostID: hostID,
            hostName: hostName,
            invitationID: UUID(),
            invitationSecret: randomBytes(count: 32),
            hostSPKIPin: hostSPKIPin,
            expiresAt: now().addingTimeInterval(120),
            routes: routes
        )
        _ = try PairingQRCode.encode(invitation)
        pending.removeAll()
        activeInvitation = InvitationState(invitation: invitation)
        return invitation
    }

    public func beginEnrollment(_ proof: EnrollmentProof) throws -> PendingEnrollment {
        guard var state = activeInvitation,
              state.invitation.invitationID == proof.invitationID else {
            throw PairingError.invitationUnavailable
        }
        guard now() <= state.invitation.expiresAt else {
            activeInvitation = nil
            throw PairingError.invitationExpired
        }
        guard state.enrollmentID == nil else { throw PairingError.invitationUnavailable }
        let transcript = try EnrollmentProof.transcript(invitation: state.invitation, proof: proof)
        guard CompanionTrust.validate(certificateDER: proof.identityCertificate, role: .phone, now: now()),
              CompanionTrust.verify(proof.transcriptSignature, message: transcript, certificateDER: proof.identityCertificate),
              (try? P256.Signing.PublicKey(x963Representation: proof.approvalPublicKey)) != nil else {
            state.failures += 1
            activeInvitation = state.failures >= 5 ? nil : state
            throw state.failures >= 5 ? PairingError.tooManyAttempts : PairingError.invalidProof
        }
        let enrollmentID = UUID()
        let code = comparisonCode(for: transcript)
        let value = PendingEnrollment(
            enrollmentID: enrollmentID,
            phoneID: proof.phoneID,
            comparisonCode: code,
            expiresAt: min(state.invitation.expiresAt, now().addingTimeInterval(120))
        )
        state.enrollmentID = enrollmentID
        activeInvitation = state
        pending[enrollmentID] = PendingState(
            pending: value, proof: proof, invitationID: state.invitation.invitationID
        )
        return value
    }

    public func approve(
        enrollmentID: UUID,
        capabilities: Set<Capability>
    ) async throws -> EnrollmentResult {
        guard let state = pending.removeValue(forKey: enrollmentID) else {
            throw PairingError.enrollmentUnavailable
        }
        guard now() <= state.pending.expiresAt else {
            activeInvitation = nil
            throw PairingError.enrollmentExpired
        }
        guard activeInvitation?.invitation.invitationID == state.invitationID else {
            throw PairingError.enrollmentUnavailable
        }
        activeInvitation = nil
        let device = PairedDevice(
            deviceID: state.proof.phoneID,
            displayName: state.proof.phoneName,
            capabilities: capabilities,
            enrolledAt: now()
        )
        let epoch = try await registry.enroll(PairedDeviceRecord(
            device: device,
            identityCertificate: state.proof.identityCertificate,
            approvalPublicKey: state.proof.approvalPublicKey
        ))
        return EnrollmentResult(device: device, policyEpoch: epoch)
    }

    public static func enrollmentTranscript(
        invitation: PairingInvitation,
        proof: EnrollmentProof
    ) throws -> Data {
        try EnrollmentProof.transcript(invitation: invitation, proof: proof)
    }

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes)
    }

    private func comparisonCode(for transcript: Data) -> String {
        let digest = SHA256.hash(data: transcript)
        let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        return String(format: "%06u", number)
    }
}
