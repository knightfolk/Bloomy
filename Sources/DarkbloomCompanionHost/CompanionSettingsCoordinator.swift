import DarkbloomCompanionProtocol
import DarkbloomTelemetry
import Foundation

public enum CompanionSettingsError: Error, Equatable, Sendable {
    case unknownDraft
    case revisionConflict
    case invalidPatch
}

public actor CompanionSettingsCoordinator {
    private struct Session {
        var draft: ProviderConfigDraft
        var values: ProviderSettingsValues
    }
    private let provider: any ProviderControlling
    private var sessions: [UUID: Session] = [:]

    public init(provider: any ProviderControlling) { self.provider = provider }

    public func makeDraft() async throws -> SettingsSnapshot {
        let snapshot = try await provider.refresh()
        let id = UUID()
        let values = Self.values(from: snapshot.draft)
        sessions[id] = Session(draft: snapshot.draft, values: values)
        return SettingsSnapshot(
            draftID: id,
            revision: snapshot.draft.sourceRevision,
            saved: values,
            applied: Self.appliedValues(from: snapshot),
            restartRequired: false
        )
    }

    public func patch(_ request: SettingsPatchRequest) throws -> SettingsSnapshot {
        guard var session = sessions[request.draftID] else { throw CompanionSettingsError.unknownDraft }
        guard session.draft.sourceRevision == request.expectedRevision else {
            throw CompanionSettingsError.revisionConflict
        }
        guard let providerPatch = request.patch.provider, request.patch.app == nil else {
            throw CompanionSettingsError.invalidPatch
        }
        let current = session.values
        let enabled = providerPatch.enabledModels ?? current.enabledModels
        let requestedPreload = providerPatch.preloadModels ?? current.preloadModels
        let startupPreload = providerPatch.startupPreload ?? current.startupPreload
        let preload = startupPreload ? requestedPreload : []
        let concurrency = providerPatch.maximumConcurrentRequests ?? current.maximumConcurrentRequests
        let slots = providerPatch.residentModelSlots ?? current.residentModelSlots
        guard Set(preload).isSubset(of: Set(enabled)),
              Set(enabled).count == enabled.count,
              Set(preload).count == preload.count,
              (1...24).contains(concurrency),
              (1...16).contains(slots) else { throw CompanionSettingsError.invalidPatch }
        let values = ProviderSettingsValues(
            enabledModels: enabled,
            preloadModels: preload,
            maximumConcurrentRequests: concurrency,
            residentModelSlots: slots,
            startupPreload: startupPreload
        )
        session.values = values
        session.draft = session.draft
            .withSelection(.init(enabled: enabled, preloaded: preload))
            .withMaxModelSlots(slots)
            .withEngineV2MaxConcurrent(concurrency)
        sessions[request.draftID] = session
        return SettingsSnapshot(
            draftID: request.draftID,
            revision: session.draft.sourceRevision,
            saved: values,
            applied: nil,
            restartRequired: session.draft.hasChanges
        )
    }

    public func save(draftID: UUID, expectedRevision: String?) async throws -> SettingsSnapshot {
        guard let session = sessions[draftID] else { throw CompanionSettingsError.unknownDraft }
        guard expectedRevision == nil || expectedRevision == session.draft.sourceRevision else {
            throw CompanionSettingsError.revisionConflict
        }
        let completion = try await provider.performSave(session.draft, onPhase: nil)
        let refreshed: ProviderControlSnapshot
        if let snapshot = completion.controls.snapshot {
            refreshed = snapshot
        } else {
            refreshed = try await provider.refresh()
        }
        let values = Self.values(from: refreshed.draft)
        sessions[draftID] = Session(draft: refreshed.draft, values: values)
        return SettingsSnapshot(
            draftID: draftID,
            revision: refreshed.draft.sourceRevision,
            saved: values,
            applied: Self.appliedValues(from: refreshed),
            restartRequired: completion.result.restartRequired
        )
    }

    public func currentRevision() async -> String? {
        try? await provider.refresh().draft.sourceRevision
    }

    private static func values(from draft: ProviderConfigDraft) -> ProviderSettingsValues {
        ProviderSettingsValues(
            enabledModels: draft.selection.enabled,
            preloadModels: draft.selection.preloaded,
            maximumConcurrentRequests: draft.engineV2MaxConcurrent ?? 1,
            residentModelSlots: draft.maxModelSlots ?? 1,
            startupPreload: !draft.selection.preloaded.isEmpty
        )
    }

    private static func appliedValues(from snapshot: ProviderControlSnapshot) -> ProviderSettingsValues? {
        guard snapshot.sources.daemon.isMarkedFresh else { return nil }
        return values(from: snapshot.draft)
    }
}
