import Foundation
import Combine
import DarkbloomTelemetry

/// Owns the opt-in watcher. Telemetry polling supplies its clock ticks; it has
/// no independent background timer and cannot run while Bloomy is closed.
@MainActor
final class InactivityNudgeStore: ObservableObject {
    var actionHistory: ActionHistoryStore?
    private var lastRecordedPause: ActionHistoryReason?
    static let keyService = "dev.darkbloom.control.inactivity-nudge-key"
    @Published private(set) var enabled: Bool
    @Published private(set) var inactivityMinutes: Int
    @Published private(set) var status = "Automatic nudge is off."
    /// Nil means the metadata lookup is still in progress. Presence never
    /// reads the secret and does not promise that a later request can use it.
    @Published private(set) var keyPresence: ConsumerKeyPresence?
    var keyPresent: Bool { keyPresence == .configured }
    var keyStatusNotice: String? {
        switch keyPresence {
        case nil: "Checking saved key…"
        case .unavailable: "Keychain status is unavailable. Try again."
        case .configured, .missing: nil
        }
    }
    @Published private(set) var lastAttempt: Date?
    @Published private(set) var isManuallyNudging = false
    @Published private(set) var manualStatus: String?

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
    private var manualTask: Task<Bool, Never>?
    private var generation = 0
    private var lastCheck: Date?
    private var attempts: [Double]
    private var invalidLedger = false
    private var keyStatusTask: Task<Void, Never>?
    private var keyStatusGeneration = 0
    private static let prefix = "inactivityNudge."

