import Foundation
import Testing
@testable import DarkbloomCompanionProtocol

@Suite("Companion wire contract")
struct ContractTests {
    @Test("bounds model snapshots and history pages")
    func boundsModelsAndHistoryPage() throws {
        let models = (0...ProtocolLimits.maximumModels).map { index in
            ModelSummary(id: "model-\(index)", name: "Model \(index)")
        }
        #expect(throws: ProtocolError.tooManyModels(257)) {
            try CompanionSnapshot.validated(
                hostID: UUID(), runtimeEpoch: UUID(), sequence: 1, generatedAt: .now,
                observations: [], models: models, states: .fixture
            )
        }

        let bucketIndexes = Array(0...ProtocolLimits.maximumHistoryBuckets)
        let buckets: [HistoryBucket] = bucketIndexes.map { index in
            let start = Date(timeIntervalSince1970: Double(index) * 3_600)
            let end = Date(timeIntervalSince1970: Double(index + 1) * 3_600)
            return HistoryBucket(
                start: start,
                end: end,
                observations: []
            )
        }
        #expect(throws: ProtocolError.tooManyHistoryBuckets(169)) {
            try HistoryPage.validated(
                buckets: buckets, hostTimeZoneID: "America/Phoenix", coverage: 1, nextCursor: nil
            )
        }
    }

    @Test("rejects ambiguous snapshots and unsafe display strings")
    func rejectsAmbiguousSnapshotsAndStrings() throws {
        let duplicate = [
            ModelSummary(id: "same-model", name: "First"),
            ModelSummary(id: "same-model", name: "Second"),
        ]
        #expect(throws: ProtocolError.invalidField("snapshot.duplicateModel")) {
            try CompanionSnapshot.validated(
                hostID: UUID(), runtimeEpoch: UUID(), sequence: 1, generatedAt: .now,
                observations: [], models: duplicate, states: .fixture
            )
        }

        let observations = (0...ProtocolLimits.maximumObservations).map { _ in
            MetricObservation(
                metric: .requestsServed, value: 1, unit: .count,
                scope: .localProvider, provenance: .direct, capturedAt: .now,
                sourceAgeSeconds: 0, availability: .available, reason: nil
            )
        }
        #expect(throws: ProtocolError.tooManyObservations(65)) {
            try CompanionSnapshot.validated(
                hostID: UUID(), runtimeEpoch: UUID(), sequence: 1, generatedAt: .now,
                observations: observations, models: [], states: .fixture
            )
        }

        #expect(throws: ProtocolError.invalidField("route.host")) {
            try RouteCandidate(kind: .lan, host: "host\nspoof", port: 49_444).validate()
        }
        #expect(throws: ProtocolError.invalidField("model.name")) {
            try ModelSummary(id: "safe", name: "\t").validate()
        }
    }

    @Test("bootstrap accepts only enrollment traffic")
    func bootstrapAcceptsEnrollmentOnly() throws {
        for type in MessageType.allCases {
            let envelope = try Envelope.fixture(for: type)
            if type.isBootstrapMessage {
                #expect(throws: Never.self) { try envelope.validate(for: .bootstrap) }
            } else {
                #expect(throws: ProtocolError.messageNotAllowed(type, .bootstrap)) {
                    try envelope.validate(for: .bootstrap)
                }
            }
        }
    }

    @Test("every message case round trips with its exact typed payload")
    func exactMessageCasesRoundTrip() throws {
        #expect(Set(MessageType.allCases) == Set([
            .pairingInvitation, .enrollmentProof, .pendingEnrollment, .enrollmentResult,
            .sessionChallenge, .sessionAuthenticate,
            .monitorSubscribe, .companionSnapshot, .historyQuery, .historyPage,
            .alertHistoryQuery, .alertHistoryPage,
            .settingsDraft, .settingsSnapshot, .settingsPatch, .settingsSave,
            .controlProposal, .preparedCommand, .signedApproval, .operationQuery,
            .operationStatus, .deviceList, .deviceRevoke, .deviceRevokeResponse, .safeError,
        ]))

        for type in MessageType.allCases {
            let envelope = try Envelope.fixture(for: type)
            let encoded = try FrameEncoder().encode(envelope)
            var decoder = FrameDecoder()
            #expect(try decoder.append(encoded) == [envelope])
        }
    }

    @Test("commands retain request, operation, revision, and exact signed bytes")
    func commandIdentityAndBytes() throws {
        let requestID = UUID()
        let commandID = UUID()
        let signed = Data("host-issued-exact-json".utf8)
        let prepared = PreparedCommand(
            commandID: commandID,
            requestID: requestID,
            hostID: UUID(),
            deviceID: UUID(),
            runtimeEpoch: UUID(),
            action: .providerLifecycle(.restart),
            risk: .interruptsActiveWork,
            expectedRevision: "opaque-r7",
            policyEpoch: 4,
            nonce: Data(repeating: 7, count: 32),
            expiresAt: Date(timeIntervalSince1970: 1_800_000_060),
            signedPayload: signed
        )
        let approval = SignedApproval(commandID: commandID, signedPayload: signed, signature: Data(repeating: 9, count: 64))
        let status = OperationStatus(
            operationID: UUID(), requestID: requestID, commandID: commandID,
            state: .reconciling, progress: nil, error: nil, updatedAt: Date(timeIntervalSince1970: 1_800_000_001)
        )
        #expect(prepared.requestID == requestID)
        #expect(prepared.expectedRevision == "opaque-r7")
        #expect(approval.signedPayload == signed)
        #expect(status.operationID != commandID)
    }

    @Test("Apply Live is an explicit capability and signed command action")
    func applyLiveContract() throws {
        #expect(Capability.allCases.contains(.providerLiveSwitch))
        #expect(RuntimeState.allCases.contains(.scheduledIdle))
        #expect(RuntimeState.allCases.contains(.preloading))
        #expect(RuntimeState.allCases.contains(.switching))
        let requestID = UUID()
        let proposal = ControlProposal(
            requestID: requestID,
            expectedRevision: "saved-r8",
            action: .applySavedModelsLive
        )
        let envelope = Envelope(
            requestID: requestID,
            payload: .controlProposal(proposal)
        )

        let encoded = try FrameEncoder().encode(envelope)
        #expect(String(decoding: encoded, as: UTF8.self).contains(
            "\"type\":\"applySavedModelsLive\""
        ))
        var decoder = FrameDecoder()
        #expect(try decoder.append(encoded) == [envelope])
    }

    @Test("settings reject empty, duplicate, and preload-outside-enabled states")
    func rejectsAmbiguousSettings() {
        #expect(throws: ProtocolError.invalidField("settings.emptyPatch")) {
            try SettingsPatch().validate()
        }
        #expect(throws: ProtocolError.invalidField("appSettings.emptyPatch")) {
            try AppSettingsPatch().validate()
        }
        #expect(throws: ProtocolError.invalidField("settings.duplicateModel")) {
            try ProviderSettingsValues(enabledModels: ["a", "a"]).validate()
        }
        #expect(throws: ProtocolError.invalidField("settings.preloadNotEnabled")) {
            try ProviderSettingsValues(enabledModels: ["a"], preloadModels: ["b"]).validate()
        }
        #expect(throws: ProtocolError.invalidField("settings.values")) {
            try ProviderSettingsValues(
                enabledModels: ["a"], residentModelSlots: ProtocolLimits.maximumResidentModelSlots + 1
            ).validate()
        }
        #expect(throws: ProtocolError.invalidField("settings.residentModelSlots")) {
            try ProviderSettingsPatch(
                residentModelSlots: ProtocolLimits.maximumResidentModelSlots + 1
            ).validate()
        }
    }

    @Test("paired hosts expose route metadata without private trust material")
    func pairedHostIsPublicMetadataOnly() throws {
        let host = PairedHost(
            hostID: UUID(), displayName: "Studio Mac", routes: PeerRouteHints(candidates: [
                RouteCandidate(kind: .tailnet, host: "studio.example.ts.net", port: 49_443)
            ]), lastConnectedAt: nil
        )
        try host.validate()
        let encoded = try JSONEncoder().encode(host)
        let wire = String(decoding: encoded, as: UTF8.self)
        #expect(!wire.contains("privateKey"))
        #expect(!wire.contains("pin"))
    }
}

