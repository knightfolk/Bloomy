import AppKit
import DarkbloomTelemetry
import Testing
@testable import DarkbloomMonitor

/// Exercises the same guard Sparkle calls, using only in-memory services.
/// These tests never start the provider, access credentials, or send traffic.
@Suite("App update work protection", .serialized)
@MainActor
struct AppUpdateWorkProtectionTests {
    @Test("independent dashboard and pop-out drafts survive closing and release the actual update guard separately")
    func independentRetainedChatDrafts() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        fixture.chat.startConversation(route: .local)
        let active = try #require(fixture.chat.conversation?.id)
        fixture.status.showDashboard(section: .chat, activate: false)
        fixture.status.showChatWindow(activate: false)
        let dashboard = try #require(fixture.status.dashboardWindowController)
        let popOut = try #require(fixture.status.chatWindowController)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        #expect(dashboard.chatDraft !== popOut.chatDraft)
        dashboard.chatDraft.updateText("Dashboard draft", in: active)
        popOut.chatDraft.updateText("Pop-out draft", in: active)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        dashboard.close()
        popOut.close()
        #expect(dashboard.chatDraft.text == "Dashboard draft")
        #expect(popOut.chatDraft.text == "Pop-out draft")
        #expect(!fixture.delegate.canRelaunchForAppUpdate())

