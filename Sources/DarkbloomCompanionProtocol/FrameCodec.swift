import Foundation

public struct FrameEncoder: Sendable {
    public init() {}

    public func encode(_ envelope: Envelope) throws -> Data {
        try envelope.validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let payload = try encoder.encode(envelope)
        guard payload.count <= ProtocolLimits.maximumFrameBytes else {
            throw ProtocolError.frameTooLarge(payload.count)
        }
        if envelope.messageType.hasCommandSizeLimit, payload.count > ProtocolLimits.maximumCommandBytes {
            throw ProtocolError.commandTooLarge(payload.count)
        }
        var frame = Data(capacity: 4 + payload.count)
        let length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        return frame
    }
}

public struct FrameDecoder: Sendable {
    private var buffer = Data()

    public init() {}

    public mutating func append(_ bytes: Data) throws -> [Envelope] {
        guard buffer.count <= ProtocolLimits.maximumBufferedBytes,
              bytes.count <= ProtocolLimits.maximumBufferedBytes - buffer.count else {
            throw ProtocolError.bufferedInputTooLarge(buffer.count + bytes.count)
        }
        if !bytes.isEmpty { buffer.append(bytes) }
        var decoded: [Envelope] = []
        while buffer.count >= 4 {
            let length = Int(buffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            guard length > 0 else { throw ProtocolError.invalidFrameLength(length) }
            guard length <= ProtocolLimits.maximumFrameBytes else { throw ProtocolError.frameTooLarge(length) }
            let frameLength = 4 + length
            guard buffer.count >= frameLength else { break }
            let payloadStart = buffer.index(buffer.startIndex, offsetBy: 4)
            let payloadEnd = buffer.index(payloadStart, offsetBy: length)
            let json = Data(buffer[payloadStart..<payloadEnd])
            try JSONStructureValidator.validate(json)
            let messageType = try JSONWireSchema.validate(json)
            if messageType?.hasCommandSizeLimit == true,
               json.count > ProtocolLimits.maximumCommandBytes {
                throw ProtocolError.commandTooLarge(json.count)
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .millisecondsSince1970
            do {
                guard decoded.count < ProtocolLimits.maximumFramesPerAppend else {
                    throw ProtocolError.tooManyFrames(decoded.count + 1)
                }
                decoded.append(try decoder.decode(Envelope.self, from: json))
            } catch let error as ProtocolError {
                throw error
            } catch {
                throw ProtocolError.malformedJSON
            }
            buffer.removeFirst(frameLength)
        }
        return decoded
    }

    public mutating func finish() throws -> [Envelope] {
        let values = try append(Data())
        guard buffer.isEmpty else { throw ProtocolError.incompleteFrame }
        return values
    }
}

private enum JSONWireSchema {
    static func validate(_ data: Data) throws -> MessageType? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProtocolError.malformedJSON
        }
        try closed(root, ["protocolMajor", "messageType", "requestID", "payload"], "envelope")
        guard (root["protocolMajor"] as? NSNumber)?.uint16Value == ProtocolLimits.currentMajor,
              let rawType = root["messageType"] as? String,
              let type = MessageType(rawValue: rawType),
              let payload = root["payload"] as? [String: Any] else { return nil }
        try validatePayload(payload, type: type)
        return type
    }

