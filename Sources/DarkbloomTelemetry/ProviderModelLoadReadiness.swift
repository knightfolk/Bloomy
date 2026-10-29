import Foundation

/// A snapshot, not a promise that a future request will fit. Inputs must be
/// matched to the running provider and freshness-checked by the caller.
public struct ProviderModelLoadReadiness: Equatable, Sendable {
    public enum Kind: Equatable, Sendable { case preloading, onDemand, temporarilyBusy, preloadSkipped, preloadBlocked, coldLoadBlocked }
    public let kind: Kind
    public let modelGB: Double?
    public let headroomGB: Double?
    public let usableGB: Double?
    public let noEvictionShortfallGB: Double?
    public let coldLoadShortfallGB: Double?

    public static func make(modelID: String, estimatedMemoryGB: Double?, state: DaemonState) -> Self? {
        guard state.advertisedModels?.contains(modelID) == true,
              !state.warmModels.contains(modelID), state.currentModel != modelID,
              !state.slots.contains(where: { $0.model == modelID }) else { return nil }
        func bare(_ kind: Kind) -> Self {
            Self(kind: kind, modelGB: nil, headroomGB: nil, usableGB: nil,
                 noEvictionShortfallGB: nil, coldLoadShortfallGB: nil)
        }
        if state.startupPreloadPendingModels?.contains(modelID) == true { return bare(.preloading) }
        guard let model = estimatedMemoryGB, model.isFinite, model > 0,
              let capacity = state.capacity, let headroom = capacity.loadHeadroomGB,
              let usable = capacity.loadUsableGB, headroom.isFinite, usable.isFinite,
              headroom >= 0, usable >= 0, (model + headroom).isFinite else { return nil }
        let shortfall = max(0, model + headroom - usable)
        if shortfall == 0 { return bare(.onDemand) }
        if state.inferenceActive || state.requestWorkPending == true || state.loadTransitionActive == true
            || capacity.loadTransitionActive == true { return bare(.temporarilyBusy) }
        // Missing activity fields cannot prove an idle, stable snapshot.
        guard state.requestWorkPending == false,
              state.loadTransitionActive != nil || capacity.loadTransitionActive != nil else { return nil }
        let free = capacity.freeForLoadGB.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        let kind: Kind = free.map { $0 >= model ? .preloadSkipped : .coldLoadBlocked } ?? .preloadBlocked
        return Self(kind: kind, modelGB: model, headroomGB: headroom, usableGB: usable,
                    noEvictionShortfallGB: shortfall,
                    coldLoadShortfallGB: free.flatMap { $0 < model ? model - $0 : nil })
    }
}
