import Foundation
import Combine
import Darwin
import DarkbloomTelemetry

/// Opt-in automation above the existing native CLI switch transaction. Public
/// demand is a utilization proxy, never a reservation or a payout guarantee.
@MainActor
final class ProfitSwitchStore: ObservableObject {
    @Published private(set) var timing: ProfitSwitchTiming
    @Published private(set) var enabled: Bool
    @Published private(set) var status = "Automatic model switching is off."
    @Published private(set) var lastAttempt: Date?

    private let control: ProviderControlStore
    private let defaults: UserDefaults
    private let now: () -> Date
    private let installedMemoryGB: Double
    private let availableMemoryGB: () -> Double?
    private var policy: ProfitSwitchPolicy
    private var task: Task<Void, Never>?
    private var generation = 0
    private var currentIdentity: ProcessIdentity?
    private var currentModel: String?
    private var currentSince: Date?
    private var lastObservation: Date?
    private var latestTelemetry: TelemetrySnapshot?
    private var latestNetwork: SourceAvailability<NetworkCapacitySnapshot> = .unavailable(reason: "Waiting")
    private var latestProfits: [ModelServingProfitAverage] = []
    private var profitsCapturedAt: Date?
    private var attempts: [Double]
    private var departed: [String: Double]
    private var loading: [String: Double]
    private var invalidLedger: Bool
    private static let prefix = "profitSwitch."

    init(control: ProviderControlStore, defaults: UserDefaults = .standard,
         now: @escaping () -> Date = Date.init,
         installedMemoryGB: Double = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824,
         availableMemoryGB: @escaping () -> Double? = { ProfitSwitchStore.readAvailableMemoryGB() }) {
        self.control = control
        self.defaults = defaults
        self.now = now
        self.installedMemoryGB = installedMemoryGB
        self.availableMemoryGB = availableMemoryGB
        let savedTiming = defaults.data(forKey: Self.prefix + "timing")
            .flatMap { try? JSONDecoder().decode(ProfitSwitchTiming.self, from: $0) } ?? .init()
        timing = savedTiming
        policy = ProfitSwitchPolicy(timing: savedTiming)
        enabled = defaults.bool(forKey: Self.prefix + "enabled")
        let savedAttempts = defaults.object(forKey: Self.prefix + "attempts")
        let savedDeparted = defaults.object(forKey: Self.prefix + "departed")
        let savedLoading = defaults.object(forKey: Self.prefix + "loading")
        attempts = savedAttempts as? [Double] ?? []
        departed = savedDeparted as? [String: Double] ?? [:]
        loading = savedLoading as? [String: Double] ?? [:]
        invalidLedger = (savedAttempts != nil && savedAttempts as? [Double] == nil)
            || (savedDeparted != nil && savedDeparted as? [String: Double] == nil)
            || (savedLoading != nil && savedLoading as? [String: Double] == nil)
        lastAttempt = attempts.filter(\.isFinite).max().map(Date.init(timeIntervalSince1970:))
        if enabled { status = "Waiting for fresh model and profit evidence." }
    }

    func updateTiming(_ value: ProfitSwitchTiming) {
        timing = value
        control.actionHistory?.record(action: .profitSettings, trigger: .manual, outcome: .succeeded)
        defaults.set(try? JSONEncoder().encode(value), forKey: Self.prefix + "timing")
        generation += 1
        task?.cancel()
        policy = ProfitSwitchPolicy(timing: value)
        // A settings change must establish a new sustained lead. The current
        // model's observed tenure and attempt history remain authoritative.
        status = enabled ? "Timing updated. Waiting for a sustained advantage." : "Automatic model switching is off."
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        control.actionHistory?.record(action: .profitSettings, trigger: .manual, outcome: .succeeded, reason: value ? .completed : .disabled)
        defaults.set(value, forKey: Self.prefix + "enabled")
        generation += 1
        task?.cancel()
        policy.reset()
        currentSince = nil
        currentModel = nil
        currentIdentity = nil
        status = value ? "Observing the current model for at least \(timing.minimumHoldMinutes) minutes." : "Automatic model switching is off."
    }

    func stop() async {
        generation += 1
        let pending = task
        pending?.cancel()
        await pending?.value
        policy.reset()
        currentSince = nil
    }

