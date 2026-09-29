import DarkbloomTelemetry
import Foundation

/// Only discovery published by the live network provider can authorize Swap.
/// A standalone server, saved Hosting preference, or unrelated loopback service
/// cannot identify the provider whose resident model the user intends to change.
struct AppModelSwapEndpointProvider: LocalModelSwapEndpointProviding {
    let discovery: any LocalEndpointFetching
    var processIdentity: @Sendable (Int32) -> ProcessIdentity? = { ProcessIdentity.read(pid: $0) }
    var now: @Sendable () -> Date = { Date() }

    func endpoint(expectedProcessIdentity expected: ProcessIdentity) async -> ChatLocalEndpoint? {
        guard case .live(let record) = await discovery.fetch(),
              record.processID == expected.pid,
              processIdentity(expected.pid) == expected,
              let written = record.updatedAt,
              written.timeIntervalSince1970.isFinite,
              written.timeIntervalSince1970 >= Double(expected.startTimeMicros) / 1_000_000 - 1,
              written <= now(),
              record.host == "127.0.0.1",
              let origin = URLComponents(string: record.baseURL),
              origin.scheme == "http", origin.host == "127.0.0.1",
              origin.port == Int(record.port) else { return nil }
        var token: String?
        record.withBearerToken { token = $0 }
        return ChatLocalEndpoint.make(baseURL: record.baseURL, token: token)
    }
}
