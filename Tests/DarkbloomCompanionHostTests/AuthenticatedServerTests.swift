import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import Foundation
import Testing

@Suite(.serialized)
struct AuthenticatedServerTests {
    @Test func authenticatedSessionSupportsSequentialRequestsBeyondHandshakeDeadline() async throws {
        #expect(AuthenticatedCompanionServer.defaultAuthenticatedIdleTimeout == 300)
        let host = try CompanionIdentity.makeEphemeral(role: .host)
        let phone = try CompanionIdentity.makeEphemeral(role: .phone)
        let deviceID = UUID()
        let calls = LockedCounter()
        let server = try AuthenticatedCompanionServer(
            identity: host,
            authenticate: { authentication, challenge in
                authentication.deviceID == deviceID && CompanionTrust.verify(
                    authentication.signature,
                    message: CompanionHostCoordinator.sessionTranscript(
                        deviceID: deviceID, nonce: challenge.nonce
                    ),
                    certificateDER: phone.certificateDER
                )
            },
            handler: { _, request in
                calls.increment()
                return .init(
                    requestID: request.requestID,
                    payload: .safeError(.init(code: .unavailable))
                )
            }
        )
        let port = try await server.start()
        let client = try await CompanionClientSession.connect(
            route: .init(kind: .lan, host: "127.0.0.1", port: port),
            identity: phone,
            expectedHostSPKI: host.spkiSHA256,
            deviceID: deviceID
        )
        _ = try await client.request(.monitorSubscribe(.init()))
        try await Task.sleep(for: .seconds(11))
        _ = try await client.request(.settingsDraft(.init()))
        #expect(calls.value == 2)
        await client.close()
        await server.stop()
    }

    @Test func sessionChallengeBindsTransportCertificateToDevice() async throws {
        let host = try CompanionIdentity.makeEphemeral(role: .host)
        let phone = try CompanionIdentity.makeEphemeral(role: .phone)
        let deviceID = UUID()
        let server = try AuthenticatedCompanionServer(
            identity: host,
            authenticate: { authentication, challenge in
                guard authentication.deviceID == deviceID,
                      authentication.nonce == challenge.nonce else { return false }
                return CompanionTrust.verify(
                    authentication.signature,
                    message: CompanionHostCoordinator.sessionTranscript(
                        deviceID: deviceID, nonce: authentication.nonce
                    ),
                    certificateDER: phone.certificateDER
                )
            },
            handler: { authenticatedID, request in
                #expect(authenticatedID == deviceID)
                return Envelope(
                    requestID: request.requestID,
                    payload: .safeError(.init(code: .unavailable))
                )
            }
        )
        let port = try await server.start()
        let client = try await CompanionTLSConnection.connect(
            port: port, identity: phone, expectedHostSPKI: host.spkiSHA256
        )
        let challengeEnvelope = try await client.receiveEnvelope()
        guard case let .sessionChallenge(challenge) = challengeEnvelope.payload else {
            Issue.record("Expected a session challenge"); return
        }
        let signature = try phone.sign(CompanionHostCoordinator.sessionTranscript(
            deviceID: deviceID, nonce: challenge.nonce
        ))
        try await client.sendEnvelope(.init(
            requestID: challengeEnvelope.requestID,
            payload: .sessionAuthenticate(.init(
                deviceID: deviceID, nonce: challenge.nonce, signature: signature
            ))
        ))
        let requestID = UUID()
        try await client.sendEnvelope(.init(
            requestID: requestID, payload: .monitorSubscribe(.init())
        ))
        let response = try await client.receiveEnvelope()
        #expect(response.requestID == requestID)
        #expect(response.payload == .safeError(.init(code: .unavailable)))
        server.revoke(deviceID)
        await #expect(throws: (any Error).self) {
            try await client.sendEnvelope(.init(
                requestID: UUID(), payload: .monitorSubscribe(.init())
            ))
            _ = try await client.receiveEnvelope(timeout: 1)
        }
        client.cancel()
        await server.stop()
    }

    @Test func wrongTransportSignatureNeverReachesHandler() async throws {
        let host = try CompanionIdentity.makeEphemeral(role: .host)
        let enrolledPhone = try CompanionIdentity.makeEphemeral(role: .phone)
        let stranger = try CompanionIdentity.makeEphemeral(role: .phone)
        let deviceID = UUID()
        let calls = LockedCounter()
        let server = try AuthenticatedCompanionServer(
            identity: host,
            authenticate: { authentication, challenge in
                CompanionTrust.verify(
                    authentication.signature,
                    message: CompanionHostCoordinator.sessionTranscript(
                        deviceID: deviceID, nonce: challenge.nonce
                    ),
                    certificateDER: enrolledPhone.certificateDER
                )
            },
            handler: { _, request in
                calls.increment()
                return .init(requestID: request.requestID, payload: .safeError(.init(code: .unavailable)))
            }
        )
        let port = try await server.start()
        let client = try await CompanionTLSConnection.connect(
            port: port, identity: stranger, expectedHostSPKI: host.spkiSHA256
        )
        let envelope = try await client.receiveEnvelope()
        guard case let .sessionChallenge(challenge) = envelope.payload else { return }
        try await client.sendEnvelope(.init(
            requestID: envelope.requestID,
            payload: .sessionAuthenticate(.init(
                deviceID: deviceID,
                nonce: challenge.nonce,
                signature: try stranger.sign(CompanionHostCoordinator.sessionTranscript(
                    deviceID: deviceID, nonce: challenge.nonce
                ))
            ))
        ))
        await #expect(throws: (any Error).self) {
            try await client.sendEnvelope(.init(
                requestID: UUID(), payload: .monitorSubscribe(.init())
            ))
            _ = try await client.receiveEnvelope(timeout: 1)
        }
        #expect(calls.value == 0)
        client.cancel()
        await server.stop()
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}
