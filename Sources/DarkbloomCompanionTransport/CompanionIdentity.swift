import CryptoKit
import Foundation
import Security
import SwiftASN1
import X509

public enum CompanionIdentityRole: String, Sendable { case host, phone }

public enum CompanionIdentityError: Error, Equatable, Sendable {
    case keyCreationFailed
    case certificateCreationFailed
    case identityCreationFailed
    case signingFailed
    case invalidCertificate
    case inconsistentPersistentState
    case keychainFailure(OSStatus)
}

/// A TLS identity. `makeEphemeral` is used by deterministic tests and simulator
/// fixtures; production hosts load the same material through `HostIdentityStore`.
public struct CompanionIdentity: @unchecked Sendable {
    public let identity: SecIdentity
    public let certificate: SecCertificate
    public let certificateDER: Data
    public let spkiSHA256: Data
    private let privateKey: SecKey

    init(identity: SecIdentity, certificate: SecCertificate, certificateDER: Data, spkiSHA256: Data, privateKey: SecKey) {
        self.identity = identity
        self.certificate = certificate
        self.certificateDER = certificateDER
        self.spkiSHA256 = spkiSHA256
        self.privateKey = privateKey
    }

    public static func makeEphemeral(
        role: CompanionIdentityRole,
        now: Date = Date(),
        validFor: TimeInterval = 365 * 24 * 60 * 60
    ) throws -> Self {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: false,
        ]
        var creationError: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &creationError) else {
            throw CompanionIdentityError.keyCreationFailed
        }
        return try make(role: role, key: key, now: now, validFor: validFor)
    }

    static func make(
        role: CompanionIdentityRole,
        key: SecKey,
        now: Date,
        validFor: TimeInterval
    ) throws -> Self {
        let privateKey = try Certificate.PrivateKey(key)
        let name = try DistinguishedName { CommonName("Darkbloom Companion \(role.rawValue)") }
        var extensions = try [
            Certificate.Extension(BasicConstraints.notCertificateAuthority, critical: true),
            Certificate.Extension(KeyUsage(digitalSignature: true), critical: true),
            Certificate.Extension(ExtendedKeyUsage([role == .host ? .serverAuth : .clientAuth]), critical: false),
        ]
        if role == .host {
            extensions.append(try Certificate.Extension(
                SubjectAlternativeNames([.dnsName("darkbloom-companion.invalid")]), critical: false
            ))
        }
        let certificate = try Certificate(
            version: .v3,
            serialNumber: Certificate.SerialNumber(),
            publicKey: privateKey.publicKey,
            notValidBefore: now.addingTimeInterval(-60),
            notValidAfter: now.addingTimeInterval(validFor),
            issuer: name,
            subject: name,
            signatureAlgorithm: .ecdsaWithSHA256,
            extensions: Certificate.Extensions(extensions),
            issuerPrivateKey: privateKey
        )
        var serializer = DER.Serializer()
        try serializer.serialize(certificate)
        let der = Data(serializer.serializedBytes)
        guard let nativeCertificate = SecCertificateCreateWithData(nil, der as CFData) else {
            throw CompanionIdentityError.certificateCreationFailed
        }
        guard let identity = SecIdentityCreate(nil, nativeCertificate, key) else {
            throw CompanionIdentityError.identityCreationFailed
        }
        return Self(
            identity: identity,
            certificate: nativeCertificate,
            certificateDER: der,
            spkiSHA256: try canonicalSPKIHash(certificate.publicKey),
            privateKey: key
        )
    }

    public func sign(_ data: Data) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256, data as CFData, &error
        ) else { throw CompanionIdentityError.signingFailed }
        return signature as Data
    }
}

/// Loads one per-install host identity. A partial or corrupt Keychain record is
/// a recovery condition and never silently creates a new host pin.
public struct CompanionIdentityStore: Sendable {
    private let namespace: String
    private let role: CompanionIdentityRole
    public init(
        namespace: String = "dev.darkbloom.companion.host",
        role: CompanionIdentityRole = .host
    ) {
        self.namespace = namespace
        self.role = role
    }

