import DarkbloomTelemetry
import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("Provider request card source quality")
@MainActor
struct ProviderRequestCardPresentationTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("current request modes retain their numeric meaning and detailed current copy",
          arguments: [ProviderRequestActivityMode.idle, .active, .draining, .stopped])
    func currentModes(mode: ProviderRequestActivityMode) {
        let state = daemon(mode: mode, writtenAt: now.timeIntervalSince1970)
        let card = ProviderRequestCardPresentation.make(source: .available(value: state, capturedAt: now), now: now)
        #expect(card.activity.mode == mode)
        #expect(card.activity.value == expectedValue(mode))
        #expect(!card.showsLastReport)
        #expect(card.accessibilityLabel == card.activity.detail)
        #expect(card.accessibilityValue == "\(card.activity.value), \(card.activity.status)")
        #expect(card.help == card.activity.detail)
    }

    @Test("retained idle, active, draining, and stopped reports never speak current activity",
          arguments: [ProviderRequestActivityMode.idle, .active, .draining, .stopped])
    func staleModes(mode: ProviderRequestActivityMode) {
        let state = daemon(mode: mode, writtenAt: now.timeIntervalSince1970)
        // An explicit failed read stays stale even when the old timestamp is recent.
        let card = ProviderRequestCardPresentation.make(
            source: .stale(value: state, capturedAt: now, reason: "Synthetic read failed"), now: now)
        #expect(card.activity.mode == mode)
        #expect(card.activity.value == expectedValue(mode))
        #expect(card.showsLastReport)
        #expect(card.accessibilityLabel.contains("Last reported provider request activity"))
        #expect(card.accessibilityLabel.contains("Current activity is unknown"))
        #expect(!card.accessibilityLabel.contains("currently active"))
        #expect(card.accessibilityValue == "Last report, \(card.activity.value), \(card.activity.status)")
        #expect(card.help == card.accessibilityLabel)
        #expect(card.help != card.activity.detail)
    }

    @Test("available reports follow the daemon-age boundary and reject future or invalid evidence",
          arguments: [10.0, 10.001, -1.0, Double.nan, Double.infinity, -Double.infinity])
    func availableTimestampQuality(age: Double) {
        let state = daemon(mode: .active, writtenAt: now.timeIntervalSince1970 - age)
        let card = ProviderRequestCardPresentation.make(source: .available(value: state, capturedAt: now), now: now)
        let isCurrent = age.isFinite && (0...10).contains(age)
        #expect(card.activity.value == "1+")
        #expect(card.showsLastReport == !isCurrent)
        if isCurrent {
            #expect(card.accessibilityLabel == card.activity.detail)
        } else {
            #expect(card.accessibilityLabel.contains("Current activity is unknown"))
            #expect(card.accessibilityValue.hasPrefix("Last report, "))
            #expect(card.help == card.accessibilityLabel)
        }
    }

    @Test("missing daemon data is unavailable rather than zero or a last report")
    func unavailableHasNoRetainedReport() {
        let card = ProviderRequestCardPresentation.make(source: .unavailable(reason: "Not acquired"), now: now)
        #expect(card.activity.mode == .unavailable)
        #expect(card.activity.value == "—")
        #expect(card.activity.status == "Unavailable")
        #expect(!card.showsLastReport)
        #expect(card.accessibilityValue == "—, Unavailable")
        #expect(card.accessibilityLabel == "Provider request activity is not available.")
        #expect(card.help == card.accessibilityLabel)
    }

    @Test("a missing inference signal fails decoding instead of inventing idle activity")
    func missingInferenceDoesNotBecomeZero() throws {
        let url = try #require(Bundle.module.url(forResource: "daemon-state-online", withExtension: "json", subdirectory: "Fixtures"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json.removeValue(forKey: "inference_active")
        let data = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) { try DaemonStateParser.parse(data) }
    }

    private func expectedValue(_ mode: ProviderRequestActivityMode) -> String {
        switch mode {
        case .idle, .stopped: "0"
        case .active: "1+"
        case .draining: "7"
        case .unavailable: "—"
        }
    }

    private func daemon(mode: ProviderRequestActivityMode, writtenAt: TimeInterval) -> DaemonState {
        let lifecycle: ProviderLifecycleState? = switch mode {
        case .draining: .init(outcome: .draining, remainingRequests: 7, coordinatorAcknowledged: false)
        case .stopped: .init(outcome: .stopped, remainingRequests: 0)
        default: nil
        }
        return DaemonState(schema: 1, version: "fixture", currentModel: "fixture", warmModels: [],
            stats: ProviderStats(tokensGenerated: 0, requestsServed: 0, usageGaps: 0), trust: nil,
            capacity: nil, slots: [], inferenceActive: mode == .active || mode == .draining,
            startedAt: now.timeIntervalSince1970 - 60, writtenAt: writtenAt, pid: 42,
            processIdentity: ProcessIdentity(pid: 42, startTimeMicros: 42), lifecycle: lifecycle)
    }
}
