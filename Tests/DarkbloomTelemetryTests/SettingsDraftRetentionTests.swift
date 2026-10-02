import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Settings draft retention", .serialized)
@MainActor
struct SettingsDraftRetentionTests {
    @Test("retained idle and fan edits independently block the production update guard until saved", arguments: [false, true])
    func retainedSettingsBlockAppUpdate(fan: Bool) async throws {
        let fixture = try SettingsUpdateGuardFixture()
        defer { fixture.close() }
        await fixture.extras.refresh()
        fixture.status.showSettings(page: .provider, activate: false)
        let dashboard = try #require(fixture.status.dashboardWindowController)
        let draft = dashboard.settingsDraft
        #expect(fixture.delegate.canRelaunchForAppUpdate())

        if fan { draft.selectFanPreset(.cooling) }
        else { draft.editIdle("90") }
        #expect(dashboard.hasUnsavedSettingsEdits)
        #expect(fixture.status.hasUnsavedSettingsEdits)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())

        if fan {
            let revision = draft.fanRevision
            try await fixture.extras.configureFan(policy: FanPreset.cooling.policy)
            draft.didSaveFan(revision: revision, source: fixture.extras.snapshot?.fanStatus)
        } else {
            let revision = draft.idleRevision
            try await fixture.extras.saveIdle(minutes: 90)
            draft.didSaveIdle(revision: revision, source: fixture.extras.snapshot?.idlePolicy)
        }
        #expect(!dashboard.hasUnsavedSettingsEdits)
        #expect(!fixture.status.hasUnsavedSettingsEdits)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        #expect(await fixture.client.mutationCount == 1)
        await fixture.monitor.stop()
    }

    @Test("route changes and closing then reopening retain settings and update protection")
    func retainedSettingsGuardSurvivesWindowRoutes() async throws {
        let fixture = try SettingsUpdateGuardFixture()
        defer { fixture.close() }
        await fixture.extras.refresh()
        fixture.status.showSettings(page: .provider, activate: false)
        let dashboard = try #require(fixture.status.dashboardWindowController)
        let window = try #require(dashboard.window)
        let draft = dashboard.settingsDraft
        draft.editIdle("-")
        draft.selectFanPreset(.cooling)
        fixture.status.showDashboard(section: .overview, activate: false)
        #expect(dashboard.navigation.selected == .overview)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        dashboard.close()
        #expect(!window.isVisible)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())

        fixture.status.showSettings(page: .provider, activate: false)
        let reopened = try #require(fixture.status.dashboardWindowController)
        #expect(reopened === dashboard)
        #expect(reopened.settingsDraft === draft)
        #expect(reopened.window === window)
        let content = try #require(window.contentView)
        try await settle(content)
        #expect(try idleField(in: content).stringValue == "-")
        #expect(draft.fanPreset == .cooling)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())

        // Saving one page must not clear the other retained page's protection.
        draft.didSaveIdle(revision: draft.idleRevision, source: idleSource(30))
        #expect(!draft.idleDirty)
        #expect(draft.fanDirty)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        #expect(await fixture.client.mutationCount == 0)
        await fixture.monitor.stop()
    }

    @Test("idle text survives complete removal and return, including partial invalid edits", arguments: ["3045", "", "-", "10x", "10081"])
    func idleRemovalAndReturn(text: String) async throws {
        let client = SettingsDraftFixtureClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        let draft = ProviderSettingsDraftState()
        let host = NSHostingController(rootView: idleView(store: store, draft: draft))
        let window = makeWindow(host)
        defer { window.close() }
        try await settle(host.view)
        #expect(try idleField(in: host.view).stringValue == "30")
        draft.editIdle(text)
        try await settle(host.view)
        #expect(try idleField(in: host.view).stringValue == text)

        host.rootView = AnyView(Text("Overview"))
        try await settle(host.view)
        await client.changeIdle(to: 60)
        await store.refresh()
        host.rootView = idleView(store: store, draft: draft)
        try await settle(host.view)
        #expect(try idleField(in: host.view).stringValue == text)
        #expect(draft.idleDirty)
        #expect(await client.mutationCount == 0)
        await store.stop()
    }

