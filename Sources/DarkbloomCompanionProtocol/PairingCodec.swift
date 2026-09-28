import Foundation

public enum PairingQRCodeError: Error, Equatable, Sendable {
    case malformedQRCode
    case qrCodeTooLarge
}

public enum PairingQRCode {
    public static let prefix = "dc-pair:1:"
    public static let maximumBytes = 2_048

    public static func encode(_ invitation: PairingInvitation) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(invitation)
        let encoded = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let result = prefix + encoded
        guard result.utf8.count <= maximumBytes else { throw PairingQRCodeError.qrCodeTooLarge }
        return result
    }

    public static func decode(_ string: String) throws -> PairingInvitation {
        guard string.utf8.count <= maximumBytes, string.hasPrefix(prefix) else {
            throw PairingQRCodeError.malformedQRCode
        }
        var base64 = String(string.dropFirst(prefix.count))
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64) else { throw PairingQRCodeError.malformedQRCode }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let invitation = try? decoder.decode(PairingInvitation.self, from: data),
              invitation.invitationSecret.count == 32,
              invitation.hostSPKIPin.count == 32,
              !invitation.routes.candidates.isEmpty else { throw PairingQRCodeError.malformedQRCode }
        return invitation
    }
}

public extension EnrollmentProof {
    static func transcript(invitation: PairingInvitation, proof: EnrollmentProof) throws -> Data {
        struct Transcript: Encodable {
            let domain: String
            let hostID: UUID
            let invitationID: UUID
            let invitationSecret: Data
            let hostSPKIPin: Data
            let phoneID: UUID
            let phoneName: String
            let identityCertificate: Data
            let approvalPublicKey: Data
            let nonce: Data
        }
        let value = Transcript(
            domain: "darkbloom-companion-enrollment-v1",
            hostID: invitation.hostID,
            invitationID: invitation.invitationID,
            invitationSecret: invitation.invitationSecret,
            hostSPKIPin: invitation.hostSPKIPin,
            phoneID: proof.phoneID,
            phoneName: proof.phoneName,
            identityCertificate: proof.identityCertificate,
            approvalPublicKey: proof.approvalPublicKey,
            nonce: proof.nonce
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
