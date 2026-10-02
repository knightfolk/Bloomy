import AppKit
import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Hosting settings store")
@MainActor
struct HostingSettingsStoreTests {
    private func makeDefaults() -> UserDefaults {
        let suiteName = "HostingSettingsStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(
        defaults: UserDefaults,
        cliVersion: String? = "0.9.7",
        lanAddresses: [String] = ["192.168.1.20"],
        endpointAvailability: LocalEndpointAvailability = .none("fixture"),
        tokenFile: any LocalEndpointTokenManaging = HostingTokenFileFake(),
        controller: HostingSpyController = HostingSpyController(),
        endpointClient: (any LocalEndpointFetching)? = nil,
        copyToken: @escaping (String) -> Bool = { _ in false }
    ) throws -> (HostingSettingsStore, HostingSpyController) {
        let controlStore = ProviderControlStore(
            controller: controller,
            hostingOptions: { .default }
        )
        let store = HostingSettingsStore(
            controlStore: controlStore,
            endpointClient: endpointClient ?? EndpointFetchFake(availability: endpointAvailability),
            tokenFile: tokenFile,
            cliVersionProvider: { cliVersion },
            defaults: defaults,
            lanScanner: { lanAddresses },
            copyToken: copyToken
        )
        store.attachControlStore(controlStore)
        store.refreshEnvironment()
        return (store, controller)
    }

    @Test("fresh defaults are off, loopback, and unconfirmed")
    func freshDefaults() throws {
        let (store, _) = try makeStore(defaults: makeDefaults())
        #expect(store.options == .default)
        #expect(store.cliSupportsHosting)
        #expect(store.pendingExposureConfirmation == nil)
    }

