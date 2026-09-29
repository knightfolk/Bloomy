import AppKit
import DarkbloomTelemetry
import SwiftUI

@main
struct DarkbloomMonitorApp: App {
    @NSApplicationDelegateAdaptor(DarkbloomMonitorAppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            AppSettingsObservedSceneRoot(delegate: appDelegate)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                ControlAppUpdateMenuItem()
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    appDelegate.showSettings()
                }
                .keyboardShortcut(",", modifiers: .command)
                Button("Open Dashboard") { appDelegate.showDashboard() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
                Button("Open Chat Window") { appDelegate.showChat() }
                    .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class DarkbloomMonitorAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    private let instanceGuard: SingleInstanceGuard
    @Published private(set) var monitorStore: MonitorStore?
    @Published private(set) var controlStore: ProviderControlStore?
    private var statusItemController: StatusItemController?

    override init() {
        self.instanceGuard = SingleInstanceGuard()
        super.init()
    }

    init(instanceGuard: SingleInstanceGuard) {
        self.instanceGuard = instanceGuard
        super.init()
    }

    func showSettings() {
        statusItemController?.showSettings()
    }

    func showDashboard() {
        statusItemController?.showDashboard()
    }

    func showChat() {
        statusItemController?.showChatWindow()
    }

    func attachStores(monitor: MonitorStore, control: ProviderControlStore) {
        monitorStore = monitor
        controlStore = control
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard DarkbloomMonitorStartupGate.acquireOrTerminate(
            instanceGuard: instanceGuard,
            terminate: { NSApplication.shared.terminate(nil) }
        ) else {
            // Do not construct MonitorStore, StatusItemController, or any
            // other UI for a duplicate or unverifiable launch.
            return
        }

        ApplicationAppearance.applyStored()
        NSApplication.shared.setActivationPolicy(.accessory)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let policy = DarkbloomSourcePolicy(
            homeDirectory: home,
            environmentPath: ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        )
        let runner = CappedProcessRunner()
        let source = LocalTelemetrySource(policy: policy, runner: runner)
        let service = TelemetryService(
            source: source,
            unifiedEvents: UnifiedLogStreamer().events()
        )
        let applicationSupport = MonitorApplicationIdentity.applicationSupportDirectory()
        let alertHistoryDatabase = try? AlertHistoryDatabase(
            url: applicationSupport.appendingPathComponent("alerts.sqlite3")
        )
        let earningsDatabase = try? EarningsDatabase(
            url: applicationSupport.appendingPathComponent("earnings.sqlite3")
        )
        let observedUptimeDatabase = try? ObservedUptimeDatabase(
            url: applicationSupport.appendingPathComponent("observed-uptime.sqlite3")
        )
        let tokenRateDatabase = try? ModelTokenRateDatabase(
            url: applicationSupport.appendingPathComponent("model-token-rates.sqlite3")
        )
        let recommendationJournal = try? RecommendationJournal(
            url: applicationSupport.appendingPathComponent("recommendations.sqlite3")
        )
        let earningsClient = AuthenticatedEarningsClient(
            homeDirectory: home,
            database: earningsDatabase
        )
        let monitorStore = MonitorStore(
            service: service,
            initial: .unavailable(now: Date()),
            providerExtras: ProviderExtrasStore(),
            earningsClient: earningsClient,
            uptimeRecorder: observedUptimeDatabase,
            alertHistory: alertHistoryDatabase,
            alertNotifier: OperationalNotificationCenter(),
            tokenRateRecorder: tokenRateDatabase,
            networkCapacityClient: PublicNetworkCapacityClient(),
            recommendationJournal: recommendationJournal,
            publicCatalogClient: PublicCatalogClient(),
            publicPricingClient: PublicPricingClient(),
            networkSeriesClient: NetworkSeriesClient()
        )
        let configExecutable = policy.cliCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) ?? policy.cliCandidates[0]
        let configStore = LocalProviderConfigStore(
            configURL: policy.providerConfig,
            executable: configExecutable,
            runner: runner
        )
        let controlService = ProviderControlService(
            policy: policy,
            telemetrySource: source,
            configStore: configStore,
            runner: runner
        )
        let localEndpointClient = LocalEndpointClient(policy: policy, runner: runner)
        let localEndpointTokenFile = LocalEndpointTokenFile(fileURL: policy.localEndpointToken)
        let hostingSettingsStore = HostingSettingsStore(
            controlStore: nil,
            endpointClient: localEndpointClient,
            tokenFile: localEndpointTokenFile,
            cliVersionProvider: { [weak monitorStore] in
                monitorStore?.snapshot.status.value?.version
            }
        )
        // The consumer API key is a distinct credential from the provider
        // device token and the local endpoint token: it lives only in the
        // Keychain and is used for Chat and the explicit free self-route
        // warm-up after a confirmed model switch.
        let consumerKeyStore = KeychainConsumerKeyStore()
        let chatStore = ChatStore(
            localClient: LocalChatClient(endpointProvider: AppLocalEndpointProvider(
                defaults: .standard,
                tokenFile: localEndpointTokenFile,
                standaloneClient: localEndpointClient
            )),
            networkClient: NetworkChatClient(consumerKeyProvider: { [consumerKeyStore] in
                consumerKeyStore.withConsumerKey { $0 }
            }),
            balanceClient: ConsumerBalanceClient(consumerKeyProvider: { [consumerKeyStore] in
                consumerKeyStore.withConsumerKey { $0 }
            }),
            pricingClient: PublicPricingClient(),
            keyStore: consumerKeyStore
        )
        let providerControlStore = ProviderControlStore(
            controller: controlService,
            warmupProbe: SelfRouteWarmupClient(keyStore: consumerKeyStore),
            swapProbe: LocalModelSwapClient(endpointProvider: AppModelSwapEndpointProvider(discovery: localEndpointClient)),
            homeDirectory: home,
            refreshTelemetry: { [weak monitorStore] in
                await monitorStore?.refreshTelemetryImmediately()
            },
            awaitStartup: { [weak monitorStore] requestedAt in
                for _ in 0..<45 {
                    try Task.checkCancellation()
                    guard let monitorStore else { throw CancellationError() }
                    await monitorStore.refreshTelemetryImmediately()
                    if case .available(let daemon, _) = monitorStore.snapshot.state,
                       daemon.writtenAt >= requestedAt.timeIntervalSince1970 {
                        return
                    }
                    try await Task.sleep(for: .seconds(2))
                }
                throw ProviderStartupTimeout()
            },
            hostingOptions: { [weak hostingSettingsStore] in
                hostingSettingsStore?.options ?? HostingSettingsStore.loadOptions(from: .standard)
            }
        )
        monitorStore.profitSwitch = ProfitSwitchStore(control: providerControlStore)
        let nudgeKeyStore = KeychainConsumerKeyStore(
            service: "dev.darkbloom.control.inactivity-nudge-key"
        )
        monitorStore.inactivityNudge = InactivityNudgeStore(
            keyStore: nudgeKeyStore,
            canAct: { [weak providerControlStore] in
                providerControlStore?.canAutomaticNudge == true
            },
            send: { [weak providerControlStore] state, canSend in
                guard let providerControlStore else { return nil }
                let catalogFamily = providerControlStore.snapshot?.inventory.myCatalog.first {
                    $0.catalogID == state.currentModel
                }?.family ?? ""
                let family = NudgeSelfRouteModel.familyFallback(
                    for: state, catalogFamily: catalogFamily
                )
                let probe = SelfRouteWarmupClient(
                    keyStore: nudgeKeyStore,
                    canSend: canSend
                )
                return await providerControlStore.performAutomaticNudge(
                    modelID: state.currentModel,
                    family: family,
                    probe: probe
                )
            }
        )
        monitorStore.attachRecommendationInventory { [weak providerControlStore] in
            providerControlStore?.snapshot
        }
        hostingSettingsStore.attachControlStore(providerControlStore)
        attachStores(monitor: monitorStore, control: providerControlStore)
        statusItemController = StatusItemController(
            store: monitorStore,
            controlStore: providerControlStore,
            hostingStore: hostingSettingsStore,
            chatStore: chatStore
        )
        ControlAppUpdater.shared.canRelaunch = { [weak providerControlStore] in
            guard let control = providerControlStore else { return true }
            return control.operation == .idle && control.draft?.hasChanges != true
                && control.pendingConfirmation == nil
        }
        ControlAppUpdater.shared.start()
        CLIUpdateStatusStore.shared.start()
        monitorStore.start()
        Task { @MainActor [weak providerControlStore, weak monitorStore] in
            await providerControlStore?.refresh()
            await monitorStore?.refreshRecommendation()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusItemController?.invalidate()
        controlStore?.cancelCurrentOperation()
        guard let monitorStore else { return }
        Task {
            await CLIUpdateStatusStore.shared.stop()
            await monitorStore.stop()
        }
    }
}

struct AppSettingsObservedSceneRoot: View {
    @ObservedObject var delegate: DarkbloomMonitorAppDelegate