        fixture.status.showDashboard(section: .chat, activate: false)
        fixture.status.showChatWindow(activate: false)
        #expect(fixture.status.dashboardWindowController === dashboard)
        #expect(fixture.status.chatWindowController === popOut)
        #expect(dashboard.chatDraft.text == "Dashboard draft")
        #expect(popOut.chatDraft.text == "Pop-out draft")
        dashboard.chatDraft.clear()
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        popOut.chatDraft.clear()
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        await fixture.monitor.stop()
    }

    @Test("obsolete and unowned retained Chat drafts do not indefinitely block the production guard")
    func obsoleteDraftsDoNotBlock() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        fixture.chat.startConversation(route: .local)
        let first = try #require(fixture.chat.conversation?.id)
        fixture.status.showDashboard(section: .chat, activate: false)
        fixture.status.showChatWindow(activate: false)
        let dashboard = try #require(fixture.status.dashboardWindowController)
        let popOut = try #require(fixture.status.chatWindowController)
        dashboard.chatDraft.updateText("Old dashboard draft", in: first)
        popOut.chatDraft.updateText("Old pop-out draft", in: first)
        dashboard.close()
        popOut.close()
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        fixture.chat.startConversation(route: .local)
        let second = try #require(fixture.chat.conversation?.id)
        #expect(second != first)
        // Check immediately, before either mounted view's onChange cleanup.
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        dashboard.chatDraft.reconcile(with: second)
        dashboard.chatDraft.updateText(" \n\t", in: second)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        popOut.chatDraft.clear()
        popOut.chatDraft.updateText("Unowned callback", in: nil)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        dashboard.chatDraft.updateText("Current draft", in: second)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        dashboard.chatDraft.clear()
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        await fixture.monitor.stop()
    }

    @Test("independent mounted-editor owners release the production guard only after the last editor clears")
    func independentEditorOwners() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        let first = UUID(), second = UUID()
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        fixture.status.updateProtection.setBlocked(true, owner: first)
        fixture.status.updateProtection.setBlocked(true, owner: second)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        fixture.status.updateProtection.endEditing(owner: first)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        // Late teardown from the first sheet cannot release the second owner.
        fixture.status.updateProtection.setBlocked(false, owner: first)
        fixture.status.updateProtection.endEditing(owner: first)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        fixture.status.updateProtection.endEditing(owner: second)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        await fixture.monitor.stop()
    }

    @Test("a retained popup settings draft blocks the production guard while the popup is closed")
    func popupDraftBlocks() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        let draft = fixture.status.popupSettingsDraft
        #expect(!fixture.status.popover.isShown)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        draft.editIdle("-")
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        let source = SourceAvailability<ProviderIdlePolicy>.available(
            value: ProviderIdlePolicy(idleTimeoutMinutes: 30, policy: "idle_timeout", summary: "Fixture", pinned: false),
            capturedAt: Date()
        )
        draft.didSaveIdle(revision: draft.idleRevision, source: source)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        await fixture.monitor.stop()
    }

    @Test("partial Hosting port and address text remain protected after close until both buffers are discarded")
    func hostingInputsBlockUntilDiscarded() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        fixture.status.showDashboard(section: .hosting, activate: false)
        let dashboard = try #require(fixture.status.dashboardWindowController)
        let draft = dashboard.hostingDraft
        let originalOptions = fixture.hosting.options
        let originalPreferences = fixture.defaults.persistentDomain(forName: fixture.namespace) as NSDictionary?
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        #expect(!fixture.hosting.canCopyBearerToken)
        draft.portText = "8x"
        draft.customAddressText = "192.168.1."
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        fixture.status.showDashboard(section: .overview, activate: false)
        dashboard.close()
        #expect(draft.portText == "8x")
        #expect(draft.customAddressText == "192.168.1.")
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        fixture.status.showDashboard(section: .hosting, activate: false)
        #expect(fixture.status.dashboardWindowController === dashboard)
        #expect(dashboard.hostingDraft === draft)
        draft.portText = String(fixture.hosting.options.port)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        draft.discardInputEdits(comparedTo: fixture.hosting.options)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        #expect(fixture.hosting.options == originalOptions)
        // Navigation can update preferences; discarding input cannot write a
        // hosting preference or dispatch the provider.
        let hostingKeys = [HostingSettingsStore.modeKey, HostingSettingsStore.portKey,
                           HostingSettingsStore.bindAddressKey, HostingSettingsStore.requiresAuthenticationKey]
        let currentPreferences = fixture.defaults.persistentDomain(forName: fixture.namespace) as NSDictionary?
        for key in hostingKeys {
            #expect((currentPreferences?[key] as? NSObject) == (originalPreferences?[key] as? NSObject))
        }
        await fixture.monitor.stop()
    }

    @Test("a pending Hosting exposure confirmation blocks updates without dispatching a restart")
    func pendingHostingConfirmationBlocks() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        fixture.hosting.refreshEnvironment()
        fixture.hosting.setMode(.unified)
        #expect(fixture.hosting.setBindAddress("0.0.0.0"))
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        await fixture.hosting.requestApply()
        #expect(fixture.hosting.pendingExposureConfirmation != nil)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        fixture.hosting.cancelPendingExposureConfirmation()
        #expect(fixture.hosting.pendingExposureConfirmation == nil)
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        await fixture.monitor.stop()
    }

    @Test("an in-flight synthetic Chat send blocks the production guard even without any open editor")
    func activeChatSendBlocks() async throws {
        let fixture = try AppUpdateWorkFixture()
        defer { fixture.close() }
        fixture.local.suspendComplete = true
        fixture.chat.startConversation(route: .local)
        try await waitUntil { fixture.chat.canSend }
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        #expect(fixture.chat.send("Inert guard test prompt"))
        #expect(fixture.chat.isSending)
        #expect(!fixture.delegate.canRelaunchForAppUpdate())
        try await waitUntil { fixture.local.pendingReleases == 1 }
        fixture.local.release(.success(ChatCompletionOutcome(content: "Synthetic reply", model: "gpt-oss-20b")))
        try await waitUntil { !fixture.chat.isSending }
        #expect(fixture.delegate.canRelaunchForAppUpdate())
        #expect(fixture.local.completeCalls.count == 1)
        await fixture.monitor.stop()
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(20)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        try #require(condition(), "The inert Chat fixture did not finish its transition")
    }
}

@MainActor
private struct AppUpdateWorkFixture {
    let namespace = "AppUpdateWork-\(UUID().uuidString)"
    let defaults: UserDefaults
    let monitor: MonitorStore
    let local: FakeChatRouteClient
    let chat: ChatStore
    let hosting: HostingSettingsStore
    let status: StatusItemController
    let delegate: DarkbloomMonitorAppDelegate

