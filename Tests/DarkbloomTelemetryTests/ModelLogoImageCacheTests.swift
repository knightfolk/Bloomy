import AppKit
import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Model logo image reuse")
@MainActor
struct ModelLogoImageCacheTests {
    @Test("the real factory reuses each family while preserving normalized pixels and geometry")
    func packagedImages() throws {
        var pixels: [Data] = []
        for family in ModelFamilyIcon.allCases {
            let source = try #require(loadSource(family))
            let baseline = try #require(originalFactory(source))
            let first = try #require(DarkbloomLogoAsset.modelImage(family: family))
            let second = try #require(DarkbloomLogoAsset.modelImage(family: family))
            #expect(first === second)
            #expect(first.size == NSSize(width: 96, height: 96))
            #expect(first.isTemplate == baseline.isTemplate)
            let actual = try raster(first)
            #expect(actual == (try raster(baseline)))
            #expect(actual.enumerated().contains { $0.offset % 4 == 3 && $0.element > 127 })
            #expect(actual.enumerated().contains { $0.offset % 4 == 3 && $0.element < 26 })
            pixels.append(actual)
        }
        #expect(Set(pixels).count == ModelFamilyIcon.allCases.count)
    }

    @Test("the cache is lazy, resolves each requested family once, and retains missing results")
    func lazyAndMissing() throws {
        var reads: [ModelFamilyIcon: Int] = [:]
        var conversions = 0
        let source = try #require(loadSource(.darkbloom))
        let cache = DarkbloomLogoAsset.ModelImageCache(source: { family in
            reads[family, default: 0] += 1
            return family == .qwen ? source : nil
        }, normalize: { image in
            conversions += 1
            return DarkbloomLogoAsset.ModelImageCache.normalizedImage(image)
        })
        #expect(reads.isEmpty)
        #expect(conversions == 0)
        let first = try #require(cache.image(family: .qwen))
        #expect(cache.image(family: .qwen) === first)
        #expect(reads == [.qwen: 1])
        #expect(conversions == 1)
        #expect(cache.image(family: .google) == nil)
        #expect(cache.image(family: .google) == nil)
        #expect(reads == [.qwen: 1, .google: 1])
        #expect(conversions == 1)
    }

    @Test("missing vendor sources preserve the brand fallback and unconvertible originals retain identity")
    func fallbackBehavior() throws {
        let brand = try #require(loadSource(.darkbloom))
        let missingVendor: NSImage? = nil
        let brandCache = DarkbloomLogoAsset.ModelImageCache(source: { _ in missingVendor ?? brand })
        let fallback = try #require(brandCache.image(family: .qwen))
        #expect(fallback.size == NSSize(width: 96, height: 96))
        #expect(try raster(fallback) == raster(try #require(originalFactory(brand))))

        let unconvertible = NSImage()
        unconvertible.isTemplate = true
        var bounds = NSRect(x: 0, y: 0, width: 96, height: 96)
        try #require(unconvertible.cgImage(forProposedRect: &bounds, context: nil, hints: nil) == nil)
        var conversions = 0
        let originalCache = DarkbloomLogoAsset.ModelImageCache(source: { _ in unconvertible }, normalize: { source in
            conversions += 1
            return DarkbloomLogoAsset.ModelImageCache.normalizedImage(source)
        })
        #expect(originalCache.image(family: .qwen) === unconvertible)
        #expect(originalCache.image(family: .qwen) === unconvertible)
        #expect(unconvertible.isTemplate)
        #expect(unconvertible.size == .zero)
        #expect(conversions == 1)
    }

