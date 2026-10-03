import AppKit
import SwiftUI

@MainActor
final class ProbeDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var lastResult = NSTextField(labelWithString: "No confirmation dispatched")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let menu = NSMenu()
        let item = NSMenuItem()
        menu.addItem(item)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Dialog Probe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = appMenu
        NSApp.mainMenu = menu
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 380),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bloomy — Inert Native Dialog Probe"
        window.contentView = NSHostingView(rootView: ProbeView(delegate: self))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func alert(_ modal: Bool) {
        let alert = NSAlert()
        alert.messageText = "Allow LAN access?"
        alert.informativeText = "INERT PROBE. The endpoint would listen on 192.168.50.20. An API key would remain required. No connection, settings change or provider action occurs."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Allow LAN access (inert)")
        if modal {
            _ = alert.runModal()
        } else {
            alert.beginSheetModal(for: window) { _ in }
        }
    }
}

struct ProbeView: View {
    let delegate: ProbeDelegate
    @State private var showDialog = false
    @State private var result = "No real actions are connected."

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Synthetic native confirmation comparison").font(.title2)
            Text("AppKit and SwiftUI reference dialogs. No network or provider actions.")
            HStack {
                Button("AppKit sheet") { delegate.alert(false) }
                Button("AppKit modal") { delegate.alert(true) }
                Button("SwiftUI confirmation") { showDialog = true }
            }
            Text(result).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog("Allow LAN access?", isPresented: $showDialog, titleVisibility: .visible) {
            Button("Allow LAN access (inert)") { result = "Inert confirmation selected." }
            Button("Cancel", role: .cancel) { result = "Cancelled." }
        } message: {
            Text("INERT PROBE. The endpoint would listen on 192.168.50.20. An API key would remain required. No connection, settings change or provider action occurs.")
        }
    }
}

@main
struct ProbeMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = ProbeDelegate()
        app.delegate = delegate
        app.run()
    }
}
