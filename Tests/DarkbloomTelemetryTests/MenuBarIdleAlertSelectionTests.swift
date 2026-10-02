import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Menu-bar idle alert selection")
@MainActor
struct MenuBarIdleAlertSelectionTests {
    @Test("unknown preferences display the runtime default without rewriting storage", arguments: [99, -1])
    func unknownSelection(rawValue: Int) {
        var stored = rawValue
        let selection = MenuBarIdleAlertSelection.binding(to: Binding(get: { stored }, set: { stored = $0 }))

        #expect(selection.wrappedValue == 5)
        #expect(MenuBarAttentionPolicy.threshold(for: stored) == MenuBarAttentionPolicy.threshold(for: selection.wrappedValue))
        #expect(stored == rawValue)
    }

    @Test("supported preferences retain their selected option", arguments: MenuBarAttentionPolicy.supportedMinutes)
    func supportedSelection(rawValue: Int) {
        var stored = rawValue
        let selection = MenuBarIdleAlertSelection.binding(to: Binding(get: { stored }, set: { stored = $0 }))

        #expect(selection.wrappedValue == rawValue)
        #expect(stored == rawValue)
    }

    @Test("choosing Off replaces an unknown preference and disables the alert")
    func chooseOff() {
        var stored = 99
        let selection = MenuBarIdleAlertSelection.binding(to: Binding(get: { stored }, set: { stored = $0 }))

        selection.wrappedValue = 0
        #expect(stored == 0)
        #expect(selection.wrappedValue == 0)
        #expect(MenuBarAttentionPolicy.threshold(for: stored) == nil)

        selection.wrappedValue = 10
        #expect(stored == 10)
        #expect(selection.wrappedValue == 10)
        #expect(MenuBarAttentionPolicy.threshold(for: stored) == 600)
    }

    @Test("unsupported choices cannot replace a saved supported option", arguments: [99, -1])
    func rejectUnsupportedChoice(rawValue: Int) {
        var stored = 10
        let selection = MenuBarIdleAlertSelection.binding(to: Binding(get: { stored }, set: { stored = $0 }))

        selection.wrappedValue = rawValue
        #expect(stored == 10)
        #expect(selection.wrappedValue == 10)
    }
}
