import AppKit
import Foundation
import SwiftUI

/// Opt-in proof under the fixture's normal NSApplication.run(). The staged
/// NetworkCacheStore default is FixtureNetworkCache; no live client is built.
@MainActor
enum NetworkCacheVisibilityProof {
    static func run(outputDirectory: URL) async -> Bool {
        let report = CacheVisibilityReport(outputDirectory: outputDirectory)
        var fixture: CacheVisibilityWindow?
        do {
            try cacheRequire(NSApplication.shared.isRunning, "A normal native application run loop is required")
            try report.write(terminal: "running")
            let baseline = await FixtureNetworkCacheProbe.shared.readCount()
            report.baselineReads = baseline
            let owned = CacheVisibilityWindow()
            fixture = owned
            owned.present()

            try await report.check("visible_initial_read") {
                try await waitUntil("Initial cache child/read did not mount") {
                    guard owned.window.isVisible && !owned.window.isMiniaturized
                        && owned.state.isVisible && owned.state.childMounted
                        && owned.state.renderedVisible == true else { return false }
                    return await awaitReadCountIs(baseline + 1)
                }
                return await owned.evidence(baseline: baseline)
            }

            owned.window.miniaturize(nil)
            try await waitUntil("The real native minimize notification did not hide the child") {
                owned.window.isMiniaturized && !owned.state.isVisible
                    && owned.state.renderedVisible == false
            }
            let minimizedReads = await FixtureNetworkCacheProbe.shared.readCount()
            try cacheRequire(minimizedReads == baseline + 1, "Minimizing caused an extra read")
            try await report.check("minimized_no_reads_over_65_seconds") {
                try await holdUnchanged(reads: minimizedReads, stage: "minimized", report: report) {
                    owned.window.isMiniaturized && !owned.state.isVisible
                        && owned.state.childMounted && owned.state.renderedVisible == false
                }
                return await owned.evidence(baseline: baseline)
            }

            let restorationStarted = ContinuousClock.now
            owned.window.deminiaturize(nil)
            try await report.check("restoration_immediate_read") {
                try await waitUntil("Restored cache child did not refresh within five seconds") {
                    guard owned.window.isVisible && !owned.window.isMiniaturized
                        && owned.state.isVisible && owned.state.renderedVisible == true else { return false }
                    return await awaitReadCountIs(baseline + 2)
                }
                var evidence = await owned.evidence(baseline: baseline)
                evidence["restorationReadLatencySeconds"] = seconds(restorationStarted.duration(to: .now))
                return evidence
            }

            owned.state.includesCache = false
            try await waitUntil("Removing the route did not dismantle the real child") { !owned.state.childMounted }
            let absentReads = await FixtureNetworkCacheProbe.shared.readCount()
            try cacheRequire(absentReads == baseline + 2, "Route removal caused an extra read")
            try await report.check("route_absent_no_reads_over_65_seconds") {
                try await holdUnchanged(reads: absentReads, stage: "route-absent", report: report) {
                    owned.window.isVisible && owned.state.isVisible
                        && !owned.state.includesCache && !owned.state.childMounted
                }
                return await owned.evidence(baseline: baseline)
            }

            let reinsertionStarted = ContinuousClock.now
            owned.state.includesCache = true
            try await report.check("route_reinsertion_immediate_read") {
                try await waitUntil("Reinserted cache child did not refresh within five seconds") {
                    guard owned.state.childMounted && owned.state.renderedVisible == true else { return false }
                    return await awaitReadCountIs(baseline + 3)
                }
                var evidence = await owned.evidence(baseline: baseline)
                evidence["reinsertionReadLatencySeconds"] = seconds(reinsertionStarted.duration(to: .now))
                return evidence
            }
        } catch {
            report.failures.append(error is CancellationError ? "Proof cancelled" : error.localizedDescription)
        }

        // A cancelled caller must still let the normal AppKit loop dismantle
        // this owned host. This finite cleanup task never inherits cancellation.
        if let fixture {
            let cleanup = Task { @MainActor in
                report.cleanup = await fixture.close(baseline: report.baselineReads)
            }
            await cleanup.value
            if report.cleanup["passed"] as? Bool != true { report.failures.append("Owned window/child cleanup failed") }
        }
        return report.finish()
    }

