import DarkbloomCompanionProtocol
import Foundation
import Security

public struct PairedDeviceRecord: Codable, Equatable, Sendable {
    public let device: PairedDevice
    public let identityCertificate: Data
    public let approvalPublicKey: Data

    public init(device: PairedDevice, identityCertificate: Data, approvalPublicKey: Data) {
        self.device = device
        self.identityCertificate = identityCertificate
        self.approvalPublicKey = approvalPublicKey
    }
}

public protocol PairedDeviceRegistry: Sendable {
    var policyEpoch: UInt64 { get async }
    func records() async throws -> [PairedDeviceRecord]
    func record(for deviceID: UUID) async -> PairedDeviceRecord?
    func enroll(_ record: PairedDeviceRecord) async throws -> UInt64
    func revoke(_ deviceID: UUID) async throws
}

public enum DeviceRegistryError: Error, Equatable, Sendable {
    case capacityReached
    case duplicateDevice
    case corruptStore
    case keychainFailure(OSStatus)
}

public actor InMemoryPairedDeviceRegistry: PairedDeviceRegistry {
    private var stored: [UUID: PairedDeviceRecord]
    public private(set) var policyEpoch: UInt64

    public init(records: [PairedDeviceRecord] = [], policyEpoch: UInt64 = 1) {
        self.stored = Dictionary(uniqueKeysWithValues: records.map { ($0.device.deviceID, $0) })
        self.policyEpoch = policyEpoch
    }

    public func records() -> [PairedDeviceRecord] {
        stored.values.sorted { $0.device.enrolledAt < $1.device.enrolledAt }
    }

    public func record(for deviceID: UUID) -> PairedDeviceRecord? { stored[deviceID] }

    public func enroll(_ record: PairedDeviceRecord) throws -> UInt64 {
        guard stored[record.device.deviceID] == nil else { throw DeviceRegistryError.duplicateDevice }
        guard stored.count < 8 else { throw DeviceRegistryError.capacityReached }
        stored[record.device.deviceID] = record
        policyEpoch &+= 1
        return policyEpoch
    }

    public func revoke(_ deviceID: UUID) {
        if stored.removeValue(forKey: deviceID) != nil { policyEpoch &+= 1 }
    }
}

/// Persists the allowlist and policy epoch as one Keychain item so revocation
/// cannot expose a half-written state. The item never contains provider secrets.
public actor KeychainPairedDeviceRegistry: PairedDeviceRegistry {
    private struct State: Codable { var epoch: UInt64; var records: [PairedDeviceRecord] }
    private let service: String
    private let account: String
    private var state: State

    public init(service: String = "dev.darkbloom.companion.devices", account: String = "allowlist") throws {
        self.service = service
        self.account = account
        state = try Self.load(service: service, account: account) ?? State(epoch: 1, records: [])
    }

    public var policyEpoch: UInt64 { state.epoch }
    public func records() -> [PairedDeviceRecord] { state.records }
    public func record(for deviceID: UUID) -> PairedDeviceRecord? {
        state.records.first { $0.device.deviceID == deviceID }
    }

    public func enroll(_ record: PairedDeviceRecord) throws -> UInt64 {
        guard !state.records.contains(where: { $0.device.deviceID == record.device.deviceID }) else {
            throw DeviceRegistryError.duplicateDevice
        }
        guard state.records.count < 8 else { throw DeviceRegistryError.capacityReached }
        var candidate = state
        candidate.records.append(record)
        candidate.epoch &+= 1
        try persist(candidate)
        state = candidate
        return state.epoch
    }

    public func revoke(_ deviceID: UUID) throws {
        var candidate = state
        candidate.records.removeAll { $0.device.deviceID == deviceID }
        guard candidate.records.count != state.records.count else { return }
        candidate.epoch &+= 1
        try persist(candidate)
        state = candidate
    }

    private func persist(_ candidate: State) throws {
        let data = try JSONEncoder().encode(candidate)
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var insertion = query
            for (key, value) in attributes { insertion[key] = value }
            let added = SecItemAdd(insertion as CFDictionary, nil)
            guard added == errSecSuccess else { throw DeviceRegistryError.keychainFailure(added) }
        } else if status != errSecSuccess {
            throw DeviceRegistryError.keychainFailure(status)
        }
    }

    private static func load(service: String, account: String) throws -> State? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword, kSecAttrService: service,
            kSecAttrAccount: account, kSecReturnData: true, kSecMatchLimit: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data else {
            throw DeviceRegistryError.keychainFailure(status)
        }
        guard let decoded = try? JSONDecoder().decode(State.self, from: data),
              decoded.records.count <= 8,
              Set(decoded.records.map(\.device.deviceID)).count == decoded.records.count else {
            throw DeviceRegistryError.corruptStore
        }
        return decoded
    }
}
