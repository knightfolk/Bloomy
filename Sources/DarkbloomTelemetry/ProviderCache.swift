import Foundation

/// Saved cache settings, not evidence of the running provider's effective settings.
public struct ProviderCacheStatus: Equatable, Sendable {
    public let directory: String
    /// The selected parent folder reported by the volume check, when available.
    /// `directory` is the effective namespaced cache root inside this folder.
    public let selectedDirectory: String?
    public let dailyWriteBytes: Int64?
    public let hasVolume: Bool
    public let hasProblem: Bool
    /// Private volume evidence; never displayed in the settings UI.
    let volumeUUID: String?

    public init(directory: String, dailyWriteBytes: Int64?, hasVolume: Bool, hasProblem: Bool, selectedDirectory: String? = nil, volumeUUID: String? = nil) {
        self.directory = directory; self.dailyWriteBytes = dailyWriteBytes
        self.hasVolume = hasVolume; self.hasProblem = hasProblem
        self.selectedDirectory = selectedDirectory
        self.volumeUUID = volumeUUID
    }
}

public enum ProviderCacheChange: Equatable, Sendable {
    case dailyWriteGB(Double)
    case directory(String)
    case resetDirectory
}

/// Private disk identity returned by Darkbloom's volume inspection.
struct ProviderCacheVolumeIdentity: Equatable, Sendable {
    let directory: String
    let uuid: String
}

public enum ProviderCacheParser {
    static func parseVolumeIdentity(_ data: Data) throws -> ProviderCacheVolumeIdentity {
        struct Payload: Decodable {
            struct Volume: Decodable { let directory: String; let uuid: String }
            let scope: String
            let volume: Volume?
            let problem: String?
        }
        guard data.count <= 256 * 1024 else { throw ProviderExtrasParseError.invalidPayload }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            guard payload.scope == "saved_settings", payload.problem == nil, let volume = payload.volume,
                  let uuid = UUID(uuidString: volume.uuid),
                  uuid.uuidString != "00000000-0000-0000-0000-000000000000",
                  volume.directory.utf8.count <= 4096,
                  volume.directory.rangeOfCharacter(from: .controlCharacters) == nil,
                  normalizedSelectedDirectory(volume.directory) == volume.directory else {
                throw ProviderExtrasParseError.invalidValue
            }
            return .init(directory: volume.directory, uuid: volume.uuid)
        } catch let error as ProviderExtrasParseError { throw error }
        catch { throw ProviderExtrasParseError.invalidPayload }
    }

    /// Matches the provider's known system aliases without resolving symlinks.
    public static func normalizedSelectedDirectory(_ path: String) -> String? {
        guard path.hasPrefix("/"), !path.utf8.contains(0) else { return nil }
        let components = path.split(separator: "/")
        guard !components.contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        var normalized = "/" + components.joined(separator: "/")
        if normalized == "/var" || normalized.hasPrefix("/var/") || normalized == "/tmp" || normalized.hasPrefix("/tmp/") {
            normalized = "/private" + normalized
        }
        return normalized
    }

    public static func parse(_ data: Data) throws -> ProviderCacheStatus {
        guard data.count <= 256 * 1024 else { throw ProviderExtrasParseError.invalidPayload }
        struct Payload: Decodable {
            struct Volume: Decodable { let directory: String?; let uuid: String? }
            let directory: String
            let dailyWriteBytes: Int64?
            let unlimited: Bool?
            let dailyWriteSource: String
            let scope: String
            let volume: Volume?
            let problem: String?
        }
        do {
            let value = try JSONDecoder().decode(Payload.self, from: data)
            guard value.scope == "saved_settings", value.directory.hasPrefix("/"),
                  value.directory.utf8.count <= 4096,
                  value.directory.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw ProviderExtrasParseError.invalidValue
            }
            if let selected = value.volume?.directory {
                guard selected.hasPrefix("/"), selected.utf8.count <= 4096,
                      selected.rangeOfCharacter(from: .controlCharacters) == nil else { throw ProviderExtrasParseError.invalidValue }
            }
            if let uuid = value.volume?.uuid, UUID(uuidString: uuid) == nil { throw ProviderExtrasParseError.invalidValue }
            switch value.dailyWriteSource {
            case "saved_settings":
                guard let bytes = value.dailyWriteBytes, bytes >= 0, value.unlimited == (bytes == 0) else {
                    throw ProviderExtrasParseError.invalidValue
                }
            case "startup_environment_or_default":
                guard value.dailyWriteBytes == nil, value.unlimited == nil else { throw ProviderExtrasParseError.invalidValue }
            default: throw ProviderExtrasParseError.unsupportedValue
            }
            return ProviderCacheStatus(directory: value.directory, dailyWriteBytes: value.dailyWriteBytes,
                                       hasVolume: value.volume != nil, hasProblem: value.problem != nil,
                                       selectedDirectory: value.volume?.directory, volumeUUID: value.volume?.uuid)
        } catch let error as ProviderExtrasParseError { throw error }
        catch { throw ProviderExtrasParseError.invalidPayload }
    }

    public static func validDailyWriteGB(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value * 1_000_000_000 < Double(Int64.max)
            && (value == 0 || value * 1_000_000_000 >= 1)
    }
}