    private static func validatePayload(_ value: [String: Any], type: MessageType) throws {
        switch type {
        case .pairingInvitation:
            try closed(value, ["hostID", "hostName", "invitationID", "invitationSecret", "hostSPKIPin", "expiresAt", "routes"], type.rawValue)
            if let routes = value["routes"] as? [String: Any] {
                try closed(routes, ["candidates"], "pairingInvitation.routes")
                try dictionaries(routes["candidates"]).enumerated().forEach { index, candidate in
                    try closed(candidate, ["kind", "host", "port"], "pairingInvitation.routes[\(index)]")
                }
            }
        case .enrollmentProof:
            try closed(value, ["invitationID", "phoneID", "phoneName", "identityCertificate", "approvalPublicKey", "nonce", "transcriptSignature"], type.rawValue)
        case .pendingEnrollment:
            try closed(value, ["enrollmentID", "phoneID", "comparisonCode", "expiresAt"], type.rawValue)
        case .enrollmentResult:
            try closed(value, ["device", "policyEpoch"], type.rawValue)
            try pairedDevice(value["device"], path: "enrollmentResult.device")
        case .sessionChallenge:
            try closed(value, ["nonce", "expiresAt"], type.rawValue)
        case .sessionAuthenticate:
            try closed(value, ["deviceID", "nonce", "signature"], type.rawValue)
        case .monitorSubscribe:
            try closed(value, ["minimumIntervalSeconds"], type.rawValue)
        case .companionSnapshot:
            try snapshot(value)
        case .historyQuery:
            try closed(value, ["periodStart", "periodEnd", "cursor", "modelID", "maximumBuckets"], type.rawValue)
        case .historyPage:
            try closed(value, ["buckets", "hostTimeZoneID", "coverage", "nextCursor"], type.rawValue)
            for (index, bucket) in dictionaries(value["buckets"]).enumerated() {
                try closed(bucket, ["start", "end", "observations"], "historyPage.buckets[\(index)]")
                try observations(bucket["observations"], path: "historyPage.buckets[\(index)].observations")
            }
        case .alertHistoryQuery:
            try closed(value, ["cursor", "maximumRecords"], type.rawValue)
        case .alertHistoryPage:
            try closed(value, ["hostID", "records", "nextCursor"], type.rawValue)
            for (index, record) in dictionaries(value["records"]).enumerated() {
                try closed(record, ["id", "code", "transition", "occurredAt", "observedDurationSeconds", "observationCount"], "alertHistoryPage.records[\(index)]")
            }
        case .settingsDraft:
            try closed(value, [], type.rawValue)
        case .settingsSnapshot:
            try closed(value, ["draftID", "revision", "saved", "applied", "concurrentRequestRange", "residentSlotRange", "restartRequired"], type.rawValue)
            try settingsValues(value["saved"], path: "settingsSnapshot.saved")
            if !(value["applied"] is NSNull), value["applied"] != nil { try settingsValues(value["applied"], path: "settingsSnapshot.applied") }
            try integerRange(value["concurrentRequestRange"], path: "settingsSnapshot.concurrentRequestRange")
            try integerRange(value["residentSlotRange"], path: "settingsSnapshot.residentSlotRange")
        case .settingsPatch:
            try closed(value, ["draftID", "expectedRevision", "patch"], type.rawValue)
            try settingsPatch(value["patch"], path: "settingsPatch.patch")
        case .settingsSave:
            try closed(value, ["draftID", "expectedRevision"], type.rawValue)
        case .controlProposal:
            try closed(value, ["requestID", "expectedRevision", "action"], type.rawValue)
            try action(value["action"], path: "controlProposal.action")
        case .preparedCommand:
            try closed(value, ["commandID", "requestID", "hostID", "deviceID", "runtimeEpoch", "action", "risk", "expectedRevision", "policyEpoch", "nonce", "expiresAt", "signedPayload"], type.rawValue)
            try action(value["action"], path: "preparedCommand.action")
        case .signedApproval:
            try closed(value, ["commandID", "signedPayload", "signature"], type.rawValue)
        case .operationQuery:
            try closed(value, ["operationID"], type.rawValue)
        case .operationStatus:
            try closed(value, ["operationID", "requestID", "commandID", "state", "progress", "error", "updatedAt"], type.rawValue)
            if !(value["error"] is NSNull), let error = value["error"] as? [String: Any] {
                try closed(error, ["code", "reason", "retryAfterSeconds"], "operationStatus.error")
            }
        case .deviceList:
            try closed(value, ["mode", "devices"], type.rawValue)
            for (index, device) in dictionaries(value["devices"]).enumerated() {
                try pairedDevice(device, path: "deviceList.devices[\(index)]")
            }
        case .deviceRevoke:
            try closed(value, ["deviceID"], type.rawValue)
        case .deviceRevokeResponse:
            try closed(value, ["deviceID"], type.rawValue)
        case .safeError:
            try closed(value, ["code", "reason", "retryAfterSeconds"], type.rawValue)
        }
    }

