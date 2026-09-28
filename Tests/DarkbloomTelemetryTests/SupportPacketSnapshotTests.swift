import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Sanitized support packet")
struct SupportPacketSnapshotTests {
    @Test("packet is deterministic and includes only explicitly allowlisted models")
    func deterministicAllowlist() throws {
        let input = snapshot(at: 100, model: "private-model-canary")
        let allowlist: Set<String> = ["allowed/model"]
        let first = try SupportPacketSnapshot.make(
            snapshot: input,
            alerts: [alert(.providerOffline, .raised, at: 90)],
            allowlistedModelIDs: allowlist,
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let second = try SupportPacketSnapshot.make(
            snapshot: input,
            alerts: [alert(.providerOffline, .raised, at: 90)],
            allowlistedModelIDs: allowlist,
            createdAt: Date(timeIntervalSince1970: 101)
        )

        #expect(first.data == second.data)
        #expect(first.data.count <= SupportPacketSnapshot.maximumBytes)
        let object = try #require(JSONSerialization.jsonObject(with: first.data) as? [String: Any])
        #expect(object["model_ids"] as? [String] == ["allowed/model"])
        #expect(!first.previewText.contains("private-model-canary"))
    }

    @Test("secret canaries from telemetry and diagnostics never enter the packet")
    func excludesSensitiveSourceFields() throws {
        let packet = try SupportPacketSnapshot.make(
            snapshot: snapshot(at: 100, model: "unlisted/model"),
            alerts: [alert(.modelUnknown, .raised, at: 99)],
            allowlistedModelIDs: [],
            createdAt: Date(timeIntervalSince1970: 101)
        )
        let text = packet.previewText
        for canary in [
            "fixture-home-canary", "fixture-account-canary", "fixture-url-canary",
            "fixture-prose-canary", "fixture-model-canary", "424242",
            "coordinator-secret-canary", "config-path-secret-canary"
        ] {
            #expect(!text.contains(canary), "Support packet leaked \(canary)")
        }
        let document = try #require(JSONSerialization.jsonObject(with: packet.data) as? [String: Any])
        #expect(document["model_ids"] as? [String] == [])
        #expect(document["current_model_id"] == nil)
        #expect(text.contains("provider_offline") == false)
        #expect(text.contains("model_unknown"))
    }

    @Test("large histories are trimmed at whole records to stay under 256 KiB")
    func byteCap() throws {
        let alerts = (0..<8_000).map { index in
            alert(.modelUnknown, .raised, at: index, duration: 86_400, observations: 999_999)
        }
        let packet = try SupportPacketSnapshot.make(
            snapshot: snapshot(at: 9_000, model: "allowed/model"),
            alerts: alerts,
            allowlistedModelIDs: ["allowed/model"],
            createdAt: Date(timeIntervalSince1970: 9_001)
        )
        #expect(packet.data.count <= 256 * 1_024)
        #expect(packet.alertCount > 0)
        #expect(packet.alertCount < alerts.count)
        #expect(packet.omittedAlertCount == alerts.count - packet.alertCount)
        let object = try #require(JSONSerialization.jsonObject(with: packet.data) as? [String: Any])
        let records = try #require(object["alerts"] as? [[String: Any]])
        #expect(records.count == packet.alertCount)
        #expect(records.allSatisfy { $0["code"] as? String == "model_unknown" })
    }

    @Test("recommendation summary exports only bounded states and allowlisted model IDs")
    func recommendationPrivacy() throws {
        let date = Date(timeIntervalSince1970: 100)
        let current = RecommendationCandidateInput(
            modelID: "allowed/model", enabled: true, downloaded: true,
            capacity: .init(capturedAt: date, ready: true, activeRequests: 0, queuedRequests: 0, warmProviders: 1),
            readiness: .init(capturedAt: date, compatible: true, locallyReady: true, memoryFits: true)
        )
        let privateModel = RecommendationCandidateInput(
            modelID: "private-recommendation-canary", enabled: true, downloaded: true,
            capacity: .init(capturedAt: date, ready: true, activeRequests: 1, queuedRequests: 2, warmProviders: 1),
            readiness: .init(capturedAt: date, compatible: true, locallyReady: true, memoryFits: true),
            tokenRates: [.init(capturedAt: date, tokensPerSecond: 123_456_789, sampleCount: 1)],
            observedWork: [.init(
                capturedAt: date, period: DateInterval(start: date.addingTimeInterval(-3_600), end: date),
                microUSD: 987_654_321, jobs: 1, recordedHours: 1, unknownHours: 0,
                uncertainBoundaryHours: 0, scope: .sameAccount
            )]
        )
        let decision = RecommendationEvaluator.evaluate(.init(
            evaluatedAt: date, currentModelID: "allowed/model", inventoryCapturedAt: date,
            capacityIsDraining: false, candidates: [current, privateModel]
        ))
        #expect(decision.outcome == .consider(modelID: "private-recommendation-canary"))
        let packet = try SupportPacketSnapshot.make(
            snapshot: snapshot(at: 100, model: "allowed/model"), alerts: [],
            allowlistedModelIDs: ["allowed/model"], recommendation: decision,
            recommendationHistory: Array(repeating: decision, count: 40), createdAt: date
        )
        let text = packet.previewText
        #expect(!text.contains("private-recommendation-canary"))
        #expect(!text.contains("123456789"))
        #expect(!text.contains("987654321"))
        let document = try #require(JSONSerialization.jsonObject(with: packet.data) as? [String: Any])
        let summary = try #require(document["recommendation"] as? [String: Any])
        #expect(summary["outcome"] as? String == "consider")
        #expect(summary["selected_model_id"] == nil)
        let factors = try #require(summary["factor_states"] as? [[String: Any]])
        #expect(factors.count <= 12)
        #expect(factors.allSatisfy { $0["numeric_value"] == nil })
        let history = try #require(document["recommendation_history"] as? [[String: Any]])
        #expect(history.count == 12)
        #expect(history.allSatisfy { $0["selected_model_id"] == nil })
    }

    private func snapshot(at seconds: Int, model: String) -> TelemetrySnapshot {
        let date = Date(timeIntervalSince1970: TimeInterval(seconds))
        var status = StatusSnapshot()
        status.version = "fixture-version"
        status.providerName = "provider-prose-canary"
        status.configPath = "/Users/fixture-home-canary/config-path-secret-canary"
        status.coordinator = "https://fixture-url-canary.invalid/coordinator-secret-canary"
        status.authorization = "fixture-account-canary"
        status.authorizationAdvice = ["fixture-prose-canary"]

        let daemon = DaemonState(
            schema: 1,
            version: "fixture-version",
            currentModel: model,
            warmModels: ["allowed/model", "fixture-model-canary"],
            stats: ProviderStats(tokensGenerated: 12, requestsServed: 3, usageGaps: 0),
            trust: TrustState(
                level: "fixture-account-canary",
                status: "online",
                reason: "fixture-prose-canary",
                receivedAt: date.timeIntervalSince1970
            ),
            capacity: nil,
            slots: [],
            inferenceActive: true,
            startedAt: date.timeIntervalSince1970 - 10,
            writtenAt: date.timeIntervalSince1970,
            pid: 424_242,
            processIdentity: ProcessIdentity(pid: 424_242, startTimeMicros: 9),
            coordinatorURL: "https://fixture-url-canary.invalid/coordinator-secret-canary",
            modelLoadFailures: [ModelLoadFailure(model: "fixture-model-canary", code: .unknown)],
            configPath: "/Users/fixture-home-canary/config-path-secret-canary"
        )
        return TelemetrySnapshot(
            state: .available(value: daemon, capturedAt: date),
            loadedModels: .available(
                value: LoadedModelsState(schema: 1, models: ["allowed/model", "fixture-model-canary"],
                                         updatedAt: date.timeIntervalSince1970),
                capturedAt: date
            ),
            status: .available(value: status, capturedAt: date),
            eventFeed: .unavailable(reason: "fixture-prose-canary"),
            tokenRate: .unavailable(reason: "fixture-prose-canary"),
            diagnostics: [AcquisitionDiagnostic(
                id: "fixture-account-canary",
                source: "fixture-prose-canary",
                message: "fixture-prose-canary /Users/fixture-home-canary 424242 https://fixture-url-canary.invalid",
                occurredAt: date
            )],
            capturedAt: date,
            menuStatus: .online
        )
    }

    private func alert(
        _ code: OperationalAlertCode,
        _ kind: AlertTransitionKind,
        at seconds: Int,
        duration: Int? = nil,
        observations: Int = 1
    ) -> AlertRecord {
        AlertRecord(
            id: Int64(seconds + 1),
            code: code,
            kind: kind,
            occurredAt: Date(timeIntervalSince1970: TimeInterval(seconds)),
            observedDurationSeconds: duration,
            observationCount: observations
        )
    }
}