    @Test("preferences persist and reload with safe fallbacks")
    func persistenceRoundTrip() throws {
        let defaults = makeDefaults()
        let (store, _) = try makeStore(defaults: defaults)
        store.setMode(.unified)
        #expect(store.setPortText("8123"))
        store.setBindAddress("192.168.1.20")
        store.setRequiresAuthentication(false)

        let reloaded = HostingSettingsStore.loadOptions(from: defaults)
        #expect(reloaded == HostingOptions(
            mode: .unified,
            port: 8123,
            bindAddress: "192.168.1.20",
            requiresAuthentication: false
        ))

        defaults.removeObject(forKey: HostingSettingsStore.requiresAuthenticationKey)
        #expect(HostingSettingsStore.loadOptions(from: defaults).requiresAuthentication)

        defaults.set("banana", forKey: HostingSettingsStore.bindAddressKey)
        defaults.set(70_000, forKey: HostingSettingsStore.portKey)
        defaults.set("sideways", forKey: HostingSettingsStore.modeKey)
        let recovered = HostingSettingsStore.loadOptions(from: defaults)
        #expect(recovered == .default)
    }

    @Test("a custom bearer token is saved for the CLI and never enters app preferences")
    func savesCustomBearerToken() throws {
        let defaults = makeDefaults()
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostingSettingsToken-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokenFile = LocalEndpointTokenFile(fileURL: directory.appendingPathComponent("local_token"))
        let (store, _) = try makeStore(defaults: defaults, tokenFile: tokenFile)
        store.setMode(.unified)

        let token = "custom-openai-client-key-12345"
        #expect(store.saveBearerToken(token))
        #expect(store.localTokenNeedsRestart)
        #expect(store.localTokenStatusMessage?.contains("Apply changes") == true)
        #expect(store.localTokenStatusMessage?.contains(token) == false)
        #expect(store.canCopyBearerToken)

        var savedToken: String?
        #expect(tokenFile.withBearerToken { savedToken = $0 })
        #expect(savedToken == token)
        #expect(defaults.dictionaryRepresentation().values.allSatisfy { ($0 as? String) != token })
    }

    @Test("a custom token is reported for Terminal restart in unmanaged local-only mode")
    func standaloneTokenRequiresTerminalRestart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostingStandaloneToken-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokenFile = LocalEndpointTokenFile(fileURL: directory.appendingPathComponent("local_token"))
        let (store, _) = try makeStore(defaults: makeDefaults(), tokenFile: tokenFile)
        store.setMode(.standalone)

        #expect(store.saveBearerToken("custom-openai-client-key-12345"))
        #expect(!store.localTokenNeedsRestart)
        #expect(store.localTokenStatusMessage?.contains("darkbloom start --local") == true)
        #expect(store.localTokenStatusMessage?.contains("Terminal") == true)
    }

    @Test("saving a custom token while auth is disabled retains it for a later authenticated start")
    func savesTokenForLaterAuthenticatedStart() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HostingNoAuthToken-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let tokenFile = LocalEndpointTokenFile(fileURL: directory.appendingPathComponent("local_token"))
        let (store, _) = try makeStore(defaults: makeDefaults(), tokenFile: tokenFile)
        store.setRequiresAuthentication(false)

        #expect(store.saveBearerToken("custom-openai-client-key-12345"))
        #expect(store.localTokenStatusMessage?.contains("Darkbloom's protected token file") == true)
    }

    @Test("an invalid port text is rejected without changing the saved value")
    func invalidPortText() throws {
        let defaults = makeDefaults()
        let (store, _) = try makeStore(defaults: defaults)
        #expect(store.setPortText("8123"))
        #expect(!store.setPortText("0"))
        #expect(!store.setPortText("99999"))
        #expect(!store.setPortText("abc"))
        #expect(store.options.port == 8123)
    }

    @Test("the unified URL follows the configured local or LAN bind")
    func configuredEndpointURL() throws {
        let (store, _) = try makeStore(defaults: makeDefaults())
        #expect(store.configuredEndpointURL == nil)

        store.setMode(.unified)
        #expect(store.configuredEndpointURL == "http://127.0.0.1:8000/v1")
        store.setPortText("8123")
        store.setBindAddress("192.168.1.20")
        #expect(store.configuredEndpointURL == "http://192.168.1.20:8123/v1")
        store.setBindAddress(HostingOptions.allInterfacesBindAddress)
        #expect(store.configuredEndpointURL == "http://127.0.0.1:8123/v1")
    }

    @Test("a loopback unified apply dispatches immediately through the control gate")
    func loopbackApplyDispatches() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        store.setMode(.unified)
        store.setPortText("8123")
        await store.requestApply()
        let executions = await controller.hostingExecutions
        #expect(executions.count == 1)
        #expect(executions.first?.action == .start)
        #expect(executions.first?.hosting == HostingOptions(mode: .unified, port: 8123, bindAddress: "127.0.0.1"))
        #expect(store.pendingExposureConfirmation == nil)
        #expect(store.errorMessage == nil)
    }

    @Test("a token saved after restart stays pending when the older apply finishes")
    func newerSavedTokenRemainsPendingAfterApply() async throws {
        let controller = HostingSpyController(delaysHostingCompletion: true)
        let (store, _) = try makeStore(defaults: makeDefaults(), controller: controller)
        store.setMode(.unified)
        #expect(store.saveBearerToken("synthetic-first-key-12345"))

        let apply = Task { await store.requestApply() }
        await controller.waitForHostingRestart()
        #expect(store.saveBearerToken("synthetic-newer-key-12345"))
        await controller.completeHostingRestart()
        await apply.value

        #expect(store.localTokenNeedsRestart)
        #expect(store.localTokenStatusMessage?.contains("Apply changes") == true)
        #expect(store.localTokenStatusMessage?.contains("has restarted") == false)
    }

    @Test("apply clears the restart notice when its saved token has not changed")
    func appliedSavedTokenClearsRestartNotice() async throws {
        let (store, _) = try makeStore(defaults: makeDefaults())
        store.setMode(.unified)
        #expect(store.saveBearerToken("synthetic-first-key-12345"))

        await store.requestApply()

        #expect(!store.localTokenNeedsRestart)
        #expect(store.localTokenStatusMessage?.contains("has restarted") == true)
    }

    @Test("applying restored authentication invalidates old unauthenticated discovery")
    func applyInvalidatesUnauthenticatedEndpointDetails() async throws {
        let record = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        let (store, _) = try makeStore(
            defaults: makeDefaults(), endpointAvailability: .live(record),
            tokenFile: HostingTokenFileFake(token: "synthetic-saved-key-12345")
        )
        store.setMode(.unified)
        store.setRequiresAuthentication(false)
        await store.fetchEndpointDetails()
        store.setRequiresAuthentication(true)

        await store.requestApply()

        #expect(store.endpointDetails == nil)
        #expect(store.canCopyBearerToken)
    }

    @Test("an unauthenticated cached record permits an explicit fresh copy attempt")
    func unauthenticatedCacheDoesNotDisableCopyRetry() async throws {
        let record = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        let (store, _) = try makeStore(defaults: makeDefaults(), endpointAvailability: .live(record))
        await store.fetchEndpointDetails()

        #expect(store.canCopyBearerToken)
    }

    @Test("copy retries discovery and uses the fresh active key rather than a cached or saved key")
    func copyUsesFreshEndpointToken() async throws {
        let unauthenticated = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        let authenticated = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "synthetic-active-key-12345",
            host: "127.0.0.1", port: 8000, processID: 4243
        )
        var copiedToken: String?
        let (store, _) = try makeStore(
            defaults: makeDefaults(),
            tokenFile: HostingTokenFileFake(token: "synthetic-saved-key-12345"),
            endpointClient: EndpointSequenceFake([.live(unauthenticated), .live(authenticated)]),
            copyToken: { copiedToken = $0; return true }
        )
        await store.fetchEndpointDetails()

        #expect(store.canCopyBearerToken)
        #expect(await store.copyBearerTokenToPasteboard())
        #expect(copiedToken == "synthetic-active-key-12345")
        #expect(store.errorMessage == nil)
    }

    @Test("copy refuses a freshly unauthenticated endpoint even when a saved key exists")
    func copyRejectsUnauthenticatedEndpoint() async throws {
        let record = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        var copied = false
        let (store, _) = try makeStore(
            defaults: makeDefaults(), endpointAvailability: .live(record),
            tokenFile: HostingTokenFileFake(token: "synthetic-saved-key-12345"),
            copyToken: { _ in copied = true; return true }
        )

        #expect(!(await store.copyBearerTokenToPasteboard()))
        #expect(!copied)
        #expect(store.errorMessage?.contains("authentication disabled") == true)
    }

    @Test("copy falls back to the saved key only when no live endpoint is advertised")
    func copyUsesSavedKeyWithoutEndpoint() async throws {
        var copiedToken: String?
        let (store, _) = try makeStore(
            defaults: makeDefaults(),
            tokenFile: HostingTokenFileFake(token: "synthetic-saved-key-12345"),
            copyToken: { copiedToken = $0; return true }
        )

        #expect(await store.copyBearerTokenToPasteboard())
        #expect(copiedToken == "synthetic-saved-key-12345")
    }

    @Test("copy reports an unavailable key without writing anything")
    func copyWithoutAnyKey() async throws {
        var copied = false
        let (store, _) = try makeStore(
            defaults: makeDefaults(), copyToken: { _ in copied = true; return true }
        )

        #expect(!store.canCopyBearerToken)
        #expect(!(await store.copyBearerTokenToPasteboard()))
        #expect(!copied)
        #expect(store.errorMessage?.contains("not available yet") == true)
    }

    @Test("a failed apply retains the restart warning and existing discovery")
    func failedApplyPreservesTokenAndDiscovery() async throws {
        let record = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "synthetic-active-key-12345",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        let (store, _) = try makeStore(
            defaults: makeDefaults(), endpointAvailability: .live(record),
            controller: HostingSpyController(failsHosting: true)
        )
        store.setMode(.unified)
        await store.fetchEndpointDetails()
        #expect(store.saveBearerToken("synthetic-newer-key-12345"))

        await store.requestApply()

        #expect(store.localTokenNeedsRestart)
        #expect(store.endpointDetails == .live(record))
        #expect(store.localTokenStatusMessage?.contains("Apply changes") == true)
        #expect(store.errorMessage != nil)
    }

    @Test("an unauthenticated apply does not claim the endpoint is using the saved token")
    func unauthenticatedApplyKeepsTokenNoticeTruthful() async throws {
        let (store, _) = try makeStore(defaults: makeDefaults())
        store.setMode(.unified)
        #expect(store.saveBearerToken("synthetic-saved-key-12345"))
        store.setRequiresAuthentication(false)

        await store.requestApply()
        await store.confirmPendingExposureConfirmation()

        #expect(!store.localTokenNeedsRestart)
        #expect(store.localTokenStatusMessage?.contains("has restarted with the saved token") == false)
        #expect(store.localTokenStatusMessage?.contains("next time") == true)
    }

    @Test("a discovery read started before apply cannot restore the old endpoint cache")
    func oldDiscoveryCannotReturnAfterApply() async throws {
        let oldRecord = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        let endpointClient = DelayedEndpointFake(first: .live(oldRecord))
        let (store, _) = try makeStore(defaults: makeDefaults(), endpointClient: endpointClient)
        store.setMode(.unified)
        let discovery = Task { await store.fetchEndpointDetails() }
        await endpointClient.waitForFirstFetch()

        await store.requestApply()
        await endpointClient.completeFirstFetch()
        await discovery.value

        #expect(store.endpointDetails == nil)
        #expect(!store.isFetchingEndpointDetails)
    }

    @Test("an older overlapping copy cannot copy a superseded endpoint credential")
    func overlappingCopiesDiscardOlderDiscovery() async throws {
        let oldRecord = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "synthetic-old-key-12345",
            host: "127.0.0.1", port: 8000, processID: 4242
        )
        let newRecord = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1", apiKey: "synthetic-new-key-12345",
            host: "127.0.0.1", port: 8000, processID: 4243
        )
        let endpointClient = DelayedEndpointFake(first: .live(oldRecord), next: .live(newRecord))
        var copiedTokens: [String] = []
        let (store, _) = try makeStore(
            defaults: makeDefaults(), endpointClient: endpointClient,
            copyToken: { copiedTokens.append($0); return true }
        )
        let olderCopy = Task { await store.copyBearerTokenToPasteboard() }
        await endpointClient.waitForFirstFetch()

        #expect(await store.copyBearerTokenToPasteboard())
        await endpointClient.completeFirstFetch()
        #expect(!(await olderCopy.value))

        #expect(copiedTokens == ["synthetic-new-key-12345"])
        #expect(store.endpointDetails == .live(newRecord))
        #expect(!store.isFetchingEndpointDetails)
    }

    @Test("a rejected overlapping apply cannot clear a newer token's restart warning")
    func overlappingApplyRetainsPendingToken() async throws {
        let controller = HostingSpyController(delaysHostingCompletion: true)
        let (store, _) = try makeStore(defaults: makeDefaults(), controller: controller)
        store.setMode(.unified)
        #expect(store.saveBearerToken("synthetic-first-key-12345"))
        let olderApply = Task { await store.requestApply() }
        await controller.waitForHostingRestart()
        #expect(store.saveBearerToken("synthetic-newer-key-12345"))

        await store.requestApply()
        #expect(store.errorMessage != nil)
        #expect(store.localTokenNeedsRestart)
        await controller.completeHostingRestart()
        await olderApply.value

        #expect(store.localTokenNeedsRestart)
        #expect(store.localTokenStatusMessage?.contains("has restarted") == false)
    }

    @Test("a LAN bind never dispatches without explicit confirmation")
    func lanApplyRequiresConfirmation() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        store.setMode(.unified)
        store.setPortText("8123")
        store.setBindAddress("192.168.1.20")
        #expect(store.lanAddresses == ["192.168.1.20"])

        await store.requestApply()
        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.pendingExposureConfirmation == HostingOptions(mode: .unified, port: 8123, bindAddress: "192.168.1.20"))

        store.cancelPendingExposureConfirmation()
        #expect(store.pendingExposureConfirmation == nil)
        #expect(await controller.hostingExecutions.isEmpty)

        await store.requestApply()
        await store.confirmPendingExposureConfirmation()
        let executions = await controller.hostingExecutions
        #expect(executions.count == 1)
        #expect(executions.first?.hosting.bindAddress == "192.168.1.20")
        #expect(store.pendingExposureConfirmation == nil)
    }

    @Test("an all-interfaces bind also requires confirmation")
    func allInterfacesRequiresConfirmation() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        store.setMode(.unified)
        store.setBindAddress("0.0.0.0")
        await store.requestApply()
        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.pendingExposureConfirmation != nil)
    }

    @Test("a saved private address must still belong to an active LAN interface")
    func staleLANAddressIsRejected() async throws {
        let (store, controller) = try makeStore(
            defaults: makeDefaults(),
            lanAddresses: []
        )
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply()

        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.pendingExposureConfirmation == nil)
        #expect(store.errorMessage == "That address is not active on this Mac. Choose a current LAN or tailnet address, or use loopback.")
    }

    @Test("disabling authentication requires confirmation even on loopback")
    func unauthenticatedApplyRequiresConfirmation() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        store.setMode(.unified)
        store.setRequiresAuthentication(false)

        await store.requestApply()

        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.pendingExposureConfirmation?.bindAddress == HostingOptions.loopbackBindAddress)
        #expect(store.exposureConfirmationTitle == "Disable API-key authentication?")
        #expect(store.exposureConfirmationMessage.contains("anyone who can reach this endpoint"))

        await store.confirmPendingExposureConfirmation()
        let executions = await controller.hostingExecutions
        #expect(executions.count == 1)
        #expect(executions.first?.hosting.requiresAuthentication == false)
        #expect(store.pendingExposureConfirmation == nil)
    }

    @Test("standalone preview reflects the selected local CLI options")
    func standaloneCommandPreview() throws {
        let (store, _) = try makeStore(
            defaults: makeDefaults(),
            lanAddresses: ["192.168.1.20", "100.101.22.3"]
        )
        store.setMode(.standalone)
        store.setPortText("8123")
        store.setBindAddress("100.101.22.3")
        store.setRequiresAuthentication(false)

        #expect(store.standaloneStartCommand == "darkbloom start --local --port 8123 --bind 100.101.22.3 --no-auth")
    }

    @Test("standalone command preview requires the selected interface to be active")
    func standaloneCommandRejectsInactiveAddress() throws {
        let (store, _) = try makeStore(defaults: makeDefaults(), lanAddresses: ["192.168.1.20"])
        store.setMode(.standalone)
        store.setBindAddress("192.168.1.99")

        #expect(store.standaloneStartCommand == nil)
    }

    @Test("authentication warning explains the selected mode without promising a nonexistent gate")
    func unauthenticatedWarningMatchesMode() throws {
        let (store, _) = try makeStore(defaults: makeDefaults())
        store.setRequiresAuthentication(false)
        #expect(store.unauthenticatedAccessWarning.contains("No local endpoint is active"))

        store.setMode(.unified)
        #expect(store.unauthenticatedAccessWarning.contains("second confirmation before the provider is restarted"))

        store.setMode(.standalone)
        #expect(store.unauthenticatedAccessWarning.contains("app will not run or supervise this command"))
    }

    @Test("an unverified CLI blocks every apply")
    func unsupportedCLIBlocksApply() async throws {
        let (store, controller) = try makeStore(
            defaults: makeDefaults(),
            cliVersion: "0.8.15"
        )
        #expect(!store.cliSupportsHosting)
        store.setMode(.unified)
        await store.requestApply()
        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.errorMessage == HostingSettingsStore.unsupportedMessage(cliVersion: "0.8.15"))
    }

    @Test("standalone mode is represented as unavailable and never dispatched")
    func standaloneIsNeverDispatched() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        store.setMode(.standalone)
        await store.requestApply()
        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.errorMessage == HostingEndpointMode.standaloneUnavailableReason)
    }

    @Test("endpoint details stay in memory and the token stays hidden")
    func endpointDetailsHandling() async throws {
        let record = LocalEndpointRecord(
            baseURL: "http://127.0.0.1:8000/v1",
            apiKey: "synthetic-token-value",
            host: "127.0.0.1",
            port: 8000,
            processID: 4242
        )
        let (store, _) = try makeStore(
            defaults: makeDefaults(),
            endpointAvailability: .live(record)
        )
        await store.fetchEndpointDetails()
        guard case .live(let observed) = store.endpointDetails else {
            Issue.record("expected a live endpoint")
            return
        }
        #expect(observed.processID == 4242)
        #expect(store.canCopyBearerToken)
        #expect(String(describing: observed).contains("bearerToken"))
        #expect(!String(describing: observed).contains("synthetic-token-value"))
    }
}

