import AppKit
import DarkbloomTelemetry
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Model visit presentation", .serialized)
@MainActor
struct ModelVisitSectionTests {
    @Test("resident-only model filters retain coverage without borrowing old-model work")
    func residentOnlyFilter() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        for active in [false, true] {
            let rows = [0.0, 30.0].map { seconds in
                let date = start.addingTimeInterval(seconds)
                return PerformanceSample(observedAt: date, sourceCapturedAt: date, quality: .current,
                    providerSession: "1:100", model: "qwen", residentModels: ["gemma"],
                    inferenceActive: active, tokensPerSecond: 50, tokensGenerated: 10, requestsServed: 1)
            }
            let result = PerformanceMetricsSnapshot(samples: rows, range: .init(start: start, end: start.addingTimeInterval(60)), model: "gemma")
            #expect(result.models.contains("gemma"))
            #expect(result.summary.coveredSeconds == 30)
            #expect(result.summary.averageTokenRate == nil)
            #expect(result.ratePoints.isEmpty)
            #expect(result.latestForModel?.model == "gemma")
            #expect(result.summary.activeCoveredSeconds == (active ? 0 : 30))
            #expect(result.summary.completedRequests == nil)
        }
    }

    @Test("visit counts use full history while rendering stays bounded")
    func fullHistoryCounts() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = (0..<1_100).map { index in
            sample(at: start.addingTimeInterval(Double(index) * 30), model: index.isMultiple(of: 2) ? "qwen" : "gemma")
        }
        let range = DateInterval(start: start, end: samples.last!.observedAt)
        let all = PerformanceMetricsSnapshot(samples: samples, range: range, model: nil)
        #expect(all.visits.count == 500)
        #expect(all.withoutWorkVisits.count == 500)
        #expect(all.visitSummary.completedNoObservedWorkCount == 1_098)
        let selected = PerformanceMetricsSnapshot(samples: samples, range: range, model: "qwen")
        #expect(selected.visitSummary.visitCount == 550)
        #expect(selected.visitSummary.completedNoObservedWorkCount == 549)
        #expect(selected.visits.allSatisfy { $0.model == "qwen" && $0.durationSeconds == 30 })
    }

    @Test("visit list fits narrow and wide layouts", arguments: [420.0, 780.0])
    func nativeVisitRendering(width: Double) async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let samples = [
            sample(at: start, model: "qwen3.8-27b"),
            sample(at: start.addingTimeInterval(30), model: "gemma-4-26b-qat-4bit"),
            sample(at: start.addingTimeInterval(120), model: "gemma-4-26b-qat-4bit"),
            sample(at: start.addingTimeInterval(180), model: "gpt-oss-20b"),
            sample(at: start.addingTimeInterval(210), model: "gpt-oss-20b", active: true),
            sample(at: start.addingTimeInterval(240), model: "qwen3.8-27b"),
        ]
        let visits = ModelVisitHistory(samples: samples).visits
        #expect(visits.contains { $0.outcome == .noObservedWork && $0.durationSeconds == 150 })
        #expect(visits.contains { $0.outcome == .worked })
        let host = NSHostingController(rootView: ModelVisitSection(visits: visits)
            .padding(20).frame(width: width).background(Color(nsColor: .windowBackgroundColor)))
        let window = NSWindow(contentViewController: host)
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: width, height: 550))
        window.orderBack(nil)
        defer { window.close() }
        try await Task.sleep(for: .milliseconds(150))
        host.view.layoutSubtreeIfNeeded()
        #expect(abs(host.view.frame.width - width) < 1)
        guard ProcessInfo.processInfo.environment["DARKBLOOM_RENDER_EVIDENCE"] == "1" else { return }
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(window.windowNumber), "/tmp/bloomy-model-visits-\(Int(width)).png"]
        try capture.run(); capture.waitUntilExit()
        #expect(capture.terminationStatus == 0)
    }

    private func sample(at date: Date, model: String, active: Bool = false) -> PerformanceSample {
        .init(observedAt: date, sourceCapturedAt: date, quality: .current,
              providerSession: "1:100", model: model, residentModels: [model],
              inferenceActive: active, tokensGenerated: 0, requestsServed: 0)
    }
}
