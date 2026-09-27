import Foundation
import Testing
@testable import DarkbloomCompanionHost
import DarkbloomCompanionTransport

@Suite(.serialized)
struct IdentityStoreTests {
    @Test func keychainIdentityRoundTripsWithoutChangingPin() throws {
        let store = HostIdentityStore(namespace: "dev.darkbloom.tests.\(UUID().uuidString)")
        defer { store.deleteForTesting() }
        let first = try store.loadOrCreate()
        let second = try store.loadOrCreate()
        #expect(first.certificateDER == second.certificateDER)
        #expect(first.spkiSHA256 == second.spkiSHA256)
        let message = Data("persistent identity".utf8)
        #expect(CompanionTrust.verify(try second.sign(message), message: message, certificateDER: first.certificateDER))
    }
}
