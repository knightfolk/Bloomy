import DarkbloomTelemetry
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Provider idle and beta display freshness")
@MainActor
struct ProviderAdvancedSettingsPresentationTests {
    private typealias Evidence = ProviderAdvancedSettingsView.EvidencePresentation
    private let capturedAt = Date(timeIntervalSince1970: 1_000)
    private var policy: ProviderIdlePolicy {
        .init(idleTimeoutMinutes: 5, policy: "fixture", summary: "fixture", pinned: false)
    }

    @Test("successful reads visibly expire at the shared settings boundary", arguments: [0.0, 45.0, 45.001, -1.0])
    func successfulReadExpiry(age: TimeInterval) {
        let source: SourceAvailability<ProviderIdlePolicy> = .available(value: policy, capturedAt: capturedAt)
        let evidence = Evidence(source: source, at: capturedAt.addingTimeInterval(age))
        let isFresh = age >= 0 && age <= 45
        #expect(evidence.isFresh == isFresh)
        #expect(evidence.label("After 5 min") == (isFresh ? "After 5 min" : "Last known: After 5 min"))
    }

    @Test("last-good, unavailable and missing reads cannot enable changes", arguments: ["stale", "unavailable", "missing"])
    func unavailableEvidence(mode: String) {
        let source: SourceAvailability<ProviderIdlePolicy>?
        switch mode {
        case "stale": source = .stale(value: policy, capturedAt: capturedAt, reason: "fixture")
        case "unavailable": source = .unavailable(reason: "fixture")
        default: source = nil
        }
        let evidence = Evidence(source: source, at: capturedAt)
        #expect(!evidence.isFresh)
        #expect(evidence.label("After 5 min") == "Last known: After 5 min")
        #expect(evidence.transitions.isEmpty)
    }

    @Test("empty beta results qualify the observed absence when evidence expires or is retained", arguments: ["fresh", "expired", "stale"])
    func emptyBetaFeatures(mode: String) {
        let source: SourceAvailability<[ProviderBetaFeature]> = mode == "stale"
            ? .stale(value: [], capturedAt: capturedAt, reason: "fixture")
            : .available(value: [], capturedAt: capturedAt)
        let now = mode == "expired" ? capturedAt.addingTimeInterval(45.001) : capturedAt
        let evidence = Evidence(source: source, at: now)
        if mode == "fresh" {
            #expect(evidence.isFresh)
            #expect(evidence.emptyBetaFeaturesMessage == "No configurable beta features are available in this build.")
        } else {
            #expect(!evidence.isFresh)
            #expect(evidence.emptyBetaFeaturesMessage == "No configurable beta features were reported at the last check.")
            #expect(!evidence.emptyBetaFeaturesMessage.contains("are available in this build"))
        }
    }

    @Test("an explicit display date expires controls even while the store date remains frozen", arguments: [45.0, 45.001])
    func displayDateControls(age: TimeInterval) {
        let source: SourceAvailability<ProviderIdlePolicy> = .available(value: policy, capturedAt: capturedAt)
        let storeEvidence = Evidence(source: source, at: capturedAt)
        let displayEvidence = Evidence(source: source, at: capturedAt.addingTimeInterval(age))
        #expect(storeEvidence.canSaveIdle(text: "45", isDirty: true, isSaving: false, mutationInFlight: false))
        #expect(storeEvidence.canChangeBeta(id: "mtp"))
        let freshAtDisplayDate = age <= 45
        #expect(displayEvidence.canSaveIdle(text: "45", isDirty: true, isSaving: false, mutationInFlight: false) == freshAtDisplayDate)
        #expect(displayEvidence.canChangeBeta(id: "mtp") == freshAtDisplayDate)
        #expect(!displayEvidence.canChangeBeta(id: "unsupported-fixture"))
        for text in ["invalid", "10081", "-1"] {
            #expect(!displayEvidence.canSaveIdle(text: text, isDirty: true, isSaving: false, mutationInFlight: false))
        }
        #expect(!displayEvidence.canSaveIdle(text: "45", isDirty: false, isSaving: false, mutationInFlight: false))
        #expect(!displayEvidence.canSaveIdle(text: "45", isDirty: true, isSaving: true, mutationInFlight: false))
        #expect(!displayEvidence.canSaveIdle(text: "45", isDirty: true, isSaving: false, mutationInFlight: true))
    }

