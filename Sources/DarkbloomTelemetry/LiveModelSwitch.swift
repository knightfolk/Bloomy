import Foundation

public enum ProviderLiveSwitchAvailability: Equatable, Sendable {
    case available
    case inProgress
    case unavailable(String)

    public var isAvailable: Bool { self == .available }

    public static func evaluate(
        daemon: DaemonState?,
        daemonSource: ProviderControlSourceState,
        providerConfig: URL,
        at currentTime: Date
    ) -> Self {
        guard daemonSource.evaluated(
            at: currentTime,
            invalidReason: "Provider state is unavailable",
            staleReason: "Provider state is stale",
            futureReason: "Provider state timestamp is in the future"
        ).isMarkedFresh, let daemon else {
            return .unavailable("Refresh current provider state before applying live")
        }
        guard let modelSwitch = daemon.modelSwitch,
              daemon.runtimeCapabilities != nil,
              let configPath = daemon.configPath, !configPath.isEmpty,
              daemon.coordinatorURL != nil else {
            return .unavailable("Upgrade the running provider to use Apply Live")
        }
        guard URL(fileURLWithPath: configPath).standardizedFileURL.path
                == providerConfig.standardizedFileURL.path else {
            return .unavailable("The running provider uses a different configuration")
        }
        if [.validating, .draining, .switching].contains(modelSwitch.outcome) {
            return .inProgress
        }
        if let lifecycle = daemon.lifecycle,
           [.draining, .busy, .timedOut].contains(lifecycle.outcome) {
            return .unavailable("Finish the current provider lifecycle action before applying live")
        }
        return .available
    }
}