    private static func snapshot(_ value: [String: Any]) throws {
        try closed(value, ["schema", "hostID", "runtimeEpoch", "sequence", "generatedAt", "observations", "models", "states", "capabilities"], "companionSnapshot")
        try observations(value["observations"], path: "companionSnapshot.observations")
        for (index, model) in dictionaries(value["models"]).enumerated() {
            try closed(model, ["id", "name", "enabled", "advertised", "resident", "active", "tokenRate", "rateWindow"], "companionSnapshot.models[\(index)]")
        }
        if let states = value["states"] as? [String: Any] {
            try closed(states, ["provider", "macApp", "helper", "connection"], "companionSnapshot.states")
            for name in ["provider", "macApp", "helper", "connection"] {
                if let state = states[name] as? [String: Any] {
                    try closed(state, ["state", "observedAt", "reason"], "companionSnapshot.states.\(name)")
                }
            }
        }
    }

    private static func observations(_ any: Any?, path: String) throws {
        // Observation objects are the sole additive surface within protocol major 1.
        // Known fields remain strongly typed by MetricObservation after this check.
        guard any == nil || any is [Any] else { throw ProtocolError.malformedJSON }
    }

    private static func settingsValues(_ any: Any?, path: String) throws {
        guard let value = any as? [String: Any] else { throw ProtocolError.malformedJSON }
        try closed(value, ["enabledModels", "preloadModels", "maximumConcurrentRequests", "residentModelSlots", "startupPreload"], path)
    }

    private static func integerRange(_ any: Any?, path: String) throws {
        guard let value = any as? [String: Any] else { throw ProtocolError.malformedJSON }
        try closed(value, ["minimum", "maximum"], path)
    }

    private static func settingsPatch(_ any: Any?, path: String) throws {
        guard let value = any as? [String: Any] else { throw ProtocolError.malformedJSON }
        try closed(value, ["provider", "app"], path)
        if let provider = value["provider"] as? [String: Any] {
            try closed(provider, ["enabledModels", "preloadModels", "maximumConcurrentRequests", "residentModelSlots", "startupPreload"], path + ".provider")
        }
        if let app = value["app"] as? [String: Any] {
            try closed(app, ["electricityRatePerKWh", "currencyCode"], path + ".app")
        }
    }

    private static func action(_ any: Any?, path: String) throws {
        guard let value = any as? [String: Any], let type = value["type"] as? String else {
            throw ProtocolError.malformedJSON
        }
        switch type {
        case "providerLifecycle", "appLifecycle": try closed(value, ["type", "action"], path)
        case "applySavedModelsLive": try closed(value, ["type"], path)
        case "applySettings":
            try closed(value, ["type", "draftID", "patch"], path)
            try settingsPatch(value["patch"], path: path + ".patch")
        case "saveSettings": try closed(value, ["type", "draftID"], path)
        default: break // ControlAction emits the typed unknown-command error.
        }
    }

    private static func pairedDevice(_ any: Any?, path: String) throws {
        guard let value = any as? [String: Any] else { throw ProtocolError.malformedJSON }
        try closed(value, ["deviceID", "displayName", "capabilities", "enrolledAt"], path)
    }

    private static func dictionaries(_ any: Any?) -> [[String: Any]] {
        (any as? [Any])?.compactMap { $0 as? [String: Any] } ?? []
    }

    private static func closed(_ value: [String: Any], _ allowed: Set<String>, _ path: String) throws {
        if let unknown = value.keys.filter({ !allowed.contains($0) }).sorted().first {
            throw ProtocolError.unknownJSONField("\(path).\(unknown)")
        }
    }
}

private enum JSONStructureValidator {
    static func validate(_ data: Data) throws {
        var parser = JSONParser(bytes: Array(data))
        try parser.parse()
    }
}

private struct JSONParser {
    let bytes: [UInt8]
    var index = 0

