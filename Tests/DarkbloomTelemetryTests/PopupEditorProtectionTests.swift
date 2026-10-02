import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Popup editor protection", .serialized)
@MainActor
struct PopupEditorProtectionTests {
    @Test("initial Auto suggestion is clean, deliberate changes and verified readback are revision-aware")
    func automaticPlanRevisionProtection() {
        var draft = PopupAutoPlanDraft()
        draft.initialize(modelID: "fixture-a")
        #expect(!draft.hasChanges)
        draft.edit(modelID: "fixture-b")
        #expect(draft.hasChanges)
        let submittedRevision = draft.revision
        draft.edit(modelID: "fixture-c")
        let acceptedOlderSave = draft.didSave(modelID: "fixture-b", revision: submittedRevision)
        #expect(!acceptedOlderSave)
        #expect(draft.preferredModelID == "fixture-c")
        #expect(draft.hasChanges)
        let acceptedCurrentSave = draft.didSave(modelID: "fixture-c", revision: draft.revision)
        #expect(acceptedCurrentSave)
        #expect(!draft.hasChanges)
        draft.edit(modelID: "fixture-a")
        #expect(draft.hasChanges)
        draft.edit(modelID: "fixture-c")
        #expect(!draft.hasChanges)
    }

    @Test("delayed Auto refresh does not replace a selection made while it was loading")
    func automaticPlanInitializationPreservesEdits() {
        var draft = PopupAutoPlanDraft()
        draft.edit(modelID: "fixture-chosen")
        draft.initialize(modelID: "fixture-default")
        #expect(draft.preferredModelID == "fixture-chosen")
        #expect(draft.hasChanges)
        let acceptedDifferentSelection = draft.didSave(modelID: "fixture-other", revision: draft.revision)
        #expect(!acceptedDifferentSelection)
        #expect(draft.hasChanges)
    }

    @Test("clearing an initialized Auto choice is still an unfinished edit")
    func emptyAutomaticPlanChoiceRemainsProtected() {
        var draft = PopupAutoPlanDraft()
        #expect(!draft.hasChanges)
        draft.initialize(modelID: "fixture-a")
        draft.edit(modelID: "")
        #expect(draft.hasChanges)
        draft.edit(modelID: "fixture-a")
        #expect(!draft.hasChanges)
    }

    @Test("Discard restores only its own page from latest observed values, including stale evidence")
    func independentPageDiscard() {
        let draft = ProviderSettingsDraftState()
        draft.editIdle("invalid")
        draft.selectFanPreset(.cooling)
        let submittedIdle = draft.idleRevision
        let submittedFan = draft.fanRevision
        draft.discardIdle(from: .stale(value: idlePolicy(60), capturedAt: .distantPast, reason: "Fixture"))
        #expect(draft.idleMinutesText == "60")
        #expect(!draft.idleDirty)
        #expect(draft.fanDirty)
        #expect(draft.fanPreset == .cooling)
        #expect(draft.idleRevision != submittedIdle)
        #expect(draft.fanRevision == submittedFan)

        draft.editIdle("90")
        draft.discardFan(from: fanSource(.quiet))
        #expect(draft.idleDirty)
        #expect(draft.idleMinutesText == "90")
        #expect(!draft.fanDirty)
        #expect(draft.fanPolicy == FanPreset.quiet.policy)
        #expect(draft.fanPreset == .quiet)
        #expect(draft.fanRevision != submittedFan)
    }

    @Test("save results submitted before Discard cannot consume edits made afterward")
    func discardedSaveCannotClearNewEdits() {
        let draft = ProviderSettingsDraftState()
        draft.editIdle("90")
        draft.selectFanPreset(.cooling)
        let idleRevision = draft.idleRevision
        let fanRevision = draft.fanRevision
        draft.discardIdle(from: .available(value: idlePolicy(30), capturedAt: Date()))
        draft.discardFan(from: fanSource(.quiet))
        draft.editIdle("-")
        draft.editFanSpeed(83)
        draft.didSaveIdle(revision: idleRevision, source: .available(value: idlePolicy(90), capturedAt: Date()))
        draft.didSaveFan(revision: fanRevision, source: fanSource(.cooling))
        #expect(draft.idleMinutesText == "-")
        #expect(draft.idleDirty)
        #expect(draft.fanSpeedPercent == 83)
        #expect(draft.fanDirty)
        #expect(draft.fanPreset == nil)
    }

