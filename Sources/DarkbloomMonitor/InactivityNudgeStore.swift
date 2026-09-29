import Foundation
import Combine
import DarkbloomTelemetry

/// Owns the opt-in watcher. Telemetry polling supplies its clock ticks; it has
/// no independent background timer and cannot run while Bloomy is closed.
@MainActor
final class InactivityNudgeStore: ObservableObject {
    static let keyService = "dev.darkbloom.control.inactivity-nudge-key"
    @Published private(set) var enabled: Bool
    @Published private(set) var inactivityMinutes: Int
    @Published private(set) var status = "Automatic nudge is off."
    @Published private(set) var keyPresent: Bool
    @Published private(set) var lastAttempt: Date?

    private let keyStore: any ConsumerKeyManaging
    private let defaults: UserDefaults
    private let now: () -> Date
    private let evidence: @Sendable (Date) async -> NudgeEarningsEvidence
    private let canAct: @MainActor () -> Bool
    private let send: @MainActor (DaemonState, @escaping @Sendable () async -> Bool) async -> SelfRouteWarmupResult?
    private var policy = InactivityNudgePolicy()
    private var eligibleSince: Date?
    private var latestState: DaemonState?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var lastCheck: Date?
    private var attempts: [Double]
    private var invalidLedger = false
    private static let prefix = "inactivityNudge."

    init(
        keyStore: any ConsumerKeyManaging = KeychainConsumerKeyStore(service: keyService),
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        evidence: @escaping @Sendable (Date) async -> NudgeEarningsEvidence = { since in
            await AuthenticatedEarningsClient(homeDirectory: FileManager.default.homeDirectoryForCurrentUser)
                .nudgeEvidence(since: since)
        },
        canAct: @escaping @MainActor () -> Bool,
        send: @escaping @MainActor (DaemonState, @escaping @Sendable () async -> Bool) async -> SelfRouteWarmupResult?
    ) {
        self.keyStore = keyStore
        self.defaults = defaults
        self.now = now
        self.evidence = evidence
        self.canAct = canAct
        self.send = send
        enabled = defaults.bool(forKey: Self.prefix + "enabled")
        let savedMinutes = defaults.integer(forKey: Self.prefix + "minutes")
        inactivityMinutes = [15, 30, 60].contains(savedMinutes) ? savedMinutes : 15
        keyPresent = keyStore.hasKey
        let saved = defaults.object(forKey: Self.prefix + "attempts")
        attempts = saved as? [Double] ?? []
        invalidLedger = saved != nil && saved as? [Double] == nil
        lastAttempt = attempts.filter { $0.isFinite }.max().map(Date.init(timeIntervalSince1970:))
        if enabled { status = "Waiting for fresh idle evidence." }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        defaults.set(value, forKey: Self.prefix + "enabled")
        resetPending()
        status = value ? "Waiting for fresh idle evidence." : "Automatic nudge is off."
    }

    func setInactivityMinutes(_ value: Int) {
        guard [15, 30, 60].contains(value) else { return }
        inactivityMinutes = value
        defaults.set(value, forKey: Self.prefix + "minutes")
        resetPending()
    }

    func saveKey(_ key: String) -> String? {
        do {
            try keyStore.store(key)
            keyPresent = keyStore.hasKey
            resetPending()
            return nil
        } catch {
            return "Could not save the key. Check its format and Keychain access."
        }
    }

    func removeKey() {
        resetPending()
        keyStore.remove()
        keyPresent = keyStore.hasKey
        status = keyPresent ? "Keychain could not remove the key." : "Add a watcher key in Settings."
    }

    func stop() async {
        let pending = task
        resetPending()
        await pending?.value
    }

    private func resetPending() {
        generation += 1
        task?.cancel()
        // Keep the task slot occupied until cancellation unwinds, so replacing
        // a key or toggling cannot create two concurrent network requests.
        policy.reset()
        eligibleSince = nil
        latestState = nil
        lastCheck = nil
    }

    func observe(_ snapshot: TelemetrySnapshot) {
        if case .available(let state, _) = snapshot.state {
            observe(state)
        } else { observe(nil as DaemonState?) }
    }

    func observe(_ state: DaemonState?) {
        let instant = now()
        latestState = state
        guard enabled, keyPresent else {
            policy.reset()
            eligibleSince = nil
            status = enabled ? "Add a watcher key in Settings." : "Automatic nudge is off."
            return
        }
        // While our task owns the control gate, keep consuming telemetry so
        // new work invalidates the candidate before the POST is sent.
        guard task != nil || canAct() else {
            policy.reset()
            eligibleSince = nil
            status = "Paused while provider settings are changing."
            return
        }
        eligibleSince = policy.observe(state, at: instant, threshold: Double(inactivityMinutes) * 60)
        guard task == nil else { return }
        guard let since = eligibleSince, let state else {
            status = "Watching for \(inactivityMinutes) minutes of continuous idle time."
            return
        }
        guard budgetAvailable(at: instant) else { return }
        if let lastCheck, instant.timeIntervalSince(lastCheck) < 600 { return }
        lastCheck = instant
        let ticket = generation
        status = "Checking fresh account earnings."
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            let result = await self.evidence(since)
            guard self.candidateValid(ticket: ticket, since: since), self.canAct() else { return }
            guard result == .baseRewardsOnly else {
                self.status = result == .workRecorded
                    ? "Account work was recorded; no nudge needed."
                    : "Waiting for complete base-reward-only earnings evidence."
                return
            }
            let attemptTime = self.now()
            guard self.budgetAvailable(at: attemptTime) else { return }
            // Persist before dispatch, including failed or cancelled attempts.
            self.attempts.append(attemptTime.timeIntervalSince1970)
            self.defaults.set(self.attempts, forKey: Self.prefix + "attempts")
            self.lastAttempt = attemptTime
            self.status = "Sending one self-route nudge."
            let outcome = await self.send(state) { [weak self] in
                await self?.candidateValid(ticket: ticket, since: since) ?? false
            }
            guard self.generation == ticket else { return }
            self.policy.reset()
            self.eligibleSince = nil
            switch outcome {
            case .sent: self.status = "Self-test responded. Watching for public work."
            case .missingKey: self.status = "Watcher key is unavailable."
            case .keyRejected: self.status = "Watcher key was rejected. Update it in Settings."
            case .modelUnavailable: self.status = "Warm model is unavailable for self-routing."
            case .failed, nil: self.status = "Nudge did not complete. Cooldown is active."
            }
        }
    }

    private func candidateValid(ticket: Int, since: Date) -> Bool {
        guard !Task.isCancelled, enabled, keyPresent, generation == ticket,
              eligibleSince == since else { return false }
        // Re-evaluate freshness even when no telemetry tick arrived during GET.
        eligibleSince = policy.observe(latestState, at: now(), threshold: Double(inactivityMinutes) * 60)
        return eligibleSince == since
    }

    private func budgetAvailable(at date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        guard seconds.isFinite, !invalidLedger,
              attempts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= seconds }) else {
            status = "Paused: attempt history or system clock needs attention."
            return false
        }
        attempts.removeAll { seconds - $0 >= 86_400 }
        guard attempts.count < 3 else {
            status = "Daily limit reached (3 attempts in 24 hours)."
            return false
        }
        if let latest = attempts.max(), seconds - latest < 3_600 {
            status = "Cooldown: at least 1 hour between attempts."
            return false
        }
        return true
    }
}