private actor HostingSpyController: ProviderControlling {
    struct HostingExecution: Equatable, Sendable {
        let action: ProviderLifecycleAction
        let hosting: HostingOptions
    }

    private let snapshot: ProviderControlSnapshot
    private(set) var hostingExecutions: [HostingExecution] = []
    private let delaysHostingCompletion: Bool
    private let failsHosting: Bool
    private var hostingCompletion: CheckedContinuation<Void, Never>?
    private var hostingStarted: CheckedContinuation<Void, Never>?

    init(delaysHostingCompletion: Bool = false, failsHosting: Bool = false) {
        self.delaysHostingCompletion = delaysHostingCompletion
        self.failsHosting = failsHosting
        let draft = ProviderConfigDraft(
            sourceRevision: "fixture",
            original: ProviderModelSelection(enabled: ["model-a"], preloaded: []),
            selection: ProviderModelSelection(enabled: ["model-a"], preloaded: []),
            originalMaxModelSlots: 1,
            maxModelSlots: 1
        )
        snapshot = ProviderControlSnapshot(
            inventory: ModelInventoryBuilder.build(
                catalog: [],
                local: [],
                selection: ProviderModelSelection(enabled: [], preloaded: []),
                daemon: nil,
                loadedModels: []
            ),
            draft: draft,
            capturedAt: Date(timeIntervalSince1970: 1_750_000_000)
        )
    }

    func refresh() async throws -> ProviderControlSnapshot { snapshot }

    func save(_ draft: ProviderConfigDraft) async throws -> ProviderConfigSaveResult {
        throw ProviderControlError.invalidOutput("unused")
    }

    func download(
        _ modelID: String,
        onOutput: (@Sendable (ProcessOutputChunk) -> Void)?
    ) async throws {}

    func delete(_ localModelID: String) async throws {}

    func activityRisk() async -> ProviderActivityRisk { .idle }

    func waitForHostingRestart() async {
        guard hostingExecutions.isEmpty else { return }
        await withCheckedContinuation { hostingStarted = $0 }
    }

    func completeHostingRestart() {
        hostingCompletion?.resume()
        hostingCompletion = nil
    }

    func execute(
        _ action: ProviderLifecycleAction,
        enabledModels: [String]
    ) async throws {}

    func performLifecycle(
        _ action: ProviderLifecycleAction,
        enabledModels: [String],
        hosting: HostingOptions,
        onPhase: ProviderMutationPhaseObserver?
    ) async throws -> ProviderMutationCompletion {
        hostingExecutions.append(HostingExecution(action: action, hosting: hosting))
        if failsHosting { throw ProviderControlError.invalidOutput("fixture") }
        if delaysHostingCompletion {
            await withCheckedContinuation {
                hostingCompletion = $0
                hostingStarted?.resume()
                hostingStarted = nil
            }
        }
        return .refreshUncertain
    }
}