    /// A manual request still needs fresh, idle evidence and an exclusive
    /// self-route key, but it does not consume the automatic watcher's budget.
    var manualUnavailableReason: String? {
        if isManuallyNudging || task != nil { return "A nudge is already in progress." }
        if let keyStatusNotice { return keyStatusNotice }
        if !keyPresent { return "Add a nudge key below." }
        if !canAct() { return "Finish the current provider action before nudging." }
        if Self.manualEligibleState(latestState, at: now()) == nil {
            return "Wait for fresh idle state with exactly one warm model."
        }
        return nil
    }

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
        keyPresence = nil
        let saved = defaults.object(forKey: Self.prefix + "attempts")
        attempts = saved as? [Double] ?? []
        invalidLedger = saved != nil && saved as? [Double] == nil
        lastAttempt = attempts.filter { $0.isFinite }.max().map(Date.init(timeIntervalSince1970:))
        if enabled { status = "Checking saved key…" }
        beginKeyStatusCheck()
    }

    /// Joins an in-flight metadata check or retries an unavailable status.
    /// The synchronous Security call runs outside the main actor.
    func refreshKeyStatus() async {
        if keyStatusTask == nil { beginKeyStatusCheck() }
        await keyStatusTask?.value
    }

    private func invalidateKeyStatus() {
        keyStatusGeneration += 1
        keyStatusTask?.cancel()
        keyStatusTask = nil
    }

    private func beginKeyStatusCheck(reportRemoval: Bool = false) {
        keyPresence = nil
        let ticket = keyStatusGeneration
        let keyStore = keyStore
        keyStatusTask = Task { [weak self] in
            let result = await keyStore.keyPresenceInBackground()
            guard !Task.isCancelled, let self, self.keyStatusGeneration == ticket else { return }
            self.keyPresence = result
            self.keyStatusTask = nil
            if reportRemoval {
                let removed = result == .missing
                self.actionHistory?.record(action: .nudgeKey, trigger: .manual,
                    outcome: removed ? .succeeded : .failed,
                    reason: removed ? .disabled : .requestFailed)
                let message = switch result {
                case .missing: "Add a nudge key below."
                case .configured: "Keychain could not remove the nudge key."
                case .unavailable: "Could not verify key removal. Refresh key status."
                }
                self.manualStatus = message
                self.status = message
            } else if self.enabled {
                self.status = self.keyStatusNotice
                    ?? (self.keyPresent ? "Waiting for fresh idle evidence." : "Add a nudge key in Settings.")
            }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        actionHistory?.record(action: .nudgeSettings, trigger: .manual, outcome: .succeeded, reason: value ? .completed : .disabled)
        defaults.set(value, forKey: Self.prefix + "enabled")
        resetPending()
        status = value ? (keyStatusNotice
            ?? (keyPresent ? "Waiting for fresh idle evidence." : "Add a nudge key in Settings."))
            : "Automatic nudge is off."
    }

    func setInactivityMinutes(_ value: Int) {
        guard [15, 30, 60].contains(value) else { return }
        inactivityMinutes = value
        actionHistory?.record(action: .nudgeSettings, trigger: .manual, outcome: .succeeded)
        defaults.set(value, forKey: Self.prefix + "minutes")
        resetPending()
    }

    func saveKey(_ key: String) -> String? {
        do {
            try keyStore.store(key)
            invalidateKeyStatus()
            keyPresence = .configured
            resetPending()
            actionHistory?.record(action: .nudgeKey, trigger: .manual, outcome: .succeeded)
            manualStatus = "Nudge key saved securely."
            return nil
        } catch {
            return "Could not save the key. Check its format and Keychain access."
        }
    }

    func removeKey() {
        resetPending()
        invalidateKeyStatus()
        keyStore.remove()
        manualStatus = "Checking saved key…"
        status = "Checking saved key…"
        beginKeyStatusCheck(reportRemoval: true)
    }

    func stop() async {
        let pending = task
        let manual = manualTask
        resetPending()
        await pending?.value
        _ = await manual?.value
    }

    private func resetPending() {
        generation += 1
        task?.cancel()
        if manualTask != nil { manualStatus = "Manual nudge canceled." }
        manualTask?.cancel()
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
        // A manual request owns this interval. Do not start an automatic
        // account check or rebuild its continuous-idle window in parallel.
        if isManuallyNudging { return }
        guard enabled, keyPresent else {
            policy.reset()
            eligibleSince = nil
            status = enabled ? (keyStatusNotice ?? "Add a nudge key in Settings.") : "Automatic nudge is off."
            recordWatcherPause(enabled ? (keyPresence == .missing ? .keyMissing : .providerNotReady) : .disabled)
            return
        }
        // While our task owns the control gate, keep consuming telemetry so
        // new work invalidates the candidate before the POST is sent.
        guard task != nil || canAct() else {
            policy.reset()
            eligibleSince = nil
            status = "Paused while provider settings are changing."
            recordWatcherPause(.providerBusy)
            return
        }
        eligibleSince = policy.observe(state, at: instant, threshold: Double(inactivityMinutes) * 60)
        guard task == nil else { return }
        guard let since = eligibleSince, let state else {
            let ready = NudgeIdleStateEligibility.eligibleState(state, at: instant) != nil
            status = ready ? "Watching for \(inactivityMinutes) minutes of continuous idle time."
                : "Paused: waiting for fresh, idle provider state."
            recordWatcherPause(ready ? nil : .providerNotReady)
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
                self.recordWatcherPause(result == .workRecorded ? .workRecorded : .earningsUnavailable)
                return
            }
            let attemptTime = self.now()
            guard self.budgetAvailable(at: attemptTime) else { return }
            // Persist before dispatch, including failed or cancelled attempts.
            self.attempts.append(attemptTime.timeIntervalSince1970)
            self.defaults.set(self.attempts, forKey: Self.prefix + "attempts")
            self.lastAttempt = attemptTime
            self.status = "Sending one self-route nudge."
            let outcome = await self.recordedSend(state, trigger: .automatic) { [weak self] in
                await self?.candidateValid(ticket: ticket, since: since) ?? false
            }
            guard self.generation == ticket else { return }
            self.policy.reset()
            self.eligibleSince = nil
            switch outcome {
            case .sent: self.status = "Self-test responded. Watching for public work."
            case .missingKey: self.status = "Nudge key is unavailable."
            case .keyRejected: self.status = "Nudge key was rejected. Update it in Settings."
            case .modelUnavailable: self.status = "Warm model is unavailable for self-routing; no nudge was sent."
            case .failed, nil: self.status = "Nudge did not complete. Cooldown is active."
            }
        }
    }

    /// Sends one explicit, bounded self-route request through the existing
    /// Keychain-backed client and provider operation gate. No earnings query,
    /// automatic idle threshold, or automatic attempt ledger applies here.
    @discardableResult
    func nudgeNow() async -> Bool {
        guard let reason = manualUnavailableReason else {
            guard let state = Self.manualEligibleState(latestState, at: now()) else {
                manualStatus = "Wait for fresh idle state with exactly one warm model."
                return false
            }
            // A manual attempt starts a new automatic continuous-idle window.
            policy.reset()
            eligibleSince = nil
            lastCheck = nil
            isManuallyNudging = true
            manualStatus = "Sending one self-route nudge."
            let ticket = generation
            let candidate = ManualCandidate(state: state)
            let request = Task { @MainActor [weak self] () -> Bool in
                guard let self else { return false }
                defer {
                    self.manualTask = nil
                    self.isManuallyNudging = false
                }
                let outcome = await self.recordedSend(state, trigger: .manual) { [weak self] in
                    await self?.manualCandidateValid(ticket: ticket, candidate: candidate) ?? false
                }
                guard self.generation == ticket else { return false }
                guard !Task.isCancelled else {
                    self.manualStatus = "Manual nudge canceled."
                    return false
                }
                switch outcome {
                case .sent:
                    self.manualStatus = "Self-test responded. Public work is not guaranteed."
                    return true
                case .missingKey:
                    self.invalidateKeyStatus()
                    self.beginKeyStatusCheck()
                    self.manualStatus = "Nudge key is unavailable. Check Keychain access or replace it in Settings."
                case .keyRejected:
                    self.manualStatus = "Nudge key was rejected. Update it below."
                case .modelUnavailable:
                    self.manualStatus = "Warm model is unavailable for self-routing; no nudge was sent."
                case .failed, nil:
                    self.manualStatus = "Nudge did not complete."
                }
                return false
            }
            manualTask = request
            return await withTaskCancellationHandler {
                await request.value
            } onCancel: {
                request.cancel()
            }
        }
        manualStatus = reason
        return false
    }

    private func recordedSend(
        _ state: DaemonState, trigger: ActionHistoryTrigger,
        canSend: @escaping @Sendable () async -> Bool
    ) async -> SelfRouteWarmupResult? {
        let id = actionHistory?.record(action: .nudge, trigger: trigger,
            outcome: .started, model: state.currentModel)
        let outcome = await send(state, canSend)
        let result: ActionHistoryOutcome
        let reason: ActionHistoryReason?
        if Task.isCancelled { result = .cancelled; reason = nil }
        else {
            switch outcome {
            case .sent: result = .succeeded; reason = .completed
            case .missingKey: result = .skipped; reason = .keyMissing
            case .keyRejected: result = .failed; reason = .keyRejected
            case .modelUnavailable: result = .skipped; reason = .modelUnavailable
            case .failed: result = .failed; reason = .requestFailed
            case nil: result = .skipped; reason = .providerBusy
            }
        }
        actionHistory?.finish(id, outcome: result, reason: reason)
        return outcome
    }

    private func recordWatcherPause(_ reason: ActionHistoryReason?) {
        guard reason != lastRecordedPause else { return }
        lastRecordedPause = reason
        guard let reason else { return }
        actionHistory?.record(action: .watcher, trigger: .automatic, outcome: .skipped,
            model: latestState?.currentModel, reason: reason)
    }

    private struct ManualCandidate: Sendable {
        let processIdentity: ProcessIdentity
        let model: String
        let stats: ProviderStats

        init(state: DaemonState) {
            processIdentity = state.processIdentity
            model = state.currentModel
            stats = state.stats
        }
    }

    private func manualCandidateValid(ticket: Int, candidate: ManualCandidate) -> Bool {
        guard !Task.isCancelled, generation == ticket, isManuallyNudging,
              keyPresent,
              let state = Self.manualEligibleState(latestState, at: now()) else { return false }
        return state.processIdentity == candidate.processIdentity
            && state.currentModel == candidate.model
            && state.stats == candidate.stats
    }

    private static func manualEligibleState(_ state: DaemonState?, at now: Date) -> DaemonState? {
        NudgeIdleStateEligibility.eligibleState(state, at: now)
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
            recordWatcherPause(.providerNotReady)
            return false
        }
        attempts.removeAll { seconds - $0 >= 86_400 }
        guard attempts.count < 3 else {
            status = "Daily limit reached (3 attempts in 24 hours)."
            recordWatcherPause(.dailyLimit)
            return false
        }
        if let latest = attempts.max(), seconds - latest < 3_600 {
            status = "Cooldown: at least 1 hour between attempts."
            recordWatcherPause(.cooldown)
            return false
        }
        return true
    }
}

/// A family alias is safe only when this provider advertises the one warm
/// model alone. With multiple advertised builds, an alias could select a
/// different (possibly cold) model, so the nudge requires the exact ID.
enum NudgeSelfRouteModel {
    static func familyFallback(for state: DaemonState, catalogFamily: String) -> String {
        state.advertisedModels == [state.currentModel] ? catalogFamily : ""
    }
}
