import Foundation
import Testing
@testable import DarkbloomCompanionProtocol

@Suite("Companion snapshot privacy")
struct SnapshotPrivacyTests {
    @Test("wire snapshots omit host-only secret canaries")
    func omitsSecretCanaries() throws {
        let hostOnly = [
            "provider-token-canary", "account-key-canary", "/Users/canary/private",
            "wss://coordinator.canary/private", "raw prompt canary", "raw response canary",
        ]
        let encoded = try FrameEncoder().encode(.fixtureSnapshot)
        let wire = String(decoding: encoded, as: UTF8.self)
        for secret in hostOnly {
            #expect(!wire.contains(secret))
        }
        #expect(!wire.contains("coordinatorURL"))
        #expect(!wire.contains("filesystemPath"))
        #expect(!wire.contains("rawLog"))
    }

    @Test("stale observations retain source capture time")
    func preservesStaleCaptureTime() throws {
        let captured = Date(timeIntervalSince1970: 1_700_000_000)
        let observation = MetricObservation(
            metric: .tokenRate,
            value: 42,
            unit: .tokensPerSecond,
            scope: .localProvider,
            provenance: .derived,
            capturedAt: captured,
            sourceAgeSeconds: 35,
            availability: .stale,
            reason: .sourceRefreshFailed
        )
        let snapshot = try CompanionSnapshot.validated(
            hostID: UUID(), runtimeEpoch: UUID(), sequence: 4,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_035),
            observations: [observation], models: [], states: .fixture
        )
        let envelope = Envelope(requestID: UUID(), payload: .companionSnapshot(snapshot))
        let encoded = try FrameEncoder().encode(envelope)
        var decoder = FrameDecoder()
        let decoded = try #require(try decoder.append(encoded).first)
        guard case let .companionSnapshot(roundTrip) = decoded.payload else {
            Issue.record("Expected companion snapshot payload")
            return
        }
        #expect(roundTrip.observations.first?.capturedAt == captured)
        #expect(roundTrip.observations.first?.sourceAgeSeconds == 35)
        #expect(roundTrip.observations.first?.availability == .stale)
    }

    @Test("account earnings retain explicit currency and account scope")
    func preservesEarningsAttribution() throws {
        let earnings = MetricObservation(
            metric: .accountEarnings,
            value: 12.34,
            unit: .currency,
            scope: .account,
            provenance: .direct,
            capturedAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceAgeSeconds: 1,
            availability: .available,
            reason: nil,
            currencyCode: "USD"
        )
        try earnings.validate()
        let encoded = try JSONEncoder().encode(earnings)
        #expect(String(decoding: encoded, as: UTF8.self).contains("\"currencyCode\":\"USD\""))
        #expect(throws: ProtocolError.invalidField("observation.currencyCode")) {
            try MetricObservation(
                metric: .accountEarnings, value: 1, unit: .currency, scope: .account,
                provenance: .direct, capturedAt: .now, sourceAgeSeconds: 0,
                availability: .available, reason: nil
            ).validate()
        }
    }
}

extension RuntimeStates {
    static let fixture = RuntimeStates(
        provider: .init(state: .running, observedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        macApp: .init(state: .running, observedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        helper: .init(state: .running, observedAt: Date(timeIntervalSince1970: 1_800_000_000)),
        connection: .init(state: .connected, observedAt: Date(timeIntervalSince1970: 1_800_000_000))
    )
}

extension Envelope {
    static let fixtureSnapshot: Envelope = {
        let snapshot = try! CompanionSnapshot.validated(
            hostID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            runtimeEpoch: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            sequence: 7,
            generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            observations: [
                MetricObservation(
                    metric: .tokenRate, value: 12.5, unit: .tokensPerSecond,
                    scope: .localProvider, provenance: .derived,
                    capturedAt: Date(timeIntervalSince1970: 1_799_999_995),
                    sourceAgeSeconds: 5, availability: .available, reason: nil
                )
            ],
            models: [ModelSummary(
                id: "model-safe", name: "Safe Model", enabled: true,
                advertised: true, resident: true, active: false,
                tokenRate: 12.5, rateWindow: .activeSample
            )],
            states: .fixture,
            capabilities: [.monitor, .providerLifecycle]
        )
        return Envelope(
            requestID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            payload: .companionSnapshot(snapshot)
        )
    }()
}