    init() throws {
        defaults = try #require(UserDefaults(suiteName: namespace))
        monitor = MonitorStore(service: TelemetryService(source: UpdateWorkInertTelemetrySource()),
            initial: .unavailable(now: Date()), energyPreferences: defaults,
            gpuUsage: SystemGPUUsageStore(read: { nil }), menuAttentionPreferences: defaults)
        let control = ProviderControlStore(controller: UpdateWorkInertController())
        local = FakeChatRouteClient()
        chat = ChatStore(localClient: local, networkClient: FakeChatRouteClient(),
            balanceClient: FakeBalanceClient(), pricingClient: FakePricingClient(),
            keyStore: FakeConsumerKeyStore(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        hosting = HostingSettingsStore(controlStore: control, endpointClient: UpdateWorkNoEndpoint(),
            tokenFile: UpdateWorkNoTokenFile(), cliVersionProvider: { "0.9.7" }, defaults: defaults,
            lanScanner: { [] }, copyToken: { _ in Issue.record("Update guard fixtures must not copy credentials"); return false })
        status = StatusItemController(store: monitor, controlStore: control, hostingStore: hosting,
            chatStore: chat, defaults: defaults)
        delegate = DarkbloomMonitorAppDelegate(instanceGuard: SingleInstanceGuard(), statusItemController: status)
        delegate.attachStores(monitor: monitor, control: control)
    }

    func close() {
        chat.cancelSend()
        local.suspendComplete = false
        local.release(.success(ChatCompletionOutcome(content: "Fixture cleanup", model: "gpt-oss-20b")))
        status.invalidate()
        defaults.removePersistentDomain(forName: namespace)
    }
}

private struct UpdateWorkUnexpectedMutation: Error {}

private struct UpdateWorkInertController: ProviderControlling {
    func refresh() async throws -> ProviderControlSnapshot { throw UpdateWorkUnexpectedMutation() }
    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        Issue.record("Update guard fixtures must not save provider settings")
        throw UpdateWorkUnexpectedMutation()
    }
    func download(_ modelID: String, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws {
        Issue.record("Update guard fixtures must not download models")
        throw UpdateWorkUnexpectedMutation()
    }
    func delete(_ localModelID: String) async throws {
        Issue.record("Update guard fixtures must not delete models")
        throw UpdateWorkUnexpectedMutation()
    }
    func activityRisk() async -> ProviderActivityRisk { .idle }
    func execute(_ action: ProviderLifecycleAction, enabledModels: [String]) async throws {
        Issue.record("Update guard fixtures must not dispatch provider operations")
        throw UpdateWorkUnexpectedMutation()
    }
}

private struct UpdateWorkInertTelemetrySource: TelemetrySource {
    func readDaemonState() async throws -> DaemonState { throw UpdateWorkUnexpectedMutation() }
    func readLoadedModels() async throws -> LoadedModelsState { throw UpdateWorkUnexpectedMutation() }
    func readStatus() async throws -> StatusSnapshot { throw UpdateWorkUnexpectedMutation() }
    func readLegacyEvents(limit: Int) async throws -> [LogEvent] { throw UpdateWorkUnexpectedMutation() }
}

private struct UpdateWorkNoEndpoint: LocalEndpointFetching {
    func fetch() async -> LocalEndpointAvailability {
        Issue.record("Update guard fixtures must not query a live endpoint")
        return .none(LocalEndpointClient.noLiveEndpointReason)
    }
}

private struct UpdateWorkNoTokenFile: LocalEndpointTokenManaging {
    func withBearerToken(_ action: (String) -> Void) -> Bool {
        // Hosting renders its Copy button's availability through
        // canCopyBearerToken. Model an absent token entirely in memory;
        // never open a file or supply any token text to the callback.
        return false
    }
    func saveBearerToken(_ token: String) throws {
        Issue.record("Update guard fixtures must not save credentials")
        throw UpdateWorkUnexpectedMutation()
    }
}
