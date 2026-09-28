import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Operational alert transitions")
struct OperationalAlertsTests {
    @Test("a sustained fresh outage raises once, recovers, then rearms")
    func sustainedOutageRecoveryAndRearm() {
        var engine = OperationalAlertEngine(policy: .init(
            sustainedOutageDuration: 20,
            coldStartGraceDuration: 5,
            maximumEvidenceGap: 15
        ))

        #expect(engine.transitions(for: snapshot(at: 0, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 10, trust: "offline")).isEmpty)
        let raised = engine.transitions(for: snapshot(at: 20, trust: "offline"))
        #expect(raised.map(\.code) == [.providerOffline])
        #expect(raised.map(\.kind) == [.raised])
        #expect(engine.transitions(for: snapshot(at: 30, trust: "offline")).isEmpty)

        let recovered = engine.transitions(for: snapshot(at: 31, trust: "online"))
        #expect(recovered.map(\.kind) == [.recovered])
        #expect(recovered.map(\.code) == [.providerOffline])

        #expect(engine.transitions(for: snapshot(at: 40, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 50, trust: "offline")).isEmpty)
        let rearmed = engine.transitions(for: snapshot(at: 60, trust: "offline"))
        #expect(rearmed.map(\.kind) == [.raised])
    }

    @Test("scheduled idle and the cold-start grace do not create outage alerts")
    func scheduledIdleAndColdStartSuppression() {
        var engine = OperationalAlertEngine(policy: .init(
            sustainedOutageDuration: 10,
            coldStartGraceDuration: 30,
            maximumEvidenceGap: 120
        ))

        #expect(engine.transitions(for: snapshot(at: 0, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 10, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 29, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 30, trust: "offline")).map(\.kind) == [.raised])

        let idle = snapshot(at: 40, trust: "offline", scheduledIdle: true)
        #expect(engine.transitions(for: idle).map(\.kind) == [.suppressed])
        #expect(engine.transitions(for: snapshot(at: 41, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 51, trust: "offline")).map(\.kind) == [.raised])
    }

    @Test("stale and unavailable snapshots cannot raise or recover alerts")
    func staleTelemetryIsNotEvidence() {
        var engine = OperationalAlertEngine(policy: .init(
            sustainedOutageDuration: 1,
            coldStartGraceDuration: 0,
            maximumEvidenceGap: 15
        ))

        #expect(engine.transitions(for: snapshot(at: 0, trust: "offline")).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 2, trust: "offline")).map(\.kind) == [.raised])
        #expect(engine.transitions(for: snapshot(at: 3, trust: "online", availability: .stale)).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 4, trust: "offline", availability: .unavailable)).isEmpty)
        #expect(engine.transitions(for: snapshot(at: 5, trust: "online")).map(\.kind) == [.recovered])
    }

    @Test("fixed lifecycle and model failure codes deduplicate and recover")
    func fixedFailureCodes() {
        var engine = OperationalAlertEngine(policy: .init(
            sustainedOutageDuration: 1,
            coldStartGraceDuration: 0
        ))
        let first = snapshot(at: 0, trust: "online", lifecycle: .timedOut,
                             failures: [.insufficientMemory])
        let raised = engine.transitions(for: first)
        #expect(Set(raised.map(\.code)) == [.lifecycleTimedOut, .modelInsufficientMemory])
        #expect(raised.allSatisfy { $0.kind == .raised })

        let duplicate = snapshot(at: 1, trust: "online", lifecycle: .timedOut,
                                 failures: [.insufficientMemory, .insufficientMemory])
        #expect(engine.transitions(for: duplicate).isEmpty)

        let recovered = engine.transitions(for: snapshot(at: 2, trust: "online", lifecycle: .serving))
        #expect(Set(recovered.map(\.code)) == [.lifecycleTimedOut, .modelInsufficientMemory])
        #expect(recovered.allSatisfy { $0.kind == .recovered })
    }

    private func snapshot(
        at seconds: Int,
        trust: String,
        scheduledIdle: Bool = false,
        availability: FixtureAvailability = .available,
        lifecycle: ProviderLifecycleOutcome? = nil,
        failures: [ModelLoadFailureCode] = []
    ) -> TelemetrySnapshot {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        let state = daemon(at: date, trust: trust, scheduledIdle: scheduledIdle,
                           lifecycle: lifecycle, failures: failures)
        let source: SourceAvailability<DaemonState>
        switch availability {
        case .available:
            source = .available(value: state, capturedAt: date)
        case .stale:
            source = .stale(value: state, capturedAt: date, reason: "untrusted fixture prose")
        case .unavailable:
            source = .unavailable(reason: "untrusted fixture prose")
        }
        return TelemetrySnapshot(
            state: source,
            loadedModels: .unavailable(reason: "unused"),
            status: .unavailable(reason: "unused"),
            eventFeed: .unavailable(reason: "unused"),
            tokenRate: .unavailable(reason: "unused"),
            diagnostics: [],
            capturedAt: date,
            menuStatus: trust == "offline" ? .offline : .online
        )
    }

    private func daemon(
        at date: Date,
        trust: String,
        scheduledIdle: Bool,
        lifecycle: ProviderLifecycleOutcome?,
        failures: [ModelLoadFailureCode]
    ) -> DaemonState {
        DaemonState(
            schema: 1,
            version: "fixture",
            currentModel: "allowed/model",
            warmModels: [],
            stats: ProviderStats(tokensGenerated: 0, requestsServed: 0, usageGaps: 0),
            trust: TrustState(level: "fixture", status: trust, reason: "unknown", receivedAt: date.timeIntervalSince1970),
            capacity: nil,
            slots: [],
            inferenceActive: false,
            startedAt: 0,
            writtenAt: date.timeIntervalSince1970,
            pid: 12345,
            processIdentity: ProcessIdentity(pid: 12345, startTimeMicros: 1),
            modelLoadFailures: failures.map {
                ModelLoadFailure(model: "private-model-id", code: $0, occurredAt: date.timeIntervalSince1970)
            },
            lifecycle: lifecycle.map { ProviderLifecycleState(outcome: $0) },
            availability: scheduledIdle
                ? ProviderAvailabilityState(phase: .waitingForSchedule)
                : nil
        )
    }

    private enum FixtureAvailability { case available, stale, unavailable }
}
