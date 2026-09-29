import CryptoKit
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import Foundation
import Observation
import UIKit

enum CompanionConnection: Equatable {
    case unpaired
    case pairing
    case awaitingApproval(code: String)
    case connecting
    case connected
    case disconnected
}

protocol CompanionSession: Sendable {
    func request(_ payload: EnvelopePayload, timeout: TimeInterval) async throws -> Envelope
    func close() async
}

protocol CompanionSessionConnecting: Sendable {
    func connect(
        route: RouteCandidate,
        identity: CompanionIdentity,
        expectedHostSPKI: Data,
        deviceID: UUID
    ) async throws -> any CompanionSession
}

private struct LiveCompanionSession: CompanionSession {
    let session: CompanionClientSession

    func request(_ payload: EnvelopePayload, timeout: TimeInterval = 10) async throws -> Envelope {
        try await session.request(payload, timeout: timeout)
    }

    func close() async { await session.close() }
}

private struct LiveCompanionSessionConnector: CompanionSessionConnecting {
    func connect(
        route: RouteCandidate,
        identity: CompanionIdentity,
        expectedHostSPKI: Data,
        deviceID: UUID
    ) async throws -> any CompanionSession {
        LiveCompanionSession(session: try await CompanionClientSession.connect(
            route: route, identity: identity,
            expectedHostSPKI: expectedHostSPKI, deviceID: deviceID
        ))
    }
}

struct FleetHostStatus: Identifiable {
    let host: StoredHost
    let connection: CompanionConnection
    let snapshot: CompanionSnapshot?
    let isStale: Bool
    let errorMessage: String?
    let latestAlert: CompanionAlertRecord?

    var id: UUID { host.hostID }
}

@MainActor
@Observable
final class CompanionStore {
    typealias Connection = CompanionConnection
    typealias IdentityLoader = @Sendable () throws -> CompanionIdentity

    private struct HostSessionState {
        var connection: Connection = .disconnected
        var snapshot: CompanionSnapshot?
        var settings: SettingsSnapshot?
        var pendingCommand: PreparedCommand?
        var lastOperation: OperationStatus?
        var errorMessage: String?
        var freshness = SnapshotFreshness()
        var session: (any CompanionSession)?
        var generation: UInt64 = 0
        var alertRecords: [CompanionAlertRecord] = []
        var alertNextCursor: Int64?
        var alertHistoryLoaded = false
    }

    private(set) var registry: HostRegistry
    private var hostStates: [UUID: HostSessionState] = [:]
    private var pendingInvitation: PairingInvitation?
    private var pendingComparisonCode: String?
    private var pairingHostID: UUID?
    private var pairingInProgress = false
    private var unpairedErrorMessage: String?
    private let approvalKeys = ApprovalKeyStore()
    private let defaults: UserDefaults
    private let deviceID: UUID
    private let connector: any CompanionSessionConnecting
    private let identityLoader: IdentityLoader

    var qrText = ""
    let autoPairFixture: Bool

    var hosts: [StoredHost] { registry.hosts }
    var host: StoredHost? { registry.selectedHost }
    var selectedHostID: UUID? { registry.selectedHostID }
    var snapshot: CompanionSnapshot? { selectedState?.snapshot }
    var settings: SettingsSnapshot? { selectedState?.settings }
    var pendingCommand: PreparedCommand? { selectedState?.pendingCommand }
    var lastOperation: OperationStatus? { selectedState?.lastOperation }
    var snapshotFreshness: SnapshotFreshness { selectedState?.freshness ?? SnapshotFreshness() }
    var snapshotIsStale: Bool { snapshotFreshness.isStale(at: .now) }
    var selectedAlertRecords: [CompanionAlertRecord] { selectedState?.alertRecords ?? [] }
    var alertNextCursor: Int64? { selectedState?.alertNextCursor }
    var alertHistoryLoaded: Bool { selectedState?.alertHistoryLoaded ?? false }

    var connection: Connection {
        get {
            if pairingInProgress, pairingHostID == nil { return .pairing }
            guard let id = pairingHostID ?? registry.selectedHostID else { return .unpaired }
            return hostStates[id]?.connection ?? .disconnected
        }
        set {
            guard let id = pairingHostID ?? registry.selectedHostID else { return }
            updateState(id) { $0.connection = newValue }
        }
    }

