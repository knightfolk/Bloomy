import AppKit
import SwiftUI

/// A native menu finishes its dismissal before invoking navigation. A nested
/// SwiftUI popover can consume the parent NSPopover's close request instead.
struct PopupMoreControl: View {
    let openDashboard: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    var body: some View {
        PopupMoreMenuButton(openDashboard: openDashboard, openSettings: openSettings, quit: quit)
            .frame(maxWidth: .infinity).frame(height: 47)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            .modifier(PopupKeyboardReveal())
    }
}

struct PopupMoreMenuButton: NSViewRepresentable {
    let openDashboard: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(actions: self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "More", target: context.coordinator, action: #selector(Coordinator.showMenu(_:)))
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: nil)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 17, weight: .medium)
        button.imagePosition = .imageAbove
        button.imageHugsTitle = true
        button.contentTintColor = .labelColor
        button.font = .systemFont(ofSize: 10, weight: .medium)
        button.setAccessibilityLabel("More")
        button.setAccessibilityIdentifier("popup.more")
        button.toolTip = "Dashboard, Settings and Quit"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.actions = self
    }

    @MainActor final class Coordinator: NSObject {
        var actions: PopupMoreMenuButton
        init(actions: PopupMoreMenuButton) { self.actions = actions }

        @objc func showMenu(_ sender: NSButton) {
            let menu = NSMenu(title: "More")
            menu.addItem(item("Dashboard", symbol: "rectangle.grid.2x2", action: #selector(dashboard)))
            menu.addItem(item("Settings", symbol: "gearshape", action: #selector(settings)))
            menu.addItem(.separator())
            menu.addItem(item("Quit Bloomy", symbol: "rectangle.portrait.and.arrow.right", action: #selector(quitApp)))
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.minY), in: sender)
        }

        private func item(_ title: String, symbol: String, action: Selector) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            return item
        }

        @objc private func dashboard() { actions.openDashboard() }
        @objc private func settings() { actions.openSettings() }
        @objc private func quitApp() { actions.quit() }
    }
}
