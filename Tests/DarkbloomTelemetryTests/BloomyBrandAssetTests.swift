import AppKit
import Testing
@testable import DarkbloomMonitor

@Suite("Bloomy packaged branding")
@MainActor
struct BloomyBrandAssetTests {
    @Test("new brand resources load and produce a visible tintable menu-bar image")
    func bundledBrandAssets() throws {
        for name in ["bloomy-mark", "bloomy-menubar"] {
            let url = try #require(AppResources.url(named: name, extension: "svg"))
            let image = try #require(NSImage(contentsOf: url))
            #expect(image.isValid)
        }
        let icon = try #require(AppResources.url(named: "AppIcon", extension: "icns"))
        #expect(try #require(NSImage(contentsOf: icon)).isValid)
        let image = try #require(DarkbloomLogoAsset.menuBarImage(tint: .systemGreen))
        var bounds = NSRect(x: 0, y: 0, width: 18, height: 18)
        let cgImage = try #require(image.cgImage(forProposedRect: &bounds, context: nil, hints: nil))
        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        var opaque = 0
        var transparent = 0
        for y in 0..<bitmap.pixelsHigh {
            for x in 0..<bitmap.pixelsWide {
                let color = try #require(bitmap.colorAt(x: x, y: y))
                if color.alphaComponent > 0.5 { opaque += 1 }
                if color.alphaComponent < 0.1 { transparent += 1 }
            }
        }
        #expect(opaque > 20)
        #expect(transparent > 20)
    }
}
