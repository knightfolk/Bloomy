import AppKit
import DarkbloomTelemetry
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Support packet preview", .serialized)
@MainActor
struct SupportPacketPreviewTests {
    @Test("preview renders the immutable bytes that the document will export")
    func rendersFrozenPacket() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let snapshot = try SupportPacketSnapshot.make(
            snapshot: .unavailable(now: now),
            alerts: [],
            allowlistedModelIDs: [],
            createdAt: now
        )
        let document = SupportPacketDocument(snapshot: snapshot)
        let host = NSHostingController(rootView: SupportPacketPreviewView(snapshot: snapshot))
        let window = NSWindow(contentViewController: host)
        window.title = "Darkbloom Support Packet Fixture"
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 700, height: 650))
        window.orderBack(nil)
        defer { window.close() }

        try await Task.sleep(for: .milliseconds(200))
        host.view.layoutSubtreeIfNeeded()
        #expect(document.data == snapshot.data)
        #expect(snapshot.data.count <= SupportPacketSnapshot.maximumBytes)
        #expect(snapshot.previewText.contains("state_availability"))

        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/darkbloom-support-packet-preview.png"]
        try capture.run()
        capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }
}
