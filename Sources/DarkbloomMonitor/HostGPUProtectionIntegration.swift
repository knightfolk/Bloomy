import DarkbloomTelemetry
import Foundation

extension MonitorStore {
    /// A fresh stopped status is needed before restarting a protection-owned
    /// stop. Missing state or a retained daemon file does not prove shutdown.
    var freshProviderRunningForGPUProtection: Bool? {
        guard case .available(let status, let capturedAt) = snapshot.status,
              (0...10).contains(Date().timeIntervalSince(capturedAt)),
              let daemon = status.daemon?.lowercased() else { return nil }
        if daemon.hasPrefix("running") { return true }
        if daemon.hasPrefix("stopped") || daemon.hasPrefix("not running") { return false }
        return nil
    }

    var hostGPUProviderContext: HostGPUProtectionProviderContext? {
        let instant = Date()
        guard case .available(let state, let capturedAt) = snapshot.state,
              (0...10).contains(instant.timeIntervalSince(capturedAt)),
              (0...10).contains(instant.timeIntervalSince1970 - state.writtenAt) else { return nil }
        let transitioning = state.startupPreloadPendingModels?.isEmpty != true
            || state.lifecycle?.outcome != .serving
            || state.lifecycle?.remainingRequests != 0
            || state.availability != nil
            || !state.modelLoadFailures.isEmpty
            || state.modelSwitch.map { ![.serving, .switched].contains($0.outcome) || $0.remainingRequests != 0 } == true
            || state.autopilotPhaseIsUnrecognized
            || ["transitioning", "recovering", "waiting_inventory"].contains(state.autopilotPhase ?? "")
        return .init(running: state.trust?.status == "online", idle: !state.inferenceActive,
            capturedAt: Date(timeIntervalSince1970: state.writtenAt),
            identity: "\(state.processIdentity.pid):\(state.processIdentity.startTimeMicros)",
            isTransitioning: transitioning)
    }

    func observeHostGPUProtection() {
        let sample: HostGPUProtectionSample?
        if case .current(let percent, let capturedAt) = gpuUsage.reading() {
            sample = .init(percent: percent, capturedAt: capturedAt)
        } else { sample = nil }
        hostGPUProtection?.observe(sample: sample, provider: hostGPUProviderContext)
    }

    func attachHostGPUProtection(_ protection: HostGPUProtectionStore) {
        hostGPUProtection = protection
        gpuUsage.onSample = { [weak self] in self?.observeHostGPUProtection() }
    }
}
