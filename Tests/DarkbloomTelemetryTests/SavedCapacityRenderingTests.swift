import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Saved capacity fallback layout", .serialized)
@MainActor
struct SavedCapacityRenderingTests {
    @Test("read-only saved limits fit at a narrow width in both appearances",
          arguments: [false, true], ["light", "dark"])
    func rendersSavedLimits(stale: Bool, appearance: String) async throws {
        let selection = ProviderModelSelection(enabled: (1...7).map { "model-\($0)" },
                                              preloaded: ["model-1"])
        let draft = ProviderConfigDraft(sourceRevision: "fixture", original: selection,
            selection: selection, originalMaxModelSlots: 1, originalEngineV2MaxConcurrent: 8)
        let capacity = ProviderSavedCapacity(draft: draft)
        let capturedAt = Date(timeIntervalSince1970: 1_791_000_000)
        let availability: SourceAvailability<ProviderSavedCapacity> = stale
            ? .stale(value: capacity, capturedAt: capturedAt, reason: "Saved capacity settings could not be read.")
            : .available(value: capacity, capturedAt: capturedAt)
        let content = SavedProviderCapacityView(capacity: capacity, availability: availability)
            .padding(16)
            .environment(\.colorScheme, appearance == "light" ? .light : .dark)
            .background(appearance == "light" ? Color.white : Color(white: 0.12))
        let renderer = ImageRenderer(content: content)
        renderer.proposedSize = ProposedViewSize(width: 440, height: nil)
        renderer.scale = 2
        let image = try #require(renderer.nsImage)
        #expect(image.size.width == 440)
        #expect(image.size.height <= 320)
        let tiff = try #require(image.tiffRepresentation)
        let bitmap = try #require(NSBitmapImageRep(data: tiff))
        var visiblePixels = 0
        // Require actual variation beyond the plain preview background.
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 4) {
                if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB),
                   color.alphaComponent > 0.5,
                   appearance == "light" ? color.redComponent < 0.8 : color.redComponent > 0.3 {
                    visiblePixels += 1
                }
            }
        }
        #expect(visiblePixels > 100)
        guard ProcessInfo.processInfo.environment["BLOOMY_SAVED_CAPACITY_RENDER_EVIDENCE"] == "1" else { return }
        let data = try #require(bitmap.representation(using: .png, properties: [:]))
        let name = "saved-capacity-\(appearance)-\(stale ? "stale" : "saved").png"
        try data.write(to: URL(fileURLWithPath: "/tmp/bloomy-efficiency-20261001/\(name)"))
    }
}
