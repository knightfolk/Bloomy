import DarkbloomCompanionProtocol
import Foundation

struct StoredHost: Codable, Equatable, Sendable, Identifiable {
    let hostID: UUID
    let name: String
    let routes: PeerRouteHints
    let spkiPin: Data

    var id: UUID { hostID }

    init(hostID: UUID, name: String, routes: PeerRouteHints, spkiPin: Data) {
        self.hostID = hostID
        self.name = name
        self.routes = routes
        self.spkiPin = spkiPin
    }

    private enum CodingKeys: String, CodingKey { case hostID, name, routes, spkiPin }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hostID = try container.decode(UUID.self, forKey: .hostID)
        name = try container.decode(String.self, forKey: .name)
        routes = try container.decode(PeerRouteHints.self, forKey: .routes)
        spkiPin = try container.decode(Data.self, forKey: .spkiPin)
        try validate()
    }

    func encode(to encoder: Encoder) throws {
        try validate()
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hostID, forKey: .hostID)
        try container.encode(name, forKey: .name)
        try container.encode(routes, forKey: .routes)
        try container.encode(spkiPin, forKey: .spkiPin)
    }

    private func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 160,
              name.rangeOfCharacter(from: .controlCharacters) == nil,
              (1...8).contains(routes.candidates.count),
              routes.candidates.allSatisfy({
                  !$0.host.isEmpty && $0.host.utf8.count <= 255 && $0.port > 0
                      && $0.host.rangeOfCharacter(from: .controlCharacters) == nil
              }),
              (32...128).contains(spkiPin.count) else {
            throw RegistryError.invalidHost
        }
    }
}

struct HostRegistry: Codable, Equatable, Sendable {
    static let storageKey = "companion.hostRegistry"
    static let legacyStorageKey = "companion.host"
    static let maximumHosts = 32

    private(set) var hosts: [StoredHost]
    private(set) var selectedHostID: UUID?

    var selectedHost: StoredHost? {
        guard let selectedHostID else { return nil }
        return hosts.first { $0.hostID == selectedHostID }
    }

    init(hosts: [StoredHost] = [], selectedHostID: UUID? = nil) {
        self.hosts = Self.uniqueHosts(hosts)
        if let selectedHostID, self.hosts.contains(where: { $0.hostID == selectedHostID }) {
            self.selectedHostID = selectedHostID
        } else {
            self.selectedHostID = self.hosts.first?.hostID
        }
    }

    mutating func upsert(_ host: StoredHost, select: Bool = false) {
        if let index = hosts.firstIndex(where: { $0.hostID == host.hostID }) {
            hosts[index] = host
        } else if hosts.count < Self.maximumHosts {
            hosts.append(host)
        } else {
            return
        }
        if select || selectedHostID == nil { selectedHostID = host.hostID }
    }

    mutating func select(_ hostID: UUID) {
        guard hosts.contains(where: { $0.hostID == hostID }) else { return }
        selectedHostID = hostID
    }

    @discardableResult
    mutating func remove(_ hostID: UUID) -> StoredHost? {
        guard let index = hosts.firstIndex(where: { $0.hostID == hostID }) else { return nil }
        let removed = hosts.remove(at: index)
        if selectedHostID == hostID { selectedHostID = hosts.first?.hostID }
        return removed
    }

    func host(for id: UUID) -> StoredHost? { hosts.first { $0.hostID == id } }

    static func load(from defaults: UserDefaults) -> HostRegistry {
        if let data = defaults.data(forKey: storageKey),
           let restored = try? JSONDecoder().decode(Self.self, from: data) {
            return restored
        }
        guard let legacyData = defaults.data(forKey: legacyStorageKey),
              let legacyHost = try? JSONDecoder().decode(StoredHost.self, from: legacyData) else {
            return HostRegistry()
        }
        let migrated = HostRegistry(hosts: [legacyHost], selectedHostID: legacyHost.hostID)
        if let data = try? JSONEncoder().encode(migrated) {
            defaults.set(data, forKey: storageKey)
            defaults.removeObject(forKey: legacyStorageKey)
        }
        return migrated
    }

    func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.storageKey)
        defaults.removeObject(forKey: Self.legacyStorageKey)
    }

    private static func uniqueHosts(_ hosts: [StoredHost]) -> [StoredHost] {
        var seen = Set<UUID>()
        return hosts.filter { seen.insert($0.hostID).inserted }.prefix(maximumHosts).map { $0 }
    }

    private enum CodingKeys: String, CodingKey { case hosts, selectedHostID }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let hosts = try container.decode([StoredHost].self, forKey: .hosts)
        guard hosts.count <= Self.maximumHosts,
              Set(hosts.map(\.hostID)).count == hosts.count else {
            throw RegistryError.invalidRegistry
        }
        self.init(
            hosts: hosts,
            selectedHostID: try container.decodeIfPresent(UUID.self, forKey: .selectedHostID)
        )
    }

    func encode(to encoder: Encoder) throws {
        guard hosts.count <= Self.maximumHosts,
              Set(hosts.map(\.hostID)).count == hosts.count,
              (selectedHostID == nil || hosts.contains { $0.hostID == selectedHostID }) else {
            throw RegistryError.invalidRegistry
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(hosts, forKey: .hosts)
        try container.encodeIfPresent(selectedHostID, forKey: .selectedHostID)
    }
}

private enum RegistryError: Error { case invalidHost, invalidRegistry }
