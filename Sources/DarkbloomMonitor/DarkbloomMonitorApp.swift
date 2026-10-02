import AppKit
import DarkbloomTelemetry
import SwiftUI

/// SwiftUI content is hosted by the existing AppKit window controllers. A native
/// application entry avoids registering a second Settings window scene.
@main
@MainActor
enum DarkbloomMonitorApp {
    static func main() {
        let application = NSApplication.shared
        let delegate = DarkbloomMonitorAppDelegate()
        application.delegate = delegate
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

@MainActor
final class DarkbloomMonitorAppDelegate: NSObject, NSApplicationDelegate, ObservableObject, NSMenuItemValidation {
    private let instanceGuard: SingleInstanceGuard
    @Published private(set) var monitorStore: MonitorStore?
    @Published private(set) var controlStore: ProviderControlStore?
    private var statusItemController: StatusItemController?

    override init() {
        self.instanceGuard = SingleInstanceGuard()
        super.init()
    }

    init(instanceGuard: SingleInstanceGuard, statusItemController: StatusItemController? = nil) {
        self.instanceGuard = instanceGuard
        self.statusItemController = statusItemController
        super.init()
    }

    @objc func showSettings() {
        statusItemController?.showSettings()
    }

    @objc func showDashboard() {
        statusItemController?.showDashboard()
    }

    @objc func showChat() {
        statusItemController?.showChatWindow()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return false
    }

    @objc func checkForAppUpdates() {
        ControlAppUpdater.shared.check()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForAppUpdates) {
            return ControlAppUpdater.shared.canCheck
        }
        return true
    }

    func installApplicationMenus(application: NSApplication = .shared) {
        let menu = makeMainMenu(application: application)
        application.mainMenu = menu
        application.servicesMenu = menu.items.first?.submenu?.items
            .first(where: { $0.title == "Services" })?.submenu
        application.windowsMenu = menu.items.first(where: { $0.title == "Window" })?.submenu
    }

    func makeMainMenu(application: NSApplication = .shared) -> NSMenu {
        let mainMenu = NSMenu()
        let appMenu = NSMenu(title: MonitorApplicationIdentity.displayName)
        let appItem = NSMenuItem(title: appMenu.title, action: nil, keyEquivalent: "")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        func add(_ title: String, action: Selector, key: String = "",
                 modifiers: NSEvent.ModifierFlags = .command,
                 target: AnyObject? = nil, to menu: NSMenu) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = modifiers
            item.target = target
            menu.addItem(item)
        }

        add("About \(MonitorApplicationIdentity.displayName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), target: application, to: appMenu)
        add("Check for Updates…", action: #selector(checkForAppUpdates), target: self, to: appMenu)
        appMenu.addItem(.separator())
        add("Settings…", action: #selector(showSettings), key: ",", target: self, to: appMenu)
        add("Open Dashboard", action: #selector(showDashboard), key: "d", modifiers: [.command, .shift], target: self, to: appMenu)
        add("Open Chat Window", action: #selector(showChat), key: "c", modifiers: [.command, .shift], target: self, to: appMenu)
        appMenu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        appMenu.addItem(services)
        appMenu.addItem(.separator())
        add("Hide \(MonitorApplicationIdentity.displayName)", action: #selector(NSApplication.hide(_:)), key: "h", target: application, to: appMenu)
        add("Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), key: "h", modifiers: [.command, .option], target: application, to: appMenu)
        add("Show All", action: #selector(NSApplication.unhideAllApplications(_:)), target: application, to: appMenu)
        appMenu.addItem(.separator())
        add("Quit \(MonitorApplicationIdentity.displayName)", action: #selector(NSApplication.terminate(_:)), key: "q", target: application, to: appMenu)

        let editMenu = NSMenu(title: "Edit")
        let editItem = NSMenuItem(title: editMenu.title, action: nil, keyEquivalent: "")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        add("Undo", action: NSSelectorFromString("undo:"), key: "z", to: editMenu)
        add("Redo", action: NSSelectorFromString("redo:"), key: "z", modifiers: [.command, .shift], to: editMenu)
        editMenu.addItem(.separator())
        add("Cut", action: #selector(NSText.cut(_:)), key: "x", to: editMenu)
        add("Copy", action: #selector(NSText.copy(_:)), key: "c", to: editMenu)
        add("Paste", action: #selector(NSText.paste(_:)), key: "v", to: editMenu)
        add("Select All", action: #selector(NSText.selectAll(_:)), key: "a", to: editMenu)

        let windowMenu = NSMenu(title: "Window")
        let windowItem = NSMenuItem(title: windowMenu.title, action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        mainMenu.addItem(windowItem)
        add("Close", action: #selector(NSWindow.performClose(_:)), key: "w", to: windowMenu)
        add("Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m", to: windowMenu)
        add("Zoom", action: #selector(NSWindow.performZoom(_:)), to: windowMenu)
        windowMenu.addItem(.separator())
        add("Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), target: application, to: windowMenu)
        return mainMenu
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

        installApplicationMenus()
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
        let actionHistory = ActionHistoryStore(url: applicationSupport.appendingPathComponent("actions.sqlite3"))
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
            database: earningsDatabase,
            observeAccount: { [weak actionHistory] account, capturedAt in
                await actionHistory?.ingest(account, capturedAt: capturedAt)
            }
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
        monitorStore.actionHistory = actionHistory
        monitorStore.performanceHistory = PerformanceHistoryStore(
            url: applicationSupport.appendingPathComponent("performance-history.sqlite3")
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
        let nudgeKeyStore = KeychainConsumerKeyStore(
            service: "dev.darkbloom.control.inactivity-nudge-key"
        )
        let providerControlStore = ProviderControlStore(
            controller: controlService,
            warmupProbe: SelfRouteWarmupClient(keyStore: consumerKeyStore),
            swapProbe: LocalModelSwapClient(endpointProvider: AppModelSwapEndpointProvider(discovery: localEndpointClient)),
            swapNudge: { modelID, canSend in
                await SelfRouteWarmupClient(keyStore: nudgeKeyStore, canSend: canSend)
                    .warm(modelID: modelID, family: "")
            },
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
        providerControlStore.actionHistory = actionHistory
        monitorStore.profitSwitch = ProfitSwitchStore(control: providerControlStore)
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
        monitorStore.inactivityNudge?.actionHistory = actionHistory
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

private struct ProviderStartupTimeout: Error {}