    public func loadOrCreate(now: Date = Date()) throws -> CompanionIdentity {
        let tag = Data("\(namespace).key".utf8)
        let certificateAccount = "\(namespace).certificate"
        let keyResult = try loadKey(tag: tag)
        let certificateData = try loadCertificate(account: certificateAccount)
        switch (keyResult, certificateData) {
        case (nil, nil):
            let key = try createPermanentKey(tag: tag)
            do {
                let identity = try CompanionIdentity.make(
                    role: role, key: key, now: now, validFor: 5 * 365 * 24 * 60 * 60
                )
                try saveCertificate(identity.certificateDER, account: certificateAccount)
                return identity
            } catch {
                SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag] as CFDictionary)
                throw error
            }
        case let (.some(key), .some(der)):
            guard CompanionTrust.validate(certificateDER: der, role: role, now: now),
                  let certificate = SecCertificateCreateWithData(nil, der as CFData),
                  let identity = SecIdentityCreate(nil, certificate, key),
                  let spki = CompanionTrust.spkiHash(certificateDER: der) else {
                throw CompanionIdentityError.inconsistentPersistentState
            }
            return CompanionIdentity(
                identity: identity, certificate: certificate, certificateDER: der,
                spkiSHA256: spki, privateKey: key
            )
        default:
            throw CompanionIdentityError.inconsistentPersistentState
        }
    }

    public func deleteForTesting() {
        let tag = Data("\(namespace).key".utf8)
        SecItemDelete([kSecClass: kSecClassKey, kSecAttrApplicationTag: tag] as CFDictionary)
        SecItemDelete([
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: namespace,
            kSecAttrAccount: "\(namespace).certificate",
        ] as CFDictionary)
    }

    private func createPermanentKey(tag: Data) throws -> SecKey {
        var attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits: 256,
            kSecAttrIsPermanent: true,
            kSecAttrApplicationTag: tag,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        #if os(iOS) && !targetEnvironment(simulator)
        if role == .phone {
            // A physical phone must keep its TLS client key non-exportable.
            // Simulator builds deliberately use the software Keychain path.
            attributes[kSecAttrTokenID] = kSecAttrTokenIDSecureEnclave
        }
        #endif
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw CompanionIdentityError.keyCreationFailed
        }
        return key
    }

    private func loadKey(tag: Data) throws -> SecKey? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassKey, kSecAttrApplicationTag: tag,
            kSecAttrKeyType: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
            kSecReturnRef: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let key = item as! SecKey? else {
            throw CompanionIdentityError.keychainFailure(status)
        }
        return key
    }

    private func loadCertificate(account: String) throws -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: namespace,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw CompanionIdentityError.keychainFailure(status)
        }
        return data
    }

    private func saveCertificate(_ data: Data, account: String) throws {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: namespace,
            kSecAttrAccount: account, kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw CompanionIdentityError.keychainFailure(status) }
    }
}

public typealias HostIdentityStore = CompanionIdentityStore

public enum CompanionTrust {
    public static func validate(
        _ certificates: [SecCertificate],
        expectedSPKI: Data?,
        role: CompanionIdentityRole,
        now: Date = Date()
    ) -> Bool {
        guard certificates.count == 1 else { return false }
        return validate(
            certificateDER: SecCertificateCopyData(certificates[0]) as Data,
            expectedSPKI: expectedSPKI,
            role: role,
            now: now
        )
    }

    public static func spkiHash(certificateDER: Data) -> Data? {
        guard let native = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let certificate = try? Certificate(native) else { return nil }
        return try? canonicalSPKIHash(certificate.publicKey)
    }
    public static func validate(
        certificateDER: Data,
        expectedSPKI: Data? = nil,
        role: CompanionIdentityRole,
        now: Date = Date()
    ) -> Bool {
        guard let native = SecCertificateCreateWithData(nil, certificateDER as CFData) else { return false }
        do {
            let certificate = try Certificate(native)
            guard certificate.version == .v3,
                  certificate.issuer == certificate.subject,
                  certificate.notValidBefore <= now,
                  now <= certificate.notValidAfter,
                  P256.Signing.PublicKey(certificate.publicKey) != nil,
                  certificate.signatureAlgorithm == .ecdsaWithSHA256,
                  certificate.publicKey.isValidSignature(certificate.signature, for: certificate),
                  try certificate.extensions.basicConstraints == .notCertificateAuthority,
                  certificate.extensions[oid: .X509ExtensionID.basicConstraints]?.critical == true,
                  try certificate.extensions.keyUsage == KeyUsage(digitalSignature: true),
                  certificate.extensions[oid: .X509ExtensionID.keyUsage]?.critical == true,
                  let eku = try certificate.extensions.extendedKeyUsage,
                  Array(eku) == [role == .host ? .serverAuth : .clientAuth]
            else { return false }
            if let expectedSPKI, try canonicalSPKIHash(certificate.publicKey) != expectedSPKI { return false }
            let understood: Set<ASN1ObjectIdentifier> = [
                .X509ExtensionID.basicConstraints, .X509ExtensionID.keyUsage,
                .X509ExtensionID.extendedKeyUsage, .X509ExtensionID.subjectAlternativeName,
            ]
            return certificate.extensions.allSatisfy { !$0.critical || understood.contains($0.oid) }
        } catch { return false }
    }

    public static func verify(_ signature: Data, message: Data, certificateDER: Data) -> Bool {
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData),
              let key = SecCertificateCopyKey(certificate) else { return false }
        var error: Unmanaged<CFError>?
        return SecKeyVerifySignature(
            key, .ecdsaSignatureMessageX962SHA256,
            message as CFData, signature as CFData, &error
        )
    }
}

private func canonicalSPKIHash(_ publicKey: Certificate.PublicKey) throws -> Data {
    var serializer = DER.Serializer()
    try serializer.serialize(publicKey)
    return Data(SHA256.hash(data: Data(serializer.serializedBytes)))
}
