import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import XCTest
@testable import DarkbloomCompanion

final class MultiHostCompanionTests: XCTestCase {
    @MainActor
    func testCommandsUseOnlyTheSelectedHostsSession() async throws {
        let setup = try makeSetup(failingHost: nil)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        let store = setup.store
        XCTAssertNotEqual(store.displayName(for: setup.first), store.displayName(for: setup.second))

        await store.connectAfterApproval()
        store.selectHost(setup.second.hostID)
        await store.connectAfterApproval()
        await store.prepare(.providerLifecycle(.restart))

        let firstRequests = await setup.firstSession.requestTypes
        let secondRequests = await setup.secondSession.requestTypes
        XCTAssertFalse(firstRequests.contains(.controlProposal))
        XCTAssertTrue(secondRequests.contains(.controlProposal))
        XCTAssertEqual(store.pendingCommand?.hostID, setup.second.hostID)
        XCTAssertEqual(store.selectedHostID, setup.second.hostID)
    }

    @MainActor
    func testHostFailuresAndClockSkewRemainAttributedPerIdentity() async throws {
        let setup = try makeSetup(failingHost: .first)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }

        await setup.store.connectAfterApproval()
        setup.store.selectHost(setup.second.hostID)
        await setup.store.connectAfterApproval()

        let statuses = Dictionary(uniqueKeysWithValues: setup.store.fleetHostStatuses.map { ($0.id, $0) })
        XCTAssertEqual(statuses[setup.first.hostID]?.connection, .disconnected)
        XCTAssertNotNil(statuses[setup.first.hostID]?.errorMessage)
        XCTAssertEqual(statuses[setup.second.hostID]?.connection, .connected)
        XCTAssertFalse(statuses[setup.second.hostID]?.isStale ?? true)
        XCTAssertEqual(statuses[setup.second.hostID]?.snapshot?.hostID, setup.second.hostID)
        XCTAssertEqual(setup.store.selectedHostID, setup.second.hostID)
    }

    @MainActor
    func testAlertHistoryIsRequestedAndRetainedOnlyForItsHost() async throws {
        let setup = try makeSetup(failingHost: nil)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        setup.store.selectHost(setup.second.hostID)

        await setup.store.loadAlertHistory(hostID: setup.second.hostID, maximumRecords: 1_000)

        XCTAssertEqual(setup.store.selectedAlertRecords.map(\.id), [4, 3, 2, 1])
        XCTAssertEqual(setup.store.alertNextCursor, nil)
        let requests = await setup.secondSession.alertHistoryQueries
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.maximumRecords, ProtocolLimits.maximumAlertHistoryRecordsPerPage)
        let firstQueries = await setup.firstSession.alertHistoryQueries
        XCTAssertTrue(firstQueries.isEmpty)
    }

    @MainActor
    func testLocalForgetRemovesOneHostWithoutRevokingEitherPairing() async throws {
        let setup = try makeSetup(failingHost: nil)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        await setup.store.connectAfterApproval()

        await setup.store.forgetHost(hostID: setup.first.hostID)

        XCTAssertEqual(setup.store.hosts.map(\.hostID), [setup.second.hostID])
        XCTAssertEqual(setup.store.selectedHostID, setup.second.hostID)
        let firstRequests = await setup.firstSession.requestTypes
        XCTAssertFalse(firstRequests.contains(.deviceRevoke))
    }

    @MainActor
    func testRemoteSelfRevokeRemovesOnlySelectedHost() async throws {
        let setup = try makeSetup(failingHost: nil)
        defer { setup.defaults.removePersistentDomain(forName: setup.suite) }
        await setup.store.connectAfterApproval()

        await setup.store.revokeSelectedPhone()

        XCTAssertEqual(setup.store.hosts.map(\.hostID), [setup.second.hostID])
        XCTAssertEqual(setup.store.selectedHostID, setup.second.hostID)
        let firstRequests = await setup.firstSession.requestTypes
        let secondRequests = await setup.secondSession.requestTypes
        XCTAssertTrue(firstRequests.contains(.deviceRevoke))
        XCTAssertFalse(secondRequests.contains(.deviceRevoke))
    }

    private struct Setup {
        let suite: String
        let defaults: UserDefaults
        let first: StoredHost
        let second: StoredHost
        let firstSession: HostTestSession
        let secondSession: HostTestSession
        let store: CompanionStore
    }

    @MainActor
    private func makeSetup(failingHost: TestHostSelection?) throws -> Setup {
        let suite = "MultiHostCompanionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let first = makeHost(name: "Duplicate Mac", pinByte: 1)
        let second = makeHost(name: "Duplicate Mac", pinByte: 2)
        let now = Date()
        let deviceID = UUID()
        let firstSession = HostTestSession(
            hostID: first.hostID, deviceID: deviceID,
            generatedAt: Date(timeIntervalSince1970: -1_000_000_000),
            shouldFailMonitor: failingHost == .first
        )
        let secondSession = HostTestSession(
            hostID: second.hostID, deviceID: deviceID,
            generatedAt: Date(timeIntervalSince1970: 4_000_000_000),
            shouldFailMonitor: failingHost == .second
        )
        let registry = HostRegistry(hosts: [first, second], selectedHostID: first.hostID)
        registry.save(to: defaults)
        let connector = HostTestConnector(sessions: [first.spkiPin: firstSession, second.spkiPin: secondSession])
        let identity = try CompanionIdentity.makeEphemeral(role: .phone, now: now)
        let store = CompanionStore(
            defaults: defaults,
            connector: connector,
            identityLoader: { identity },
            deviceID: deviceID
        )
        return Setup(
            suite: suite, defaults: defaults,
            first: first, second: second,
            firstSession: firstSession, secondSession: secondSession,
            store: store
        )
    }

    private func makeHost(name: String, pinByte: UInt8) -> StoredHost {
        StoredHost(
            hostID: UUID(), name: name,
            routes: .init(candidates: [.init(kind: .tailnet, host: "100.64.0.\(pinByte)", port: 49_444)]),
            spkiPin: Data(repeating: pinByte, count: 32)
        )
    }
}

