import DarkbloomCompanionProtocol
import CryptoKit
import XCTest
@testable import DarkbloomCompanion

final class CompanionClientTests: XCTestCase {
    func testAppearanceDefaultsToSystemAndMapsExplicitOverrides() {
        XCTAssertEqual(CompanionAppearanceMode(storedValue: nil), .system)
        XCTAssertEqual(CompanionAppearanceMode(storedValue: "future-mode"), .system)
        XCTAssertNil(CompanionAppearanceMode.system.colorScheme)
        XCTAssertEqual(CompanionAppearanceMode.light.colorScheme, .light)
        XCTAssertEqual(CompanionAppearanceMode.dark.colorScheme, .dark)
    }

    func testApprovalKeyIsStableAndProducesVerifiableSignatures() throws {
        let service = "dev.darkbloom.companion.tests.\(UUID().uuidString)"
        let store = ApprovalKeyStore(service: service)
        defer { store.deleteForTesting() }
        let message = Data("approved command".utf8)

        let publicKey = try P256.Signing.PublicKey(x963Representation: store.publicKey())
        let signature = try P256.Signing.ECDSASignature(derRepresentation: store.sign(message))

        XCTAssertTrue(publicKey.isValidSignature(signature, for: message))
        XCTAssertEqual(try store.publicKey(), publicKey.x963Representation)
    }

    func testSnapshotFreshnessUsesMonotonicElapsedTime() {
        let received = ContinuousClock.now
        var freshness = SnapshotFreshness(maximumAge: .seconds(15))
        XCTAssertTrue(freshness.isStale(at: received))
        freshness.didReceive(at: received)
        XCTAssertFalse(freshness.isStale(at: received.advanced(by: .seconds(14))))
        XCTAssertTrue(freshness.isStale(at: received.advanced(by: .seconds(16))))
    }

    func testPairingQRCodeRoundTripPreservesPinAndRoutes() throws {
        let invitation = PairingInvitation(
            hostID: UUID(), hostName: "Test Mac", invitationID: UUID(),
            invitationSecret: Data(repeating: 1, count: 32),
            hostSPKIPin: Data(repeating: 2, count: 32),
            expiresAt: .now.addingTimeInterval(120),
            routes: .init(candidates: [.init(kind: .lan, host: "192.0.2.1", port: 49_444)])
        )
        let encoded = try PairingQRCode.encode(invitation)
        XCTAssertLessThanOrEqual(encoded.utf8.count, PairingQRCode.maximumBytes)
        let decoded = try PairingQRCode.decode(encoded)
        XCTAssertEqual(decoded.hostID, invitation.hostID)
        XCTAssertEqual(decoded.invitationID, invitation.invitationID)
        XCTAssertEqual(decoded.invitationSecret, invitation.invitationSecret)
        XCTAssertEqual(decoded.hostSPKIPin, invitation.hostSPKIPin)
        XCTAssertEqual(decoded.routes, invitation.routes)
        XCTAssertEqual(decoded.expiresAt.timeIntervalSince1970, invitation.expiresAt.timeIntervalSince1970, accuracy: 0.001)
    }

    @MainActor
    func testLegacySingleHostMigratesToIdentityKeyedRegistry() throws {
        let suite = "CompanionClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertNil(CompanionStore(defaults: defaults).host)
        let host = StoredHost(
            hostID: UUID(), name: "Saved Mac",
            routes: .init(candidates: [.init(kind: .tailnet, host: "100.64.0.1", port: 49_444)]),
            spkiPin: Data(repeating: 3, count: 32)
        )
        defaults.set(try JSONEncoder().encode(host), forKey: "companion.host")
        let store = CompanionStore(defaults: defaults)
        XCTAssertEqual(store.host, host)
        XCTAssertEqual(store.hosts.map(\.hostID), [host.hostID])
        XCTAssertNil(defaults.data(forKey: "companion.host"))
        XCTAssertNotNil(defaults.data(forKey: HostRegistry.storageKey))
    }

    func testRegistryAllowsDuplicateNamesAndRemovesOnlyMatchingIdentity() throws {
        let name = "Darkbloom Mac"
        let first = makeHost(name: name)
        let second = makeHost(name: name)
        var registry = HostRegistry(hosts: [first, second], selectedHostID: second.hostID)

        XCTAssertEqual(registry.hosts.map(\.name), [name, name])
        XCTAssertEqual(registry.selectedHostID, second.hostID)
        XCTAssertEqual(registry.remove(first.hostID), first)
        XCTAssertEqual(registry.hosts, [second])
        XCTAssertEqual(registry.selectedHostID, second.hostID)
    }

    func testRegistryPersistsSelectedIdentity() throws {
        let suite = "CompanionClientTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let first = makeHost(name: "Mac")
        let second = makeHost(name: "Mac")
        var registry = HostRegistry(hosts: [first, second], selectedHostID: first.hostID)
        registry.select(second.hostID)
        registry.save(to: defaults)

        let restored = HostRegistry.load(from: defaults)
        XCTAssertEqual(restored, registry)
        XCTAssertEqual(restored.selectedHost?.hostID, second.hostID)
    }

    private func makeHost(name: String) -> StoredHost {
        StoredHost(
            hostID: UUID(), name: name,
            routes: .init(candidates: [.init(kind: .tailnet, host: "100.64.0.1", port: 49_444)]),
            spkiPin: Data(repeating: 3, count: 32)
        )
    }
}
