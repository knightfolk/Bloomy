import AppKit
import Foundation
import SwiftUI
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Overview model summary", .serialized)
@MainActor
struct OverviewModelSummaryTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }

    @Test("render input rejects duplicate future expired undated and previous-day rates")
    func qualifiedRates() {
        let valid = rate("valid", speed: 24.7)
        let values = [valid, rate("duplicate"), rate("duplicate"),
            rate("future", end: now.addingTimeInterval(1)),
            rate("expired", end: now.addingTimeInterval(-601)),
            rate("previous-day", start: calendar.startOfDay(for: now).addingTimeInterval(-86_400)),
            .init(model: "undated", tokensPerSecond: 10, sampleCount: 1),
            rate("invalid", speed: .infinity)]
        let original = summary(rates: values)
        #expect(original.metrics(for: "valid").map(\.value) == ["24.7"])
        #expect(original.metrics(for: "valid").first?.caption == "avg tok/s today")
        for id in ["duplicate", "future", "expired", "previous-day", "undated", "invalid", "missing"] {
            #expect(original.metrics(for: id).map(\.id) == ["learning"])
        }
        #expect(summary(rates: [rate("valid", speed: 31.2)]).metrics(for: "valid").first?.value == "31.2")
        // A new render re-evaluates the real clock instead of retaining a
        // formerly valid history value after its ten-minute query lifetime.
        let expired = summary(rates: [valid], at: now.addingTimeInterval(601))
        #expect(expired.metrics(for: "valid").map(\.id) == ["learning"])
    }

    @Test("serving averages preserve first-match gross and net attribution")
    func firstServingAverage() {
        let gross = serving("model", gross: 1.2, net: nil)
        let net = serving("model", gross: 2.0, net: 0.99)
        let grossFirst = summary(rates: [rate("model")], serving: [gross, net]).metrics(for: "model")
        #expect(grossFirst.map(\.id) == ["speed", "earnings"])
        #expect(grossFirst.last?.caption == "derived gross / active h")
        #expect(grossFirst.last?.value == ActivityAmountPresentation.hourlyAmount(1.2))
        let netFirst = summary(serving: [net, gross]).metrics(for: "model")
        #expect(netFirst.first?.caption == "est. net / active h")
        #expect(netFirst.first?.value == ActivityAmountPresentation.hourlyAmount(0.99))
    }

    @Test("Overview demand matches model manager freshness and retains failed reads")
    func demandFreshnessParity() {
        let model = capacity("model", active: 4, queued: 1, loaded: 3)
        let snapshot = NetworkCapacitySnapshot(models: [model], capturedAt: now)
        let sources: [SourceAvailability<NetworkCapacitySnapshot>] = [
            .available(value: snapshot, capturedAt: now),
            .stale(value: snapshot, capturedAt: now, reason: "Read failed"),
            .unavailable(reason: "No reading")]
        for source in sources {
            let manager = ModelManagerTelemetry(networkCapacity: source.value,
                networkSourceAvailable: { if case .available = source { true } else { false } }())
            for time in [now, now.addingTimeInterval(121), now.addingTimeInterval(-6)] {
                let overview = summary(network: source, at: time)
                #expect(overview.demand(for: "model") == manager.demand(modelID: "model", at: time))
                #expect(overview.demand(for: "missing").model == nil)
                #expect(!overview.demand(for: "missing").isCurrent)
            }
        }
        let retained = summary(network: sources[1]).demand(for: "model")
        #expect(retained.title == "Demand stale")
        #expect(retained.model == model)
        #expect(retained.counts == "4 active · 1 queued")
        #expect(summary().demand(for: "model").title == "Demand unavailable")
    }

    @Test("shared demand scale includes unshown models and zero-loaded pressure stays unknown")
    func fullNetworkScale() {
        let shown = capacity("shown", active: 4, loaded: 2)
        let unshown = capacity("unshown", active: 40, loaded: 2)
        let unloaded = capacity("unloaded", active: 500, loaded: 0)
        let snapshot = NetworkCapacitySnapshot(models: [shown, unshown, unloaded], capturedAt: now)
        let overview = summary(network: .available(value: snapshot, capturedAt: now))
        #expect(overview.demandScale.upperBound == 20)
        #expect(overview.demandScale.fraction(for: shown) == 0.1)
        #expect(overview.demandScale.fraction(for: unloaded) == nil)
        #expect(overview.demand(for: "unloaded").model == unloaded)
        // Reading only one selected row cannot change the complete snapshot's ruler.
        _ = overview.metrics(for: "shown")
        _ = overview.demand(for: "shown")
        #expect(overview.demandScale == ModelDemandScale(models: snapshot.models))
        let retained = summary(network: .stale(value: snapshot, capturedAt: now, reason: "Failed"))
        #expect(retained.demandScale == overview.demandScale)
    }

    @Test("canonical model identity keeps same-alias histories separate")
    func canonicalIdentity() {
        let first = "vendor-a/gpt-oss-20b"
        let second = "vendor-b/gpt-oss-20b"
        #expect(ModelDisplayName.short(first) == ModelDisplayName.short(second))
        let model = capacity(first, active: 2, loaded: 1)
        let snapshot = NetworkCapacitySnapshot(models: [model], capturedAt: now)
        let overview = summary(rates: [rate(first)], serving: [serving(second, gross: 1, net: nil)],
            network: .available(value: snapshot, capturedAt: now))
        #expect(overview.metrics(for: first).map(\.id) == ["speed"])
        #expect(overview.metrics(for: second).map(\.id) == ["earnings"])
        #expect(overview.metrics(for: "gpt-oss-20b").map(\.id) == ["learning"])
        #expect(overview.demand(for: first).model == model)
        #expect(overview.demand(for: second).model == nil)
        let row = OverviewModelSummaryRow(model: .init(name: first, state: .active), summary: overview)
        #expect(row.model.id == first)
    }

    @Test("native rows retain equal 52pt height across widths history demand and residency states",
          arguments: [300.0, 528.0, 800.0])
    func rowGeometry(width: Double) throws {
        let id = "qwen3.6-35b-a3b-vl-mtp-mxfp8"
        let model = capacity(id, active: 11, queued: 1, loaded: 5)
        let network = NetworkCapacitySnapshot(models: [model], capturedAt: now)
        let measured = summary(rates: [rate(id)], serving: [serving(id, gross: 1.2, net: 0.99)],
            network: .available(value: network, capturedAt: now))
        let learning = summary()
        let retained = summary(serving: [serving(id, gross: 1.2, net: nil)],
            network: .stale(value: network, capturedAt: now, reason: "Retained"))
        for input in [measured, learning, retained] {
            for state in [DashboardModelState.active, .loadedIdle, .availableUnloaded] {
                let row = OverviewModelSummaryRow(model: .init(name: id, state: state), summary: input)
                    .frame(width: width)
                let host = NSHostingView(rootView: row)
                #expect(abs(host.fittingSize.width - width) < 0.1)
                #expect(abs(host.fittingSize.height - 52) < 0.1)
                let rendered = try #require(ImageRenderer(content: row).nsImage)
                #expect(abs(rendered.size.width - width) < 0.1)
                #expect(abs(rendered.size.height - 52) < 0.1)
            }
        }
    }

    @Test("small hourly amounts and metric units render intact at narrower row widths",
          arguments: [300.0, 528.0])
    func preciseMetricRendering(width: Double) throws {
        func renderedRow(_ width: Double, earningsValue: String = "$0.0050") throws -> CGImage {
            let view = CompactModelCard(modelID: "EigenLabs/Qwen3.8-27B-4bit-mtp", status: "Active",
                metrics: [
                    .init(id: "speed", symbol: "speedometer", value: "52.7", caption: "avg tok/s today"),
                    .init(id: "earnings", symbol: "dollarsign.circle", value: earningsValue, caption: "est. net / active h")
                ], compact: true, horizontal: true)
                .frame(width: width)
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            if earningsValue == "$0.0050",
               let directory = ProcessInfo.processInfo.environment["DARKBLOOM_PRECISION_EVIDENCE"] {
                let folder = URL(fileURLWithPath: directory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let bitmap = NSBitmapImageRep(cgImage: image)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: folder.appendingPathComponent("row-\(Int(width)).png"))
            }
            return image
        }
        // Compare actual foreground glyphs, not bitmap padding or the
        // width-dependent native control-background gradient. At 2x scale
        // this crop includes the complete trailing numeric text and units.
        func metricGlyphs(_ image: CGImage) throws -> [Bool] {
            let crop = try #require(image.cropping(to: .init(
                x: image.width - 360, y: 16, width: 340, height: 64)))
            var pixels = [UInt8](repeating: 0, count: crop.width * crop.height * 4)
            try pixels.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress,
                    width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: crop.width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue))
                context.draw(crop, in: .init(x: 0, y: 0, width: crop.width, height: crop.height))
            }
            return stride(from: 0, to: pixels.count, by: 4).map {
                max(pixels[$0], pixels[$0 + 1], pixels[$0 + 2]) >= 80
            }
        }
        func differences(_ lhs: [Bool], _ rhs: [Bool]) -> Int {
            zip(lhs, rhs).filter { $0 != $1 }.count
        }
        let narrow = try renderedRow(width)
        let wide = try renderedRow(800)
        #expect(narrow.width == Int(width * 2))
        #expect(narrow.height == 104)
        let narrowGlyphs = try metricGlyphs(narrow)
        let wideGlyphs = try metricGlyphs(wide)
        #expect(wideGlyphs.filter { $0 }.count > 1_000)
        // A few antialiased edge pixels may cross the foreground threshold
        // as the native background changes; lost digits alter many glyphs.
        #expect(differences(narrowGlyphs, wideGlyphs) <= 4)
        let lostPrecision = try metricGlyphs(renderedRow(800, earningsValue: "$0.00…"))
        #expect(differences(lostPrecision, wideGlyphs) > 50)
    }

    private func summary(rates: [ModelTokenRateAverage] = [], serving: [ModelServingProfitAverage] = [],
        network: SourceAvailability<NetworkCapacitySnapshot> = .unavailable(reason: "Fixture"),
        at date: Date? = nil) -> OverviewModelSummaryPresentation {
        .init(tokenRates: rates, servingAverages: serving, networkCapacity: network,
            at: date ?? now, calendar: calendar)
    }

    private func rate(_ id: String, speed: Double = 10, start: Date? = nil, end: Date? = nil) -> ModelTokenRateAverage {
        .init(model: id, tokensPerSecond: speed, sampleCount: 10,
            queryPeriod: .init(start: start ?? calendar.startOfDay(for: now), end: end ?? now))
    }

    private func serving(_ id: String, gross: Double, net: Double?) -> ModelServingProfitAverage {
        .init(model: id, grossUSDPerActiveHour: gross, incrementalElectricityUSDPerActiveHour: net == nil ? nil : 0.21,
            profitUSDPerActiveHour: net, activeHours: 2.5, coveredEarningHours: 3,
            activePowerSamples: 900, idlePowerSamples: net == nil ? 0 : 500)
    }

    private func capacity(_ id: String, active: Int, queued: Int = 0, loaded: Int) -> NetworkModelCapacity {
        .init(id: id, ready: true, canAccept: true, routableProviders: loaded,
            warmProviders: loaded, runningProviders: loaded, coldProviders: 0,
            activeRequests: active, queuedRequests: queued, queueLimit: 8,
            aggregateTokensPerSecond: 125, estimatedTimeToFirstTokenMS: 240,
            tokenBudgetRemaining: 750, tokenBudgetTotal: 1_000)
    }
}
