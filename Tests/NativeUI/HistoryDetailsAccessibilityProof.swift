// Opt-in native proof. SwiftPM's hosted windows do not reliably expose this
// SwiftUI accessibility tree; run under the inert app's NSApplication.run().
import AppKit
import SwiftUI
import DarkbloomTelemetry

@MainActor
enum HistoryDetailsAccessibilityProof {
    static func run(outputDirectory: URL) async -> [String: Any] {
        var failures: [String] = []
        var observed: [[String: Any]] = []
        let scratch = outputDirectory.appendingPathComponent("history-fields-\(UUID())")
        do {
            let url = scratch.appendingPathComponent("actions.sqlite")
            let database = try ActionHistoryDatabase(url: url)
            let event = ActionHistoryEvent(id: UUID(), occurredAt: Date(), action: .job,
                trigger: .provider, outcome: .succeeded, model: "gemma-4-26b-qat-4bit",
                job: .init(earningID: 14998, promptTokens: 120, completionTokens: 40, amountMicroUSD: 199))
            try database.record(event)
            let store = ActionHistoryStore(url: url)
            let host = NSHostingController(rootView: ActionHistoryView(store: store, selectedID: event.id))
            let window = NSWindow(contentViewController: host)
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 550, height: 650))
            window.orderFront(nil)
            defer { window.close() }
            try await Task.sleep(for: .milliseconds(200))
            host.view.layoutSubtreeIfNeeded()
            let nodes = descendants(window)
            let fields = nodes.filter { (attribute($0, "accessibilityIdentifier") as? String)?.hasPrefix("actionHistory.field.") == true }
            if fields.count != 9 { failures.append("Expected 9 independent field groups; observed \(fields.count)") }
            let expected: [(String, String?)] = [("Time", nil), ("Action", "Job"),
                ("Trigger", "Provider"), ("Result", "Succeeded"), ("Model", "Gemma 4 · 26B"),
                ("Earning ID (not request ID)", "14,998"), ("Prompt tokens", "120"),
                ("Completion tokens", "40"), ("Reported amount", "$0.000199")]
            for (label, expectedValue) in expected {
                let matched = fields.filter { attribute($0, "accessibilityIdentifier") as? String == "actionHistory.field.\(label)" }
                guard matched.count == 1, let field = matched.first else {
                    failures.append("Missing or duplicate native field: \(label)"); continue
                }
                let values = descendants(field).flatMap(strings)
                observed.append(["label": label, "values": values])
                if !values.contains(label) { failures.append("Missing native caption: \(label)") }
                if let expectedValue, !values.contains(expectedValue) { failures.append("Missing exact value for \(label): \(expectedValue)") }
            }
            if !nodes.flatMap(strings).contains(where: { $0.contains("Account-wide earnings record") }) {
                failures.append("Missing account-wide qualification")
            }
        } catch { failures.append(error.localizedDescription) }
        let result: [String: Any] = ["synthetic": true, "terminal": failures.isEmpty ? "success" : "failure",
            "success": failures.isEmpty, "expectedFieldCount": 9, "fields": observed, "failures": failures]
        do {
            let data = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: outputDirectory.appendingPathComponent("history-fields-accessibility-proof.json"), options: .atomic)
        } catch { return ["synthetic": true, "terminal": "failure", "success": false, "failures": ["Could not save proof: \(error.localizedDescription)"]] }
        return result
    }

    private static func attribute(_ node: NSObject, _ key: String) -> Any? {
        guard node.responds(to: NSSelectorFromString(key)) else { return nil }
        return node.value(forKey: key)
    }
    private static func strings(_ node: NSObject) -> [String] {
        ["accessibilityLabel", "accessibilityTitle", "accessibilityValue"].compactMap { attribute(node, $0) as? String }
    }
    private static func descendants(_ root: NSObject) -> [NSObject] {
        var nodes: [NSObject] = [], seen: Set<ObjectIdentifier> = []
        func visit(_ node: NSObject) {
            guard seen.insert(ObjectIdentifier(node)).inserted, nodes.count < 500 else { return }
            nodes.append(node)
            for child in attribute(node, "accessibilityChildren") as? [NSObject] ?? [] { visit(child) }
            if let window = node as? NSWindow, let content = window.contentView { visit(content) }
            if let view = node as? NSView {
                if let unignored = NSAccessibility.unignoredDescendant(of: view) as? NSObject { visit(unignored) }
                for child in view.subviews { visit(child) }
            }
        }
        visit(root)
        return nodes
    }
}