    @Test("Discard without source data clears only the affected buffer and independent editors stay separate")
    func unavailableDiscardIsLocal() {
        let first = ProviderSettingsDraftState()
        let second = ProviderSettingsDraftState()
        first.editIdle("")
        first.selectFanPreset(.cooling)
        second.editIdle("120")
        second.selectFanPreset(.balanced)
        first.discardIdle(from: nil)
        first.discardFan(from: nil)
        #expect(!first.hasChanges)
        #expect(first.idleMinutesText.isEmpty)
        #expect(first.fanPolicy == .default)
        #expect(second.idleMinutesText == "120")
        #expect(second.fanPreset == .balanced)
        #expect(second.hasChanges)
    }

    @Test("Nudge setup registers even invalid unfinished input immediately; removing one editor preserves the other")
    func mountedNudgeEditorsOwnTheirProtection() async throws {
        let namespace = "PopupEditorProtection-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: namespace))
        defer { defaults.removePersistentDomain(forName: namespace) }
        let store = InactivityNudgeStore(keyStore: PopupUnusedNudgeKeyStore(), defaults: defaults,
            evidence: { _ in .unavailable }, canAct: { false }, send: { _, _ in nil })
        await store.refreshKeyStatus()
        let protection = AppUpdateEditorProtection()
        let first = NSHostingController(rootView: AnyView(NudgeSetupGuide(store: store, updateProtection: protection)))
        let second = NSHostingController(rootView: AnyView(NudgeSetupGuide(store: store, updateProtection: protection)))
        let firstWindow = makeWindow(first)
        let secondWindow = makeWindow(second)
        defer { firstWindow.close(); secondWindow.close() }
        try await settle(first.view)
        try await settle(second.view)
        #expect(!protection.hasBlockingEditors)
        try enterUnfinishedInput(in: first.view)
        #expect(protection.blockingOwners.count == 1)
        try enterUnfinishedInput(in: second.view)
        #expect(protection.blockingOwners.count == 2)
        first.rootView = AnyView(Text("Closed editor"))
        try await settle(first.view)
        #expect(protection.blockingOwners.count == 1)
        second.rootView = AnyView(Text("Closed editor"))
        try await settle(second.view)
        #expect(!protection.hasBlockingEditors)
        await store.stop()
    }

    private func enterUnfinishedInput(in view: NSView) throws {
        func find(_ view: NSView) -> NSSecureTextField? {
            if let field = view as? NSSecureTextField { return field }
            return view.subviews.lazy.compactMap(find).first
        }
        let field = try #require(find(view), "Setup must mount its local secure input")
        field.stringValue = " "
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
    }

    private func makeWindow(_ host: NSHostingController<AnyView>) -> NSWindow {
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 540, height: 640))
        window.orderBack(nil)
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }

    private func idlePolicy(_ minutes: Int) -> ProviderIdlePolicy {
        ProviderIdlePolicy(idleTimeoutMinutes: minutes, policy: "idle_timeout", summary: "Fixture", pinned: false)
    }

    private func fanSource(_ preset: FanPreset) -> SourceAvailability<ProviderFanStatus> {
        let policy = preset.policy
        let status = ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
            helper: ProviderFanHelperStatus(enabled: true, providerActive: false, mode: "idle", chip: "Fixture",
                gpuTemperatureCelsius: 40, triggerTemperatureCelsius: policy.triggerTemperatureCelsius,
                releaseTemperatureCelsius: 35, speedPercent: policy.speedPercent, fans: [], updatedAt: Date()),
            diagnostic: ProviderFanDiagnostic(chip: "Fixture", supported: true, gpuTemperatures: [], fans: []),
            helperErrorPresent: false, diagnosticErrorPresent: false)
        return .available(value: status, capturedAt: Date())
    }
}

private struct PopupUnusedNudgeKeyStore: ConsumerKeyManaging {
    var hasKey: Bool { false }
    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? { nil }
    func store(_ key: String) throws { throw ConsumerKeyStoreError.invalidKey }
    func remove() {}
}
