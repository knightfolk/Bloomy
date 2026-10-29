import Foundation

/// Saved cache settings, not evidence of the running provider's effective settings.
public struct ProviderCacheStatus: Equatable, Sendable {
    public let directory: String
    public let dailyWriteBytes: Int64?
    public let hasVolume: Bool
    public let hasProblem: Bool

    public init(directory: String, dailyWriteBytes: Int64?, hasVolume: Bool, hasProblem: Bool) {
        self.directory = directory; self.dailyWriteBytes = dailyWriteBytes
        self.hasVolume = hasVolume; self.hasProblem = hasProblem
    }
}

public enum ProviderCacheChange: Equatable, Sendable {
    case dailyWriteGB(Double)
    case directory(String)
    case resetDirectory
}

public enum ProviderCacheParser {
    public static func parse(_ data: Data) throws -> ProviderCacheStatus {
        guard data.count <= 256 * 1024 else { throw ProviderExtrasParseError.invalidPayload }
        struct Payload: Decodable {
            struct Volume: Decodable {}
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
                                       hasVolume: value.volume != nil, hasProblem: value.problem != nil)
        } catch let error as ProviderExtrasParseError { throw error }
        catch { throw ProviderExtrasParseError.invalidPayload }
    }

    public static func validDailyWriteGB(_ value: Double) -> Bool {
        value.isFinite && value >= 0 && value * 1_000_000_000 < Double(Int64.max)
            && (value == 0 || value * 1_000_000_000 >= 1)
    }
}
