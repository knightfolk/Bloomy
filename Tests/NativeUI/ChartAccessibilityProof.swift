// Opt-in synthetic proof under the fixture's normal NSApplication.run().
// It never reads provider preferences or invokes a real telemetry reader.
import AppKit
import Foundation
import SwiftUI
import DarkbloomTelemetry

@MainActor
enum ChartAccessibilityProof {
    static func run(outputDirectory: URL) async -> Bool {
        var cases: [[String: Any]] = []
        var failures: [String] = []
        func report(terminal: String) throws {
            let passed = terminal == "completed" && cases.count == 2 && failures.isEmpty
            let value: [String: Any] = ["proof": "chart-accessibility", "synthetic": true,
                "terminal": terminal, "passed": passed, "expectedCaseCount": 2,
                "completedcases": cases.map { $0["name"] as? String ?? "" },
                "cases": cases, "failures": failures]
            try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputDirectory.appendingPathComponent("chart-accessibility-proof.json"), options: .atomic)
        }
        do { try report(terminal: "running") }
        catch { failures.append("Initial report write failed: \(error.localizedDescription)") }
        for stale in [false, true] {
            let caseName = stale ? "stale-metrics-refresh" : "empty-metrics-refresh"
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let samples = stale ? [PerformanceSample(
                observedAt: now.addingTimeInterval(-120), sourceCapturedAt: now.addingTimeInterval(-120),
                quality: .stale, providerSession: "fixture", model: "gemma", residentModels: ["gemma"],
                advertisedModels: ["gemma"], inferenceActive: true, tokensPerSecond: 30
            )] : []
            var refreshes = 0
            let host = NSHostingController(rootView: PerformanceMetricsContent(
                samples: samples, recordingStartedAt: nil, now: now, onRefresh: { refreshes += 1 }
            ))
            let window = NSWindow(contentViewController: host)
            window.isReleasedWhenClosed = false
            window.title = "Chart accessibility proof — synthetic"
            window.setContentSize(NSSize(width: 570, height: 650))
            window.makeKeyAndOrderFront(nil)
            var result: [String: Any] = ["name": caseName, "passed": false]
            do {
                let elements = try await readyChartAccessibilityDescendants(of: window, identifier: "activity.metrics.refresh")
                let buttons = elements.filter { chartAccessibilityAttribute("accessibilityRole", of: $0) as? String == "AXButton" }
                let matches = buttons.filter { chartAccessibilityName(of: $0) == "Refresh metrics" }
                result["matchingButtonCount"] = matches.count
                result["nativeNodeCount"] = elements.count
                if matches.count != 1 {
                    print("ChartAXDiagnostics case=\(caseName): \(chartAccessibilitySummary(elements))")
                }
                try chartRequire(matches.count == 1, "Expected exactly one native AXButton named Refresh metrics; found \(matches.count)")
                let refresh = matches[0]
                let identifier = chartAccessibilityAttribute("accessibilityIdentifier", of: refresh) as? String ?? ""
                result["identifier"] = identifier
                try chartRequire(identifier == "activity.metrics.refresh", "Refresh metrics native identifier is incorrect")
                try chartRequire(!buttons.contains { chartAccessibilityName(of: $0).contains("samples, Refresh metrics") },
                    "Recording status is folded into the Refresh button's name")
                try pressChartAccessibilityButton(refresh)
                try await Task.sleep(for: .milliseconds(100))
                result["refreshCallbackCount"] = refreshes
                try chartRequire(refreshes == 1, "One native press must invoke the refresh callback exactly once")
                if stale {
                    try chartRequire(PerformanceMetricsPresentation.ratePoints(samples: samples).isEmpty,
                        "Stale observations must not invent measured-speed points")
                }
                result["passed"] = true
            } catch {
                let message = "\(caseName): \(error.localizedDescription)"
                result["failure"] = message
                failures.append(message)
            }
            window.close() // The fixture keeps its anchor window until all proofs finish.
            cases.append(result)
            do { try report(terminal: "running") }
            catch { failures.append("Case report write failed: \(error.localizedDescription)") }
        }
        do { try report(terminal: "completed") }
        catch { failures.append("Terminal report write failed: \(error.localizedDescription)") }
        let passed = cases.count == 2 && failures.isEmpty
        print("ChartAccessibilityProof TERMINAL_\(passed ? "SUCCESS" : "FAILURE") completed=\(cases.count) expected=2 failures=\(failures.count)")
        return passed
    }
}

