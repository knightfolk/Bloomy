import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Pure provider readiness")
struct ProviderReadinessTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let identity = ProcessIdentity(pid: 42, startTimeMicros: 900_000_000)
    private let lease = ProviderAuthorizationStatus(
        path: "app_attest", expiresAt: 1_100, sessionIDPresent: true, machineIDPresent: true
    )

    @Test("fresh current and legacy authorization distinguish active and idle work")
    func currentAuthorization() {
        let idle = present(state())
        #expect(idle.state == .ready)
        #expect(idle.title == "Ready · no active work")
        #expect(idle.suggestedAction == nil)
        #expect(present(state(active: true)).state == .serving)
        #expect(present(state(active: true)).title == "Serving now")
        let legacy = present(state(trust: trust(authorization: nil, level: "hardware")))
        #expect(legacy.state == .ready)
        #expect(legacy.evidence.first { $0.id == .authorization }?.value == "Legacy verified")
        #expect(present(state(trust: trust(authorization: ProviderAuthorizationStatus(path: "legacy")))).state == .ready)
    }

    @Test("online status cannot bypass missing or reused process identity")
    func requiresObservedIdentity() {
        let sample = state(active: true)
        for supplied in [nil, ProcessIdentity(pid: 42, startTimeMicros: 901_000_000), ProcessIdentity(pid: 43, startTimeMicros: 900_000_000)] {
            let result = ProviderReadinessPresentation.make(snapshot: snapshot(sample), now: now, liveProcessIdentity: supplied)
            #expect(result.state == .unconfirmed)
            #expect(result.evidence.first { $0.id == .work }?.value == "Unknown")
            #expect(ProviderVerification.evaluateObservedIdentity(state: sample, expectedCoordinator: "https://coordinator.example", now: now, liveProcessIdentity: supplied).state == .wrongProcess)
        }
    }

    @Test("absent expired unknown or pre-start authorization cannot claim ready")
    func authorizationGates() {
        let cases: [TrustState?] = [
            nil,
            trust(authorization: nil),
            trust(authorization: ProviderAuthorizationStatus(path: "app_attest", expiresAt: 999, sessionIDPresent: true, machineIDPresent: true)),
            trust(authorization: ProviderAuthorizationStatus(path: "unknown", expiresAt: 1_100)),
            trust(authorization: ProviderAuthorizationStatus(protocolVersion: 2, path: "app_attest", expiresAt: 1_100)),
            trust(authorization: ProviderAuthorizationStatus(path: "app_attest", expiresAt: 1_100)),
        ]
        for value in cases { #expect(present(state(trust: value)).state == .authorizationRequired) }
        #expect(present(state(startedAt: 998)).state == .authorizationRequired)
        #expect(present(state(trust: trust(status: "offline"))).state == .offline)
        #expect(present(state(coordinator: "https://different.example")).state == .unconfirmed)
    }

    @Test("source labels never bypass stale future or nonfinite timestamps")
    func sourceFreshness() {
        for timestamp in [989.0, 1_001, .infinity, .nan] {
            #expect(present(state(writtenAt: timestamp)).state == .stale)
            #expect(present(state(), capturedAt: Date(timeIntervalSince1970: timestamp)).state == .stale)
            #expect(present(state(), daemonCapturedAt: Date(timeIntervalSince1970: timestamp)).state == .stale)
            #expect(present(state(trust: trust(receivedAt: timestamp))).state == .stale)
        }
        let stale = snapshot(state(), stateStale: true)
        #expect(ProviderReadinessPresentation.make(snapshot: stale, now: now, liveProcessIdentity: identity).state == .stale)
        let missing = TelemetrySnapshot.unavailable(now: now)
        #expect(ProviderReadinessPresentation.make(snapshot: missing, now: now, liveProcessIdentity: identity).state == .unavailable)
        #expect(present(state(), now: Date(timeIntervalSince1970: .infinity)).state == .stale)
    }

    @Test("expected coordinator comes only from available CLI status within two polling intervals")
    func configurationFreshness() {
        #expect(present(state(), statusCapturedAt: Date(timeIntervalSince1970: 940)).state == .ready)
        for timestamp in [939.0, 1_001, .infinity, .nan] {
            #expect(present(state(), statusCapturedAt: Date(timeIntervalSince1970: timestamp)).state == .unconfirmed)
        }
        #expect(present(state(), statusStale: true).state == .unconfirmed)
        #expect(present(state(), statusUnavailable: true).state == .unconfirmed)
        #expect(present(state(), expectedCoordinator: nil).state == .unconfirmed)
    }

    @Test("scheduled waiting may intentionally have no trust observation")
    func scheduledWaiting() {
        let scheduled = state(trust: .some(nil), warm: [], advertised: nil, availability: ProviderAvailabilityState(phase: .waitingForSchedule))
        let value = present(scheduled)
        #expect(value.state == .scheduledWaiting)
        #expect(value.tone == .neutral)
        #expect(value.evidence.first { $0.id == .authorization }?.value == "Unconfirmed")
        #expect(value.evidence.first { $0.id == .work }?.value == "Scheduled idle")
        #expect(present(scheduled, capturedAt: Date(timeIntervalSince1970: 989)).state == .stale)
    }

    @Test("completed drain outside a scheduled window is intentional waiting")
    func scheduledDrainContract() {
        let schedule = ProviderAvailabilityState(phase: .waitingForSchedule)
        let drained = present(state(trust: .some(nil), warm: [], advertised: nil,
                                    lifecycle: ProviderLifecycleState(outcome: .drained), availability: schedule))
        #expect(drained.state == .scheduledWaiting)
        #expect(drained.tone == .neutral)
        #expect(drained.evidence.first { $0.id == .work }?.value == "Scheduled idle")
        #expect(drained.evidence.first { $0.id == .work }?.detail.contains("intentionally waiting outside") == true)
        for lifecycle in [nil, ProviderLifecycleState(outcome: .drained)] {
            let active = present(state(active: true, trust: .some(nil), lifecycle: lifecycle, availability: schedule))
            #expect(active.evidence.first { $0.id == .work }?.value == "Inference active")
        }
        for outcome in [ProviderLifecycleOutcome.stopped, .forced, .timedOut, .draining] {
            let value = present(state(trust: .some(nil), lifecycle: ProviderLifecycleState(outcome: outcome), availability: schedule))
            #expect(value.state != .scheduledWaiting)
            #expect(value.evidence.first { $0.id == .work }?.value != "Scheduled idle")
        }
    }

    @Test("long-running inference and accepted drain work need no monetary evidence")
    func observedWorkIsNotMoney() {
        #expect(present(state(active: true, startedAt: 1)).state == .serving)
        let draining = present(state(active: true, startedAt: 1, lifecycle: ProviderLifecycleState(outcome: .draining, remainingRequests: 5, coordinatorAcknowledged: false)))
        #expect(draining.state == .transitioning)
        #expect(draining.suggestedAction == nil)
        #expect(draining.evidence.first { $0.id == .work }?.value == "5 accepted remaining")
        let copy = text(draining).lowercased()
        for word in ["credit", "earning", "paid", "stall", "restart", "retry"] { #expect(!copy.contains(word)) }
    }

    @Test("advertised cold models are on demand and missing advertisement remains unknown")
    func modelReadiness() {
        #expect(present(state(warm: [])).state == .onDemand)
        #expect(present(state(warm: ["other"])).state == .onDemand)
        #expect(present(state(advertised: nil)).state == .modelsUnknown)
        #expect(present(state(advertised: [])).state == .modelsUnknown)
        #expect(present(state(loadFailures: [ModelLoadFailure(model: "model", code: .timedOut, occurredAt: 990)])).state == .ready)
    }

    @Test("preload and live model changes are transitions with no recovery action")
    func modelTransitions() {
        let preloading = present(state(preload: ["model"]))
        #expect(preloading.state == .transitioning)
        #expect(preloading.suggestedAction == nil)
        for outcome in [ProviderModelSwitchOutcome.validating, .draining, .switching] {
            let switching = present(state(modelSwitch: ProviderModelSwitchState(outcome: outcome, models: ["model"])))
            #expect(switching.state == .transitioning)
            #expect(switching.suggestedAction == nil)
        }
        #expect(present(state(modelSwitch: ProviderModelSwitchState(outcome: .timedOut, models: []))).state == .interrupted)
        #expect(present(state(modelSwitch: ProviderModelSwitchState(outcome: .busy, models: []))).state == .busy)
    }

    @Test("unrecognized provider phases cannot fall through to readiness")
    func unrecognizedPhases() {
        let values = [
            present(state(active: true, lifecycle: ProviderLifecycleState(outcome: .unknown))),
            present(state(active: true, modelSwitch: ProviderModelSwitchState(outcome: .unknown, models: []))),
            present(state(active: true, availability: ProviderAvailabilityState(phase: .unknown))),
        ]
        for value in values {
            #expect(value.state == .unconfirmed)
            #expect(value.tone == .caution)
            #expect(value.evidence.first { $0.id == .authorization }?.value == "Verified")
            #expect(value.evidence.first { $0.id == .models }?.value == "Warm advertised model")
        }
    }

    @Test("validation and pending preload preserve evidence that existing work may continue")
    func preparationDoesNotImplyServingPaused() {
        let validation = present(state(active: true, modelSwitch: ProviderModelSwitchState(outcome: .validating, models: ["other"])))
        #expect(validation.title == "Validating model selection")
        #expect(!validation.detail.contains("New work is paused"))
        #expect(validation.evidence.first { $0.id == .work }?.value == "Inference active")
        let preload = present(state(active: true, preload: ["other"]))
        #expect(preload.detail.contains("other warm models may continue serving"))
        #expect(!preload.detail.contains("before normal serving begins"))
        #expect(preload.evidence.first { $0.id == .work }?.value == "Inference active")
        let draining = present(state(active: true, modelSwitch: ProviderModelSwitchState(outcome: .draining, models: ["other"], remainingRequests: 3)))
        #expect(draining.evidence.first { $0.id == .work }?.value == "3 accepted remaining")
        #expect(draining.evidence.first { $0.id == .work }?.detail.contains("paused") == true)
    }

    @Test("stopped forced timed out and busy lifecycle remain conservative")
    func lifecycleOutcomes() {
        for outcome in [ProviderLifecycleOutcome.stopped, .drained] {
            let stopped = present(state(active: true, lifecycle: ProviderLifecycleState(outcome: outcome)))
            #expect(stopped.state == .stopped)
            #expect(stopped.evidence.first { $0.id == .work }?.value == "Stopped")
            #expect(stopped.evidence.first { $0.id == .models }?.value == "Warm advertised model")
            #expect(stopped.evidence.first { $0.id == .authorization }?.detail.contains("provider controls may still pause serving") == true)
        }
        for outcome in [ProviderLifecycleOutcome.forced, .timedOut] {
            #expect(present(state(active: true, lifecycle: ProviderLifecycleState(outcome: outcome))).state == .interrupted)
        }
        #expect(present(state(lifecycle: ProviderLifecycleState(outcome: .busy))).state == .busy)
    }

    @Test("presentation never includes arbitrary upstream prose identifiers or model lists")
    func boundedCopy() {
        let canary = "PRIVATE_CANARY_NEVER_RENDER"
        let value = present(state(trust: TrustState(level: canary, status: "online", reason: canary, receivedAt: 997, authorization: lease), warm: [canary], advertised: [canary], preload: [canary], modelSwitch: ProviderModelSwitchState(outcome: .switching, models: [canary]), loadFailures: [ModelLoadFailure(model: canary)]))
        #expect(!text(value).contains(canary))
        #expect(!text(present(state(), expectedCoordinator: "https://\(canary).example")).contains(canary))
        #expect(!text(present(state(), statusStale: true)).contains(canary))
    }

    private func text(_ value: ProviderReadinessPresentation) -> String {
        ([value.title, value.detail, value.symbolName] + value.evidence.flatMap { [$0.title, $0.value, $0.detail] }).joined(separator: " ")
    }

    private func trust(authorization: ProviderAuthorizationStatus? = nil, level: String = "unknown", status: String = "online", receivedAt: TimeInterval = 997) -> TrustState {
        TrustState(level: level, status: status, reason: "PRIVATE_CANARY_NEVER_RENDER", receivedAt: receivedAt, authorization: authorization)
    }

    private func state(active: Bool = false, trust suppliedTrust: TrustState?? = nil, startedAt: TimeInterval = 900, writtenAt: TimeInterval = 997, warm: [String] = ["model"], advertised: [String]? = ["model"], coordinator: String = "wss://coordinator.example/ws/provider", lifecycle: ProviderLifecycleState? = nil, preload: [String]? = nil, modelSwitch: ProviderModelSwitchState? = nil, availability: ProviderAvailabilityState? = nil, loadFailures: [ModelLoadFailure] = []) -> DaemonState {
        DaemonState(schema: 1, version: "fixture", currentModel: "model", warmModels: warm,
                    stats: ProviderStats(tokensGenerated: 999_999, requestsServed: 999_999, usageGaps: 0),
                    trust: suppliedTrust ?? trust(authorization: lease), capacity: nil, slots: [],
                    inferenceActive: active, startedAt: startedAt, writtenAt: writtenAt,
                    pid: identity.pid, processIdentity: identity, advertisedModels: advertised,
                    coordinatorURL: coordinator, modelLoadFailures: loadFailures, lifecycle: lifecycle,
                    startupPreloadPendingModels: preload, modelSwitch: modelSwitch, availability: availability)
    }

    private func present(_ daemon: DaemonState, now suppliedNow: Date? = nil, capturedAt: Date? = nil, daemonCapturedAt: Date? = nil, statusCapturedAt: Date? = nil, statusStale: Bool = false, statusUnavailable: Bool = false, expectedCoordinator: String? = "https://coordinator.example") -> ProviderReadinessPresentation {
        ProviderReadinessPresentation.make(snapshot: snapshot(daemon, capturedAt: capturedAt, daemonCapturedAt: daemonCapturedAt, statusCapturedAt: statusCapturedAt, statusStale: statusStale, statusUnavailable: statusUnavailable, expectedCoordinator: expectedCoordinator), now: suppliedNow ?? now, liveProcessIdentity: identity)
    }

    private func snapshot(_ daemon: DaemonState, capturedAt: Date? = nil, daemonCapturedAt: Date? = nil, statusCapturedAt: Date? = nil, stateStale: Bool = false, statusStale: Bool = false, statusUnavailable: Bool = false, expectedCoordinator: String? = "https://coordinator.example") -> TelemetrySnapshot {
        var status = StatusSnapshot()
        status.coordinator = expectedCoordinator
        let stateSource: SourceAvailability<DaemonState> = stateStale ? .stale(value: daemon, capturedAt: daemonCapturedAt ?? now, reason: "PRIVATE_CANARY_NEVER_RENDER") : .available(value: daemon, capturedAt: daemonCapturedAt ?? now)
        let statusSource: SourceAvailability<StatusSnapshot> = statusUnavailable ? .unavailable(reason: "PRIVATE_CANARY_NEVER_RENDER") : statusStale ? .stale(value: status, capturedAt: statusCapturedAt ?? now, reason: "PRIVATE_CANARY_NEVER_RENDER") : .available(value: status, capturedAt: statusCapturedAt ?? now)
        return TelemetrySnapshot(state: stateSource, loadedModels: .unavailable(reason: "fixture"), status: statusSource, eventFeed: .unavailable(reason: "fixture"), tokenRate: .unavailable(reason: "fixture"), diagnostics: [], capturedAt: capturedAt ?? now, menuStatus: .online)
    }
}
