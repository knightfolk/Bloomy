import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Local model swap request", .serialized)
struct LocalModelSwapTests {
    private let identity = ProcessIdentity(pid: 42, startTimeMicros: 1234)

    @Test("one exact local model request is capped at eight output tokens")
    func sendsExactLocalRequest() async {
        SwapURLProtocol.reset(models: #"{"object":"list","data":[{"id":"gemma-exact"}]}"#)
        let result = await client(endpoint: "http://127.0.0.1:8000", token: "local-token")
            .request(modelID: "gemma-exact", expectedProcessIdentity: identity, canSend: { true })

        #expect(result == .sent)
        #expect(SwapURLProtocol.paths() == ["/v1/models", "/v1/chat/completions"])
        #expect(SwapURLProtocol.completionModel() == "gemma-exact")
        #expect(SwapURLProtocol.completionMaxTokens() == 8)
        #expect(SwapURLProtocol.allRequestsLocalAndAuthenticated)
    }

    @Test("family-only listing cannot substitute for an exact advertised build")
    func familyAliasCannotDispatch() async {
        SwapURLProtocol.reset(models: #"{"object":"list","data":[{"id":"gemma-family"}]}"#)
        let result = await client(endpoint: "http://127.0.0.1:8000", token: "local-token")
            .request(modelID: "gemma-exact", expectedProcessIdentity: identity, canSend: { true })

        #expect(result == .modelUnavailable)
        #expect(SwapURLProtocol.paths() == ["/v1/models"])
    }

    @Test("a newly busy provider prevents inference after model listing")
    func preSendGuardBlocks() async {
        SwapURLProtocol.reset(models: #"{"object":"list","data":[{"id":"gemma-exact"}]}"#)
        let result = await client(endpoint: "http://127.0.0.1:8000", token: "local-token")
            .request(modelID: "gemma-exact", expectedProcessIdentity: identity, canSend: { false })

        #expect(result == .failed)
        #expect(SwapURLProtocol.paths() == ["/v1/models"])
    }

    @Test("only a loopback endpoint may receive the swap request")
    func nonLocalEndpointBlocked() async {
        SwapURLProtocol.reset(models: #"{"object":"list","data":[{"id":"gemma-exact"}]}"#)
        let result = await client(endpoint: "https://api.darkbloom.dev", token: "local-token")
            .request(modelID: "gemma-exact", expectedProcessIdentity: identity, canSend: { true })

        #expect(result == .endpointUnavailable)
        #expect(SwapURLProtocol.paths().isEmpty)
    }

    private func client(endpoint: String, token: String) -> LocalModelSwapClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SwapURLProtocol.self]
        return LocalModelSwapClient(
            endpointProvider: FixedSwapEndpoint(endpoint: ChatLocalEndpoint.make(baseURL: endpoint, token: token)),
            session: URLSession(configuration: configuration)
        )
    }
}

private struct FixedSwapEndpoint: LocalModelSwapEndpointProviding {
    let endpoint: ChatLocalEndpoint?
    func endpoint(expectedProcessIdentity: ProcessIdentity) async -> ChatLocalEndpoint? { endpoint }
}

private final class SwapURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var seen: [URLRequest] = []
    private nonisolated(unsafe) static var modelsBody = ""

    static func reset(models: String) {
        lock.withLock { seen = []; modelsBody = models }
    }

    static func paths() -> [String] {
        lock.withLock { seen.map { $0.url?.path ?? "" } }
    }

    static func completionModel() -> String? { completionBody()?["model"] as? String }
    static func completionMaxTokens() -> Int? { completionBody()?["max_tokens"] as? Int }
    static var allRequestsLocalAndAuthenticated: Bool {
        lock.withLock {
            seen.allSatisfy {
                $0.url?.host == "127.0.0.1" && $0.url?.scheme == "http" &&
                    $0.value(forHTTPHeaderField: "Authorization") == "Bearer local-token"
            }
        }
    }

    private static func completionBody() -> [String: Any]? {
        lock.withLock {
            guard let request = seen.first(where: { $0.url?.path == "/v1/chat/completions" }),
                  let data = bodyData(request) else {
                return nil
            }
            return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        }
    }

    private static func bodyData(_ request: URLRequest) -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count >= 0 else { return nil }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let body = Self.lock.withLock { () -> String in
            Self.seen.append(request)
            return Self.modelsBody
        }
        let payload = request.url?.path == "/v1/models" ? body
            : #"{"model":"gemma-exact","choices":[{"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}"#
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(payload.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
