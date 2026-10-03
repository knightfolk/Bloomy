import Foundation
import Combine
import DarkbloomTelemetry

/// Uses the existing host GPU sampler. Successful, confirmed pauses are owned
/// only for this app session; persisted settings never grant restart authority.
@MainActor
final class HostGPUProtectionStore: ObservableObject {
    enum Phase: String, Equatable {
        case off, watch, warning, pausing, paused, resuming, unavailable, error
    }

    enum Event: Equatable {
        case settingsChanged, warning, pauseSucceeded, pauseFailed, resumeSucceeded, resumeFailed
    }

    @Published private(set) var settings: HostGPUProtectionSettings
    @Published private(set) var phase: Phase = .off
    @Published private(set) var status = "Host GPU protection is off."
    var isHoldingProvider: Bool { ownsPause || task != nil || phase == .pausing || phase == .resuming }

    private let defaults: UserDefaults
    private let now: () -> Date
    private let pause: @MainActor () async -> Bool
    private let resume: @MainActor () async -> Bool
    private let canAct: @MainActor () -> Bool
    private let shouldRetainPause: @MainActor () -> Bool
    private let actionWasDeferred: @MainActor () -> Bool
    private let onEvent: @MainActor (Event) -> Void
    private var policy: HostGPUProtectionPolicy
    private var task: Task<Void, Never>?
    private var generation = 0
    private var settingsRevision = 0
    private var ownsPause = false
    private var pausedSince: Date?
    private var failed = false
    private var stopped = false
    private var needsManualStart = false
    private var latestProvider: HostGPUProtectionProviderContext?
    private var latestSample: HostGPUProtectionSample?
    private static let settingsKey = "hostGPUProtection.settings"

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         pause: @escaping @MainActor () async -> Bool,
         resume: @escaping @MainActor () async -> Bool,
         canAct: @escaping @MainActor () -> Bool,
         shouldRetainPause: @escaping @MainActor () -> Bool = { true },
         actionWasDeferred: @escaping @MainActor () -> Bool = { false },
         onEvent: @escaping @MainActor (Event) -> Void = { _ in }) {
        self.defaults = defaults
        self.now = now
        self.pause = pause
        self.resume = resume
        self.canAct = canAct
        self.shouldRetainPause = shouldRetainPause
        self.actionWasDeferred = actionWasDeferred
        self.onEvent = onEvent
        let saved = defaults.data(forKey: Self.settingsKey)
            .flatMap { try? JSONDecoder().decode(HostGPUProtectionSettings.self, from: $0) }
        let settings = saved.flatMap { $0.validationError == nil ? $0 : nil } ?? .init()
        self.settings = settings
        policy = .init(settings: settings)
        if settings.mode != .off {
            phase = .watch
            status = "Watching whole-Mac GPU usage while the provider is idle."
        }
    }

    /// Invalid settings are rejected without persisting or disturbing a pause.
    func updateSettings(_ value: HostGPUProtectionSettings) {
        guard let error = value.validationError else {
            settings = value
            settingsRevision += 1
            defaults.set(try? JSONEncoder().encode(value), forKey: Self.settingsKey)
            onEvent(.settingsChanged)
            if value.mode != .automaticPause {
                generation += 1
                task?.cancel()
            }
            policy = .init(settings: value)
            failed = false
            if value.mode != .automaticPause, ownsPause || phase == .pausing || phase == .resuming {
                abandonPause()
            }
            if task == nil || value.mode != .automaticPause { updateRestingStatus() }
            return
        }
        phase = .error
        status = error
    }

    /// Explicit retry re-arms failed automation and requires a new observation streak.
    func retry() {
        guard !stopped, task == nil else { return }
        failed = false
        policy.reset()
        updateRestingStatus()
    }

    /// Call before a manual provider/config mutation. Revocation never starts it.
    func invalidatePauseOwnership() {
        generation += 1
        task?.cancel()
        if ownsPause || phase == .pausing || phase == .resuming { abandonPause() }
        policy.reset()
        updateRestingStatus()
    }

    /// Cancel and join the task before application shutdown tears down controls.
    func stop() async {
        stopped = true
        generation += 1
        let pending = task
        pending?.cancel()
        await pending?.value
        task = nil
        if ownsPause { abandonPause() }
        policy.reset()
        updateRestingStatus()
    }

    func observe(sample: HostGPUProtectionSample?, provider: HostGPUProtectionProviderContext?) {
        guard !stopped else { return }
        latestProvider = provider
        latestSample = sample
        if ownsPause, !shouldRetainPause() { invalidatePauseOwnership() }
        guard task == nil, !failed else { return }
        if needsManualStart {
            // A fresh running identity establishes that the user has restarted.
            let age = provider.map { now().timeIntervalSince($0.capturedAt) }
            guard provider?.running == true, provider?.identity != nil,
                  let age, age.isFinite, (0...10).contains(age) else {
                updateRestingStatus()
                return
            }
            needsManualStart = false
        }
        let decision = policy.observe(sample: sample, provider: provider, at: now(), pausedSince: ownsPause ? pausedSince : nil)
        switch decision {
        case .off:
            updateRestingStatus()
        case .unavailable(let reason):
            phase = ownsPause ? .paused : .unavailable
            status = ownsPause ? "Provider paused. \(reason)" : reason
        case .watching:
            updateRestingStatus()
        case .breached:
            if settings.mode == .warn {
                if phase != .warning { onEvent(.warning) }
                phase = .warning
                status = "High whole-Mac GPU usage observed while the provider is idle."
            } else if settings.mode == .automaticPause, canAct() {
                beginPause()
            } else {
                phase = .watch
                status = "High host GPU usage; waiting for provider controls to be available."
                policy.reset()
            }
        case .recovered:
            guard ownsPause, settings.mode == .automaticPause, shouldRetainPause(), canAct() else { return }
            beginResume()
        }
    }

    private func beginPause() {
        let ticket = generation
        let revision = settingsRevision
        let identity = latestProvider?.identity
        phase = .pausing
        status = "Pausing the idle provider for sustained high host GPU usage."
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            guard !Task.isCancelled, !self.stopped, self.generation == ticket,
                  self.settingsRevision == revision,
                  self.settings.mode == .automaticPause, self.canAct(),
                  self.currentIdleEvidence(identity: identity) else {
                self.updateRestingStatus()
                return
            }
            let success = await self.pause()
            self.policy.reset()
            guard self.generation == ticket, !self.stopped, !Task.isCancelled else {
                if success { self.needsManualStart = true }
                self.updateRestingStatus()
                return
            }
            if success {
                self.ownsPause = true
                self.pausedSince = self.now()
                self.phase = .paused
                self.status = "Provider paused. Waiting for sustained lower whole-Mac GPU usage."
                self.onEvent(.pauseSucceeded)
            } else if self.actionWasDeferred() {
                self.updateRestingStatus()
            } else {
                self.failed = true
                self.phase = .error
                self.status = "Provider pause was not confirmed. Retry explicitly; automatic restart is disabled."
                self.onEvent(.pauseFailed)
            }
        }
    }

    private func beginResume() {
        let ticket = generation
        let revision = settingsRevision
        phase = .resuming
        status = "Resuming the provider after sustained host GPU recovery."
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            guard !Task.isCancelled, !self.stopped, self.generation == ticket,
                  self.settingsRevision == revision,
                  self.ownsPause, self.settings.mode == .automaticPause,
                  self.shouldRetainPause(), self.canAct(), self.currentRecoveryEvidence() else {
                self.updateRestingStatus()
                return
            }
            let success = await self.resume()
            self.policy.reset()
            if success {
                self.ownsPause = false
                self.pausedSince = nil
            }
            guard self.generation == ticket, !self.stopped, !Task.isCancelled else {
                self.updateRestingStatus()
                return
            }
            if success {
                self.ownsPause = false
                self.pausedSince = nil
                self.phase = .watch
                self.status = "Provider resumed. Watching whole-Mac GPU usage while idle."
                self.onEvent(.resumeSucceeded)
            } else if self.actionWasDeferred() {
                self.updateRestingStatus()
            } else {
                self.failed = true
                self.phase = .error
                self.status = "Provider restart was not confirmed. Retry explicitly or start it manually."
                self.onEvent(.resumeFailed)
            }
        }
    }

    private func currentIdleEvidence(identity: String?) -> Bool {
        guard let provider = latestProvider, let sample = latestSample,
              let identity, !identity.isEmpty, provider.identity == identity,
              provider.running, provider.idle, !provider.isTransitioning,
              sample.percent >= settings.ceilingPercent else { return false }
        let instant = now()
        let providerAge = instant.timeIntervalSince(provider.capturedAt)
        let sampleAge = instant.timeIntervalSince(sample.capturedAt)
        return providerAge.isFinite && (0...10).contains(providerAge)
            && sampleAge.isFinite && (0...10).contains(sampleAge)
    }

    private func currentRecoveryEvidence() -> Bool {
        guard let sample = latestSample, sample.percent < settings.resumePercent else { return false }
        let age = now().timeIntervalSince(sample.capturedAt)
        return age.isFinite && (0...10).contains(age)
    }

    private func abandonPause() {
        ownsPause = false
        pausedSince = nil
        needsManualStart = true
    }

    private func updateRestingStatus() {
        if needsManualStart {
            phase = settings.mode == .off ? .off : .unavailable
            status = "Automatic restart ownership ended. The provider needs a manual start if it is stopped."
        } else if ownsPause {
            phase = .paused
            status = "Provider paused. Waiting for sustained lower whole-Mac GPU usage."
        } else if settings.mode == .off || stopped {
            phase = .off
            status = "Host GPU protection is off."
        } else {
            phase = .watch
            status = "Watching whole-Mac GPU usage while the provider is idle."
        }
    }
}