    var body: some View {
        AppSettingsSceneRoot(
            controlStore: delegate.controlStore,
            monitorStore: delegate.monitorStore
        )
    }
}

struct AppSettingsSceneRoot: View {
    let controlStore: ProviderControlStore?
    var monitorStore: MonitorStore? = nil

    @ViewBuilder
    var body: some View {
        if let controlStore, let monitorStore {
            ProviderSettingsRoot(controlStore: controlStore, monitorStore: monitorStore)
        } else {
            ProgressView("Starting \(MonitorApplicationIdentity.displayName)…")
                .frame(width: 420, height: 180)
        }
    }
}

struct ProviderSettingsRoot: View {
    @ObservedObject var controlStore: ProviderControlStore
    var monitorStore: MonitorStore? = nil
    var extrasStore: ProviderExtrasStore? { monitorStore?.providerExtras }

    var body: some View {
        MonitorSettingsView(
            extrasStore: extrasStore,
            controlStore: controlStore,
            monitorStore: monitorStore
        )
        .frame(width: 900, height: 650)
    }
}

private struct ControlAppUpdateMenuItem: View {
    @ObservedObject var updater = ControlAppUpdater.shared
    var body: some View {
        Button("Check for Updates…", action: updater.check).disabled(!updater.canCheck)
    }
}

private struct ProviderStartupTimeout: Error {}
