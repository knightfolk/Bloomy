import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Host GPU protection policy")
struct HostGPUProtectionPolicyTests {
    private let start = Date(timeIntervalSince1970: 2_000_000_000)

    private func provider(at date: Date, idle: Bool = true, identity: String? = "provider-1",
                          transitioning: Bool = false) -> HostGPUProtectionProviderContext {
        .init(running: true, idle: idle, capturedAt: date, identity: identity, isTransitioning: transitioning)
    }

    private func sample(_ percent: Double = 90, at date: Date) -> HostGPUProtectionSample {
        .init(percent: percent, capturedAt: date)
    }

    @Test func defaultOffAndBoundedSettings() {
        var policy = HostGPUProtectionPolicy()
        #expect(policy.observe(sample: sample(at: start), provider: provider(at: start), at: start) == .off)
        #expect(HostGPUProtectionSettings().validationError == nil)
        for settings in [HostGPUProtectionSettings(ceilingPercent: .nan),
                         .init(resumePercent: 80), .init(breachSeconds: 0),
                         .init(recoverySeconds: .infinity), .init(minimumPausedSeconds: -1),
                         .init(throughputFloorPercent: 9), .init(slowdownSeconds: 601)] {
            #expect(settings.validationError != nil)
        }
    }

    @Test func legacySettingsRetainValuesAndDefaultNewSlowdownFields() throws {
        let legacy = Data(#"{"mode":"warn","ceilingPercent":85,"resumePercent":55,"breachSeconds":18,"recoverySeconds":90,"minimumPausedSeconds":150}"#.utf8)
        let decoded = try JSONDecoder().decode(HostGPUProtectionSettings.self, from: legacy)
        #expect(decoded.mode == .warn)
        #expect(decoded.ceilingPercent == 85)
        #expect(decoded.minimumPausedSeconds == 150)
        #expect(decoded.throughputFloorPercent == 60)
        #expect(decoded.slowdownSeconds == 30)
        #expect(try JSONDecoder().decode(HostGPUProtectionSettings.self, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func sustainedBreachAndHysteresis() {
        var policy = HostGPUProtectionPolicy(settings: .init(mode: .automaticPause))
        for offset in stride(from: 0, through: 12, by: 3) {
            let date = start.addingTimeInterval(Double(offset))
            #expect(policy.observe(sample: sample(at: date), provider: provider(at: date), at: date) == .watching)
        }
        let date = start.addingTimeInterval(15)
        #expect(policy.observe(sample: sample(at: date), provider: provider(at: date), at: date) == .breached)
        policy.reset()
        for offset in stride(from: 0, through: 117, by: 3) {
            let date = start.addingTimeInterval(Double(offset))
            // A stopped provider needs no fresh idle state to observe recovery.
            #expect(policy.observe(sample: sample(59, at: date), provider: nil, at: date, pausedSince: start) == .watching)
        }
        let recovered = start.addingTimeInterval(120)
        #expect(policy.observe(sample: sample(59, at: recovered), provider: nil, at: recovered, pausedSince: start) == .recovered)
        let boundary = recovered.addingTimeInterval(3)
        #expect(policy.observe(sample: sample(60, at: boundary), provider: nil, at: boundary, pausedSince: start) == .watching)
    }

    @Test("Inference, transitioning, stale context, and missing identity cannot authorize a pause")
    func ineligibleProviders() {
        for context in [provider(at: start, idle: false), provider(at: start, transitioning: true),
                        provider(at: start, identity: nil), provider(at: start.addingTimeInterval(-11)),
                        provider(at: start.addingTimeInterval(1))] {
            var policy = HostGPUProtectionPolicy(settings: .init(mode: .automaticPause))
            let decision = policy.observe(sample: sample(at: start), provider: context, at: start)
            if case .unavailable = decision {} else { Issue.record("Unsafe provider accepted: \(decision)") }
        }
    }

    @Test("Missing, stale, future, and discontinuous GPU samples reset the dwell")
    func invalidSamplesBreakContinuity() {
        for badSample in [nil, sample(at: start.addingTimeInterval(-11)),
                          sample(at: start.addingTimeInterval(4)), sample(.nan, at: start.addingTimeInterval(3))] {
            var policy = HostGPUProtectionPolicy(settings: .init(mode: .warn, breachSeconds: 3))
            #expect(policy.observe(sample: sample(at: start), provider: provider(at: start), at: start) == .watching)
            let date = start.addingTimeInterval(3)
            if case .unavailable = policy.observe(sample: badSample, provider: provider(at: date), at: date) {} else {
                Issue.record("Invalid sample did not reset")
            }
            let next = date.addingTimeInterval(3)
            #expect(policy.observe(sample: sample(at: next), provider: provider(at: next), at: next) == .watching)
        }
        var policy = HostGPUProtectionPolicy(settings: .init(mode: .warn, breachSeconds: 3))
        _ = policy.observe(sample: sample(at: start), provider: provider(at: start), at: start)
        let gap = start.addingTimeInterval(11)
        #expect(policy.observe(sample: sample(at: gap), provider: provider(at: gap), at: gap) == .watching)
    }

    @Test func duplicateSamplesNeverAdvanceButPreserveIdleStreak() {
        var policy = HostGPUProtectionPolicy(settings: .init(mode: .warn, breachSeconds: 6))
        for offset in [0, 3] {
            let date = start.addingTimeInterval(Double(offset))
            #expect(policy.observe(sample: sample(at: date), provider: provider(at: date), at: date) == .watching)
            let duplicateAt = date.addingTimeInterval(1)
            if case .unavailable = policy.observe(sample: sample(at: date), provider: provider(at: duplicateAt), at: duplicateAt) {} else {
                Issue.record("Duplicate advanced decision")
            }
        }
        let date = start.addingTimeInterval(6)
        #expect(policy.observe(sample: sample(at: date), provider: provider(at: date), at: date) == .breached)
    }

    @Test func duplicateSamplesWithActiveWorkResetBreach() {
        var policy = HostGPUProtectionPolicy(settings: .init(mode: .warn, breachSeconds: 6))
        _ = policy.observe(sample: sample(at: start), provider: provider(at: start), at: start)
        let active = start.addingTimeInterval(1)
        _ = policy.observe(sample: sample(at: start), provider: provider(at: active, idle: false), at: active)
        let date = start.addingTimeInterval(6)
        #expect(policy.observe(sample: sample(at: date), provider: provider(at: date), at: date) == .watching)
    }

    @Test func providerIdentityChangesAndActivityResetBreach() {
        var policy = HostGPUProtectionPolicy(settings: .init(mode: .warn, breachSeconds: 6))
        _ = policy.observe(sample: sample(at: start), provider: provider(at: start), at: start)
        let changed = start.addingTimeInterval(3)
        #expect(policy.observe(sample: sample(at: changed), provider: provider(at: changed, identity: "provider-2"), at: changed) == .watching)
        let next = start.addingTimeInterval(6)
        #expect(policy.observe(sample: sample(at: next), provider: provider(at: next, identity: "provider-2"), at: next) == .watching)
        let active = start.addingTimeInterval(9)
        _ = policy.observe(sample: sample(at: active), provider: provider(at: active, idle: false), at: active)
        let idle = start.addingTimeInterval(12)
        #expect(policy.observe(sample: sample(at: idle), provider: provider(at: idle), at: idle) == .watching)
    }

    @Test func recoveryRequiresSustainedLowerReadings() {
        var policy = HostGPUProtectionPolicy(settings: .init(mode: .automaticPause, recoverySeconds: 6, minimumPausedSeconds: 0))
        for (offset, percent) in [(0, 59.0), (3, 70), (6, 59), (9, 59)] {
            let date = start.addingTimeInterval(Double(offset))
            #expect(policy.observe(sample: sample(percent, at: date), provider: nil, at: date, pausedSince: start) == .watching)
        }
        let date = start.addingTimeInterval(12)
        #expect(policy.observe(sample: sample(59, at: date), provider: nil, at: date, pausedSince: start) == .recovered)
    }
}
