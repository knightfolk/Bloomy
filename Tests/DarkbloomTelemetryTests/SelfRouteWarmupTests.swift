import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Post-switch self-route warm-up", .serialized)
struct SelfRouteWarmupTests {
    @Test("the probe lists self models and sends exactly one owner-only completion")
    func sendsOneSelfRequest() async {
        WarmupFixtureProtocol.reset()
        let result = await SelfRouteWarmupClient(
            keyStore: FixedWarmupKey(key: "dk-synthetic-test-key"),
            session: makeSession()
        ).warm(modelID: "gemma-4-26b-qat-4bit", family: "gemma-4-26b")

        #expect(result == .sent)
        let paths = WarmupFixtureProtocol.paths()
        #expect(paths == ["/v1/models", "/v1/chat/completions"])
    }

    @Test("without a saved key there is no network request")
    func missingKeySkips() async {
        WarmupFixtureProtocol.reset()
        let result = await SelfRouteWarmupClient(
            keyStore: FixedWarmupKey(key: nil), session: makeSession()
        ).warm(modelID: "gemma-4-26b-qat-4bit", family: "gemma-4-26b")

        #expect(result == .missingKey)
        #expect(WarmupFixtureProtocol.paths().isEmpty)
    }

    @Test("a missing self-route alias never triggers paid network inference")
    func aliasMissingSkipsCompletion() async {
        WarmupFixtureProtocol.reset(models: #"{"object":"list","data":[{"id":"different-model"}]}"#)
        let result = await SelfRouteWarmupClient(
            keyStore: FixedWarmupKey(key: "dk-synthetic-test-key"), session: makeSession()
        ).warm(modelID: "gemma-4-26b-qat-4bit", family: "gemma-4-26b")

        #expect(result == .modelUnavailable)
        #expect(WarmupFixtureProtocol.paths() == ["/v1/models"])
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WarmupFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private struct FixedWarmupKey: ConsumerKeyReading {
    let key: String?
    var hasKey: Bool { key != nil }
    func withConsumerKey<R>(_ body: (String) throws -> R) rethrows -> R? {
        guard let key else { return nil }
        return try body(key)
    }
}

private final class WarmupFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var seenPaths: [String] = []
    private nonisolated(unsafe) static var modelsBody = #"{"object":"list","data":[{"id":"gemma-4-26b"}]}"#

    static func reset(models: String = #"{"object":"list","data":[{"id":"gemma-4-26b"}]}"#) {
        lock.withLock { seenPaths = []; modelsBody = models }
    }

    static func paths() -> [String] { lock.withLock { seenPaths } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        let body = Self.lock.withLock { () -> String in
            Self.seenPaths.append(path)
            return Self.modelsBody
        }
        let valid = request.url?.host == "api.darkbloom.dev"
            && request.url?.scheme == "https"
            && request.value(forHTTPHeaderField: "X-Darkbloom-Route") == "self"
            && request.value(forHTTPHeaderField: "Authorization") == "Bearer dk-synthetic-test-key"
        let status = valid ? 200 : 500
        let payload = path == "/v1/models" ? body
            : #"{"model":"gemma-4-26b","choices":[{"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
