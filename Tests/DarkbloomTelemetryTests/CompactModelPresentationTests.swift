import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@Suite("Compact model presentation")
struct CompactModelPresentationTests {
    @Test func shortNamesPreserveUnknownVariants() {
        #expect(ModelDisplayName.short("gpt-oss-20b") == "GPT-OSS · 20B")
        #expect(ModelDisplayName.short("vendor/qwen4-30b-special") == "Qwen 4 · 30B special")
        #expect(ModelDisplayName.short("vendor/qwen4-30b-other") != ModelDisplayName.short("vendor/qwen4-30b-special"))
        #expect(ModelDisplayName.short("vendor/custom_variant") == "custom variant")
    }

    @Test func advertisingRequiresFreshRuntimeAndDistinguishesMissingFromEmpty() throws {
        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let url = try #require(Bundle.module.url(forResource: "daemon-state-online", withExtension: "json", subdirectory: "Fixtures"))
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        json["written_at"] = now.timeIntervalSince1970
        func snapshot(_ object: [String: Any], capturedAt: Date = now, status: SourceAvailability<StatusSnapshot> = .unavailable(reason: "fixture")) throws -> TelemetrySnapshot {
            let state = try DaemonStateParser.parse(JSONSerialization.data(withJSONObject: object))
            return TelemetrySnapshot(state: .available(value: state, capturedAt: capturedAt),
                loadedModels: .unavailable(reason: "fixture"), status: status,
                eventFeed: .unavailable(reason: "fixture"), tokenRate: .unavailable(reason: "fixture"),
                diagnostics: [], capturedAt: now, menuStatus: .online)
        }
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json), control: nil, now: now) == nil)
        json["advertised_models"] = [String]()
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json), control: nil, now: now) == [])
        json["advertised_models"] = ["model-b", "model-a", "model-a"]
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json), control: nil, now: now) == ["model-a", "model-b"])
        json["advertised_models"] = ["gemma-4-26b", "gemma-4-26b-8bit", "gemma-4-26b-qat-4bit", "Qwen3.5-9B"]
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json), control: nil, now: now) ==
            ["Qwen3.5-9B", "gemma-4-26b", "gemma-4-26b-8bit", "gemma-4-26b-qat-4bit"])
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json), control: nil, now: now.addingTimeInterval(11)) == nil)
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json, capturedAt: now.addingTimeInterval(-11)), control: nil, now: now) == nil)
        var stopped = StatusSnapshot()
        stopped.daemon = "Stopped"
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json, status: .available(value: stopped, capturedAt: now)), control: nil, now: now) == [])
        json["written_at"] = now.timeIntervalSince1970 + 1
        #expect(try PopupModelGroups.advertised(snapshot: snapshot(json), control: nil, now: now) == nil)
    }
}