    @Test("fan page removal releases polling while retaining edits and preset selection")
    func fanRemovalAndReturn() async throws {
        let client = SettingsDraftFixtureClient()
        let store = ProviderExtrasStore(client: client)
        await store.refresh()
        let draft = ProviderSettingsDraftState()
        let control = ProviderControlStore(controller: SettingsDraftInertController())
        let host = NSHostingController(rootView: AnyView(MonitorSettingsView(
            extrasStore: store, controlStore: control, selection: .fans, draft: draft)))
        let window = makeWindow(host)
        defer { window.close() }
        try await settle(host.view)
        #expect(store.visibleFanSubscriberCount == 1)
        draft.selectFanPreset(.cooling)
        host.rootView = AnyView(MonitorSettingsView(
            extrasStore: store, controlStore: control, selection: .provider, draft: draft))
        try await settle(host.view)
        #expect(store.visibleFanSubscriberCount == 0)
        #expect(draft.fanDirty)
        #expect(draft.fanPreset == .cooling)
        await client.changeFan(to: .quiet)
        await store.refresh()
        host.rootView = AnyView(Text("Overview"))
        try await settle(host.view)
        host.rootView = AnyView(MonitorSettingsView(
            extrasStore: store, controlStore: control, selection: .fans, draft: draft))
        try await settle(host.view)
        #expect(store.visibleFanSubscriberCount == 1)
        #expect(draft.fanPolicy == FanPreset.cooling.policy)
        #expect(draft.fanPreset == .cooling)
        #expect(draft.fanDirty)
        #expect(await client.mutationCount == 0)
        host.rootView = AnyView(Text("Overview"))
        try await settle(host.view)
        #expect(store.visibleFanSubscriberCount == 0)
        await store.stop()
    }

    @Test("clean drafts track source updates and successful saves use readback")
    func cleanSourceAndSaveReadback() {
        let draft = ProviderSettingsDraftState()
        draft.syncIdle(from: idleSource(30))
        draft.syncIdle(from: idleSource(60))
        #expect(draft.idleMinutesText == "60")
        draft.editIdle(" 90 ")
        draft.syncIdle(from: idleSource(120))
        #expect(draft.idleMinutesText == " 90 ")
        draft.didSaveIdle(revision: draft.idleRevision, source: idleSource(90))
        #expect(draft.idleMinutesText == "90")
        #expect(!draft.idleDirty)
        draft.syncFan(from: fanSource(.quiet))
        draft.syncFan(from: fanSource(.balanced))
        #expect(draft.fanPreset == .balanced)
        draft.editFanSpeed(83)
        draft.editFanTemperature(43)
        draft.syncFan(from: fanSource(.quiet))
        #expect(draft.fanSpeedPercent == 83)
        #expect(draft.fanTriggerTemperature == 43)
        #expect(draft.fanPreset == nil)
        draft.didSaveFan(revision: draft.fanRevision, source: fanSource(.cooling))
        #expect(draft.fanPolicy == FanPreset.cooling.policy)
        #expect(!draft.fanDirty)
    }

    @Test("a late save result cannot clear edits made after its submission")
    func lateSavePreservesNewerEdits() {
        let draft = ProviderSettingsDraftState()
        draft.editIdle("90")
        let idleRevision = draft.idleRevision
        draft.editIdle("")
        draft.didSaveIdle(revision: idleRevision, source: idleSource(90))
        #expect(draft.idleMinutesText.isEmpty)
        #expect(draft.idleDirty)
        draft.selectFanPreset(.balanced)
        let fanRevision = draft.fanRevision
        draft.editFanSpeed(83)
        draft.didSaveFan(revision: fanRevision, source: fanSource(.balanced))
        #expect(draft.fanSpeedPercent == 83)
        #expect(draft.fanDirty)
        #expect(draft.fanPreset == nil)
    }

    @Test("standalone editors and retained dashboard drafts are independent")
    func independentEditors() async throws {
        let store = ProviderExtrasStore(client: SettingsDraftFixtureClient())
        await store.refresh()
        let retained = ProviderSettingsDraftState()
        retained.editIdle("3045")
        retained.selectFanPreset(.cooling)
        let first = NSHostingController(rootView: idleView(store: store))
        let second = NSHostingController(rootView: idleView(store: store))
        let firstWindow = makeWindow(first)
        let secondWindow = makeWindow(second)
        defer { firstWindow.close(); secondWindow.close() }
        try await settle(first.view)
        try await settle(second.view)
        let field = try idleField(in: first.view)
        field.stringValue = "90"
        field.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: field))
        try await settle(first.view)
        #expect(try idleField(in: first.view).stringValue == "90")
        #expect(try idleField(in: second.view).stringValue == "30")
        #expect(retained.idleMinutesText == "3045")
        #expect(retained.fanPreset == .cooling)
        await store.stop()
    }

    private func idleView(store: ProviderExtrasStore, draft: ProviderSettingsDraftState? = nil) -> AnyView {
        AnyView(Form {
            ProviderAdvancedSettingsView(store: store, performMutation: { _, _ in false },
                showsAutoUpdate: false, showsFanControls: false, draft: draft)
        }.formStyle(.grouped))
    }

    private func makeWindow(_ host: NSHostingController<AnyView>) -> NSWindow {
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 800, height: 680))
        window.orderBack(nil)
        return window
    }

    private func settle(_ view: NSView) async throws {
        try await Task.sleep(for: .milliseconds(150))
        view.layoutSubtreeIfNeeded()
    }

    private func idleField(in view: NSView) throws -> NSTextField {
        func find(_ current: NSView) -> NSTextField? {
            if let field = current as? NSTextField, field.isEditable { return field }
            for child in current.subviews {
                if let field = find(child) { return field }
            }
            return nil
        }
        return try #require(find(view), "Provider idle minutes must mount its text field")
    }

    private func idleSource(_ minutes: Int) -> SourceAvailability<ProviderIdlePolicy> {
        .available(value: ProviderIdlePolicy(idleTimeoutMinutes: minutes, policy: "idle_timeout", summary: "Fixture", pinned: false), capturedAt: Date())
    }

    private func fanSource(_ preset: FanPreset) -> SourceAvailability<ProviderFanStatus> {
        .available(value: settingsDraftFanStatus(policy: preset.policy), capturedAt: Date())
    }
}