    var errorMessage: String? {
        get {
            guard let id = pairingHostID ?? registry.selectedHostID else { return unpairedErrorMessage }
            return hostStates[id]?.errorMessage
        }
        set {
            guard let id = pairingHostID ?? registry.selectedHostID else {
                unpairedErrorMessage = newValue
                return
            }
            updateState(id) { $0.errorMessage = newValue }
        }
    }

    var fleetHostStatuses: [FleetHostStatus] {
        registry.hosts.map { host in
            let state = hostStates[host.hostID] ?? HostSessionState()
            return FleetHostStatus(
                host: host,
                connection: state.connection,
                snapshot: state.snapshot,
                isStale: state.freshness.isStale(at: .now),
                errorMessage: state.errorMessage,
                latestAlert: state.alertRecords.first
            )
        }
    }

    init(
        defaults: UserDefaults = .standard,
        connector: any CompanionSessionConnecting = LiveCompanionSessionConnector(),
        identityLoader: @escaping IdentityLoader = {
            try CompanionIdentityStore(namespace: "dev.darkbloom.companion.phone", role: .phone).loadOrCreate()
        },
        deviceID: UUID? = nil
    ) {
        self.defaults = defaults
        self.connector = connector
        self.identityLoader = identityLoader
        autoPairFixture = CommandLine.arguments.contains("--auto-pair-fixture")
        if let deviceID {
            self.deviceID = deviceID
        } else if let raw = defaults.string(forKey: "companion.deviceID"), let id = UUID(uuidString: raw) {
            self.deviceID = id
        } else {
            let id = UUID()
            self.deviceID = id
            defaults.set(id.uuidString, forKey: "companion.deviceID")
        }
        registry = HostRegistry.load(from: defaults)
        for host in registry.hosts { hostStates[host.hostID] = HostSessionState() }
        if let index = CommandLine.arguments.firstIndex(of: "--fixture-pairing-code"),
           CommandLine.arguments.indices.contains(index + 1) {
            qrText = CommandLine.arguments[index + 1]
        }
    }

    func selectHost(_ hostID: UUID) {
        registry.select(hostID)
        guard registry.selectedHostID == hostID else { return }
        if hostStates[hostID] == nil { hostStates[hostID] = HostSessionState() }
        persistRegistry()
    }

    func displayName(for host: StoredHost) -> String {
        let matches = registry.hosts.filter { $0.name == host.name }
        guard matches.count > 1 else { return host.name }
        let identity = host.hostID.uuidString.lowercased()
        var prefixLength = 6
        while matches.contains(where: {
            $0.hostID != host.hostID && $0.hostID.uuidString.lowercased().hasPrefix(String(identity.prefix(prefixLength)))
        }) {
            prefixLength = min(prefixLength + 2, identity.count)
        }
        return "\(host.name) · \(identity.prefix(prefixLength))"
    }

    func pair(scannedCode: String) async {
        pairingInProgress = true
        unpairedErrorMessage = nil
        connection = .pairing
        errorMessage = nil
        do {
            let invitation = try PairingQRCode.decode(scannedCode.trimmingCharacters(in: .whitespacesAndNewlines))
            pairingHostID = invitation.hostID
            updateState(invitation.hostID) { $0.connection = .pairing; $0.errorMessage = nil }
            let identity = try identityLoader()
            let approvalPublicKey = try approvalKeys.publicKey()
            let nonce = randomBytes(count: 32)
            let unsigned = EnrollmentProof(
                invitationID: invitation.invitationID,
                phoneID: deviceID,
                phoneName: UIDevice.current.name,
                identityCertificate: identity.certificateDER,
                approvalPublicKey: approvalPublicKey,
                nonce: nonce,
                transcriptSignature: Data([0])
            )
            let signature = try identity.sign(EnrollmentProof.transcript(invitation: invitation, proof: unsigned))
            let proof = EnrollmentProof(
                invitationID: unsigned.invitationID, phoneID: unsigned.phoneID,
                phoneName: unsigned.phoneName, identityCertificate: unsigned.identityCertificate,
                approvalPublicKey: unsigned.approvalPublicKey, nonce: unsigned.nonce,
                transcriptSignature: signature
            )
            let pending = try await CompanionEnrollmentClient.submit(
                invitation: invitation, identity: identity, proof: proof
            )
            pendingInvitation = invitation
            pendingComparisonCode = pending.comparisonCode
            pairingInProgress = false
            updateState(invitation.hostID) { $0.connection = .awaitingApproval(code: pending.comparisonCode) }
            if autoPairFixture {
                await connect(to: storedHost(from: invitation), persistOnSuccess: true)
            }
        } catch {
            pairingInProgress = false
            if let pairingHostID {
                updateState(pairingHostID) { $0.connection = .disconnected; $0.errorMessage = message(for: error) }
            } else {
                errorMessage = message(for: error)
            }
        }
    }

