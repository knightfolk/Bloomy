import AppKit
import Foundation

/// Standalone, unshown AppKit regression. Compile with ModelFeedbackLayoutProof.swift.
/// The failing rectangle comes from the rejected Native153 dashboard trace.
@main
@MainActor
enum ModelFeedbackLayoutRegression {
    static func main() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let content = try require(window.contentView)
        let split = NSSplitView(frame: content.bounds)
        content.addSubview(split)

        let contained = ModelFeedbackLayoutProof.run(window: window)
        precondition(contained.passing, "Contained baseline must pass the native geometry proof.")

        split.frame = NSRect(x: 0, y: -149, width: 1280, height: 1083)
        let overflowing = ModelFeedbackLayoutProof.run(window: window)
        precondition(!overflowing.passing, "Observed Native153 overflow must fail.")
        precondition(overflowing.checks.contains { $0.name == "dashboard-split-contained" && !$0.passing })
        precondition(overflowing.measurements.contains {
            $0.name == "dashboard-split" && $0.maximumOverflowPoints == 149
        })
        let decoded = try JSONDecoder().decode(ModelFeedbackLayoutProof.Result.self,
                                               from: JSONEncoder().encode(overflowing))
        precondition(!decoded.passing && decoded.measurements.count == overflowing.measurements.count)
        print("PASS: contained baseline accepted; observed Native153 geometry rejected with 149pt overflow; Codable round trip passed.")
    }

    private static func require<T>(_ value: T?) throws -> T {
        guard let value else { throw CocoaError(.coderValueNotFound) }
        return value
    }
}
