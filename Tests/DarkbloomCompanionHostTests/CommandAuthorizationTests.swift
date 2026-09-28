import CryptoKit
import Foundation
import Testing
@testable import DarkbloomCompanionHost
import DarkbloomCompanionProtocol

@Suite(.serialized)
struct CommandAuthorizationTests {
    @Test func modifiedBytesReplayExpiryAndEpochAreRejected() async throws {
        let key = P256.Signing.PrivateKey()
        let deviceID = UUID()
        let registry = InMemoryPairedDeviceRegistry(records: [
            PairedDeviceRecord(
                device: .init(deviceID: deviceID, displayName: "Phone", capabilities: [.providerLifecycle], enrolledAt: .now),
                identityCertificate: Data([1]), approvalPublicKey: key.publicKey.x963Representation
            )
        ])
        let clock = LockedDate(Date(timeIntervalSince1970: 2_000))
        let coordinator = CommandAuthorizationCoordinator(
            hostID: UUID(), runtimeEpoch: UUID(), registry: registry,
            revision: { "r1" }, now: { clock.value }
        )
        let proposal = ControlProposal(
            requestID: UUID(), expectedRevision: "r1", action: .providerLifecycle(.stop)
        )
        let prepared = try await coordinator.prepare(proposal, deviceID: deviceID)
        var altered = prepared.signedPayload
        altered[altered.startIndex] ^= 1
        let alteredSignature = try key.signature(for: altered).derRepresentation
        await #expect(throws: AuthorizationError.signedPayloadMismatch) {
            _ = try await coordinator.authorize(.init(commandID: prepared.commandID, signedPayload: altered, signature: alteredSignature), deviceID: deviceID)
        }
        let approval = SignedApproval(
            commandID: prepared.commandID, signedPayload: prepared.signedPayload,
            signature: try key.signature(for: prepared.signedPayload).derRepresentation
        )
        let authorized = try await coordinator.authorize(approval, deviceID: deviceID)
        #expect(authorized.proposal == proposal)
        await #expect(throws: AuthorizationError.replayed) {
            _ = try await coordinator.authorize(approval, deviceID: deviceID)
        }

        let second = try await coordinator.prepare(
            .init(requestID: UUID(), expectedRevision: "r1", action: .providerLifecycle(.start)),
            deviceID: deviceID
        )
        clock.value = clock.value.addingTimeInterval(61)
        await #expect(throws: AuthorizationError.expired) {
            _ = try await coordinator.authorize(
                .init(commandID: second.commandID, signedPayload: second.signedPayload,
                      signature: try key.signature(for: second.signedPayload).derRepresentation),
                deviceID: deviceID
            )
        }
    }

    @Test func capabilityRevisionAndRevocationAreRecheckedAtDispatch() async throws {
        let key = P256.Signing.PrivateKey()
        let deviceID = UUID()
        let record = PairedDeviceRecord(
            device: .init(deviceID: deviceID, displayName: "Phone", capabilities: [.providerLifecycle], enrolledAt: .now),
            identityCertificate: Data([1]), approvalPublicKey: key.publicKey.x963Representation
        )
        let registry = InMemoryPairedDeviceRegistry(records: [record])
        let revision = LockedString("one")
        let coordinator = CommandAuthorizationCoordinator(
            hostID: UUID(), runtimeEpoch: UUID(), registry: registry, revision: { revision.value }
        )
        await #expect(throws: AuthorizationError.missingCapability(.appLifecycle)) {
            _ = try await coordinator.prepare(
                .init(requestID: UUID(), action: .appLifecycle(.quit)), deviceID: deviceID
            )
        }
        let prepared = try await coordinator.prepare(
            .init(requestID: UUID(), expectedRevision: "one", action: .providerLifecycle(.restart)),
            deviceID: deviceID
        )
        revision.value = "two"
        let approval = SignedApproval(
            commandID: prepared.commandID, signedPayload: prepared.signedPayload,
            signature: try key.signature(for: prepared.signedPayload).derRepresentation
        )
        await #expect(throws: AuthorizationError.revisionConflict) {
            _ = try await coordinator.authorize(approval, deviceID: deviceID)
        }

        revision.value = "one"
        let next = try await coordinator.prepare(
            .init(requestID: UUID(), expectedRevision: "one", action: .providerLifecycle(.stop)),
            deviceID: deviceID
        )
        await registry.revoke(deviceID)
        await #expect(throws: AuthorizationError.revoked) {
            _ = try await coordinator.authorize(
                .init(commandID: next.commandID, signedPayload: next.signedPayload,
                      signature: try key.signature(for: next.signedPayload).derRepresentation),
                deviceID: deviceID
            )
        }
    }

    @Test func pendingCommandMemoryIsBoundedAndExpiredEntriesArePruned() async throws {
        let key = P256.Signing.PrivateKey()
        let deviceID = UUID()
        let registry = InMemoryPairedDeviceRegistry(records: [
            PairedDeviceRecord(
                device: .init(deviceID: deviceID, displayName: "Phone", capabilities: [.providerLifecycle], enrolledAt: .now),
                identityCertificate: Data([1]), approvalPublicKey: key.publicKey.x963Representation
            )
        ])
        let clock = LockedDate(Date(timeIntervalSince1970: 3_000))
        let coordinator = CommandAuthorizationCoordinator(
            hostID: UUID(), runtimeEpoch: UUID(), registry: registry,
            revision: { nil }, now: { clock.value }
        )
        for _ in 0..<128 {
            _ = try await coordinator.prepare(
                .init(requestID: UUID(), action: .providerLifecycle(.stop)),
                deviceID: deviceID
            )
        }
        await #expect(throws: AuthorizationError.tooManyPendingCommands) {
            _ = try await coordinator.prepare(
                .init(requestID: UUID(), action: .providerLifecycle(.stop)),
                deviceID: deviceID
            )
        }

        clock.value = clock.value.addingTimeInterval(61)
        _ = try await coordinator.prepare(
            .init(requestID: UUID(), action: .providerLifecycle(.stop)),
            deviceID: deviceID
        )
    }
}

private final class LockedDate: @unchecked Sendable {
    private let lock = NSLock(); private var storage: Date
    init(_ value: Date) { storage = value }
    var value: Date { get { lock.withLock { storage } } set { lock.withLock { storage = newValue } } }
}
private final class LockedString: @unchecked Sendable {
    private let lock = NSLock(); private var storage: String
    init(_ value: String) { storage = value }
    var value: String { get { lock.withLock { storage } } set { lock.withLock { storage = newValue } } }
}
