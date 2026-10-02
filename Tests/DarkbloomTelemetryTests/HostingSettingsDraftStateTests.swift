import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Hosting input drafts", .serialized)
@MainActor
struct HostingSettingsDraftStateTests {
    @Test("partial ports survive repeated refresh and navigation synchronization", arguments: ["", "0", "65536", "8a"])
    func retainsInvalidPort(text: String) {
        let options = HostingOptions.default
        let draft = HostingSettingsDraftState(options: options)
        draft.portText = text

        draft.synchronize(to: options)
        draft.synchronize(to: options)

        #expect(draft.portText == text)
        #expect(draft.hasUnsavedEdits(comparedTo: options))
    }

    @Test("custom address input stays pending until it matches saved preferences")
    func retainsPendingCustomAddress() {
        var options = HostingOptions(mode: .unified, bindAddress: "192.168.1.20")
        let draft = HostingSettingsDraftState(options: options)
        draft.customAddressText = "192.168.1."
        options.requiresAuthentication = false
        draft.synchronize(to: options)
        draft.synchronize(to: options)
        #expect(draft.customAddressText == "192.168.1.")
        #expect(draft.hasUnsavedEdits(comparedTo: options))

        draft.customAddressText = "100.90.10.2"
        #expect(draft.hasUnsavedEdits(comparedTo: options))
        options.bindAddress = "100.90.10.2"
        // Current preferences release protection even before a SwiftUI refresh.
        #expect(!draft.hasUnsavedEdits(comparedTo: options))
        draft.synchronize(to: options)
        #expect(!draft.hasUnsavedEdits(comparedTo: options))
    }

    @Test("accepted ports release protection without waiting for synchronization")
    func acceptedPortMatchesActualOptions() {
        var options = HostingOptions.default
        let draft = HostingSettingsDraftState(options: options)
        draft.portText = "08123"
        #expect(draft.hasUnsavedEdits(comparedTo: options))
        options.port = 8123
        #expect(!draft.hasUnsavedEdits(comparedTo: options))
        draft.synchronize(to: options)
        #expect(!draft.hasUnsavedEdits(comparedTo: options))
    }

    @Test("each clean buffer follows preference changes independently of the dirty buffer")
    func independentBuffers() {
        var options = HostingOptions(mode: .unified, bindAddress: "192.168.1.20")
        let draft = HostingSettingsDraftState(options: options)
        draft.portText = "65536"
        options.bindAddress = "100.90.10.2"
        draft.synchronize(to: options)
        #expect(draft.portText == "65536")
        #expect(draft.customAddressText == "100.90.10.2")

        draft.discardInputEdits(comparedTo: options)
        draft.customAddressText = "unfinished address"
        options.port = 8123
        draft.synchronize(to: options)
        #expect(draft.portText == "8123")
        #expect(draft.customAddressText == "unfinished address")
        #expect(draft.hasUnsavedEdits(comparedTo: options))
    }

    @Test("an unfinished custom address survives hiding its network section")
    func hiddenAddressRetained() {
        var options = HostingOptions(mode: .unified, bindAddress: "192.168.1.20")
        let draft = HostingSettingsDraftState(options: options)
        draft.customAddressText = "192.168.1."
        options.bindAddress = HostingOptions.loopbackBindAddress
        draft.synchronize(to: options)
        #expect(draft.customAddressText == "192.168.1.")
        #expect(draft.hasUnsavedEdits(comparedTo: options))
        draft.discardInputEdits(comparedTo: options)
        #expect(draft.customAddressText.isEmpty)
        #expect(!draft.hasUnsavedEdits(comparedTo: options))
    }

    @Test("discard restores text from current options without changing preferences or credentials")
    func discardDoesNotWriteStore() throws {
        let suite = "HostingDraft-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = HostingSettingsStore(
            controlStore: nil,
            endpointClient: DraftNoEndpoint(),
            tokenFile: DraftNoTokenFile(),
            cliVersionProvider: { "0.9.7" },
            defaults: defaults,
            lanScanner: { [] }
        )
        #expect(store.setPortText("8123"))
        #expect(store.setBindAddress("192.168.1.20"))
        let originalOptions = store.options
        let originalPreferences = defaults.persistentDomain(forName: suite) as NSDictionary?
        let draft = HostingSettingsDraftState(options: store.options)
        draft.portText = "65536"
        draft.customAddressText = "192.168.1."
        #expect(draft.hasUnsavedEdits(comparedTo: store.options))

        draft.discardInputEdits(comparedTo: store.options)

        #expect(draft.portText == "8123")
        #expect(draft.customAddressText == "192.168.1.20")
        #expect(!draft.hasUnsavedEdits(comparedTo: store.options))
        #expect(store.options == originalOptions)
        #expect((defaults.persistentDomain(forName: suite) as NSDictionary?) == originalPreferences)
        #expect(store.pendingExposureConfirmation == nil)
        #expect(store.localTokenStatusMessage == nil)
    }
}

private struct DraftNoEndpoint: LocalEndpointFetching {
    func fetch() async -> LocalEndpointAvailability {
        Issue.record("Draft edits must not query an endpoint")
        return .none(LocalEndpointClient.noLiveEndpointReason)
    }
}

private struct DraftNoTokenFile: LocalEndpointTokenManaging {
    func withBearerToken(_ action: (String) -> Void) -> Bool {
        Issue.record("Draft edits must not read credentials")
        return false
    }

    func saveBearerToken(_ token: String) throws {
        Issue.record("Draft edits must not save credentials")
    }
}
