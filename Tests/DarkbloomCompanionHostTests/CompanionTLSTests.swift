import Foundation
import Testing
@testable import DarkbloomCompanionHost
@testable import DarkbloomCompanionTransport

@Suite(.serialized)
struct CompanionTLSTests {
    @Test func pinnedMutualTLSRoundTripAndRevocation() async throws {
        let host = try CompanionIdentity.makeEphemeral(role: .host)
        let phone = try CompanionIdentity.makeEphemeral(role: .phone)
        let server = try CompanionTLSServer(identity: host, allowedPhoneSPKI: phone.spkiSHA256)
        let port = try await server.start()
        let client = try await CompanionTLSConnection.connect(
            port: port, identity: phone, expectedHostSPKI: host.spkiSHA256
        )
        let payload = Data(repeating: 0x5A, count: 128 * 1_024)
        try await client.send(payload)
        #expect(try await client.receive() == payload)
        server.revokePhone()
        await #expect(throws: (any Error).self) {
            try await client.send(Data("after revoke".utf8))
            _ = try await client.receive(timeout: 1)
        }
        client.cancel()
        await server.stop()
        #expect(server.activeConnections == 0)
        #expect(server.applicationRequests == 1)
    }

    @Test func wrongHostPinAndMissingClientCertificateFailBeforeData() async throws {
        let host = try CompanionIdentity.makeEphemeral(role: .host)
        let phone = try CompanionIdentity.makeEphemeral(role: .phone)
        let impostor = try CompanionIdentity.makeEphemeral(role: .host)
        let server = try CompanionTLSServer(identity: host, allowedPhoneSPKI: phone.spkiSHA256)
        let port = try await server.start()
        await #expect(throws: (any Error).self) {
            _ = try await CompanionTLSConnection.connect(
                port: port, identity: phone, expectedHostSPKI: impostor.spkiSHA256, timeout: 2
            )
        }
        await #expect(throws: (any Error).self) {
            let client = try await CompanionTLSConnection.connect(
                port: port, identity: nil, expectedHostSPKI: host.spkiSHA256, timeout: 2
            )
            defer { client.cancel() }
            try await client.send(Data("must not arrive".utf8))
            _ = try await client.receive(timeout: 1)
        }
        #expect(server.applicationRequests == 0)
        await server.stop()
    }

    @Test func framesAreBoundedBeforeNetworkSend() async throws {
        let host = try CompanionIdentity.makeEphemeral(role: .host)
        let phone = try CompanionIdentity.makeEphemeral(role: .phone)
        let server = try CompanionTLSServer(identity: host, allowedPhoneSPKI: phone.spkiSHA256)
        let port = try await server.start()
        let client = try await CompanionTLSConnection.connect(
            port: port, identity: phone, expectedHostSPKI: host.spkiSHA256
        )
        await #expect(throws: CompanionTransportError.frameTooLarge) {
            try await client.send(Data(repeating: 0, count: CompanionTLSConnection.maximumFrame + 1))
        }
        #expect(server.applicationRequests == 0)
        client.cancel()
        await server.stop()
    }
}
