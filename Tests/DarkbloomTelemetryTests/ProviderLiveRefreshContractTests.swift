import Foundation
import Testing
@testable import DarkbloomTelemetry

/// Explicit opt-in for read-only verification against this Mac's provider.
@Suite("Live provider model refresh")
struct ProviderLiveRefreshContractTests {
    @Test("current provider model controls refresh from real sources", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_LIVE_READ_PROBE"] == "1"))
    func liveModelRefresh() async throws {
        let policy = DarkbloomSourcePolicy.currentUser
        let runner = CappedProcessRunner()
        let executable = try #require(policy.cliCandidates.first { FileManager.default.isExecutableFile(atPath: $0.path) })
        let store = LocalProviderConfigStore(configURL: policy.providerConfig, executable: executable, runner: runner)
        let source = LocalTelemetrySource(policy: policy, runner: runner)
        let service = ProviderControlService(policy: policy, telemetrySource: source, configStore: store, runner: runner)
        let snapshot = try await service.refresh()
        #expect(snapshot.sources.catalog.isMarkedFresh)
        #expect(snapshot.sources.localModels.isMarkedFresh)
        #expect(!snapshot.inventory.myCatalog.isEmpty || !snapshot.inventory.available.isEmpty)
    }
}
