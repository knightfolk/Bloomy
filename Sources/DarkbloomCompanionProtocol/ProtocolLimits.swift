import Foundation

public enum ProtocolLimits {
    public static let currentMajor: UInt16 = 1
    public static let maximumFrameBytes = 256 * 1024
    public static let maximumCommandBytes = 16 * 1024
    public static let maximumJSONDepth = 16
    public static let maximumModels = 256
    public static let maximumObservations = 64
    public static let maximumHistoryBuckets = 168
    public static let maximumRouteHints = 8
    public static let maximumDevices = 8
    public static let maximumIdentifierBytes = 128
    public static let maximumDisplayNameBytes = 160
    public static let maximumOpaqueRevisionBytes = 256
    public static let maximumBinaryFieldBytes = 8 * 1024
    public static let maximumSignedPayloadBytes = 12 * 1024
    public static let maximumResidentModelSlots = 16
    public static let maximumFramesPerAppend = 64
    public static let maximumBufferedBytes = 4 * (maximumFrameBytes + 4)
}

public enum ProtocolError: Error, Equatable, Sendable {
    case frameTooLarge(Int)
    case invalidFrameLength(Int)
    case incompleteFrame
    case duplicateJSONKey(String)
    case jsonDepthExceeded(Int)
    case malformedJSON
    case unsupportedMajor(UInt16)
    case unknownMessageType(String)
    case unknownCommand(String)
    case unknownJSONField(String)
    case payloadTypeMismatch(MessageType)
    case messageNotAllowed(MessageType, SessionPhase)
    case commandTooLarge(Int)
    case tooManyModels(Int)
    case tooManyObservations(Int)
    case tooManyHistoryBuckets(Int)
    case tooManyFrames(Int)
    case bufferedInputTooLarge(Int)
    case invalidField(String)
}

@inline(__always)
func requireBounded(_ value: String, maximumBytes: Int, field: String) throws {
    guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          value.utf8.count <= maximumBytes,
          value.rangeOfCharacter(from: .controlCharacters) == nil else {
        throw ProtocolError.invalidField(field)
    }
}

@inline(__always)
func requireFinite(_ value: Double?, field: String) throws {
    guard value?.isFinite ?? true else { throw ProtocolError.invalidField(field) }
}