    @Test("visible idle and beta displays schedule only their own finite evidence transitions")
    func separateSourceDeadlines() {
        let now = capturedAt.addingTimeInterval(10)
        let idle: SourceAvailability<ProviderIdlePolicy> = .available(value: policy, capturedAt: capturedAt)
        let beta: SourceAvailability<[ProviderBetaFeature]> = .available(value: [], capturedAt: capturedAt.addingTimeInterval(5))
        let idleEvidence = Evidence(source: idle, at: now)
        let betaEvidence = Evidence(source: beta, at: now)
        for mode in [TimelineScheduleMode.normal, .lowFrequency] {
            #expect(Array(idleEvidence.schedule(isVisible: true).entries(from: now, mode: mode))
                == [now, capturedAt.addingTimeInterval(45.001)])
            #expect(Array(betaEvidence.schedule(isVisible: true).entries(from: now, mode: mode))
                == [now, capturedAt.addingTimeInterval(50.001)])
        }
    }

    @Test("hidden displays stop deadlines and reopening evaluates current evidence")
    func hideAndRestore() {
        let source: SourceAvailability<ProviderIdlePolicy> = .available(value: policy, capturedAt: capturedAt)
        let hiddenAt = capturedAt.addingTimeInterval(10)
        let initial = Evidence(source: source, at: hiddenAt)
        #expect(Array(initial.schedule(isVisible: false).entries(from: hiddenAt, mode: .normal)) == [hiddenAt])
        let reopenedAt = capturedAt.addingTimeInterval(60)
        let reopened = Evidence(source: source, at: reopenedAt)
        #expect(!reopened.isFresh)
        #expect(Array(reopened.schedule(isVisible: true).entries(from: reopenedAt, mode: .normal)) == [reopenedAt])
        #expect(reopened.label("After 5 min") == "Last known: After 5 min")
    }

    @Test("future evidence schedules becoming usable before it later expires")
    func futureReadDeadlines() {
        let source: SourceAvailability<ProviderIdlePolicy> = .available(value: policy, capturedAt: capturedAt)
        let now = capturedAt.addingTimeInterval(-1)
        let evidence = Evidence(source: source, at: now)
        #expect(!evidence.isFresh)
        #expect(Array(evidence.schedule(isVisible: true).entries(from: now, mode: .normal))
            == [now, capturedAt, capturedAt.addingTimeInterval(45.001)])
    }

    @Test("expiry and a subsequent read preserve staged idle text and its revision")
    func stagedIdleSurvivesExpiry() {
        let source: SourceAvailability<ProviderIdlePolicy> = .available(value: policy, capturedAt: capturedAt)
        let draft = ProviderSettingsDraftState()
        draft.syncIdle(from: source)
        draft.editIdle("17")
        let revision = draft.idleRevision
        let expired = Evidence(source: source, at: capturedAt.addingTimeInterval(46))
        #expect(!expired.isFresh)
        draft.syncIdle(from: source)
        let refreshed: SourceAvailability<ProviderIdlePolicy> = .available(value:
            .init(idleTimeoutMinutes: 9, policy: "fixture", summary: "fixture", pinned: false),
            capturedAt: capturedAt.addingTimeInterval(46))
        draft.syncIdle(from: refreshed)
        #expect(draft.idleMinutesText == "17")
        #expect(draft.idleDirty)
        #expect(draft.idleRevision == revision)
        #expect(Evidence(source: refreshed, at: capturedAt.addingTimeInterval(46)).isFresh)
    }
}
