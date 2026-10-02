import Foundation

/// Display-only saved limits. This deliberately carries no model selectors,
/// configuration revision, or inventory evidence that could authorize an action.
public struct ProviderSavedCapacity: Equatable, Sendable {
    public let maxModelSlots: Int?
    public let engineV2MaxConcurrent: Int?
    public let enabledModelCount: Int
    public let preloadedModelCount: Int

    public init(draft: ProviderConfigDraft) {
        maxModelSlots = draft.originalMaxModelSlots
        engineV2MaxConcurrent = draft.originalEngineV2MaxConcurrent
        enabledModelCount = draft.original.enabled.count
        preloadedModelCount = draft.original.preloaded.count
    }
}

/// Optional read-only capability, independent of CLI inventory acquisition.
public protocol ProviderSavedCapacityReading: Sendable {
    func readSavedCapacity() async throws -> ProviderSavedCapacity
}
