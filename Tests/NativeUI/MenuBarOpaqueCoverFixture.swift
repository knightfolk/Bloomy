// An inert, independently identified app used only by the native motion probe.
import AppKit

@MainActor
private final class OpaqueCoverDelegate: NSObject, NSApplicationDelegate {
    let frame: NSRect
    let statusURL: URL
    private var window: NSWindow?
    private var finished = false

    init(frame: NSRect, statusURL: URL) {
        self.frame = frame
        self.statusURL = statusURL
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Inert cover — no provider connection"
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .normal
        window.alphaValue = 1
        window.isOpaque = true
        window.hasShadow = false
        window.backgroundColor = .black
        window.contentView = OpaqueCoverView(frame: NSRect(origin: .zero, size: frame.size))
        window.setFrame(frame, display: true)
        self.window = window
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        persist(event: "ready")
        FileHandle.standardInput.readabilityHandler = { [weak self] handle in
            if handle.availableData.isEmpty {
                handle.readabilityHandler = nil
                Task { @MainActor [weak self] in self?.finish(reason: "parent-request") }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 12) { [weak self] in
            self?.finish(reason: "self-timeout")
        }
    }

    func finish(reason: String) {
        guard !finished else { return }
        finished = true
        FileHandle.standardInput.readabilityHandler = nil
        window?.close()
        persist(event: "terminal", reason: reason)
        NSApplication.shared.terminate(nil)
    }

    private func persist(event: String, reason: String? = nil) {
        guard let window else { return }
        var payload: [String: Any] = ["event": event, "processID": Int(getpid()),
            "bundleID": Bundle.main.bundleIdentifier ?? "nil", "windowNumber": window.windowNumber,
            "frame": NSStringFromRect(window.frame), "opaque": window.isOpaque,
            "contentOpaque": window.contentView?.isOpaque ?? false, "alpha": window.alphaValue,
            "visible": window.isVisible, "level": window.level.rawValue, "providerConnected": false]
        if let reason { payload["reason"] = reason; payload["windowClosed"] = !window.isVisible }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) {
            try? data.write(to: statusURL, options: .atomic)
        }
    }
}

private final class OpaqueCoverView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { NSColor.black.setFill(); dirtyRect.fill() }
}

@main
private enum MenuBarOpaqueCoverFixtureApplication {
    @MainActor static func main() {
        let arguments = CommandLine.arguments
        guard arguments.count == 6 else { exit(64) }
        let values = arguments[1...4].compactMap(Double.init)
        guard values.count == 4, values.allSatisfy(\.isFinite),
              (100...1_024).contains(values[2]), (100...1_024).contains(values[3]) else { exit(64) }
        let frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard NSScreen.screens.contains(where: { $0.frame.contains(frame) }) else { exit(64) }
        let delegate = OpaqueCoverDelegate(frame: frame, statusURL: URL(fileURLWithPath: arguments[5]))
        let application = NSApplication.shared
        application.setActivationPolicy(.regular)
        application.delegate = delegate
        withExtendedLifetime(delegate) { application.run() }
    }
}
