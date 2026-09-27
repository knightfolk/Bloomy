import Foundation
import Testing
@testable import DarkbloomCompanionProtocol

@Suite("Companion frame codec")
struct FrameCodecTests {
    @Test("rejects oversized and incomplete frames")
    func rejectsOversizedAndPartialFrames() throws {
        var oversized = Data()
        oversized.append(contentsOf: [0x00, 0x04, 0x00, 0x01])
        var decoder = FrameDecoder()
        #expect(throws: ProtocolError.frameTooLarge(262_145)) {
            try decoder.append(oversized)
        }

        let frame = try FrameEncoder().encode(.fixtureSnapshot)
        var partial = FrameDecoder()
        #expect(try partial.append(frame.prefix(frame.count - 1)) == [])
        #expect(throws: ProtocolError.incompleteFrame) {
            try partial.finish()
        }

        let small = try FrameEncoder().encode(.fixtureSnapshot)
        var pairDecoder = FrameDecoder()
        #expect(try pairDecoder.append(small + small) == [.fixtureSnapshot, .fixtureSnapshot])

        var batch = Data()
        for _ in 0...ProtocolLimits.maximumFramesPerAppend { batch.append(small) }
        var batchDecoder = FrameDecoder()
        #expect(throws: ProtocolError.tooManyFrames(65)) {
            try batchDecoder.append(batch)
        }

        var bufferedDecoder = FrameDecoder()
        let oversizedChunk = Data(
            repeating: 0,
            count: ProtocolLimits.maximumBufferedBytes + 1
        )
        #expect(throws: ProtocolError.bufferedInputTooLarge(oversizedChunk.count)) {
            try bufferedDecoder.append(oversizedChunk)
        }
    }

    @Test("rejects duplicate keys and JSON deeper than sixteen containers")
    func rejectsDuplicateSecurityKeysAndDepth17() throws {
        let requestID = UUID().uuidString.lowercased()
        let duplicate = Data("""
        {"protocolMajor":1,"messageType":"monitorSubscribe","requestID":"\(requestID)","requestID":"\(requestID)","payload":{"minimumIntervalSeconds":2}}
        """.utf8)
        var duplicateDecoder = FrameDecoder()
        #expect(throws: ProtocolError.duplicateJSONKey("requestID")) {
            try duplicateDecoder.append(frame(duplicate))
        }

        let escapedDuplicate = Data("""
        {"protocolMajor":1,"messageType":"monitorSubscribe","requestID":"\(requestID)","\\u0072equestID":"\(requestID)","payload":{"minimumIntervalSeconds":2}}
        """.utf8)
        var escapedDecoder = FrameDecoder()
        #expect(throws: ProtocolError.duplicateJSONKey("requestID")) {
            try escapedDecoder.append(frame(escapedDuplicate))
        }

        let nested = String(repeating: "{\"x\":", count: 17) + "0" + String(repeating: "}", count: 17)
        let deep = Data("""
        {"protocolMajor":1,"messageType":"monitorSubscribe","requestID":"\(requestID)","payload":\(nested)}
        """.utf8)
        var deepDecoder = FrameDecoder()
        #expect(throws: ProtocolError.jsonDepthExceeded(17)) {
            try deepDecoder.append(frame(deep))
        }
    }

    @Test("rejects unsupported major versions, message types, and command cases")
    func rejectsUnknownMajorAndCommand() throws {
        let requestID = UUID().uuidString.lowercased()
        let unknownMajor = Data("""
        {"protocolMajor":2,"messageType":"monitorSubscribe","requestID":"\(requestID)","payload":{"minimumIntervalSeconds":2}}
        """.utf8)
        var majorDecoder = FrameDecoder()
        #expect(throws: ProtocolError.unsupportedMajor(2)) {
            try majorDecoder.append(frame(unknownMajor))
        }

        let unknownType = Data("""
        {"protocolMajor":1,"messageType":"runShell","requestID":"\(requestID)","payload":{}}
        """.utf8)
        var typeDecoder = FrameDecoder()
        #expect(throws: ProtocolError.unknownMessageType("runShell")) {
            try typeDecoder.append(frame(unknownType))
        }

        let unknownCommand = Data("""
        {"protocolMajor":1,"messageType":"controlProposal","requestID":"\(requestID)","payload":{"requestID":"\(requestID)","action":{"type":"runShell"}}}
        """.utf8)
        var commandDecoder = FrameDecoder()
        #expect(throws: ProtocolError.unknownCommand("runShell")) {
            try commandDecoder.append(frame(unknownCommand))
        }

        let privilegedHostingPatch = Data("""
        {"protocolMajor":1,"messageType":"controlProposal","requestID":"\(requestID)","payload":{"requestID":"\(requestID)","expectedRevision":"r1","action":{"type":"applySettings","draftID":"\(UUID().uuidString.lowercased())","patch":{"hosting":{"mode":"lan","authenticationEnabled":false}}}}}
        """.utf8)
        var hostingDecoder = FrameDecoder()
        #expect(throws: ProtocolError.unknownJSONField(
            "controlProposal.action.patch.hosting"
        )) {
            try hostingDecoder.append(frame(privilegedHostingPatch))
        }
    }

    @Test("same-major observations allow additive fields but other objects stay closed")
    func additiveObservationFieldsOnly() throws {
        let goldenURL = try #require(Bundle.module.url(
            forResource: "snapshot-envelope", withExtension: "json", subdirectory: "Fixtures"
        ))
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let additiveObservation = golden.replacingOccurrences(
            of: "\"availability\":\"available\"",
            with: "\"futureOptional\":{\"nested\":true},\"availability\":\"available\""
        )
        var additiveDecoder = FrameDecoder()
        #expect(try additiveDecoder.append(frame(Data(additiveObservation.utf8))).count == 1)

        let unknownEnvelope = golden.dropLast() + ",\"futureTopLevel\":true}"
        var envelopeDecoder = FrameDecoder()
        #expect(throws: ProtocolError.unknownJSONField("envelope.futureTopLevel")) {
            try envelopeDecoder.append(frame(Data(unknownEnvelope.utf8)))
        }

        let requestID = UUID().uuidString.lowercased()
        let unknownPayload = Data("""
        {"protocolMajor":1,"messageType":"controlProposal","requestID":"\(requestID)","payload":{"requestID":"\(requestID)","action":{"type":"providerLifecycle","action":"start"},"shell":"echo nope"}}
        """.utf8)
        var payloadDecoder = FrameDecoder()
        #expect(throws: ProtocolError.unknownJSONField("controlProposal.shell")) {
            try payloadDecoder.append(frame(unknownPayload))
        }
    }

    @Test("command envelopes have the separate sixteen KiB cap")
    func commandFrameLimit() throws {
        let payload = Data(repeating: 7, count: ProtocolLimits.maximumSignedPayloadBytes)
        let prepared = PreparedCommand(
            commandID: UUID(), requestID: UUID(), hostID: UUID(), deviceID: UUID(), runtimeEpoch: UUID(),
            action: .providerLifecycle(.start), risk: .restartsProvider, expectedRevision: "r1",
            policyEpoch: 1, nonce: Data(repeating: 8, count: 32),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_000), signedPayload: payload
        )
        let envelope = Envelope(requestID: prepared.requestID, payload: .preparedCommand(prepared))
        #expect(throws: ProtocolError.self) { try FrameEncoder().encode(envelope) }

        let requestID = UUID().uuidString.lowercased()
        let modelIDs = (0..<ProtocolLimits.maximumModels).map { index in
            String(repeating: "m", count: 96) + String(format: "%03d", index)
        }
        let object: [String: Any] = [
            "protocolMajor": 1,
            "messageType": "controlProposal",
            "requestID": requestID,
            "payload": [
                "requestID": requestID,
                "expectedRevision": "r1",
                "action": [
                    "type": "applySettings",
                    "draftID": UUID().uuidString.lowercased(),
                    "patch": ["provider": ["enabledModels": modelIDs]],
                ],
            ],
        ]
        let inboundJSON = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        #expect(inboundJSON.count > ProtocolLimits.maximumCommandBytes)
        var inboundDecoder = FrameDecoder()
        #expect(throws: ProtocolError.commandTooLarge(inboundJSON.count)) {
            try inboundDecoder.append(frame(inboundJSON))
        }
    }

    @Test("golden monitor envelope remains byte stable")
    func goldenSnapshotEnvelope() throws {
        let expected = try #require(Bundle.module.url(
            forResource: "snapshot-envelope", withExtension: "json", subdirectory: "Fixtures"
        ))
        let json = Data(try String(contentsOf: expected, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        let encoded = try FrameEncoder().encode(.fixtureSnapshot)
        #expect(encoded == frame(json))

        var decoder = FrameDecoder()
        #expect(try decoder.append(frame(json)) == [.fixtureSnapshot])
        #expect(try decoder.finish() == [])
    }
}

private func frame(_ json: Data) -> Data {
    var result = Data()
    let length = UInt32(json.count).bigEndian
    withUnsafeBytes(of: length) { result.append(contentsOf: $0) }
    result.append(json)
    return result
}
