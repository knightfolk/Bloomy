import AppKit
import DarkbloomCompanionProtocol
import DarkbloomTelemetry
import Foundation

public protocol MacAppLifecycleControlling: Sendable {
    func perform(_ action: DarkbloomCompanionProtocol.AppLifecycleAction) async throws
}

public enum MacAppLifecycleError: Error, Equatable, Sendable {
    case dirtyDraft
    case appUnavailable
    case quitRefused
    case openFailed
}

public actor WorkspaceMacAppLifecycleController: MacAppLifecycleControlling {
    private let bundleIdentifier: String
    private let bundleURL: URL
    private let canQuit: @Sendable () async -> Bool

    public init(
        bundleIdentifier: String,
        bundleURL: URL,
        canQuit: @escaping @Sendable () async -> Bool
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL.standardizedFileURL
        self.canQuit = canQuit
    }

    public func perform(_ action: DarkbloomCompanionProtocol.AppLifecycleAction) async throws {
        switch action {
        case .open:
            try await open()
        case .quit:
            try await quit()
        case .relaunch:
            try await quit()
            try await open()
        }
    }

    private func quit() async throws {
        guard await canQuit() else { throw MacAppLifecycleError.dirtyDraft }
        let applications = await MainActor.run {
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        }
        guard applications.count <= 1 else { throw MacAppLifecycleError.appUnavailable }
        guard let app = applications.first else { return }
        guard app.bundleURL?.standardizedFileURL == bundleURL else {
            throw MacAppLifecycleError.appUnavailable
        }
        guard app.terminate() else { throw MacAppLifecycleError.quitRefused }
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !app.isTerminated, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(100))
        }
        guard app.isTerminated else { throw MacAppLifecycleError.quitRefused }
    }

    private func open() async throws {
        guard Bundle(url: bundleURL)?.bundleIdentifier == bundleIdentifier else {
            throw MacAppLifecycleError.appUnavailable
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            NSWorkspace.shared.openApplication(
                at: bundleURL,
                configuration: NSWorkspace.OpenConfiguration()
            ) { _, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: ()) }
            }
        }
    }
}

public enum HostDispatchError: Error, Equatable, Sendable { case busy }

public actor HostCommandDispatcher {
    private let provider: any ProviderControlling
    private let settings: CompanionSettingsCoordinator
    private let app: any MacAppLifecycleControlling
    private let now: @Sendable () -> Date
    private var running = false
    private var operations: [UUID: OperationStatus] = [:]
    private var operationOwners: [UUID: UUID] = [:]
    private var operationOrder: [UUID] = []
    private let maximumOperations = 1_000

    public init(
        provider: any ProviderControlling,
        settings: CompanionSettingsCoordinator,
        app: any MacAppLifecycleControlling,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.provider = provider
        self.settings = settings
        self.app = app
        self.now = now
    }

    public func dispatch(_ command: AuthorizedCommand) async throws -> OperationStatus {
        guard !running else { throw HostDispatchError.busy }
        running = true
        defer { running = false }
        let operationID = UUID()
        let accepted = status(
            operationID: operationID, command: command, state: .accepted, error: nil
        )
        retain(accepted, owner: command.deviceID)
        do {
            let completion = try await perform(command.proposal.action, expectedRevision: command.proposal.expectedRevision)
            let state: OperationState = completion == .outcomeUncertain ? .outcomeUncertain : .succeeded
            let result = status(operationID: operationID, command: command, state: state, error: nil)
            retain(result, owner: command.deviceID)
            return result
        } catch {
            let safe = SafeErrorResponse(
                code: .internalFailure, reason: .internalFailure
            )
            let result = status(operationID: operationID, command: command, state: .failed, error: safe)
            retain(result, owner: command.deviceID)
            return result
        }
    }

    public func operation(_ operationID: UUID) -> OperationStatus? { operations[operationID] }

    public func operation(_ operationID: UUID, deviceID: UUID) -> OperationStatus? {
        guard operationOwners[operationID] == deviceID else { return nil }
        return operations[operationID]
    }

    private func retain(_ status: OperationStatus, owner: UUID) {
        if operations[status.operationID] == nil { operationOrder.append(status.operationID) }
        operations[status.operationID] = status
        operationOwners[status.operationID] = owner
        while operationOrder.count > maximumOperations {
            let expired = operationOrder.removeFirst()
            operations[expired] = nil
            operationOwners[expired] = nil
        }
    }

    private func perform(
        _ action: ControlAction,
        expectedRevision: String?
    ) async throws -> ProviderMutationCompletion {
        switch action {
        case let .providerLifecycle(action):
            let mapped: DarkbloomTelemetry.ProviderLifecycleAction = switch action {
            case .start: .start
            case .stop: .stop
            case .restart: .restart
            }
            return try await provider.performLifecycle(mapped, enabledModels: [], onPhase: nil)
        case .applySavedModelsLive:
            return try await provider.performLiveSwitch(enabledModels: [], onPhase: nil)
        case let .applySettings(draftID, patch):
            guard let expectedRevision else { throw CompanionSettingsError.revisionConflict }
            _ = try await settings.patch(.init(
                draftID: draftID, expectedRevision: expectedRevision, patch: patch
            ))
            return .refreshUncertain
        case let .saveSettings(draftID):
            _ = try await settings.save(draftID: draftID, expectedRevision: expectedRevision)
            return .refreshUncertain
        case let .appLifecycle(action):
            try await app.perform(action)
            return .refreshUncertain
        }
    }

    private func status(
        operationID: UUID,
        command: AuthorizedCommand,
        state: OperationState,
        error: SafeErrorResponse?
    ) -> OperationStatus {
        OperationStatus(
            operationID: operationID,
            requestID: command.proposal.requestID,
            commandID: command.commandID,
            state: state,
            progress: state == .succeeded ? 1 : nil,
            error: error,
            updatedAt: now()
        )
    }
}