    private static func awaitReadCountIs(_ expected: Int) async -> Bool {
        await FixtureNetworkCacheProbe.shared.readCount() == expected
    }

    fileprivate static func waitUntil(_ message: String, condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        repeat {
            try Task.checkCancellation()
            if await condition() { return }
            try await Task.sleep(for: .milliseconds(20))
        } while clock.now < deadline
        throw CacheVisibilityFailure(message)
    }

    private static func holdUnchanged(reads: Int, stage: String, report: CacheVisibilityReport,
        condition: @MainActor () -> Bool) async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let deadline = start.advanced(by: .seconds(65))
        var nextCheckpoint = start
        repeat {
            try Task.checkCancellation()
            try cacheRequire(condition(), "Native \(stage) condition changed during the interval")
            let count = await FixtureNetworkCacheProbe.shared.readCount()
            try cacheRequire(count == reads, "A cache read occurred while \(stage): expected \(reads), observed \(count)")
            if clock.now >= nextCheckpoint {
                report.progress = ["stage": stage, "elapsedSeconds": seconds(start.duration(to: clock.now)),
                    "readCount": count, "expectedReadCount": reads]
                try report.write(terminal: "running")
                nextCheckpoint = clock.now.advanced(by: .seconds(15))
            }
            if clock.now >= deadline { break }
            try await Task.sleep(for: min(.seconds(1), clock.now.duration(to: deadline)))
        } while true
        report.progress = ["stage": stage, "elapsedSeconds": seconds(start.duration(to: clock.now)), "readCount": reads]
    }

    fileprivate static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

@MainActor
private final class CacheVisibilityReport {
    let outputDirectory: URL
    var baselineReads = 0
    var cases: [[String: Any]] = []
    var failures: [String] = []
    var progress: [String: Any] = [:]
    var cleanup: [String: Any] = [:]
    init(outputDirectory: URL) { self.outputDirectory = outputDirectory }

    func check(_ name: String, operation: @MainActor () async throws -> [String: Any]) async throws {
        progress = ["stage": name]
        try write(terminal: "running")
        do {
            let evidence = try await operation()
            cases.append(["name": name, "passed": true, "evidence": evidence])
            try write(terminal: "running")
        } catch {
            cases.append(["name": name, "passed": false, "failure": error.localizedDescription])
            throw error
        }
    }

    func write(terminal: String) throws {
        let passed = terminal == "completed" && cases.count == 5 && failures.isEmpty
            && cases.allSatisfy { $0["passed"] as? Bool == true } && cleanup["passed"] as? Bool == true
        let value: [String: Any] = ["proof": "network-cache-native-visibility", "synthetic": true,
            "assumption": "Runs from Overview with no competing cache view; shared read counter is baselined, never reset.",
            "limits": "Minimize/restore and route remount only; delayed transport cancellation is covered by focused gated tests. No occlusion or accessibility claim.",
            "terminal": terminal, "passed": passed, "baselineReadCount": baselineReads,
            "expectedCaseCount": 5, "completedCaseCount": cases.count, "cases": cases,
            "progress": progress, "cleanup": cleanup, "failures": failures]
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: outputDirectory.appendingPathComponent("network-cache-visibility-proof.json"), options: .atomic)
    }

    func finish() -> Bool {
        do { try write(terminal: "completed") }
        catch { failures.append("Terminal report write failed: \(error.localizedDescription)") }
        let passed = cases.count == 5 && failures.isEmpty && cases.allSatisfy { $0["passed"] as? Bool == true }
            && cleanup["passed"] as? Bool == true
        print("NetworkCacheVisibilityProof TERMINAL_\(passed ? "SUCCESS" : "FAILURE") completed=\(cases.count) expected=5 failures=\(failures.count)")
        return passed
    }
}

