import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Compact popover card geometry")
@MainActor
struct CompactPopoverCardLayoutTests {
    @Test("mixed advertised and available cards keep one size in three columns")
    func mixedCardSizes() throws {
        let width: CGFloat = 170
        let speed = ModelCardMetric(id: "speed", symbol: "speedometer",
                                    value: "124.7", caption: "avg tok/s today")
        let earnings = ModelCardMetric(id: "earnings", symbol: "dollarsign.circle",
                                       value: "$0.0124", caption: "est. net / active h")
        let cases: [(String, [ModelCardMetric], Bool, Bool)] = [
            ("EigenLabs/Qwen3.8-27B-4bit-mtp", [], false, false),
            ("gemma-4-26b-qat-4bit", [speed], false, true),
            ("nvidia-nemotron-3.5-lightning", [speed, earnings], false, false),
            ("qwen3.6-35b-a3b-vl-mtp-mxfp8", [], true, true),
            ("qwen3-vl-30b-a3b-instruct", [speed], true, false),
            ("ternary-bonsai-2-27b", [speed, earnings], true, true),
        ]

        for (id, metrics, activate, useOnly) in cases {
            let card = CompactModelCard(
                modelID: id, status: activate ? "Downloaded" : useOnly ? "Loads on request" : "In memory",
                metrics: metrics, compact: true, compactWidth: width,
                activate: activate ? {} : nil,
                activationUnavailableReason: activate ? "Refresh model controls before activating a model" : nil,
                swapModel: !activate && useOnly ? {} : nil,
                switchModel: useOnly ? {} : nil,
                switchUnavailableReason: useOnly ? "Refresh current provider state before switching" : nil
            )
            let size = NSHostingController(rootView: card).sizeThatFits(in: NSSize(width: width, height: 0))
            #expect(size.width == width)
            #expect(size.height == CompactModelCard.popupHeight)
        }

        let grid = LazyVGrid(columns: Array(repeating: GridItem(.fixed(width), spacing: 8), count: 3),
                             alignment: .leading, spacing: 8) {
            ForEach(cases.indices, id: \.self) { index in
                let (id, metrics, activate, useOnly) = cases[index]
                CompactModelCard(
                    modelID: id, status: activate ? "Downloaded" : useOnly ? "Loads on request" : "In memory",
                    metrics: metrics, compact: true, compactWidth: width,
                    activate: activate ? {} : nil,
                    swapModel: !activate && useOnly ? {} : nil,
                    switchModel: useOnly ? {} : nil
                )
            }
        }
        .frame(width: width * 3 + 16)
        .background(Color(nsColor: .windowBackgroundColor))
        let host = NSHostingController(rootView: grid)
        let size = host.sizeThatFits(in: NSSize(width: width * 3 + 16, height: 0))
        #expect(size.width == width * 3 + 16)
        #expect(size.height == CompactModelCard.popupHeight * 2 + 8)

        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(size)
        window.orderBack(nil)
        defer { window.close() }
        host.view.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.view.bitmapImageRepForCachingDisplay(in: host.view.bounds))
        host.view.cacheDisplay(in: host.view.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: "/tmp/darkbloom-mixed-compact-cards.png"))
    }
}