private func settingsDraftFanStatus(policy: ProviderFanPolicy) -> ProviderFanStatus {
    ProviderFanStatus(capability: ProviderFanStatus.controlCapability, installed: true, loaded: true,
        helper: ProviderFanHelperStatus(enabled: true, providerActive: false, mode: "idle", chip: "Fixture",
            gpuTemperatureCelsius: 40, triggerTemperatureCelsius: policy.triggerTemperatureCelsius,
            releaseTemperatureCelsius: 35, speedPercent: policy.speedPercent, fans: [], updatedAt: Date()),
        diagnostic: ProviderFanDiagnostic(chip: "Fixture", supported: true, gpuTemperatures: [], fans: []),
        helperErrorPresent: false, diagnosticErrorPresent: false)
}

private actor SettingsDraftFixtureClient: ProviderExtrasProviding {
    private var minutes = 30
    private var fanPolicy = ProviderFanPolicy.default
    private(set) var mutationCount = 0
    func changeIdle(to minutes: Int) { self.minutes = minutes }
    func changeFan(to preset: FanPreset) { fanPolicy = preset.policy }
    func refresh() async -> ProviderExtrasSnapshot {
        let now = Date()
        return ProviderExtrasSnapshot(capturedAt: now,
            idlePolicy: .available(value: ProviderIdlePolicy(idleTimeoutMinutes: minutes, policy: "idle_timeout", summary: "Fixture", pinned: false), capturedAt: now),
            betaFeatures: .available(value: [], capturedAt: now),
            fanStatus: .available(value: settingsDraftFanStatus(policy: fanPolicy), capturedAt: now))
    }
    func saveIdle(minutes: Int) async throws { mutationCount += 1; self.minutes = minutes }
    func configureFan(policy: ProviderFanPolicy) async throws { mutationCount += 1; fanPolicy = policy }
    func setBeta(id: String, enabled: Bool) async throws { mutationCount += 1 }
}

private struct SettingsDraftInertController: ProviderControlling {
    func refresh() async throws -> ProviderControlSnapshot { throw SettingsDraftUnexpectedMutation() }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult { throw SettingsDraftUnexpectedMutation() }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws { throw SettingsDraftUnexpectedMutation() }
    func delete(_ localModelID: String) async throws { throw SettingsDraftUnexpectedMutation() }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws { throw SettingsDraftUnexpectedMutation() }
}
private struct SettingsDraftUnexpectedMutation: Error {}

@MainActor
private struct SettingsUpdateGuardFixture {
    let namespace = "SettingsUpdateGuard-\(UUID().uuidString)"
    let defaults: UserDefaults
    let client: SettingsDraftFixtureClient
    let extras: ProviderExtrasStore
    let monitor: MonitorStore
    let status: StatusItemController
    let delegate: DarkbloomMonitorAppDelegate

    init() throws {
        defaults = try #require(UserDefaults(suiteName: namespace))
        client = SettingsDraftFixtureClient()
        extras = ProviderExtrasStore(client: client)
        monitor = MonitorStore(
            service: TelemetryService(source: SettingsDraftUnusedTelemetrySource()),
            initial: .unavailable(now: Date()), providerExtras: extras,
            energyPreferences: defaults, menuAttentionPreferences: defaults
        )
        let control = ProviderControlStore(controller: SettingsDraftInertController())
        status = StatusItemController(store: monitor, controlStore: control, defaults: defaults)
        delegate = DarkbloomMonitorAppDelegate(instanceGuard: SingleInstanceGuard(), statusItemController: status)
        delegate.attachStores(monitor: monitor, control: control)
    }

    func close() {
        status.invalidate()
        defaults.removePersistentDomain(forName: namespace)
    }
}

private struct SettingsDraftUnusedTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw SettingsDraftUnexpectedMutation() }
    func readLoadedModels() async throws -> LoadedModelsState { throw SettingsDraftUnexpectedMutation() }
    func readStatus() async throws -> StatusSnapshot { throw SettingsDraftUnexpectedMutation() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw SettingsDraftUnexpectedMutation() }
}
