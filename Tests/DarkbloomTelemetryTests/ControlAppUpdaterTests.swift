import Foundation
import Sparkle
import Testing
@testable import DarkbloomMonitor

@MainActor
struct ControlAppUpdaterTests {
    @Test func rejectsIncompleteOrInsecureConfiguration() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        #expect(ControlAppUpdater.hasValidConfiguration(feed: "https://example.com/appcast.xml", publicKey: key))
        for feed in [nil, "", "http://example.com/appcast.xml", "file:///tmp/appcast.xml", "https://user:secret@example.com/appcast.xml"] as [String?] {
            #expect(!ControlAppUpdater.hasValidConfiguration(feed: feed, publicKey: key))
        }
        for invalid in [nil, "", "not-a-key", Data(repeating: 0, count: 31).base64EncodedString()] as [String?] {
            #expect(!ControlAppUpdater.hasValidConfiguration(feed: "https://example.com/appcast.xml", publicKey: invalid))
        }
    }

    @Test func unconfiguredUpdaterCannotEnableOrInstallUpdates() {
        let updater = ControlAppUpdater()
        updater.setAutomaticChecks(true)
        updater.setAutomaticInstall(true)
        updater.check()
        #expect(!updater.isConfigured)
        #expect(!updater.canCheck)
        #expect(!updater.automaticChecks)
        #expect(!updater.automaticInstall)
    }

    @Test("a clean guard lets Sparkle continue without invoking its deferred handler")
    func cleanGuardDoesNotPostpone() async throws {
        let fixture = try InertSparkleFixture()
        defer { fixture.close() }
        let updater = ControlAppUpdater()
        var installs = 0
        #expect(try !postpone(updater, fixture: fixture) { installs += 1 })
        await Task.yield()
        #expect(installs == 0)
        #expect(!updater.isConfigured)
        fixture.expectNoPreferencesWritten()
    }

    @Test("a blocked guard resumes its actual Sparkle handler exactly once after clearing")
    func blockedGuardResumesOnce() async throws {
        let fixture = try InertSparkleFixture()
        defer { fixture.close() }
        let updater = ControlAppUpdater()
        let guardState = RelaunchGuardState()
        updater.canRelaunch = { guardState.check() }
        var installs = 0
        #expect(try postpone(updater, fixture: fixture) { installs += 1 })
        try await waitUntil { guardState.checks >= 2 }
        #expect(installs == 0)
        guardState.allowed = true
        try await waitUntil { installs == 1 }
        let checksAfterInstall = guardState.checks
        try await Task.sleep(for: .milliseconds(1100))
        #expect(installs == 1)
        #expect(guardState.checks == checksAfterInstall)
        fixture.expectNoPreferencesWritten()
    }

    @Test("a replacement blocked callback cancels the old deferred handler")
    func blockedReplacementCancelsOldHandler() async throws {
        let fixture = try InertSparkleFixture()
        defer { fixture.close() }
        let updater = ControlAppUpdater()
        let guardState = RelaunchGuardState()
        updater.canRelaunch = { guardState.check() }
        var oldInstalls = 0, newInstalls = 0
        #expect(try postpone(updater, fixture: fixture) { oldInstalls += 1 })
        try await waitUntil { guardState.checks >= 2 }
        #expect(try postpone(updater, fixture: fixture) { newInstalls += 1 })
        guardState.allowed = true
        try await waitUntil { newInstalls == 1 }
        try await Task.sleep(for: .milliseconds(1100))
        #expect(oldInstalls == 0)
        #expect(newInstalls == 1)
        fixture.expectNoPreferencesWritten()
    }

    @Test("a clean replacement cancels the old handler before handing control back to Sparkle")
    func cleanReplacementCancelsOldHandler() async throws {
        let fixture = try InertSparkleFixture()
        defer { fixture.close() }
        let updater = ControlAppUpdater()
        let guardState = RelaunchGuardState()
        updater.canRelaunch = { guardState.check() }
        var oldInstalls = 0, newInstalls = 0
        #expect(try postpone(updater, fixture: fixture) { oldInstalls += 1 })
        try await waitUntil { guardState.checks >= 2 }
        guardState.allowed = true
        #expect(try !postpone(updater, fixture: fixture) { newInstalls += 1 })
        try await Task.sleep(for: .milliseconds(1100))
        #expect(oldInstalls == 0)
        #expect(newInstalls == 0)
        fixture.expectNoPreferencesWritten()
    }

    @Test("releasing the updater before polling starts never invokes a deferred install")
    func releasedBeforePollingDoesNotInstall() async throws {
        let fixture = try InertSparkleFixture()
        defer { fixture.close() }
        var updater: ControlAppUpdater? = ControlAppUpdater()
        updater?.canRelaunch = { false }
        weak let releasedUpdater = updater
        var installs = 0
        #expect(try postpone(#require(updater), fixture: fixture) { installs += 1 })
        updater = nil
        #expect(releasedUpdater == nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(installs == 0)
        fixture.expectNoPreferencesWritten()
    }

    @Test("blocked polling does not keep its updater owner alive")
    func releasedWhilePollingDoesNotInstall() async throws {
        let fixture = try InertSparkleFixture()
        defer { fixture.close() }
        var updater: ControlAppUpdater? = ControlAppUpdater()
        let guardState = RelaunchGuardState()
        updater?.canRelaunch = { guardState.check() }
        weak let releasedUpdater = updater
        var installs = 0
        #expect(try postpone(#require(updater), fixture: fixture) { installs += 1 })
        try await waitUntil { guardState.checks >= 2 }
        updater = nil
        #expect(releasedUpdater == nil)
        // Release even the buggy task after the assertion, so a failed run
        // cannot leave a polling owner alive beyond this test.
        guardState.allowed = true
        try await Task.sleep(for: .milliseconds(1100))
        #expect(installs == 0)
        fixture.expectNoPreferencesWritten()
    }

    private func postpone(_ updater: ControlAppUpdater, fixture: InertSparkleFixture,
                          handler: @escaping () -> Void) throws -> Bool {
        let delegate: any SPUUpdaterDelegate = updater
        return try #require(delegate.updater?(fixture.updater,
            shouldPostponeRelaunchForUpdate: fixture.item, untilInvokingBlock: handler) as Bool?)
    }

    private func waitUntil(_ condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(condition(), "The deferred Sparkle callback did not reach its expected state")
    }
}