    mutating func parse() throws {
        skipWhitespace()
        try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw ProtocolError.malformedJSON }
    }

    mutating func parseValue(depth: Int) throws {
        skipWhitespace()
        guard index < bytes.count else { throw ProtocolError.malformedJSON }
        switch bytes[index] {
        case 0x7B: try parseObject(depth: depth + 1) // {
        case 0x5B: try parseArray(depth: depth + 1) // [
        case 0x22: _ = try parseString()
        case 0x74: try consumeLiteral("true")
        case 0x66: try consumeLiteral("false")
        case 0x6E: try consumeLiteral("null")
        case 0x2D, 0x30...0x39: try parseNumber()
        default: throw ProtocolError.malformedJSON
        }
    }

    mutating func parseObject(depth: Int) throws {
        try checkDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x7D) { return }
        var keys = Set<String>()
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == 0x22 else { throw ProtocolError.malformedJSON }
            let key = try parseString()
            guard keys.insert(key).inserted else { throw ProtocolError.duplicateJSONKey(key) }
            skipWhitespace()
            guard consume(0x3A) else { throw ProtocolError.malformedJSON }
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x7D) { return }
            guard consume(0x2C) else { throw ProtocolError.malformedJSON }
        }
    }

    mutating func parseArray(depth: Int) throws {
        try checkDepth(depth)
        index += 1
        skipWhitespace()
        if consume(0x5D) { return }
        while true {
            try parseValue(depth: depth)
            skipWhitespace()
            if consume(0x5D) { return }
            guard consume(0x2C) else { throw ProtocolError.malformedJSON }
        }
    }

    mutating func parseString() throws -> String {
        let start = index
        index += 1
        while index < bytes.count {
            let byte = bytes[index]
            if byte == 0x22 {
                index += 1
                let data = Data(bytes[start..<index])
                guard let value = try? JSONDecoder().decode(String.self, from: data) else {
                    throw ProtocolError.malformedJSON
                }
                return value
            }
            if byte < 0x20 { throw ProtocolError.malformedJSON }
            if byte == 0x5C {
                index += 1
                guard index < bytes.count else { throw ProtocolError.malformedJSON }
                if bytes[index] == 0x75 {
                    guard index + 4 < bytes.count,
                          bytes[(index + 1)...(index + 4)].allSatisfy(isHexDigit) else {
                        throw ProtocolError.malformedJSON
                    }
                    index += 4
                } else if ![0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74].contains(bytes[index]) {
                    throw ProtocolError.malformedJSON
                }
            }
            index += 1
        }
        throw ProtocolError.malformedJSON
    }

    mutating func parseNumber() throws {
        let start = index
        if consume(0x2D), index >= bytes.count { throw ProtocolError.malformedJSON }
        if consume(0x30) {
            if index < bytes.count, (0x30...0x39).contains(bytes[index]) { throw ProtocolError.malformedJSON }
        } else {
            guard consumeDigits() else { throw ProtocolError.malformedJSON }
        }
        if consume(0x2E), !consumeDigits() { throw ProtocolError.malformedJSON }
        if index < bytes.count, bytes[index] == 0x65 || bytes[index] == 0x45 {
            index += 1
            if index < bytes.count, bytes[index] == 0x2B || bytes[index] == 0x2D { index += 1 }
            guard consumeDigits() else { throw ProtocolError.malformedJSON }
        }
        guard index > start else { throw ProtocolError.malformedJSON }
    }

    mutating func consumeDigits() -> Bool {
        let start = index
        while index < bytes.count, (0x30...0x39).contains(bytes[index]) { index += 1 }
        return index > start
    }

    mutating func consumeLiteral(_ literal: StaticString) throws {
        let values = Array(String(describing: literal).utf8)
        guard index + values.count <= bytes.count,
              Array(bytes[index..<(index + values.count)]) == values else {
            throw ProtocolError.malformedJSON
        }
        index += values.count
    }

    mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }

    mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    func checkDepth(_ depth: Int) throws {
        guard depth <= ProtocolLimits.maximumJSONDepth else { throw ProtocolError.jsonDepthExceeded(depth) }
    }

    private func isHexDigit(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x46).contains(byte) || (0x61...0x66).contains(byte)
    }
}