    func observe(telemetry: TelemetrySnapshot, network: SourceAvailability<NetworkCapacitySnapshot>,
                 profits: [ModelServingProfitAverage], profitsCapturedAt: Date?) {
        latestTelemetry = telemetry
        latestNetwork = network
        latestProfits = profits
        self.profitsCapturedAt = profitsCapturedAt
        let instant = now()
        guard enabled else { return }
        guard case .available(let state, _) = telemetry.state,
              servingState(state, at: instant) else {
            policy.reset()
            currentSince = nil
            status = "Paused: need fresh, single-model serving state."
            return
        }
        if currentModel != state.currentModel || currentIdentity != state.processIdentity
            || lastObservation.map({ !(0...15).contains(instant.timeIntervalSince($0)) }) == true {
            if let old = currentModel, old != state.currentModel {
                departed[old] = instant.timeIntervalSince1970
                defaults.set(departed, forKey: Self.prefix + "departed")
            }
            currentModel = state.currentModel
            currentIdentity = state.processIdentity
            currentSince = instant
            policy.reset()
        }
        if currentSince == nil { currentSince = instant }
        lastObservation = instant
        guard task == nil else { return }
        guard control.canAutomaticNudge else {
            policy.reset()
            status = "Paused while provider controls are being edited."
            return
        }
        guard let input = makeInput(state: state, at: instant) else {
            policy.reset()
            status = "Need fresh demand, measured profits, and memory headroom."
            return
        }
        let proposal = policy.observe(input, at: instant)
        guard budgetAvailable(at: instant),
              let currentSince, instant.timeIntervalSince(currentSince) >= Double(timing.minimumHoldMinutes * 60) else {
            if self.currentSince.map({ instant.timeIntervalSince($0) < Double(timing.minimumHoldMinutes * 60) }) == true {
                status = "Holding this model for at least \(timing.minimumHoldMinutes) minutes."
            }
            return
        }
        guard let proposal else {
            status = "Watching for a sustained, meaningful profit advantage."
            return
        }
        guard canReturn(to: proposal.modelID, at: instant) else {
            status = "Return cooldown: keep recently used models out for \(timing.returnCooldownMinutes) minutes."
            return
        }
        guard idle(state, at: instant) else {
            status = "Better opportunity found; waiting for current work to finish."
            return
        }
        let ticket = generation
        task = Task { [weak self] in
            guard let self else { return }
            defer { self.task = nil }
            // Existing refresh preserves a user's draft. The same control gate
            // serializes this work with nudges, manual switches, and restarts.
            await self.control.refreshPreservingDraft()
            guard !Task.isCancelled, self.enabled, self.generation == ticket,
                  self.control.canAutomaticNudge,
                  self.currentSince == currentSince,
                  let telemetry = self.latestTelemetry,
                  case .available(let latestState, _) = telemetry.state,
                  latestState.processIdentity == state.processIdentity,
                  latestState.currentModel == proposal.currentModelID,
                  self.idle(latestState, at: self.now()),
                  let snapshot = self.control.snapshot,
                  let freshState = snapshot.daemonState,
                  freshState.processIdentity == state.processIdentity,
                  freshState.currentModel == proposal.currentModelID,
                  self.idle(freshState, at: self.now()),
                  self.control.singleModelSwitchUnavailableReason(for: proposal.modelID) == nil,
                  self.budgetAvailable(at: self.now()),
                  self.canReturn(to: proposal.modelID, at: self.now()),
                  let latest = self.makeInput(state: freshState, at: self.now()),
                  // Re-evaluate the economics against the freshly read inventory.
                  let confirmed = ProfitSwitchPolicy.evaluate(latest, at: self.now(), timing: self.timing),
                  confirmed.modelID == proposal.modelID else {
                self.policy.reset()
                return
            }
            let started = self.now()
            self.attempts.append(started.timeIntervalSince1970)
            self.defaults.set(self.attempts, forKey: Self.prefix + "attempts")
            self.lastAttempt = started
            self.status = "Switching to \(proposal.modelID) for an estimated profit advantage."
            // No automatic consumer inference: the inactivity watcher has its
            // own credential, rate limit, and independent evidence requirements.
            await self.control.switchToSingleModel(proposal.modelID, sendWarmup: false, trigger: .automatic)
            let ended = self.now()
            let elapsed = ended.timeIntervalSince(started)
            if elapsed.isFinite, elapsed >= 0 {
                self.loading[proposal.modelID] = max(self.loading[proposal.modelID] ?? 0, elapsed)
                self.defaults.set(self.loading, forKey: Self.prefix + "loading")
            }
            // Reserve return protection even for uncertain/cancelled outcomes.
            self.departed[proposal.currentModelID] = ended.timeIntervalSince1970
            self.defaults.set(self.departed, forKey: Self.prefix + "departed")
            self.policy.reset()
            self.currentSince = ended
            guard self.generation == ticket else { return }
            if let resultingState = self.control.snapshot?.daemonState,
               resultingState.advertisedModels == [proposal.modelID],
               self.servingState(resultingState, at: ended),
               self.control.errorMessage == nil {
                self.status = "Switched to \(proposal.modelID). Holding for at least \(timing.minimumHoldMinutes) minutes."
            } else {
                self.status = "Switch was not confirmed. Cooldown is active; no immediate retry."
            }
        }
    }

