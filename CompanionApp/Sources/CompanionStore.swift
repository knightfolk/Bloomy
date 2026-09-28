import CryptoKit
import DarkbloomCompanionProtocol
import DarkbloomCompanionTransport
import Foundation
import Observation
import UIKit

struct StoredHost: Codable, Equatable, Sendable {
    let hostID: UUID
    let name: String
    let routes: PeerRouteHints
    let spkiPin: Data
}

@MainActor
@Observable
final class CompanionStore {
    enum Connection: Equatable {
        case unpaired
        case pairing
        case awaitingApproval(code: String)
        case connecting
        case connected
        case disconnected
    }

    var connection: Connection = .unpaired
    var snapshot: CompanionSnapshot?
    var settings: SettingsSnapshot?
    var pendingCommand: PreparedCommand?
    var lastOperation: OperationStatus?
    var errorMessage: String?
    var qrText = ""
    let autoPairFixture: Bool
    private(set) var snapshotFreshness = SnapshotFreshness()

    var snapshotIsStale: Bool { snapshotFreshness.isStale(at: .now) }

    private(set) var host: StoredHost?
    private var pendingInvitation: PairingInvitation?
    private var session: CompanionClientSession?
    private let approvalKeys = ApprovalKeyStore()
    private let defaults: UserDefaults
    private let deviceID: UUID

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autoPairFixture = CommandLine.arguments.contains("--auto-pair-fixture")
        if let raw = defaults.string(forKey: "companion.deviceID"), let id = UUID(uuidString: raw) {
            deviceID = id
        } else {
            let id = UUID(); deviceID = id
            defaults.set(id.uuidString, forKey: "companion.deviceID")
        }
        if let data = defaults.data(forKey: "companion.host"),
           let value = try? JSONDecoder().decode(StoredHost.self, from: data) {
            host = value
            connection = .disconnected
        }
        if let index = CommandLine.arguments.firstIndex(of: "--fixture-pairing-code"),
           CommandLine.arguments.indices.contains(index + 1) {
            qrText = CommandLine.arguments[index + 1]
        }
    }

    func pair(scannedCode: String) async {
        connection = .pairing
        errorMessage = nil
        do {
            let invitation = try PairingQRCode.decode(scannedCode.trimmingCharacters(in: .whitespacesAndNewlines))
            let identity = try CompanionIdentityStore(
                namespace: "dev.darkbloom.companion.phone", role: .phone
            ).loadOrCreate()
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
            let signature = try identity.sign(EnrollmentProof.transcript(
                invitation: invitation, proof: unsigned
            ))
            let proof = EnrollmentProof(
                invitationID: unsigned.invitationID,
                phoneID: unsigned.phoneID,
                phoneName: unsigned.phoneName,
                identityCertificate: unsigned.identityCertificate,
                approvalPublicKey: unsigned.approvalPublicKey,
                nonce: unsigned.nonce,
                transcriptSignature: signature
            )
            let pending = try await CompanionEnrollmentClient.submit(
                invitation: invitation, identity: identity, proof: proof
            )
            pendingInvitation = invitation
            connection = .awaitingApproval(code: pending.comparisonCode)
            if autoPairFixture {
                let candidate = StoredHost(
                    hostID: invitation.hostID,
                    name: invitation.hostName,
                    routes: invitation.routes,
                    spkiPin: invitation.hostSPKIPin
                )
                await connect(to: candidate, persistOnSuccess: true)
            }
        } catch {
            connection = host == nil ? .unpaired : .disconnected
            errorMessage = message(for: error)
        }
    }

    func connectAfterApproval() async {
        if let invitation = pendingInvitation {
            let candidate = StoredHost(
                hostID: invitation.hostID,
                name: invitation.hostName,
                routes: invitation.routes,
                spkiPin: invitation.hostSPKIPin
            )
            await connect(to: candidate, persistOnSuccess: true)
        } else if let host {
            await connect(to: host, persistOnSuccess: false)
        }
    }

    func disconnect() async {
        await session?.close()
        session = nil
        connection = host == nil ? .unpaired : .disconnected
    }

    func refresh() async {
        guard let session else { errorMessage = CompanionAppError.notConnected.localizedDescription; return }
        do {
            let response = try await session.request(.monitorSubscribe(.init(minimumIntervalSeconds: 1)))
            guard case let .companionSnapshot(value) = response.payload else { throw CompanionAppError.unexpectedResponse }
            snapshot = value
            snapshotFreshness.didReceive(at: .now)
            connection = .connected
        } catch {
            connection = .disconnected
            errorMessage = message(for: error)
        }
    }

    func loadSettings() async {
        guard let session else { errorMessage = CompanionAppError.notConnected.localizedDescription; return }
        do {
            let response = try await session.request(.settingsDraft(.init()))
            guard case let .settingsSnapshot(value) = response.payload else { throw CompanionAppError.unexpectedResponse }
            settings = value
        } catch { errorMessage = message(for: error) }
    }

    func prepare(_ action: ControlAction, expectedRevision: String? = nil) async {
        guard let session else { errorMessage = CompanionAppError.notConnected.localizedDescription; return }
        do {
            let requestID = UUID()
            let response = try await session.request(.controlProposal(.init(
                requestID: requestID, expectedRevision: expectedRevision, action: action
            )))
            guard case let .preparedCommand(value) = response.payload else {
                if case let .safeError(error) = response.payload { throw RemoteSafeError(value: error) }
                throw CompanionAppError.unexpectedResponse
            }
            pendingCommand = value
        } catch { errorMessage = message(for: error) }
    }

    func approvePendingCommand() async {
        guard let command = pendingCommand, let session else { return }
        do {
            try await approvalKeys.authenticateOwner(reason: "Approve \(command.risk.displayName) on \(host?.name ?? "your Mac")")
            let signature = try approvalKeys.sign(command.signedPayload)
            let response = try await session.request(.signedApproval(.init(
                commandID: command.commandID,
                signedPayload: command.signedPayload,
                signature: signature
            )), timeout: 700)
            guard case let .operationStatus(value) = response.payload else { throw CompanionAppError.unexpectedResponse }
            lastOperation = value
            pendingCommand = nil
            await refresh()
        } catch { errorMessage = message(for: error) }
    }

    func cancelPendingCommand() { pendingCommand = nil }

    func saveSettings(_ values: ProviderSettingsValues) async {
        guard let settings else { return }
        let patch = SettingsPatch(provider: .init(
            enabledModels: values.enabledModels,
            preloadModels: values.preloadModels,
            maximumConcurrentRequests: values.maximumConcurrentRequests,
            residentModelSlots: values.residentModelSlots,
            startupPreload: values.startupPreload
        ))
        await prepare(
            .applySettings(draftID: settings.draftID, patch: patch),
            expectedRevision: settings.revision
        )
    }

    func forgetHost() async {
        await disconnect()
        host = nil; pendingInvitation = nil; snapshot = nil; settings = nil
        defaults.removeObject(forKey: "companion.host")
        connection = .unpaired
    }

    private func connect(to host: StoredHost, persistOnSuccess: Bool) async {
        connection = .connecting
        errorMessage = nil
        do {
            let identity = try CompanionIdentityStore(
                namespace: "dev.darkbloom.companion.phone", role: .phone
            ).loadOrCreate()
            var lastError: Error = CompanionAppError.noRoute
            for route in host.routes.candidates {
                do {
                    let connected = try await CompanionClientSession.connect(
                        route: route, identity: identity,
                        expectedHostSPKI: host.spkiPin, deviceID: deviceID
                    )
                    session = connected
                    self.host = host
                    if persistOnSuccess {
                        defaults.set(try JSONEncoder().encode(host), forKey: "companion.host")
                        pendingInvitation = nil
                    }
                    connection = .connected
                    await refresh()
                    return
                } catch { lastError = error }
            }
            throw lastError
        } catch {
            connection = pendingInvitation == nil ? .disconnected : connection
            errorMessage = "The Mac has not approved this iPhone yet, or its route is unavailable. \(message(for: error))"
        }
    }

    private func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }

    private func message(for error: Error) -> String {
        if error is PairingQRCodeError { return "The pairing code is invalid. Create a new code on the Mac." }
        if let error = error as? CompanionTransportError {
            return "The secure connection failed (\(String(describing: error)))."
        }
        if error is CompanionIdentityError {
            return "This iPhone could not load its secure device identity."
        }
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
        case .quitsMacApp: "quitting Darkbloom Control"
        }
    }
}
