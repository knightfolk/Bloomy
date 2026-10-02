import Foundation

/// A private semantic comparison of the policies enrollment must preserve.
/// Values never leave this type, reach logs, or enter the public status DTO.
struct ProviderAutopilotPreservationBaseline: Equatable, Sendable {
    let privateOnly: Bool
    private let values: [String: String]

    static func read(_ url: URL) throws -> Self {
        let data = try Data(contentsOf: url)
        guard data.count <= 1_048_576, let text = String(data: data, encoding: .utf8) else {
            throw ProviderConfigError.validationFailed("Saved policy cannot be verified")
        }
        var section = ""
        var window = -1
        var values: [String: String] = [:]
        var pendingKey: String?
        var pendingValue = ""
        for raw in text.components(separatedBy: .newlines) {
            let line = canonical(raw)
            guard !line.isEmpty else { continue }
            if let key = pendingKey {
                pendingValue += line
                if balanced(pendingValue) {
                    values[key] = normalized(pendingValue, path: key)
                    pendingKey = nil; pendingValue = ""
                }
                continue
            }
            if line.hasPrefix("[["), line.hasSuffix("]]" ) {
                section = String(line.dropFirst(2).dropLast(2))
                if section == "schedule.windows" { window += 1 }
                continue
            }
            if line.hasPrefix("["), line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast())
                continue
            }
            guard let equals = line.firstIndex(of: "=") else { continue }
            let key = String(line[..<equals])
            let value = String(line[line.index(after: equals)...])
            let protected = section == "schedule" || section == "schedule.windows"
                || section == "backend" && key == "idle_timeout_mins"
                || section == "provider" && key == "memory_reserve_gb"
                || section == "coordinator" && key == "private_only"
            guard protected else { continue }
            let path = section + (section == "schedule.windows" ? ".\(window)" : "") + "." + key
            guard values[path] == nil else { throw ProviderConfigError.validationFailed("Saved policy cannot be verified") }
            if balanced(value) { values[path] = normalized(value, path: path) }
            else { pendingKey = path; pendingValue = value }
        }
        guard pendingKey == nil else { throw ProviderConfigError.validationFailed("Saved policy cannot be verified") }
        // ConfigManager materializes defaults when writing; absence and default
        // values are equivalent policies rather than a spurious lost-setting error.
        values["coordinator.private_only", default: "false"] = values["coordinator.private_only"] ?? "false"
        values["schedule.enabled", default: "false"] = values["schedule.enabled"] ?? "false"
        values["backend.idle_timeout_mins", default: "60.0"] = values["backend.idle_timeout_mins"] ?? "60.0"
        values["provider.memory_reserve_gb", default: "4.0"] = values["provider.memory_reserve_gb"] ?? "4.0"
        return Self(privateOnly: values["coordinator.private_only"] != "false", values: values)
    }

    private static func normalized(_ value: String, path: String) -> String {
        if path.hasSuffix("memory_reserve_gb") || path.hasSuffix("idle_timeout_mins"),
           let number = Double(value.replacingOccurrences(of: "_", with: "")), number.isFinite {
            return String(number)
        }
        if (value.hasPrefix("'") && value.hasSuffix("'")) || (value.hasPrefix("\"") && value.hasSuffix("\"")) {
            let decoded: String?
            if value.hasPrefix("'") { decoded = String(value.dropFirst().dropLast()) }
            else { decoded = try? JSONDecoder().decode(String.self, from: Data(value.utf8)) }
            if let decoded, let encoded = try? JSONEncoder().encode(decoded) {
                return String(data: encoded, encoding: .utf8) ?? value
            }
        }
        if path.hasSuffix(".days") {
            // Weekday membership has no ordering semantics. Upstream accepts
            // abbreviated and full names; preserve unknown values conservatively.
            let json = value.replacingOccurrences(of: "'", with: "\"").replacingOccurrences(of: ",]", with: "]")
            if let days = try? JSONDecoder().decode([String].self, from: Data(json.utf8)) {
                let aliases = ["monday": "mon", "tuesday": "tue", "wednesday": "wed", "thursday": "thu", "friday": "fri", "saturday": "sat", "sunday": "sun"]
                let normalized = Set(days.map { aliases[$0.lowercased()] ?? $0.lowercased() }).sorted()
                if let encoded = try? JSONEncoder().encode(normalized) { return String(data: encoded, encoding: .utf8) ?? value }
            }
        }
        return value
    }

    private static func canonical(_ text: String) -> String {
        var result = "", quote: Character?, escaping = false
        for character in text {
            if let active = quote {
                result.append(character)
                if escaping { escaping = false }
                else if character == "\\" && active == "\"" { escaping = true }
                else if character == active { quote = nil }
            } else if character == "#" { break }
            else if character == "\"" || character == "'" { quote = character; result.append(character) }
            else if !character.isWhitespace { result.append(character) }
        }
        return result
    }

    private static func balanced(_ text: String) -> Bool {
        var depth = 0, quote: Character?, escaping = false
        for character in text {
            if let active = quote {
                if escaping { escaping = false }
                else if character == "\\" && active == "\"" { escaping = true }
                else if character == active { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "[" || character == "{" { depth += 1 }
            else if character == "]" || character == "}" { depth -= 1 }
        }
        return quote == nil && depth == 0
    }
}