private struct ChartAccessibilityFailure: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

private func chartRequire(_ condition: Bool, _ message: String) throws {
    if !condition { throw ChartAccessibilityFailure(message) }
}

@MainActor
private func chartAccessibilityAttribute(_ getter: String, of object: NSObject) -> Any? {
    guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
    return object.value(forKey: getter)
}

@MainActor
private func chartAccessibilityDescendants(of root: NSObject) -> [NSObject] {
    var result: [NSObject] = []
    var seen = Set<ObjectIdentifier>()
    func visit(_ object: NSObject) {
        guard seen.insert(ObjectIdentifier(object)).inserted, result.count < 2_000 else { return }
        result.append(object)
        for child in chartAccessibilityAttribute("accessibilityChildren", of: object) as? [Any] ?? [] {
            if let child = child as? NSObject { visit(child) }
        }
        // Some AppKit accessibility roots omit ignored native containers.
        // Seed their actual content as well and ask for its public unignored
        // descendant; all resulting controls still require native AX identity.
        if let window = object as? NSWindow, let content = window.contentView { visit(content) }
        if let view = object as? NSView {
            if let descendant = NSAccessibility.unignoredDescendant(of: view) as? NSObject { visit(descendant) }
            for child in view.subviews { visit(child) }
        }
    }
    visit(root)
    return result
}

@MainActor
private func readyChartAccessibilityDescendants(of window: NSWindow, identifier: String) async throws -> [NSObject] {
    let deadline = Date().addingTimeInterval(8)
    var elements: [NSObject] = []
    repeat {
        try await Task.sleep(for: .milliseconds(50))
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        // The normal app run loop owns event dispatch; this only yields.
        elements = chartAccessibilityDescendants(of: window)
        if elements.contains(where: { chartAccessibilityAttribute("accessibilityIdentifier", of: $0) as? String == identifier }) {
            return elements
        }
    } while Date() < deadline
    return elements // The caller still requires exactly one named AXButton.
}

@MainActor
private func chartAccessibilityName(of object: NSObject) -> String {
    for key in ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"] {
        if let value = chartAccessibilityAttribute(key, of: object) as? String, !value.isEmpty { return value }
    }
    return ""
}

@MainActor
private func chartAccessibilitySummary(_ objects: [NSObject]) -> String {
    objects.prefix(80).map { object in
        let role = chartAccessibilityAttribute("accessibilityRole", of: object) as? String ?? "none"
        let label = chartAccessibilityAttribute("accessibilityLabel", of: object) as? String ?? "nil"
        let title = chartAccessibilityAttribute("accessibilityTitle", of: object) as? String ?? "nil"
        let identifier = chartAccessibilityAttribute("accessibilityIdentifier", of: object) as? String ?? "nil"
        return "\(type(of: object))[role=\(role); label=\(label); title=\(title); id=\(identifier)]"
    }.joined(separator: " | ")
}

@MainActor
private func pressChartAccessibilityButton(_ object: NSObject) throws {
    let selector = NSSelectorFromString("accessibilityPerformPress")
    try chartRequire(object.responds(to: selector), "Refresh metrics must expose a native press action")
    // SwiftUI's private accessibility elements implement this BOOL action
    // without necessarily declaring one of AppKit's public button protocols.
    typealias Press = @convention(c) (AnyObject, Selector) -> Bool
    let invoke = unsafeBitCast(object.method(for: selector), to: Press.self)
    try chartRequire(invoke(object, selector), "The native Refresh metrics press was rejected")
}
