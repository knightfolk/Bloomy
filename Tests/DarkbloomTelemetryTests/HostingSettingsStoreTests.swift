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

    @Test("model edits block hosting with the correct recovery and survive refresh")
    func modelEditsBlockHosting() async throws {
        let controller = HostingSpyController()
        let control = ProviderControlStore(controller: controller)
        let (store, _) = try makeStore(defaults: makeDefaults(), controller: controller)
        store.attachControlStore(control)
        await control.refresh()
        control.setEnabled(false, modelID: "model-a")
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply()
        #expect(store.pendingExposureRequest == nil)
        #expect(store.errorMessage == "Save or discard model changes in Models before applying hosting.")
        #expect(await controller.hostingExecutions.isEmpty)
        await control.refreshPreservingDraft()
        #expect(control.draft?.hasChanges == true)
        await store.requestApply()
        #expect(store.errorMessage == "Save or discard model changes in Models before applying hosting.")
        control.setEnabled(true, modelID: "model-a")
        await store.requestApply()
        let confirmation = try #require(store.pendingExposureRequest)
        // Changes made after the exposure dialog must be checked again.
        control.setEnabled(false, modelID: "model-a")
        await store.confirmExposure(confirmation)
        #expect(store.errorMessage == "Save or discard model changes in Models before applying hosting.")
        #expect(await controller.hostingExecutions.isEmpty)
        #expect(store.options.bindAddress == "192.168.1.20")
        control.setEnabled(true, modelID: "model-a")
        await store.requestApply()
        await store.confirmPendingExposureConfirmation()
        #expect(await controller.hostingExecutions.count == 1)
        #expect(store.errorMessage == nil)
    }

    @Test("hosting progress blocks a duplicate restart and clears after completion")
    func applyingBlocksDuplicateRestart() async throws {
        let controller = HostingSpyController(delaysHostingCompletion: true)
        let (store, _) = try makeStore(defaults: makeDefaults(), controller: controller)
        let apply = Task { await store.requestApply() }
        await controller.waitForHostingRestart()
        #expect(store.isApplying)
        #expect(store.applyUnavailableReason?.contains("Accepted requests drain") == true)
        await store.requestApply()
        #expect(await controller.hostingExecutions.count == 1)
        await controller.completeHostingRestart()
        await apply.value
        #expect(!store.isApplying)
        #expect(store.applyUnavailableReason == nil)
        #expect(store.errorMessage == nil)
    }

    @Test("shared provider changes notify hosting and replacing the store detaches its observer")
    func sharedControlObservation() async throws {
        let controller = HostingSpyController()
        let old = ProviderControlStore(controller: controller)
        let next = ProviderControlStore(controller: controller)
        let (store, _) = try makeStore(defaults: makeDefaults(), controller: controller)
        await old.refresh()
        await next.refresh()
        store.attachControlStore(old)
        var notifications = 0
        let observation = store.objectWillChange.sink { notifications += 1 }
        old.setEnabled(false, modelID: "model-a")
        #expect(notifications > 0)
        #expect(store.applyNeedsModelReview)
        store.attachControlStore(next)
        notifications = 0
        old.setEnabled(true, modelID: "model-a")
        #expect(notifications == 0)
        next.setEnabled(false, modelID: "model-a")
        #expect(notifications > 0)
        #expect(store.applyNeedsModelReview)
        withExtendedLifetime(observation) {}
    }

    private func makeStore(
        defaults: UserDefaults,
        cliVersion: String? = "0.9.7",
        lanAddresses: [String] = ["192.168.1.20"],
        endpointAvailability: LocalEndpointAvailability = .none("fixture"),
        tokenFile: any LocalEndpointTokenManaging = HostingTokenFileFake(),
        controller: HostingSpyController = HostingSpyController(),
        endpointClient: (any LocalEndpointFetching)? = nil,
        copyToken: @escaping (String) -> Bool = { _ in false },
        copyCommand: @escaping (String) -> Bool = { _ in false },
        now: @escaping () -> Date = Date.init
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
            copyToken: copyToken,
            copyCommand: copyCommand,
            now: now
        )
        store.attachControlStore(controlStore)
        store.refreshEnvironment()
        return (store, controller)
    }

    @Test("discovery timestamp belongs only to the latest completed read and clears with invalidation")
    func discoveryCheckedAt() async throws {
        let record = LocalEndpointRecord(baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242)
        let endpoint = DelayedEndpointFake(first: .live(record), next: .none("fixture"))
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        var clockReads = 0
        let (store, _) = try makeStore(defaults: makeDefaults(), endpointClient: endpoint, now: {
            clockReads += 1
            return stamp
        })
        store.setMode(.standalone)
        let old = Task { await store.fetchEndpointDetails() }
        await endpoint.waitForFirstFetch()
        #expect(store.endpointDetailsCheckedAt == nil)
        await store.fetchEndpointDetails()
        #expect(store.endpointDetails == .none("fixture"))
        #expect(store.endpointDetailsCheckedAt == stamp)
        await endpoint.completeFirstFetch()
        await old.value
        #expect(store.endpointDetails == .none("fixture"))
        #expect(store.endpointDetailsCheckedAt == stamp)
        #expect(clockReads == 1)
        store.refreshEnvironment()
        #expect(store.endpointDetailsCheckedAt == stamp)
        store.setMode(.unified)
        #expect(store.endpointDetails == nil)
        #expect(store.endpointDetailsCheckedAt == nil)
    }

    @Test("a live discovery receives an absolute check time and apply invalidates both")
    func liveCheckedAtClearsAfterApply() async throws {
        let record = LocalEndpointRecord(baseURL: "http://127.0.0.1:8000/v1", apiKey: "",
            host: "127.0.0.1", port: 8000, processID: 4242)
        let stamp = Date(timeIntervalSince1970: 1_800_000_000)
        let (store, _) = try makeStore(defaults: makeDefaults(), endpointAvailability: .live(record), now: { stamp })
        store.setMode(.unified)
        await store.fetchEndpointDetails()
        #expect(store.endpointDetailsCheckedAt == stamp)
        await store.requestApply()
        #expect(store.endpointDetails == nil)
        #expect(store.endpointDetailsCheckedAt == nil)
    }

    @Test("copied feedback follows the actual Terminal command and reports copy failure")
    func commandCopyIdentityAndFailure() throws {
        var copied: [String] = []
        var succeeds = true
        let (store, _) = try makeStore(defaults: makeDefaults(), copyCommand: { command in
            copied.append(command)
            return succeeds
        })
        store.setMode(.standalone)
        let first = try #require(store.standaloneStartCommand)
        #expect(store.copyStandaloneCommandToPasteboard())
        #expect(store.hasCopiedCurrentStandaloneCommand)
        #expect(copied == [first])
        #expect(store.setPortText("8123"))
        #expect(!store.hasCopiedCurrentStandaloneCommand)
        #expect(store.copyStandaloneCommandToPasteboard())
        #expect(store.hasCopiedCurrentStandaloneCommand)
        store.setBindAddress("192.168.1.20")
        #expect(!store.hasCopiedCurrentStandaloneCommand)
        #expect(store.copyStandaloneCommandToPasteboard())
        store.setRequiresAuthentication(false)
        #expect(!store.hasCopiedCurrentStandaloneCommand)
        succeeds = false
        #expect(!store.copyStandaloneCommandToPasteboard())
        #expect(!store.hasCopiedCurrentStandaloneCommand)
        #expect(store.copiedStandaloneCommand == nil)
        #expect(store.errorMessage == "Could not copy the Terminal command. Try again.")
        store.setMode(.off)
        let copyCount = copied.count
        #expect(!store.copyStandaloneCommandToPasteboard())
        #expect(copied.count == copyCount)
        #expect(store.errorMessage != nil)
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

    @Test("only the requesting Hosting editor receives its confirmation")
    func exposureHasOneEditorOwner() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        let dashboard = UUID(), popup = UUID()
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply(confirmationOwner: popup)
        let request = try #require(store.exposureConfirmation(for: popup))
        #expect(store.exposureConfirmation(for: dashboard) == nil)
        #expect(store.pendingExposureConfirmation == request.options)
        // Legacy unowned callbacks cannot consume an editor-owned request.
        store.cancelPendingExposureConfirmation()
        await store.confirmPendingExposureConfirmation()
        #expect(store.exposureConfirmation(for: popup) == request)
        #expect(await controller.hostingExecutions.isEmpty)
        store.cancelExposure(request)
        #expect(store.pendingExposureRequest == nil)
    }

    @Test("a stale dialog cannot cancel or authorize its owner's replacement request")
    func replacementExposureIsRequestScoped() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        let owner = UUID()
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply(confirmationOwner: owner)
        let older = try #require(store.exposureConfirmation(for: owner))
        store.setPortText("8123")
        await store.requestApply(confirmationOwner: owner)
        let replacement = try #require(store.exposureConfirmation(for: owner))
        #expect(older.id != replacement.id)
        store.cancelExposure(older)
        await store.confirmExposure(older)
        #expect(store.pendingExposureRequest == replacement)
        #expect(await controller.hostingExecutions.isEmpty)
        store.setPortText("8222")
        await store.confirmExposure(replacement)
        let executions = await controller.hostingExecutions
        #expect(executions.count == 1)
        #expect(executions.first?.hosting.port == 8123)
    }

    @Test("another editor's new request survives the old editor's delayed dismissal")
    func anotherEditorExposureSurvivesDismissal() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        let dashboard = UUID(), popup = UUID()
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply(confirmationOwner: dashboard)
        let older = try #require(store.exposureConfirmation(for: dashboard))
        await store.requestApply(confirmationOwner: popup)
        let current = try #require(store.exposureConfirmation(for: popup))
        #expect(store.exposureConfirmation(for: dashboard) == nil)
        let dismissal = HostingExposureDismissalCoordinator().scheduleCancellation(
            older, isPending: { store.pendingExposureRequest == older },
            cancel: { store.cancelExposure(older) })
        await dismissal.value
        await store.confirmExposure(older)
        #expect(store.pendingExposureRequest == current)
        #expect(await controller.hostingExecutions.isEmpty)
    }

    @Test("Confirm survives dialog teardown before its asynchronous action starts")
    func exposureConfirmationSurvivesBindingTeardown() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        let owner = UUID()
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply(confirmationOwner: owner)
        let request = try #require(store.exposureConfirmation(for: owner))
        let coordinator = HostingExposureDismissalCoordinator()
        let dismissal = coordinator.scheduleCancellation(
            request, isPending: { store.exposureConfirmation(for: owner) == request },
            cancel: { store.cancelExposure(request) })
        coordinator.beginConfirmation(request)
        await dismissal.value
        #expect(store.pendingExposureRequest == request)
        await store.confirmExposure(request)
        coordinator.endConfirmation(request)
        await store.confirmExposure(request)
        #expect(await controller.hostingExecutions.count == 1)
        #expect(store.pendingExposureRequest == nil)
    }

    @Test("system dismissal cancels only its exact request without dispatch")
    func exposureSystemDismissalCancelsExactRequest() async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults())
        let owner = UUID()
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply(confirmationOwner: owner)
        let request = try #require(store.exposureConfirmation(for: owner))
        let dismissal = HostingExposureDismissalCoordinator().scheduleCancellation(
            request, isPending: { store.exposureConfirmation(for: owner) == request },
            cancel: { store.cancelExposure(request) })
        await dismissal.value
        #expect(store.pendingExposureRequest == nil)
        #expect(await controller.hostingExecutions.isEmpty)
    }

    @Test("a second editor cannot open another exposure dialog during a restart")
    func newerExposureDismissesDuringOlderRestart() async throws {
        let controller = HostingSpyController(delaysHostingCompletion: true)
        let (store, _) = try makeStore(defaults: makeDefaults(), controller: controller)
        let owner = UUID()
        let coordinator = HostingExposureDismissalCoordinator()
        store.setMode(.unified)
        store.setBindAddress("192.168.1.20")
        await store.requestApply(confirmationOwner: owner)
        let older = try #require(store.exposureConfirmation(for: owner))
        coordinator.beginConfirmation(older)
        let applying = Task { await store.confirmExposure(older) }
        await controller.waitForHostingRestart()
        await store.requestApply(confirmationOwner: owner)
        #expect(store.exposureConfirmation(for: owner) == nil)
        #expect(store.errorMessage?.contains("Accepted requests drain") == true)
        #expect(store.pendingExposureRequest == nil)
        await controller.completeHostingRestart()
        await applying.value
        coordinator.endConfirmation(older)
        #expect(await controller.hostingExecutions.count == 1)
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
        #expect(store.unauthenticatedAccessWarning.contains("Fleet only is selected. Apply changes to turn off the local endpoint."))

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

    @Test("missing or malformed CLI evidence blocks apply without asking for an update",
          arguments: [Optional<String>.none, "", "unknown", "private-version-canary"])
    func unknownCLIHasNoUpdateClaim(cliVersion: String?) async throws {
        let (store, controller) = try makeStore(defaults: makeDefaults(), cliVersion: cliVersion)
        #expect(!store.cliSupportsHosting)
        store.setMode(.unified)
        await store.requestApply()
        #expect(await controller.hostingExecutions.isEmpty)
        let message = try #require(store.errorMessage)
        #expect(!message.contains("Update"))
        #expect(message.contains("Refresh"))
        #expect(message.contains(HostingCapability.minimumCLIVersion))
        #expect(!message.contains("private-version-canary"))
    }

    @Test("Hosting notices distinguish missing evidence, an old CLI and supported controls")
    func capabilityNotice() throws {
        let missing = try #require(HostingCLIRequirementPresentation.make(cliVersion: nil))
        #expect(missing.title == "CLI version unavailable")
        #expect(missing.symbol == "questionmark.circle")
        #expect(!missing.requiresUpdate)
        #expect(HostingCLIRequirementPresentation.make(cliVersion: "private-version-canary") == missing)
        let old = try #require(HostingCLIRequirementPresentation.make(cliVersion: "0.9.6"))
        #expect(old.requiresUpdate)
        #expect(old.title == "Update Darkbloom CLI")
        #expect(old.message.contains("observed CLI 0.9.6"))
        #expect(HostingCLIRequirementPresentation.make(cliVersion: "0.9.17") == nil)
    }

    @Test("refresh recovers CLI capability without changing saved hosting preferences")
    func capabilityRecovery() async throws {
        var version: String?
        let defaults = makeDefaults()
        let store = HostingSettingsStore(controlStore: nil,
            endpointClient: EndpointFetchFake(availability: .none("fixture")),
            tokenFile: HostingTokenFileFake(), cliVersionProvider: { version },
            defaults: defaults, lanScanner: { [] })
        store.setMode(.standalone)
        #expect(store.setPortText("8123"))
        let saved = defaults.dictionaryRepresentation() as NSDictionary
        store.refreshEnvironment()
        #expect(!store.cliSupportsHosting)
        #expect(!store.copyStandaloneCommandToPasteboard())
        version = "0.9.17"
        store.refreshEnvironment()
        #expect(store.cliSupportsHosting)
        #expect(store.standaloneStartCommand?.contains("8123") == true)
        version = "0.9.6"
        store.refreshEnvironment()
        #expect(!store.cliSupportsHosting)
        #expect(!store.copyStandaloneCommandToPasteboard())
        version = nil
        store.refreshEnvironment()
        #expect(!store.cliSupportsHosting)
        #expect(defaults.dictionaryRepresentation() as NSDictionary == saved)
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
