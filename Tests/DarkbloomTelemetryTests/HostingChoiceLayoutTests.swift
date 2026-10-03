import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Hosting choice layout")
@MainActor
struct HostingChoiceLayoutTests {
    @Test("adaptive columns retain the minimum width and clamp to the choice count")
    func columns() {
        #expect(HostingChoiceLayout.columns(width: 421, minimumWidth: 205, spacing: 12, count: 3) == 1)
        #expect(HostingChoiceLayout.columns(width: 422, minimumWidth: 205, spacing: 12, count: 3) == 2)
        #expect(HostingChoiceLayout.columns(width: 639, minimumWidth: 205, spacing: 12, count: 3) == 3)
        #expect(HostingChoiceLayout.columns(width: 1200, minimumWidth: 205, spacing: 12, count: 2) == 2)
    }

    @Test("earnings filters keep equal bounded widths in compact and wide layouts")
    func filterWidths() {
        let compactColumns = AdaptiveChoiceLayout.columns(width: 550, minimumWidth: 145, spacing: 8, count: 5)
        #expect(compactColumns == 3)
        #expect(AdaptiveChoiceLayout.choiceWidth(width: 550, columns: compactColumns, spacing: 8, maximumWidth: 190) == 178)
        #expect(AdaptiveChoiceLayout.choiceWidth(width: 1020, columns: 5, spacing: 8, maximumWidth: 190) == 190)
        #expect(AdaptiveChoiceLayout.choiceWidth(width: 550, columns: 2, spacing: 8, maximumWidth: 190) == 190)
        #expect(AdaptiveChoiceLayout.choiceWidth(width: 120, columns: 1, spacing: 8, maximumWidth: 190) == 120)
        #expect(AdaptiveChoiceLayout.choiceWidth(width: 422, columns: 2, spacing: 12) == 205)
    }

    @Test("all historical filter controls mount without a visible-row limit", arguments: [5, 30])
    func mountedFilters(count: Int) async {
        let root = ScrollView {
            AdaptiveChoiceLayout(minimumWidth: 145, spacing: 8, maximumWidth: 190) {
                ForEach(0..<count, id: \.self) { index in
                    Button("Model \(index)") {}.modifier(ScrollControlKeyboardReveal())
                        .frame(maxWidth: .infinity).frame(height: 30)
                }
            }
        }.frame(width: 550, height: 40)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: 550, height: 40))
        host.view.layoutSubtreeIfNeeded()
        await Task.yield()
        host.view.layoutSubtreeIfNeeded()
        #expect(anchors(in: host.view).count == count)
    }

    @Test("offscreen choice controls mount on the first layout", arguments: [1, 2, 3])
    func mountedChoices(columns: Int) async {
        let width = CGFloat(columns) * 205 + CGFloat(columns - 1) * 12
        let root = ScrollView {
            HostingChoiceLayout(minimumWidth: 205, spacing: 12) {
                ForEach(0..<3) { _ in
                    Button("Choice") {}.modifier(ScrollControlKeyboardReveal())
                        .frame(height: 160)
                }
            }
        }.frame(width: width, height: 80)
        let host = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.setContentSize(NSSize(width: width, height: 80))
        host.view.layoutSubtreeIfNeeded()
        await Task.yield()
        host.view.layoutSubtreeIfNeeded()
        #expect(anchors(in: host.view).count == 3)
    }

    private func anchors(in view: NSView) -> [KeyboardFocusRevealAnchorView] {
        (view as? KeyboardFocusRevealAnchorView).map { [$0] } ?? view.subviews.flatMap { anchors(in: $0) }
    }
}