private enum TestHostSelection: Equatable { case first, second }

private actor HostTestConnector: CompanionSessionConnecting {
    private let sessions: [Data: HostTestSession]

    init(sessions: [Data: HostTestSession]) { self.sessions = sessions }

    func connect(
        route: RouteCandidate,
        identity: CompanionIdentity,
        expectedHostSPKI: Data,
        deviceID: UUID
    ) async throws -> any CompanionSession {
        guard let session = sessions[expectedHostSPKI] else { throw CompanionTransportError.invalidTLS }
        return session
    }
}

private actor HostTestSession: CompanionSession {
    let hostID: UUID
    let deviceID: UUID
    let generatedAt: Date
    let shouldFailMonitor: Bool
    private(set) var requestTypes: [MessageType] = []
    private(set) var alertHistoryQueries: [AlertHistoryQuery] = []

    init(hostID: UUID, deviceID: UUID, generatedAt: Date, shouldFailMonitor: Bool) {
        self.hostID = hostID
        self.deviceID = deviceID
        self.generatedAt = generatedAt
        self.shouldFailMonitor = shouldFailMonitor
    }

    func request(_ payload: EnvelopePayload, timeout: TimeInterval = 10) async throws -> Envelope {
        requestTypes.append(payload.messageType)
        switch payload {
        case .monitorSubscribe:
            if shouldFailMonitor { throw CompanionTransportError.invalidTLS }
            return Envelope(requestID: UUID(), payload: .companionSnapshot(snapshot()))
        case let .controlProposal(proposal):
            let command = PreparedCommand(
                commandID: UUID(), requestID: proposal.requestID, hostID: hostID,
                deviceID: deviceID, runtimeEpoch: UUID(), action: proposal.action,
                risk: .restartsProvider, expectedRevision: "r1", policyEpoch: 1,
                nonce: Data(repeating: 4, count: 32), expiresAt: .now.addingTimeInterval(60),
                signedPayload: Data("approved-by-host".utf8)
            )
            return Envelope(requestID: proposal.requestID, payload: .preparedCommand(command))
        case let .alertHistoryQuery(query):
            alertHistoryQueries.append(query)
            let all = (1...4).map { id in
                CompanionAlertRecord(
                    id: Int64(id), code: .providerOffline,
                    transition: id == 4 ? .raised : .recovered,
                    occurredAt: Date(timeIntervalSince1970: Double(id)),
                    observedDurationSeconds: id == 4 ? 90 : nil,
                    observationCount: id
                )
            }
            let matching = all
                .filter { record in query.cursor.map { record.id < $0 } ?? true }
                .sorted { $0.id > $1.id }
            let rows = Array(matching.prefix(query.maximumRecords))
            let page = try AlertHistoryPage.validated(hostID: hostID, records: rows, nextCursor: nil)
            return Envelope(requestID: UUID(), payload: .alertHistoryPage(page))
        case let .deviceRevoke(request):
            return Envelope(requestID: UUID(), payload: .deviceRevokeResponse(.init(deviceID: request.deviceID)))
        default:
            return Envelope(requestID: UUID(), payload: .safeError(.init(code: .unavailable)))
        }
    }

    func close() async {}

    private func snapshot() -> CompanionSnapshot {
        let state = RuntimeStateObservation(state: .running, observedAt: generatedAt)
        return CompanionSnapshot(
            hostID: hostID, runtimeEpoch: UUID(), sequence: 1, generatedAt: generatedAt,
            observations: [MetricObservation(
                metric: .requestsServed, value: 12, unit: .count, scope: .localProvider,
                provenance: .direct, capturedAt: generatedAt, sourceAgeSeconds: 0,
                availability: .available, reason: nil
            )],
            models: [ModelSummary(id: "safe-model", name: "safe-model", active: true)],
            states: RuntimeStates(provider: state, macApp: state, helper: state, connection: state),
            capabilities: [.monitor, .history, .settingsWrite, .providerLifecycle]
        )
    }
}
