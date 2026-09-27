import CryptoKit
import Foundation
import LocalAuthentication
import Security

/// Keeps command approval material non-exportable on physical iPhones. The
/// simulator has no Secure Enclave, so UI and protocol tests use a software
/// key stored in the simulator's device-only Keychain.
struct ApprovalKeyStore: Sendable {
    private let service: String
    private let account = "p256-signing-key"

    init(service: String = "dev.darkbloom.companion.approval") {
        self.service = service
    }

    func publicKey() throws -> Data {
        #if targetEnvironment(simulator)
        return try loadOrCreateSimulatorKey().publicKey.x963Representation
        #else
        return try loadOrCreateSecureEnclaveKey().publicKey.x963Representation
        #endif
    }

    func sign(_ message: Data) throws -> Data {
        #if targetEnvironment(simulator)
        return try loadOrCreateSimulatorKey().signature(for: message).derRepresentation
        #else
        return try loadOrCreateSecureEnclaveKey().signature(for: message).derRepresentation
        #endif
    }

    func authenticateOwner(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? CompanionAppError.ownerAuthenticationUnavailable
        }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else {
            throw CompanionAppError.ownerAuthenticationUnavailable
        }
    }

    #if targetEnvironment(simulator)
    private func loadOrCreateSimulatorKey() throws -> P256.Signing.PrivateKey {
        if let data = try loadRepresentation() {
            return try P256.Signing.PrivateKey(rawRepresentation: data)
        }
        let key = P256.Signing.PrivateKey()
        try saveRepresentation(key.rawRepresentation)
        return key
    }
    #else
    private func loadOrCreateSecureEnclaveKey() throws -> SecureEnclave.P256.Signing.PrivateKey {
        guard SecureEnclave.isAvailable else { throw CompanionAppError.secureEnclaveUnavailable }
        if let data = try loadRepresentation() {
            return try SecureEnclave.P256.Signing.PrivateKey(dataRepresentation: data)
        }
        guard let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage],
            nil
        ) else { throw CompanionAppError.secureEnclaveUnavailable }
        let key = try SecureEnclave.P256.Signing.PrivateKey(accessControl: access)
        try saveRepresentation(key.dataRepresentation)
        return key
    }
    #endif

    private func loadRepresentation() throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CompanionAppError.keychain(status)
        }
        return data
    }

    private func saveRepresentation(_ data: Data) throws {
        let insertion: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemAdd(insertion as CFDictionary, nil)
        guard status == errSecSuccess else { throw CompanionAppError.keychain(status) }
    }

    func deleteForTesting() {
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ] as CFDictionary)
    }
}

enum CompanionAppError: Error, LocalizedError {
    case keychain(OSStatus)
    case ownerAuthenticationUnavailable
    case secureEnclaveUnavailable
    case unexpectedResponse
    case noRoute
    case notConnected

    var errorDescription: String? {
        switch self {
        case .keychain: "Secure device storage is unavailable."
        case .ownerAuthenticationUnavailable: "Unlock this iPhone to approve the command."
        case .secureEnclaveUnavailable: "This iPhone cannot create a hardware-protected approval key."
        case .unexpectedResponse: "The host returned an unexpected response."
        case .noRoute: "The pairing code has no usable route."
        case .notConnected: "Connect to the paired Mac first."
        }
    }
}