    @Test("bounded actual-factory allocation benchmark",
          .enabled(if: ProcessInfo.processInfo.environment["DARKBLOOM_LOGO_BENCHMARK"] == "1"))
    func benchmark() throws {
        let families = ModelFamilyIcon.allCases
        let sources = try Dictionary(uniqueKeysWithValues: families.map { ($0, try #require(loadSource($0))) })
        // Source loading and AppKit's first rasterization are excluded from
        // timed comparisons; both paths use the same warmed source objects.
        for family in families { _ = originalFactory(sources[family]) }
        var baselineRequests = 0
        var baselineWrappers = 0
        var candidateRequests = 0
        var candidateWrappers = 0
        let cache = DarkbloomLogoAsset.ModelImageCache(source: { sources[$0] }, normalize: { source in
            candidateRequests += 1
            let result = DarkbloomLogoAsset.ModelImageCache.normalizedImage(source)
            if result !== source { candidateWrappers += 1 }
            return result
        })
        var retained: [NSImage] = []
        let firstStart = ContinuousClock.now
        for family in families { retained.append(try #require(cache.image(family: family))) }
        let firstSeconds = seconds(firstStart.duration(to: .now))
        #expect(candidateRequests == families.count)
        #expect(candidateWrappers == families.count)
        let firstCounts = (candidateRequests, candidateWrappers)
        candidateRequests = 0
        candidateWrappers = 0
        retained.removeAll(keepingCapacity: true)
        let baselineStart = ContinuousClock.now
        for _ in 0..<100 {
            for family in families {
                retained.append(try #require(originalFactory(sources[family], request: { baselineRequests += 1 },
                    wrapper: { baselineWrappers += 1 })))
            }
        }
        let baselineSeconds = seconds(baselineStart.duration(to: .now))
        let baselineDistinct = Set(retained.map(ObjectIdentifier.init)).count
        #expect(baselineRequests == 600)
        #expect(baselineWrappers == 600)
        #expect(baselineDistinct == 600)
        retained.removeAll(keepingCapacity: true)
        let candidateStart = ContinuousClock.now
        for _ in 0..<100 {
            for family in families { retained.append(try #require(cache.image(family: family))) }
        }
        let candidateSeconds = seconds(candidateStart.duration(to: .now))
        let candidateDistinct = Set(retained.map(ObjectIdentifier.init)).count
        #expect(candidateRequests == 0)
        #expect(candidateWrappers == 0)
        #expect(candidateDistinct == families.count)
        let evidence: [String: Any] = [
            "benchmark": "model-image-factory", "calls": 600,
            "baselineProvenance": "Pre-cache modelImage normalization copied unchanged from MenuBarLabel.swift; source assets loaded once, warmed before timing.",
            "candidateProvenance": "Production ModelImageCache and normalizedImage with the same source objects; fresh cache and warmed lookup measured separately.",
            "countsAre": "CGImage requests and new NSImage wrappers, not a count of internal AppKit SVG decodes.",
            "coldCacheWithWarmSources": ["seconds": firstSeconds, "cgImageRequests": firstCounts.0, "wrappers": firstCounts.1],
            "baselineWarm": ["seconds": baselineSeconds, "cgImageRequests": baselineRequests,
                "wrappers": baselineWrappers, "retainedDistinctImages": baselineDistinct],
            "candidateWarm": ["seconds": candidateSeconds, "cgImageRequests": candidateRequests,
                "wrappers": candidateWrappers, "retainedDistinctImages": candidateDistinct],
            "scope": "Finite factory benchmark; does not establish application-level CPU or energy savings."
        ]
        print(String(decoding: try JSONSerialization.data(withJSONObject: evidence, options: [.sortedKeys]), as: UTF8.self))
    }

    private func loadSource(_ family: ModelFamilyIcon) -> NSImage? {
        func load(_ name: String) -> NSImage? {
            guard let url = AppResources.url(named: name, extension: "svg"), let image = NSImage(contentsOf: url) else { return nil }
            image.isTemplate = true
            return image
        }
        return (family == .darkbloom ? nil : load("model-\(family.rawValue)")) ?? load("bloomy-mark")
    }

    // Explicit pre-cache baseline, retained independently of the new cache's
    // converter so a changed conversion or pixel behavior is detectable.
    private func originalFactory(_ source: NSImage?, request: () -> Void = {}, wrapper: () -> Void = {}) -> NSImage? {
        guard let source else { return nil }
        var bounds = NSRect(x: 0, y: 0, width: 96, height: 96)
        request()
        guard let bitmap = source.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else { return source }
        wrapper()
        return NSImage(cgImage: bitmap, size: NSSize(width: 96, height: 96))
    }

    private func raster(_ image: NSImage) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 96,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 96 * 4, bitsPerPixel: 32))
        let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = context
        let rect = NSRect(x: 0, y: 0, width: 96, height: 96)
        NSColor.clear.setFill()
        rect.fill(using: .copy)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        context.flushGraphics()
        return Data(bytes: try #require(bitmap.bitmapData), count: bitmap.bytesPerRow * bitmap.pixelsHigh)
    }

    private func seconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