@MainActor
private final class RelaunchGuardState {
    var allowed = false
    var checks = 0

    func check() -> Bool {
        checks += 1
        return allowed
    }
}

/// Real Sparkle inputs, scoped to a disposable bundle. Initialization alone
/// does not start update checks; no start or preference setter is called.
@MainActor
private struct InertSparkleFixture {
    let namespace = "ControlAppUpdaterTests-\(UUID().uuidString)"
    let bundleURL: URL
    let updater: SPUUpdater
    let item = SUAppcastItem.empty()

    init() throws {
        bundleURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(namespace).appendingPathExtension("bundle")
        let contents = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": namespace, "CFBundleName": "Inert updater fixture",
                                  "CFBundleVersion": "1", "CFBundleShortVersionString": "1.0"]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
        let bundle = try #require(Bundle(url: bundleURL))
        let driver = SPUStandardUserDriver(hostBundle: bundle, delegate: nil)
        updater = SPUUpdater(hostBundle: bundle, applicationBundle: bundle, userDriver: driver, delegate: nil)
    }

    func expectNoPreferencesWritten() {
        #expect(UserDefaults.standard.persistentDomain(forName: namespace) == nil)
        #expect(!updater.sessionInProgress)
    }

    func close() {
        try? FileManager.default.removeItem(at: bundleURL)
    }
}