private struct EndpointFetchFake: LocalEndpointFetching {
    let availability: LocalEndpointAvailability
    func fetch() async -> LocalEndpointAvailability { availability }
}

private actor EndpointSequenceFake: LocalEndpointFetching {
    private var results: [LocalEndpointAvailability]
    init(_ results: [LocalEndpointAvailability]) { self.results = results }
    func fetch() async -> LocalEndpointAvailability { results.removeFirst() }
}

private actor DelayedEndpointFake: LocalEndpointFetching {
    private let first: LocalEndpointAvailability
    private let next: LocalEndpointAvailability
    private var firstStarted = false
    private var firstCompletion: CheckedContinuation<LocalEndpointAvailability, Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?

    init(first: LocalEndpointAvailability, next: LocalEndpointAvailability = .none("fixture")) {
        self.first = first
        self.next = next
    }

    func fetch() async -> LocalEndpointAvailability {
        guard !firstStarted else { return next }
        firstStarted = true
        return await withCheckedContinuation {
            firstCompletion = $0
            startWaiter?.resume()
            startWaiter = nil
        }
    }

    func waitForFirstFetch() async {
        guard !firstStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func completeFirstFetch() {
        firstCompletion?.resume(returning: first)
        firstCompletion = nil
    }
}

private struct HostingTokenFileFake: LocalEndpointTokenManaging {
    var token: String? = nil
    func withBearerToken(_ action: (String) -> Void) -> Bool {
        guard let token else { return false }
        action(token)
        return true
    }
    func saveBearerToken(_ token: String) throws {}
}