    private func servingState(_ state: DaemonState, at instant: Date) -> Bool {
        let age = instant.timeIntervalSince1970 - state.writtenAt
        guard age.isFinite, (0...10).contains(age), state.trust?.status == "online",
              state.lifecycle?.outcome == .serving,
              state.advertisedModels == [state.currentModel], state.warmModels == [state.currentModel],
              state.startupPreloadPendingModels?.isEmpty == true,
              state.availability == nil, state.modelLoadFailures.isEmpty,
              state.modelSwitch?.outcome == .serving else { return false }
        return true
    }

    private func idle(_ state: DaemonState, at instant: Date) -> Bool {
        var guardPolicy = InactivityNudgePolicy()
        return servingState(state, at: instant)
            && guardPolicy.observe(state, at: instant, threshold: 0) != nil
    }

    private func makeInput(state: DaemonState, at instant: Date) -> ProfitSwitchInput? {
        guard case .available(let network, _) = latestNetwork,
              network.isFresh(at: instant), !network.isDraining,
              let profitsCapturedAt, (0...900).contains(instant.timeIntervalSince(profitsCapturedAt)),
              Set(latestProfits.map(\.model)).count == latestProfits.count,
              Set(network.models.map(\.id)).count == network.models.count,
              let inventory = control.snapshot?.inventory,
              let capabilities = state.runtimeCapabilities,
              let availableGB = availableMemoryGB(), availableGB.isFinite, availableGB >= 0 else { return nil }
        let candidates = inventory.myCatalog.compactMap { item -> ProfitSwitchCandidate? in
            guard item.isDownloaded, item.localID != nil, item.issue == nil,
                  item.minimumRAMGB > 0, Double(item.minimumRAMGB) <= installedMemoryGB,
                  item.sizeGB.isFinite, item.sizeGB > 0,
                  item.catalogID == state.currentModel || availableGB >= item.sizeGB * 1.35 + 4,
                  let requirements = item.requiredProviderCapabilities,
                  Set(requirements).isSubset(of: Set(capabilities)),
                  let profit = latestProfits.first(where: { $0.model == item.catalogID }),
                  profit.activeHours.isFinite, profit.activeHours >= 2,
                  profit.coveredEarningHours >= 2, profit.activePowerSamples > 0, profit.idlePowerSamples > 0,
                  let net = profit.profitUSDPerActiveHour,
                  let capacity = network.models.first(where: { $0.id == item.catalogID }),
                  capacity.ready, capacity.canAccept,
                  capacity.activeRequests >= 0, capacity.queuedRequests >= 0,
                  capacity.warmProviders >= 0 else { return nil }
            let requests = capacity.activeRequests.addingReportingOverflow(capacity.queuedRequests)
            guard !requests.overflow else { return nil }
            return ProfitSwitchCandidate(
                modelID: item.catalogID, requests: requests.partialValue,
                pressure: Double(requests.partialValue) / Double(max(1, capacity.warmProviders)),
                grossUSDPerActiveHour: profit.grossUSDPerActiveHour,
                netUSDPerActiveHour: net,
                loadSeconds: max(Double(timing.loadAllowanceMinutes * 60), loading[item.catalogID] ?? 0)
            )
        }
        return ProfitSwitchInput(currentModelID: state.currentModel, candidates: candidates, capturedAt: network.capturedAt)
    }

    /// Conservative reclaimable headroom, without assuming that the current
    /// serving model will be evicted. The CLI remains final load authority.
    private static func readAvailableMemoryGB() -> Double? {
        var statistics = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        var pageSize: vm_size_t = 0
        guard result == KERN_SUCCESS, host_page_size(host, &pageSize) == KERN_SUCCESS, pageSize > 0 else { return nil }
        return (Double(statistics.free_count) + Double(statistics.inactive_count))
            * Double(pageSize) / 1_073_741_824
    }

    private func canReturn(to model: String, at instant: Date) -> Bool {
        guard let departedAt = departed[model] else { return true }
        return instant.timeIntervalSince1970 - departedAt >= Double(timing.returnCooldownMinutes * 60)
    }

    private func budgetAvailable(at instant: Date) -> Bool {
        let seconds = instant.timeIntervalSince1970
        guard seconds.isFinite, !invalidLedger,
              attempts.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= seconds }),
              departed.values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= seconds }),
              loading.values.allSatisfy({ $0.isFinite && $0 >= 0 }) else {
            status = "Paused: saved switch history or system clock needs attention."
            return false
        }
        attempts.removeAll { seconds - $0 >= 86_400 }
        departed = departed.filter { seconds - $0.value < 86_400 }
        guard attempts.count < 3 else {
            status = "Daily limit reached (three switch attempts in 24 hours)."
            return false
        }
        guard attempts.max().map({ seconds - $0 >= Double(timing.minimumHoldMinutes * 60) }) ?? true else {
            status = "Switch cooldown: at least \(timing.minimumHoldMinutes) minutes between attempts."
            return false
        }
        return true
    }
}