    func connectAfterApproval() async {
        if let invitation = pendingInvitation {
            await connect(to: storedHost(from: invitation), persistOnSuccess: true)
        } else if let host = registry.selectedHost {
            await connect(to: host, persistOnSuccess: false)
        }
    }

    func connect(hostID: UUID) async {
        guard let host = registry.host(for: hostID) else { return }
        await connect(to: host, persistOnSuccess: false)
    }

    func disconnect() async {
        guard let hostID = registry.selectedHostID else { return }
        await disconnect(hostID: hostID)
    }

    func disconnect(hostID: UUID) async {
        let session = hostStates[hostID]?.session
        updateState(hostID) {
            $0.generation &+= 1
            $0.session = nil
            $0.connection = .disconnected
        }
        await session?.close()
    }

    func refresh() async {
        guard let hostID = registry.selectedHostID else { return }
        await refresh(hostID: hostID)
    }

    func refresh(hostID: UUID) async {
        guard let session = hostStates[hostID]?.session else {
            updateState(hostID) { $0.errorMessage = CompanionAppError.notConnected.localizedDescription }
            return
        }
        let generation = hostStates[hostID]?.generation ?? 0
        do {
            let response = try await session.request(.monitorSubscribe(.init(minimumIntervalSeconds: 1)), timeout: 10)
            guard case let .companionSnapshot(value) = response.payload,
                  value.hostID == hostID else { throw CompanionAppError.unexpectedResponse }
            guard hostStates[hostID]?.generation == generation else { return }
            updateState(hostID) {
                $0.snapshot = value
                $0.freshness.didReceive(at: .now)
                $0.connection = .connected
                $0.errorMessage = nil
            }
        } catch {
            guard hostStates[hostID]?.generation == generation else { return }
            updateState(hostID) {
                $0.connection = .disconnected
                $0.session = nil
                $0.errorMessage = message(for: error)
            }
        }
    }

    func refreshFleet() async {
        for host in registry.hosts {
            await connect(to: host, persistOnSuccess: false)
        }
    }

    func loadSettings() async {
        guard let hostID = registry.selectedHostID else { return }
        guard let session = hostStates[hostID]?.session else {
            errorMessage = CompanionAppError.notConnected.localizedDescription
            return
        }
        let generation = hostStates[hostID]?.generation ?? 0
        do {
            let response = try await session.request(.settingsDraft(.init()), timeout: 10)
            guard case let .settingsSnapshot(value) = response.payload,
                  hostStates[hostID]?.generation == generation else {
                throw CompanionAppError.unexpectedResponse
            }
            updateState(hostID) { $0.settings = value }
        } catch { updateState(hostID) { $0.errorMessage = message(for: error) } }
    }

    func prepare(_ action: ControlAction, expectedRevision: String? = nil) async {
        guard let hostID = registry.selectedHostID,
              let state = hostStates[hostID],
              state.connection == .connected,
              let session = state.session else {
            errorMessage = CompanionAppError.notConnected.localizedDescription
            return
        }
        let generation = state.generation
        do {
            let requestID = UUID()
            let response = try await session.request(.controlProposal(.init(
                requestID: requestID, expectedRevision: expectedRevision, action: action
            )), timeout: 10)
            guard case let .preparedCommand(value) = response.payload,
                  value.hostID == hostID, value.deviceID == deviceID,
                  hostStates[hostID]?.generation == generation else {
                if case let .safeError(error) = response.payload { throw RemoteSafeError(value: error) }
                throw CompanionAppError.unexpectedResponse
            }
            updateState(hostID) { $0.pendingCommand = value }
        } catch { updateState(hostID) { $0.errorMessage = message(for: error) } }
    }

