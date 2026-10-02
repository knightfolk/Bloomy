import Foundation
import LocalAuthentication
import Security
import Testing
@testable import DarkbloomTelemetry

/// Presence tests inject a lookup and never access the Keychain. Other safety
/// tests reject invalid writes or read a nonexistent throwaway service; the
/// user's actual credentials are never read or modified.
@Suite("Consumer key keychain store")
struct ConsumerKeychainTests {
    @Test("presence requests only noninteractive metadata in the existing Keychain scope")
    func metadataOnlyPresence() {
        let store = KeychainConsumerKeyStore(service: "dev.darkbloom.test.presence", account: "fixture") { query in
            #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
            #expect(query[kSecAttrService as String] as? String == "dev.darkbloom.test.presence")
            #expect(query[kSecAttrAccount as String] as? String == "fixture")
            #expect(query[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
            #expect(query[kSecReturnAttributes as String] as? Bool == true)
            #expect(query[kSecReturnData as String] == nil)
            #expect(query[kSecReturnRef as String] == nil)
            #expect(query[kSecReturnPersistentRef as String] == nil)
            #expect(query[kSecValueData as String] == nil)
            #expect(query[kSecUseDataProtectionKeychain as String] == nil)
            #expect(query[kSecAttrSynchronizable as String] == nil)
            #expect((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed == true)
            return errSecSuccess
        }
        #expect(store.keyPresence() == .configured)
    }

    @Test("presence distinguishes missing items from inaccessible or failed lookups")
    func presenceResults() {
        for (status, expected) in [
            (errSecSuccess, ConsumerKeyPresence.configured),
            (errSecItemNotFound, .missing),
            (errSecInteractionNotAllowed, .unavailable),
            (errSecAuthFailed, .unavailable),
            (errSecNotAvailable, .unavailable),
            (errSecParam, .unavailable),
        ] {
            let store = KeychainConsumerKeyStore(service: "dev.darkbloom.test.presence") { _ in status }
            #expect(store.keyPresence() == expected)
        }
    }

    @Test("presence helper executes synchronous lookup away from the main actor")
    @MainActor
    func backgroundPresence() async {
        let store = KeychainConsumerKeyStore(service: "dev.darkbloom.test.presence") { _ in
            #expect(!Thread.isMainThread)
            return errSecSuccess
        }
        #expect(await store.keyPresenceInBackground() == .configured)
    }

    @Test("a canceled presence check does not start a Keychain lookup")
    @MainActor
    func canceledPresence() async {
        let store = KeychainConsumerKeyStore(service: "dev.darkbloom.test.presence") { _ in
            Issue.record("A canceled check must not enter the Keychain lookup.")
            return errSecSuccess
        }
        let request = Task { await store.keyPresenceInBackground() }
        request.cancel()
        #expect(await request.value == .unavailable)
    }

    @Test("existing key readers inherit the compatible presence implementation")
    func compatiblePresenceDefault() async {
        let configured = PresenceCompatibilityReader(hasKey: true)
        let missing = PresenceCompatibilityReader(hasKey: false)
        #expect(configured.keyPresence() == .configured)
        #expect(missing.keyPresence() == .missing)
        #expect(await configured.keyPresenceInBackground() == .configured)
        #expect(await missing.keyPresenceInBackground() == .missing)
    }

    @Test("invalid key material is rejected before any keychain write")
    func invalidWrite() {
        let store = KeychainConsumerKeyStore(service: "dev.darkbloom.test.\(UUID().uuidString)")
        #expect(throws: ConsumerKeyStoreError.invalidKey) {
            try store.store("has spaces")
        }
        #expect(throws: ConsumerKeyStoreError.invalidKey) {
            try store.store("")
        }
        #expect(store.hasKey == false)
    }

    @Test("a lookup for a nonexistent item returns nil without prompting")
    func missingItem() {
        let store = KeychainConsumerKeyStore(service: "dev.darkbloom.test.\(UUID().uuidString)")
        var observed: String?
        let found = store.withConsumerKey { key in
            observed = key
            return true
        }
        #expect(found == nil)
        #expect(observed == nil)
        #expect(store.hasKey == false)
    }

    @Test("error messages carry only fixed text and status codes, never key material")
    func sanitizedErrors() {
        #expect(ConsumerKeyStoreError.invalidKey.errorDescription?.contains("consumer API key") == true)
        let status = ConsumerKeyStoreError.keychainFailure(-34018)
        #expect(status.errorDescription?.contains("-34018") == true)
        #expect(status.errorDescription?.contains("Keychain") == true)
    }
}

private struct PresenceCompatibilityReader: ConsumerKeyReading {
    let hasKey: Bool

    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? {
        Issue.record("A configuration check must not request secret material.")
        return nil
    }
}
