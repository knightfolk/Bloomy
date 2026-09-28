import Foundation
import Testing
import DarkbloomCompanionProtocol

@Suite("Companion public API consumer")
struct PublicAPIConsumerTests {
    @Test("a consumer can construct and frame the documented portable API")
    func compilesPublicContract() throws {
        let observed = Date(timeIntervalSince1970: 1_800_000_000)
        let states = RuntimeStates(
            provider: .init(state: .running, observedAt: observed),
            macApp: .init(state: .running, observedAt: observed),
            helper: .init(state: .running, observedAt: observed),
            connection: .init(state: .connected, observedAt: observed)
        )
        let snapshot = try CompanionSnapshot.validated(
            hostID: UUID(), runtimeEpoch: UUID(), sequence: 1, generatedAt: observed,
            observations: [], models: [], states: states, capabilities: [.monitor]
        )
        let envelope = Envelope(requestID: UUID(), payload: .companionSnapshot(snapshot))
        let bytes = try FrameEncoder().encode(envelope)
        var decoder = FrameDecoder()
        #expect(try decoder.append(bytes) == [envelope])
    }
}
