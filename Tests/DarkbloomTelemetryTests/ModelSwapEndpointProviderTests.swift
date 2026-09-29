import Foundation
import Testing
import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Swap endpoint identity")
struct ModelSwapEndpointProviderTests {
    let identity = ProcessIdentity(pid: 123, startTimeMicros: 1_000_000_000)
    let now = Date(timeIntervalSince1970: 1100)

    private func record(pid: Int32 = 123, host: String = "127.0.0.1", written: TimeInterval? = 1050) -> LocalEndpointRecord {
        LocalEndpointRecord(baseURL: "http://\(host):8000", apiKey: "test-local-token",
            host: host, port: 8000, processID: pid, version: "0.9.11",
            updatedAt: written.map { Date(timeIntervalSince1970: $0) })
    }

    @Test("same-process loopback discovery resolves local authentication")
    func validProvider() async {
        let identity = identity, now = now
        let provider = AppModelSwapEndpointProvider(discovery: SwapDiscovery(result: .live(record())),
            processIdentity: { _ in identity }, now: { now })
        let endpoint = await provider.endpoint(expectedProcessIdentity: identity)
        #expect(endpoint?.origin.absoluteString == "http://127.0.0.1:8000")
        #expect(endpoint?.isAuthenticated == true)
    }

    @Test("standalone, remote, stale, future and missing discovery are rejected")
    func unsafeDiscovery() async {
        let identity = identity, now = now
        let records = [record(pid: 456), record(host: "192.168.1.2"),
                       record(host: "0.0.0.0"), record(written: 900),
                       record(written: 1200), record(written: nil)]
        for record in records {
            let provider = AppModelSwapEndpointProvider(discovery: SwapDiscovery(result: .live(record)),
                processIdentity: { _ in identity }, now: { now })
            #expect(await provider.endpoint(expectedProcessIdentity: identity) == nil)
        }
        let missing = AppModelSwapEndpointProvider(discovery: SwapDiscovery(result: .none("Unavailable")),
            processIdentity: { _ in identity }, now: { now })
        #expect(await missing.endpoint(expectedProcessIdentity: identity) == nil)
    }

    @Test("PID reuse and exited provider cannot authorize a local request")
    func processMismatch() async {
        let identity = identity, now = now
        let reused = ProcessIdentity(pid: 123, startTimeMicros: 1_050_000_000)
        for actual: ProcessIdentity? in [reused, nil] {
            let provider = AppModelSwapEndpointProvider(discovery: SwapDiscovery(result: .live(record())),
                processIdentity: { _ in actual }, now: { now })
            #expect(await provider.endpoint(expectedProcessIdentity: identity) == nil)
        }
    }
}

private struct SwapDiscovery: LocalEndpointFetching {
    let result: LocalEndpointAvailability
    func fetch() async -> LocalEndpointAvailability { result }
}