@MainActor
private final class CacheVisibilityState: ObservableObject {
    @Published var isVisible = false
    @Published var includesCache = true
    var childMounted = false
    var renderedVisible: Bool?
    var mountCount = 0
    var minimizeNotifications = 0
    var restoreNotifications = 0
}

@MainActor
private struct CacheVisibilityContent: View {
    @ObservedObject var state: CacheVisibilityState
    var body: some View {
        VStack {
            if state.includesCache {
                NetworkCacheView(isVisible: state.isVisible)
                    .background(CacheVisibilityMount(state: state, isVisible: state.isVisible))
            } else {
                Text("Synthetic route without network infrastructure")
            }
        }.padding(16).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
private struct CacheVisibilityMount: NSViewRepresentable {
    let state: CacheVisibilityState
    let isVisible: Bool
    final class Coordinator {
        weak var state: CacheVisibilityState?
        init(_ state: CacheVisibilityState) { self.state = state }
    }
    func makeCoordinator() -> Coordinator { Coordinator(state) }
    func makeNSView(context: Context) -> NSView {
        state.childMounted = true; state.mountCount += 1
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) { state.renderedVisible = isVisible }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.state?.childMounted = false
        coordinator.state?.renderedVisible = nil
    }
}

@MainActor
private final class CacheVisibilityWindow: NSObject, NSWindowDelegate {
    let state: CacheVisibilityState
    let host: NSHostingController<AnyView>
    let window: NSWindow
    override init() {
        let state = CacheVisibilityState()
        self.state = state
        host = NSHostingController(rootView: AnyView(CacheVisibilityContent(state: state)))
        window = NSWindow(contentViewController: host)
        super.init()
        window.title = "Network cache visibility proof — synthetic"
        window.isReleasedWhenClosed = false
        window.styleMask.insert([.miniaturizable, .closable])
        window.setContentSize(NSSize(width: 560, height: 240))
        window.delegate = self
    }
    func present() {
        window.makeKeyAndOrderFront(nil)
        state.isVisible = true
    }
    func windowDidMiniaturize(_ notification: Notification) {
        state.minimizeNotifications += 1; state.isVisible = false
    }
    func windowDidDeminiaturize(_ notification: Notification) {
        state.restoreNotifications += 1; state.isVisible = true
    }
    func windowWillClose(_ notification: Notification) { state.isVisible = false }

    func evidence(baseline: Int) async -> [String: Any] {
        let count = await FixtureNetworkCacheProbe.shared.readCount()
        return ["windowNumber": window.windowNumber, "nativeVisible": window.isVisible,
            "nativeMiniaturized": window.isMiniaturized, "forwardedVisible": state.isVisible,
            "childMounted": state.childMounted, "renderedVisible": state.renderedVisible.map { $0 as Any } ?? NSNull(),
            "mountCount": state.mountCount, "minimizeNotifications": state.minimizeNotifications,
            "restoreNotifications": state.restoreNotifications, "readCount": count, "readsSinceBaseline": count - baseline]
    }
    func close(baseline: Int) async -> [String: Any] {
        state.isVisible = false; state.includesCache = false
        host.rootView = AnyView(EmptyView())
        window.close()
        var failures: [String] = []
        do {
            try await NetworkCacheVisibilityProof.waitUntil("Cleanup did not dismantle the cache child") { !self.state.childMounted }
            let count = await FixtureNetworkCacheProbe.shared.readCount()
            try await Task.sleep(for: .milliseconds(500))
            try cacheRequire(await FixtureNetworkCacheProbe.shared.readCount() == count, "Cache reads continued after cleanup")
        } catch { failures.append(error.localizedDescription) }
        window.delegate = nil
        window.contentViewController = nil
        var result = await evidence(baseline: baseline)
        result["passed"] = failures.isEmpty && !window.isVisible && !state.childMounted
        result["failures"] = failures
        return result
    }
}

private struct CacheVisibilityFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private func cacheRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw CacheVisibilityFailure(message) }
}