extension Envelope {
    static func fixture(for type: MessageType) throws -> Envelope {
        let requestID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
        let hostID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let deviceID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
        let commandID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let operationID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!
        let draftID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let settings = ProviderSettingsValues(
            enabledModels: ["safe-model"], preloadModels: ["safe-model"],
            maximumConcurrentRequests: 2, residentModelSlots: 1, startupPreload: true
        )
        let patch = SettingsPatch(provider: ProviderSettingsPatch(maximumConcurrentRequests: 3))
        let action = ControlAction.providerLifecycle(.restart)
        let signed = Data("host-issued-payload".utf8)

        let payload: EnvelopePayload
        switch type {
        case .pairingInvitation:
            payload = .pairingInvitation(PairingInvitation(
                hostID: hostID, hostName: "Test Mac", invitationID: requestID,
                invitationSecret: Data(repeating: 1, count: 32), hostSPKIPin: Data(repeating: 2, count: 32),
                expiresAt: now.addingTimeInterval(120), routes: PeerRouteHints(candidates: [
                    RouteCandidate(kind: .lan, host: "192.0.2.10", port: 49_444)
                ])
            ))
        case .enrollmentProof:
            payload = .enrollmentProof(EnrollmentProof(
                invitationID: requestID, phoneID: deviceID, phoneName: "Test Phone",
                identityCertificate: Data(repeating: 3, count: 64), approvalPublicKey: Data(repeating: 4, count: 32),
                nonce: Data(repeating: 5, count: 32), transcriptSignature: Data(repeating: 6, count: 64)
            ))
        case .pendingEnrollment:
            payload = .pendingEnrollment(PendingEnrollment(
                enrollmentID: requestID, phoneID: deviceID, comparisonCode: "123456", expiresAt: now.addingTimeInterval(120)
            ))
        case .enrollmentResult:
            payload = .enrollmentResult(EnrollmentResult(
                device: PairedDevice(deviceID: deviceID, displayName: "Test Phone", capabilities: [.monitor], enrolledAt: now),
                policyEpoch: 1
            ))
        case .sessionChallenge:
            payload = .sessionChallenge(SessionChallenge(
                nonce: Data(repeating: 9, count: 32), expiresAt: now.addingTimeInterval(10)
            ))
        case .sessionAuthenticate:
            payload = .sessionAuthenticate(SessionAuthentication(
                deviceID: deviceID, nonce: Data(repeating: 9, count: 32),
                signature: Data(repeating: 10, count: 64)
            ))
        case .monitorSubscribe:
            payload = .monitorSubscribe(MonitorSubscription())
        case .companionSnapshot:
            return .fixtureSnapshot
        case .historyQuery:
            payload = .historyQuery(HistoryQuery(periodStart: now.addingTimeInterval(-3_600), periodEnd: now))
        case .historyPage:
            payload = .historyPage(try HistoryPage.validated(
                buckets: [HistoryBucket(start: now.addingTimeInterval(-3_600), end: now, observations: [])],
                hostTimeZoneID: "America/Phoenix", coverage: 1, nextCursor: nil
            ))
        case .alertHistoryQuery:
            payload = .alertHistoryQuery(AlertHistoryQuery(cursor: nil, maximumRecords: 20))
        case .alertHistoryPage:
            payload = .alertHistoryPage(try AlertHistoryPage.validated(
                hostID: hostID,
                records: [CompanionAlertRecord(
                    id: 1, code: .providerOffline, transition: .raised,
                    occurredAt: now, observedDurationSeconds: 60, observationCount: 4
                )],
                nextCursor: nil
            ))
        case .settingsDraft:
            payload = .settingsDraft(SettingsDraftRequest())
        case .settingsSnapshot:
            payload = .settingsSnapshot(SettingsSnapshot(draftID: draftID, revision: "r1", saved: settings, applied: settings))
        case .settingsPatch:
            payload = .settingsPatch(SettingsPatchRequest(draftID: draftID, expectedRevision: "r1", patch: patch))
        case .settingsSave:
            payload = .settingsSave(SettingsSaveRequest(draftID: draftID, expectedRevision: "r1"))
        case .controlProposal:
            payload = .controlProposal(ControlProposal(requestID: requestID, expectedRevision: "r1", action: action))
        case .preparedCommand:
            payload = .preparedCommand(PreparedCommand(
                commandID: commandID, requestID: requestID, hostID: hostID, deviceID: deviceID,
                runtimeEpoch: UUID(), action: action, risk: .restartsProvider,
                expectedRevision: "r1", policyEpoch: 1, nonce: Data(repeating: 7, count: 32),
                expiresAt: now.addingTimeInterval(60), signedPayload: signed
            ))
        case .signedApproval:
            payload = .signedApproval(SignedApproval(
                commandID: commandID, signedPayload: signed, signature: Data(repeating: 8, count: 64)
            ))
        case .operationQuery:
            payload = .operationQuery(OperationQuery(operationID: operationID))
        case .operationStatus:
            payload = .operationStatus(OperationStatus(
                operationID: operationID, requestID: requestID, commandID: commandID,
                state: .accepted, progress: 0, error: nil, updatedAt: now
            ))
        case .deviceList:
            payload = .deviceList(DeviceListMessage(mode: .response, devices: [
                PairedDevice(deviceID: deviceID, displayName: "Test Phone", capabilities: [.monitor], enrolledAt: now)
            ]))
        case .deviceRevoke:
            payload = .deviceRevoke(DeviceRevokeRequest(deviceID: deviceID))
        case .deviceRevokeResponse:
            payload = .deviceRevokeResponse(DeviceRevokeResponse(deviceID: deviceID))
        case .safeError:
            payload = .safeError(SafeErrorResponse(code: .unavailable, reason: .sourceRefreshFailed, retryAfterSeconds: 5))
        }
        return Envelope(requestID: requestID, payload: payload)
    }
}