    func approvePendingCommand(for command: PreparedCommand) async {
        let hostID = command.hostID
        guard registry.selectedHostID == hostID,
              let state = hostStates[hostID],
              state.pendingCommand?.commandID == command.commandID,
              let session = state.session else {
            errorMessage = "Select the Mac that prepared this command before approving it."
            return
        }
        do {
            try await approvalKeys.authenticateOwner(reason: "Approve \(command.risk.displayName) on \(registry.host(for: hostID)?.name ?? "your Mac")")
            let signature = try approvalKeys.sign(command.signedPayload)
            let response = try await session.request(.signedApproval(.init(
                commandID: command.commandID,
                signedPayload: command.signedPayload,
                signature: signature
            )), timeout: 700)
            guard case let .operationStatus(value) = response.payload else { throw CompanionAppError.unexpectedResponse }
            updateState(hostID) { $0.lastOperation = value; $0.pendingCommand = nil }
            await refresh(hostID: hostID)
        } catch { updateState(hostID) { $0.errorMessage = message(for: error) } }
    }

    func cancelPendingCommand(_ command: PreparedCommand? = nil) {
        let hostID = command?.hostID ?? registry.selectedHostID
        guard let hostID else { return }
        if command?.commandID == nil || hostStates[hostID]?.pendingCommand?.commandID == command?.commandID {
            updateState(hostID) { $0.pendingCommand = nil }
        }
    }

    func saveSettings(_ values: ProviderSettingsValues) async {
        guard let settings else { return }
        let patch = SettingsPatch(provider: .init(
            enabledModels: values.enabledModels,
            preloadModels: values.preloadModels,
            maximumConcurrentRequests: values.maximumConcurrentRequests,
            residentModelSlots: values.residentModelSlots,
            startupPreload: values.startupPreload
        ))
        await prepare(.applySettings(draftID: settings.draftID, patch: patch), expectedRevision: settings.revision)
    }

    func loadAlertHistory(hostID: UUID? = nil, cursor: Int64? = nil, maximumRecords: Int = 50) async {
        guard let hostID = hostID ?? registry.selectedHostID,
              let host = registry.host(for: hostID) else { return }
        if hostStates[hostID]?.session == nil { await connect(to: host, persistOnSuccess: false) }
        guard let state = hostStates[hostID], let session = state.session else { return }
        guard state.snapshot?.capabilities.contains(.history) == true else {
            updateState(hostID) { $0.errorMessage = "This Mac does not share alert history." }
            return
        }
        let generation = state.generation
        do {
            let boundedMaximum = min(max(maximumRecords, 1), ProtocolLimits.maximumAlertHistoryRecordsPerPage)
            let query = AlertHistoryQuery(cursor: cursor, maximumRecords: boundedMaximum)
            let response = try await session.request(.alertHistoryQuery(query), timeout: 10)
            guard case let .alertHistoryPage(page) = response.payload,
                  page.hostID == hostID, page.records.count <= boundedMaximum,
                  hostStates[hostID]?.generation == generation else {
                throw CompanionAppError.unexpectedResponse
            }
            updateState(hostID) { value in
                if cursor == nil { value.alertRecords = page.records }
                else {
                    let seen = Set(value.alertRecords.map(\.id))
                    value.alertRecords.append(contentsOf: page.records.filter { !seen.contains($0.id) })
                    value.alertRecords.sort { $0.id > $1.id }
                }
                value.alertNextCursor = page.nextCursor
                value.alertHistoryLoaded = true
            }
        } catch { updateState(hostID) { $0.errorMessage = message(for: error) } }
    }

    func forgetHost() async {
        guard let hostID = registry.selectedHostID else { return }
        await forgetHost(hostID: hostID)
    }

    func forgetHost(hostID: UUID) async {
        await disconnect(hostID: hostID)
        _ = registry.remove(hostID)
        hostStates.removeValue(forKey: hostID)
        if pairingHostID == hostID { pairingHostID = nil; pendingInvitation = nil }
        persistRegistry()
    }

    func revokeSelectedPhone() async {
        guard let hostID = registry.selectedHostID,
              let host = registry.host(for: hostID) else { return }
        if hostStates[hostID]?.session == nil { await connect(to: host, persistOnSuccess: false) }
        guard let session = hostStates[hostID]?.session else {
            errorMessage = "Connect to this Mac before revoking the iPhone pairing."
            return
        }
        do {
            let response = try await session.request(.deviceRevoke(.init(deviceID: deviceID)), timeout: 10)
            guard case let .deviceRevokeResponse(value) = response.payload, value.deviceID == deviceID else {
                throw CompanionAppError.unexpectedResponse
            }
            await forgetHost(hostID: hostID)
        } catch { updateState(hostID) { $0.errorMessage = message(for: error) } }
    }

    private var selectedState: HostSessionState? {
        guard let id = registry.selectedHostID else { return nil }
        return hostStates[id]
    }

