import DarkbloomTelemetry
import Foundation

/// Shared residency evidence for popup pills and model controls. Loaded-state
/// files change only when residency changes: require a fresh read from this
/// provider lifetime, rather than treating an old unchanged file as stale.
struct ProviderTelemetryResidency: Equatable {
    let daemonState: DaemonState
    let loadedModels: [String]
    let residentModelIDs: Set<String>

    static func make(
        daemon: SourceAvailability<DaemonState>,
        loadedModels: SourceAvailability<LoadedModelsState>,
        at currentTime: Date
    ) -> Self? {
        guard case .available(let daemon, let daemonCapturedAt) = daemon,
              case .available(let loaded, let loadedCapturedAt) = loadedModels,
              fresh(timestamp: daemonCapturedAt.timeIntervalSince1970, at: currentTime),
              fresh(timestamp: loadedCapturedAt.timeIntervalSince1970, at: currentTime),
              fresh(timestamp: daemon.writtenAt, at: currentTime),
              loaded.updatedAt.isFinite,
              daemon.startedAt.isFinite,
              loaded.updatedAt >= daemon.startedAt,
              loaded.updatedAt <= currentTime.timeIntervalSince1970
        else { return nil }
        return Self(daemonState: daemon, loadedModels: loaded.models,
            residentModelIDs: Set(loaded.models + daemon.warmModels + daemon.slots.map(\.model)))
    }

    func liveState(for item: ModelInventoryItem) -> InventoryLiveState {
        func matches(_ modelID: String) -> Bool {
            modelID == item.catalogID || modelID == item.localID
        }
        if daemonState.inferenceActive, matches(daemonState.currentModel) { return .active }
        if residentModelIDs.contains(item.catalogID)
            || item.localID.map(residentModelIDs.contains) == true { return .loadedIdle }
        // The daemon retains its last current model even after unloading.
        return .unloaded
    }

    private static func fresh(timestamp: TimeInterval, at currentTime: Date) -> Bool {
        guard timestamp.isFinite, currentTime.timeIntervalSince1970.isFinite else { return false }
        let age = currentTime.timeIntervalSince1970 - timestamp
        return age.isFinite && (0...ProviderControlSourceState.maximumEvidenceAge).contains(age)
    }
}
