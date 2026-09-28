import CryptoKit
import Foundation
import Testing
@testable import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport

@Suite(.serialized)
struct PairingCoordinatorTests {
    @Test func invitationRoundTripsThroughBoundedQRAndExpires() async throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_000))
        let registry = InMemoryPairedDeviceRegistry()
        let coordinator = PairingCoordinator(
            hostID: UUID(), hostName: "Kevin's Mac", hostSPKIPin: Data(repeating: 7, count: 32),
            routes: .init(candidates: [.init(kind: .lan, host: "mac.local", port: 9443)]),
            registry: registry, now: { clock.now }
        )
        let invitation = try await coordinator.makeInvitation()
        let qr = try PairingQRCode.encode(invitation)
        #expect(qr.utf8.count <= 2_048)
        #expect(try PairingQRCode.decode(qr) == invitation)
        clock.now = clock.now.addingTimeInterval(121)
        let phone = try TestPhoneIdentity()
        let proof = try phone.proof(for: invitation)
        await #expect(throws: PairingError.invitationExpired) {
            _ = try await coordinator.beginEnrollment(proof)
        }
    }

    @Test func wrongTranscriptAndFifthFailureCloseInvitation() async throws {
        let coordinator = PairingCoordinator.fixture()
        let invitation = try await coordinator.makeInvitation()
        let phone = try TestPhoneIdentity()
        var proof = try phone.proof(for: invitation)
        proof = EnrollmentProof(
            invitationID: proof.invitationID, phoneID: proof.phoneID, phoneName: proof.phoneName,
            identityCertificate: proof.identityCertificate, approvalPublicKey: proof.approvalPublicKey,
            nonce: proof.nonce, transcriptSignature: Data(repeating: 0, count: 64)
        )
        for _ in 0..<4 {
            await #expect(throws: PairingError.invalidProof) { _ = try await coordinator.beginEnrollment(proof) }
        }
        await #expect(throws: PairingError.tooManyAttempts) { _ = try await coordinator.beginEnrollment(proof) }
        await #expect(throws: PairingError.invitationUnavailable) { _ = try await coordinator.beginEnrollment(proof) }
    }

    @Test func onlyOneApprovalConsumesInvitationAndRevocationAdvancesPolicy() async throws {
        let registry = InMemoryPairedDeviceRegistry()
        let coordinator = PairingCoordinator.fixture(registry: registry)
        let invitation = try await coordinator.makeInvitation()
        let phone = try TestPhoneIdentity()
        let pending = try await coordinator.beginEnrollment(phone.proof(for: invitation))
        let caps: Set<Capability> = [.monitor, .providerLifecycle]
        let result = try await coordinator.approve(enrollmentID: pending.enrollmentID, capabilities: caps)
        #expect(result.device.deviceID == phone.id)
        #expect(result.device.capabilities == caps)
        await #expect(throws: PairingError.enrollmentUnavailable) {
            _ = try await coordinator.approve(enrollmentID: pending.enrollmentID, capabilities: caps)
        }
        let oldEpoch = result.policyEpoch
        await registry.revoke(phone.id)
        #expect(await registry.policyEpoch == oldEpoch + 1)
        #expect(await registry.record(for: phone.id) == nil)
    }
}

private final class TestClock: @unchecked Sendable {
    let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    var now: Date {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private struct TestPhoneIdentity {
    let id = UUID()
    let approval = P256.Signing.PrivateKey()
    let transport: CompanionIdentity

    init() throws { transport = try CompanionIdentity.makeEphemeral(role: .phone) }

    func proof(for invitation: PairingInvitation) throws -> EnrollmentProof {
        let nonce = Data(repeating: 3, count: 32)
        let unsigned = EnrollmentProof(
            invitationID: invitation.invitationID, phoneID: id, phoneName: "Test iPhone",
            identityCertificate: transport.certificateDER,
            approvalPublicKey: approval.publicKey.x963Representation,
            nonce: nonce, transcriptSignature: Data([1])
        )
        let transcript = try PairingCoordinator.enrollmentTranscript(invitation: invitation, proof: unsigned)
        let signature = try transport.sign(transcript)
        return EnrollmentProof(
            invitationID: unsigned.invitationID, phoneID: unsigned.phoneID, phoneName: unsigned.phoneName,
            identityCertificate: unsigned.identityCertificate, approvalPublicKey: unsigned.approvalPublicKey,
            nonce: unsigned.nonce, transcriptSignature: signature
        )
    }
}

private extension PairingCoordinator {
    static func fixture(registry: InMemoryPairedDeviceRegistry = .init()) -> PairingCoordinator {
        PairingCoordinator(
            hostID: UUID(), hostName: "Fixture Mac", hostSPKIPin: Data(repeating: 9, count: 32),
            routes: .init(candidates: [.init(kind: .lan, host: "127.0.0.1", port: 9443)]),
            registry: registry
        )
    }
}