    private func connect(to host: StoredHost, persistOnSuccess: Bool) async {
        let hostID = host.hostID
        if !persistOnSuccess, let session = hostStates[hostID]?.session {
            if hostStates[hostID]?.connection == .connected { await refresh(hostID: hostID); return }
            await session.close()
        }
        var generation: UInt64 = 0
        updateState(hostID) {
            $0.generation &+= 1
            generation = $0.generation
            $0.connection = .connecting
            $0.errorMessage = nil
        }
        do {
            let identity = try identityLoader()
            var connectedSession: (any CompanionSession)?
            var lastError: Error = CompanionAppError.noRoute
            for route in host.routes.candidates {
                do {
                    connectedSession = try await connector.connect(
                        route: route, identity: identity,
                        expectedHostSPKI: host.spkiPin, deviceID: deviceID
                    )
                    break
                } catch { lastError = error }
            }
            guard let connectedSession else { throw lastError }
            guard hostStates[hostID]?.generation == generation else {
                await connectedSession.close()
                return
            }
            if persistOnSuccess {
                registry.upsert(host, select: true)
                guard registry.host(for: hostID) != nil else {
                    await connectedSession.close()
                    throw MultiHostStoreError.hostLimitReached
                }
                hostStates[hostID] = hostStates[hostID] ?? HostSessionState()
                persistRegistry()
                pendingInvitation = nil
                pairingHostID = nil
                pendingComparisonCode = nil
            }
            updateState(hostID) { $0.session = connectedSession; $0.connection = .connected }
            await refresh(hostID: hostID)
        } catch {
            guard hostStates[hostID]?.generation == generation else { return }
            updateState(hostID) {
                $0.connection = .disconnected
                $0.session = nil
                if persistOnSuccess, let pendingComparisonCode {
                    $0.connection = .awaitingApproval(code: pendingComparisonCode)
                    $0.errorMessage = "The Mac is approved, but its route is unavailable. \(message(for: error))"
                } else {
                    $0.errorMessage = message(for: error)
                }
            }
        }
    }

    private func storedHost(from invitation: PairingInvitation) -> StoredHost {
        StoredHost(
            hostID: invitation.hostID, name: invitation.hostName,
            routes: invitation.routes, spkiPin: invitation.hostSPKIPin
        )
    }

    private func updateState(_ hostID: UUID, _ mutation: (inout HostSessionState) -> Void) {
        var state = hostStates[hostID] ?? HostSessionState()
        mutation(&state)
        hostStates[hostID] = state
    }

    private func persistRegistry() { registry.save(to: defaults) }

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private func message(for error: Error) -> String {
        if error is PairingQRCodeError { return "The pairing code is invalid. Create a new code on the Mac." }
        if error is MultiHostStoreError { return "Remove a saved Mac before pairing another host." }
        if let error = error as? CompanionTransportError {
            return "The secure connection failed (\(String(describing: error)))."
        }
        if error is CompanionIdentityError { return "This iPhone could not load its secure device identity." }
        return (error as? LocalizedError)?.errorDescription ?? "The request could not be completed."
    }
}

struct SnapshotFreshness: Sendable {
    private(set) var receivedAt: ContinuousClock.Instant?
    let maximumAge: Duration

    init(maximumAge: Duration = .seconds(15)) { self.maximumAge = maximumAge }
    mutating func didReceive(at instant: ContinuousClock.Instant) { receivedAt = instant }
    func isStale(at instant: ContinuousClock.Instant) -> Bool {
        guard let receivedAt else { return true }
        return receivedAt.duration(to: instant) > maximumAge
    }
}

private enum MultiHostStoreError: Error { case hostLimitReached }

private struct RemoteSafeError: LocalizedError {
    let value: SafeErrorResponse
    var errorDescription: String? {
        switch value.code {
        case .busy: "The host is busy with another operation."
        case .conflict: "The host settings changed. Refresh before trying again."
        case .expired: "The approval expired. Prepare the command again."
        case .forbidden, .unauthorized: "This iPhone is not allowed to perform that action."
        default: "The host could not complete this request."
        }
    }
}

private extension CommandRisk {
    var displayName: String {
        switch self {
        case .configurationChange: "a configuration change"
        case .restartsProvider: "a provider restart"
        case .interruptsActiveWork: "a live model change"
        case .stopsProvider: "stopping the provider"
        case .quitsMacApp: "quitting Bloomy"
        }
    }
}
