import AppKit
import Foundation

/// Read-only geometry evidence for the existing synthetic dashboard window.
/// This never opens a window, sends UI events, or touches provider state.
@MainActor
enum ModelFeedbackLayoutProof {
    struct Rect: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double

        init(_ rect: NSRect) {
            x = Double(rect.origin.x)
            y = Double(rect.origin.y)
            width = Double(rect.width)
            height = Double(rect.height)
        }
    }

    struct Check: Codable {
        let name: String
        let passing: Bool
        let detail: String
    }

    struct Measurement: Codable {
        let name: String
        let rect: Rect
        let maximumOverflowPoints: Double
    }

    struct Result: Codable {
        var proof = "model-feedback-layout"
        let passing: Bool
        let tolerancePoints: Double
        let nativeViewCount: Int
        let accessibilityNodeCount: Int
        let splitViewCandidateCount: Int
        let checks: [Check]
        let measurements: [Measurement]
        let limitations: [String]
    }

    static func run(window: NSWindow) -> Result {
        let tolerance: CGFloat = 2
        var checks: [Check] = []
        var measurements: [Measurement] = []
        var limitations = [
            "This captures current geometry; the caller must select the feedback state and window size before running it.",
            "Only the dashboard split and identified persistent footer controls are constrained; scroll documents and sidebar rows may extend offscreen."
        ]
        func check(_ name: String, _ passing: Bool, _ detail: String) {
            checks.append(.init(name: name, passing: passing, detail: detail))
        }
        guard let content = window.contentView else {
            return Result(passing: false, tolerancePoints: Double(tolerance), nativeViewCount: 0,
                          accessibilityNodeCount: 0, splitViewCandidateCount: 0,
                          checks: [.init(name: "content-view", passing: false, detail: "Window has no content view.")],
                          measurements: [], limitations: limitations)
        }
        content.layoutSubtreeIfNeeded()
        let container = content.bounds
        check("content-geometry", valid(container), "Content bounds must have finite coordinates and positive dimensions.")
        check("content-size", abs(content.frame.width - container.width) <= tolerance &&
              abs(content.frame.height - container.height) <= tolerance,
              "Content bounds and current native content frame must agree within 2 points.")
        measurements.append(.init(name: "content-bounds", rect: Rect(container), maximumOverflowPoints: 0))

        // Inspect only this window's content hierarchy. Sheets have separate
        // content views and must never become dashboard candidates.
        let views = nativeViews(root: content)
        check("bounded-native-traversal", !views.truncated, "Native view traversal is bounded to 2,000 nodes and 128 levels.")
        let candidates = views.nodes.filter { node in
            guard node.view is NSSplitView else { return false }
            var ancestor = node.view.superview
            while let view = ancestor, view !== content {
                if view is NSSplitView || view is NSScrollView { return false }
                ancestor = view.superview
            }
            return true
        }
        let shallowest = candidates.map(\.depth).min()
        let main = candidates.filter { $0.depth == shallowest }
        check("dashboard-split-identity", main.count == 1,
              "Expected exactly one shallowest dashboard NSSplitView outside scroll documents; found \(main.count).")
        if let split = main.first?.view, main.count == 1 {
            let rect = split.convert(split.bounds, to: content)
            let overflow = maximumOverflow(rect, container: container)
            measurements.append(.init(name: "dashboard-split", rect: Rect(rect), maximumOverflowPoints: Double(overflow)))
            check("dashboard-split-geometry", valid(rect), "Dashboard split must have finite coordinates and positive dimensions.")
            check("dashboard-split-contained", valid(rect) && overflow <= tolerance,
                  "Dashboard split must remain inside content bounds within 2 points; maximum overflow is \(Double(overflow)) points.")
        }

        // SwiftUI controls often have AX elements rather than NSView objects.
        // Read their public native frames without pressing or focusing them.
        let accessibility = accessibilityNodes(root: content)
        check("bounded-accessibility-traversal", !accessibility.truncated,
              "Accessibility traversal is bounded to 2,000 nodes and 128 levels.")
        var measuredFooterCount = 0
        for identifier in ["models.save", "models.apply-live"] {
            let matches = accessibility.nodes.filter {
                attribute("accessibilityIdentifier", of: $0) as? String == identifier &&
                (attribute("accessibilityHidden", of: $0) as? Bool != true)
            }
            guard !matches.isEmpty else { continue }
            check("\(identifier)-identity", matches.count == 1, "Expected one native footer control for \(identifier); found \(matches.count).")
            for (index, match) in matches.enumerated() {
                guard let screenFrame = (attribute("accessibilityFrame", of: match) as? NSValue)?.rectValue else {
                    limitations.append("\(identifier) has no readable native accessibility frame.")
                    check("\(identifier)-frame-available", false, "Identified footer control must expose its native frame.")
                    continue
                }
                let rect = content.convert(window.convertFromScreen(screenFrame), from: nil)
                let overflow = maximumOverflow(rect, container: container)
                measuredFooterCount += 1
                measurements.append(.init(name: "\(identifier).\(index)", rect: Rect(rect), maximumOverflowPoints: Double(overflow)))
                check("\(identifier)-contained-\(index)", valid(rect) && overflow <= tolerance,
                      "Persistent footer control must have positive dimensions and remain inside content bounds within 2 points.")
            }
        }
        if measuredFooterCount == 0 {
            limitations.append("No identified Models footer controls were measured; split containment is the regression check for this capture.")
        }
        return Result(passing: checks.allSatisfy(\.passing), tolerancePoints: Double(tolerance),
                      nativeViewCount: views.nodes.count, accessibilityNodeCount: accessibility.nodes.count,
                      splitViewCandidateCount: candidates.count, checks: checks,
                      measurements: measurements, limitations: limitations)
    }

    private static func valid(_ rect: NSRect) -> Bool {
        [rect.origin.x, rect.origin.y, rect.width, rect.height].allSatisfy(\.isFinite) && rect.width > 0 && rect.height > 0
    }

    private static func maximumOverflow(_ rect: NSRect, container: NSRect) -> CGFloat {
        guard valid(rect), valid(container) else { return .greatestFiniteMagnitude }
        return max(0, container.minX - rect.minX, container.minY - rect.minY,
                   rect.maxX - container.maxX, rect.maxY - container.maxY)
    }

    private static func nativeViews(root: NSView) -> (nodes: [(view: NSView, depth: Int)], truncated: Bool) {
        var nodes: [(view: NSView, depth: Int)] = []
        var pending = [(view: root, depth: 0)]
        var truncated = false
        while let node = pending.popLast() {
            guard nodes.count < 2_000 else { truncated = true; break }
            guard node.depth <= 128 else { truncated = true; continue }
            nodes.append(node)
            pending.append(contentsOf: node.view.subviews.map { (view: $0, depth: node.depth + 1) })
        }
        return (nodes, truncated)
    }

    private static func attribute(_ getter: String, of object: NSObject) -> Any? {
        guard object.responds(to: NSSelectorFromString(getter)) else { return nil }
        return object.value(forKey: getter)
    }

    private static func accessibilityNodes(root: NSView) -> (nodes: [NSObject], truncated: Bool) {
        var nodes: [NSObject] = []
        var pending: [(object: NSObject, depth: Int)] = [(root, 0)]
        var seen = Set<ObjectIdentifier>()
        var truncated = false
        while let node = pending.popLast() {
            guard seen.insert(ObjectIdentifier(node.object)).inserted else { continue }
            guard nodes.count < 2_000 else { truncated = true; break }
            guard node.depth <= 128 else { truncated = true; continue }
            nodes.append(node.object)
            let children = attribute("accessibilityChildren", of: node.object) as? [Any] ?? []
            pending.append(contentsOf: children.compactMap { child in
                (child as? NSObject).map { (object: $0, depth: node.depth + 1) }
            })
            if let view = node.object as? NSView {
                if let descendant = NSAccessibility.unignoredDescendant(of: view) as? NSObject {
                    pending.append((descendant, node.depth + 1))
                }
                pending.append(contentsOf: view.subviews.map { (object: $0, depth: node.depth + 1) })
            }
        }
        return (nodes, truncated)
    }
}
