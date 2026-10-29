import Foundation
import Testing
@testable import DarkbloomTelemetry

/// Synthetic bytes and isolated URLProtocol only. No authenticated network,
/// provider inference, remote media fetch, credential storage, or disk images.
@Suite("Network chat images")
struct ChatNetworkImageTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    fileprivate static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAAXNSR0IArs4c6QAAAERl"
        + "WElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAAB"
        + "AAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADElEQVQIHWP4z8AAAAMBAQBb2/lEAAAA"
        + "AElFTkSuQmCC")!

    private func image() throws -> ChatImageAttachment { try ChatImageAttachment(data: Self.png, mimeType: "image/png") }
    private func messages() throws -> [ChatMessagePayload] {
        [ChatMessagePayload(role: .user, content: "Synthetic image", images: [try image()]),
         ChatMessagePayload(role: .assistant, content: "Earlier reply"),
         ChatMessagePayload(role: .user, content: "Follow-up includes earlier image")]
    }

    private func snapshot(_ metadata: String = #", "input_modalities":["text","image"]"#, capturedAt: Date = Self.now) throws -> ChatModelListSnapshot {
        try ChatModelListParser.parse(Data(#"{"object":"list","data":[{"id":"synthetic-vision"\#(metadata)}]}"#.utf8), capturedAt: capturedAt)
    }
    private func capability(capturedAt: Date = Self.now) throws -> ChatNetworkImageCapability {
        try #require(snapshot(capturedAt: capturedAt).bindingNetworkRoute().networkImageCapability(for: "synthetic-vision", at: capturedAt))
    }
    private func session(_ mode: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [NetworkImageFixtureURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Bloomy-Network-Image-Fixture": mode]
        return URLSession(configuration: config)
    }

    @Test("only exact explicit input modalities authorize image input", arguments: [
        "", #", "input_modalities":null"#, #", "input_modalities":"image""#,
        #", "input_modalities":{}"#, #", "input_modalities":[]"#,
        #", "input_modalities":["text"]"#, #", "input_modalities":["Image"]"#,
        #", "input_modalities":["image",null]"#, #", "input_modalities":["image",7]"#,
        #", "input_modalities":["image","future"]"#,
        #", "input_modalities":["image","image"]"#,
        #", "input_modalities":[" image "]"#,
        #", "metadata":{"input_modalities":["text","image"],"model_type":"vision"}, "output_modalities":["image"], "supported_features":["vision"],"pricing":{"image":"0"}"#
    ])
    func invalidCapabilities(_ metadata: String) throws {
        let parsed = try snapshot(metadata).bindingNetworkRoute()
        #expect(parsed.modelIDs == ["synthetic-vision"])
        #expect(parsed.networkImageCapability(for: "synthetic-vision", at: Self.now) == nil)
    }

    @Test("route-neutral, local and manually constructed snapshots cannot authorize network images")
    func routeBinding() throws {
        let parsed = try snapshot()
        #expect(parsed.inputModalitiesByModelID["synthetic-vision"] == [.text, .image])
        #expect(parsed.networkImageCapability(for: "synthetic-vision", at: Self.now) == nil)
        let local = ChatModelListSnapshot(modelIDs: parsed.modelIDs, capturedAt: Self.now, localEndpointOrigin: URL(string: "http://127.0.0.1:8123"))
        let legacy = ChatModelListSnapshot(modelIDs: parsed.modelIDs, capturedAt: Self.now)
        #expect(local.networkImageCapability(for: "synthetic-vision", at: Self.now) == nil)
        #expect(legacy.networkImageCapability(for: "synthetic-vision", at: Self.now) == nil)
        let bound = parsed.bindingNetworkRoute()
        #expect(bound.networkImageCapability(for: "synthetic-vision", at: Self.now) != nil)
        #expect(bound.networkImageCapability(for: "Synthetic-Vision", at: Self.now) == nil)
        #expect(bound.networkImageCapability(for: "different-model", at: Self.now) == nil)
    }

    @Test("capability expires, rejects future snapshots, and does not follow model switches")
    func freshness() throws {
        let bound = try snapshot().bindingNetworkRoute()
        #expect(bound.networkImageCapability(for: "synthetic-vision", at: Self.now.addingTimeInterval(120)) != nil)
        #expect(bound.networkImageCapability(for: "synthetic-vision", at: Self.now.addingTimeInterval(120.001)) == nil)
        #expect(bound.networkImageCapability(for: "synthetic-vision", at: Self.now.addingTimeInterval(-0.001)) == nil)
        let token = try capability()
        #expect(token.isValid(for: "synthetic-vision", at: Self.now))
        #expect(!token.isValid(for: "different-model", at: Self.now))
        #expect(!token.isValid(for: "synthetic-vision", at: Self.now.addingTimeInterval(121)))
    }

    @Test("builder requires fresh matching evidence for streaming and ordinary image bodies")
    func requestGateAndWireBody() throws {
        let media = try messages()
        let evidence = try capability()
        for stream in [false, true] {
            for model in ["synthetic-vision", "different-model"] {
                #expect(throws: ChatImageError.networkImagesUnsupported) {
                    _ = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: model, messages: media, stream: stream, now: Self.now)
                }
            }
            for (model, now) in [("different-model", Self.now), ("synthetic-vision", Self.now.addingTimeInterval(121)), ("synthetic-vision", Self.now.addingTimeInterval(-1))] {
                #expect(throws: ChatImageError.networkImagesUnsupported) {
                    _ = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: model, messages: media, stream: stream, networkImageCapability: evidence, now: now)
                }
            }
            let request = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic-consumer", model: "synthetic-vision", messages: media, stream: stream, networkImageCapability: evidence, now: Self.now).urlRequest
            #expect(request.url?.absoluteString == "https://api.darkbloom.dev/v1/chat/completions")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-consumer")
            #expect(request.value(forHTTPHeaderField: "X-Darkbloom-Route") == nil)
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let parts = try #require((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
            #expect(parts[0]["type"] as? String == "text")
            #expect(parts[1]["type"] as? String == "image_url")
            #expect((parts[1]["image_url"] as? [String: String])?["url"] == "data:image/png;base64," + Self.png.base64EncodedString())
            #expect(data.count <= ChatCompletionRequest.maximumNetworkImageBodyBytes)
        }
    }

    @Test("network client denies missing, mismatched, stale and local-only evidence before credentials or HTTP")
    func clientGate() async throws {
        let isolated = session("must-not-start")
        defer { isolated.invalidateAndCancel() }
        let media = try messages()
        let evidence = try capability()
        let client = NetworkChatClient(consumerKeyProvider: { Issue.record("Invalid image evidence reached credential access"); return nil }, session: isolated, now: { Self.now })
        let staleClient = NetworkChatClient(consumerKeyProvider: { Issue.record("Stale evidence reached credential access"); return nil }, session: isolated, now: { Self.now.addingTimeInterval(121) })
        let route: any ChatCompleting = client
        let cases: [(any ChatCompleting, String, ChatNetworkImageCapability?)] = [
            (route, "synthetic-vision", nil), (route, "different-model", evidence),
            (staleClient, "synthetic-vision", evidence)
        ]
        for (target, model, token) in cases {
            await #expect(throws: ChatImageError.networkImagesUnsupported) {
                _ = try await target.complete(model: model, messages: media, imageEndpointOrigin: nil, networkImageCapability: token)
            }
            await #expect(throws: ChatImageError.networkImagesUnsupported) {
                _ = try await target.completeStreaming(model: model, messages: media, imageEndpointOrigin: nil, networkImageCapability: token) { _ in }
            }
        }
        // Neither the original API nor the local-origin overload bypasses it.
        await #expect(throws: ChatImageError.networkImagesUnsupported) { _ = try await client.complete(model: "synthetic-vision", messages: media) }
        await #expect(throws: ChatImageError.networkImagesUnsupported) { _ = try await client.completeStreaming(model: "synthetic-vision", messages: media) { _ in } }
        await #expect(throws: ChatImageError.networkImagesUnsupported) { _ = try await client.complete(model: "synthetic-vision", messages: media, imageEndpointOrigin: URL(string: "http://127.0.0.1:8123")) }
    }

    @Test("credentials cannot resume an image request after its evidence expires")
    func expiryDuringCredentials() async throws {
        let clock = NetworkImageClock(Self.now)
        let isolated = session("must-not-start")
        defer { isolated.invalidateAndCancel() }
        let client = NetworkChatClient(consumerKeyProvider: {
            clock.set(Self.now.addingTimeInterval(121))
            return "synthetic-consumer"
        }, session: isolated, now: { clock.read() })
        let media = try messages()
        let evidence = try capability()
        await #expect(throws: ChatImageError.networkImagesUnsupported) {
            _ = try await client.complete(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence)
        }
        clock.set(Self.now)
        await #expect(throws: ChatImageError.networkImagesUnsupported) {
            _ = try await client.completeStreaming(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence) { _ in }
        }
    }

    @Test("network listing binds route, verified images complete through both client transports")
    func admittedClient() async throws {
        let isolated = session("allow")
        defer { isolated.invalidateAndCancel() }
        let client = NetworkChatClient(consumerKeyProvider: { "synthetic-consumer" }, session: isolated, now: { Self.now })
        let listed = try await client.models(now: Self.now)
        #expect(listed.localEndpointOrigin == nil)
        let evidence = try #require(listed.networkImageCapability(for: "synthetic-vision", at: Self.now))
        let media = try messages()
        let erased: any ChatCompleting = client
        #expect(try await erased.complete(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence).content == "Synthetic network image reply")
        #expect(try await erased.completeStreaming(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence) { _ in }.content == "Synthetic network image reply")
    }

    @Test("image evidence does not bypass missing consumer credentials or payment rejection")
    func paidAndCredentialBoundaries() async throws {
        let media = try messages()
        let evidence = try capability()
        let deniedSession = session("must-not-start")
        defer { deniedSession.invalidateAndCancel() }
        let keyless = NetworkChatClient(consumerKeyProvider: { nil }, session: deniedSession, now: { Self.now })
        await #expect(throws: ChatClientError.missingConsumerKey) {
            _ = try await keyless.complete(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence)
        }
        let paymentSession = session("payment")
        defer { paymentSession.invalidateAndCancel() }
        let paid = NetworkChatClient(consumerKeyProvider: { "synthetic-consumer" }, session: paymentSession, now: { Self.now })
        await #expect(throws: ChatClientError.paymentRequired) {
            _ = try await paid.complete(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence)
        }
        await #expect(throws: ChatClientError.paymentRequired) {
            _ = try await paid.completeStreaming(model: "synthetic-vision", messages: media, imageEndpointOrigin: nil, networkImageCapability: evidence) { _ in }
        }
    }

    @Test("network image admission preserves aggregate, role and text-body limits")
    func requestBounds() throws {
        let evidence = try capability()
        let image = try image()
        #expect(throws: ChatImageError.tooManyImages) {
            _ = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: "synthetic-vision", messages: (0..<5).map { _ in .init(role: .user, content: "", images: [image]) }, networkImageCapability: evidence, now: Self.now)
        }
        #expect(throws: ChatImageError.imagesRequireUserRole) {
            _ = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: "synthetic-vision", messages: [.init(role: .assistant, content: "", images: [image])], networkImageCapability: evidence, now: Self.now)
        }
        let text = ChatMessagePayload(role: .user, content: String(repeating: "a", count: ChatCompletionRequest.maximumMessageCharacters))
        #expect(throws: ChatClientError.requestTooLarge) {
            _ = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: "synthetic-vision", messages: Array(repeating: text, count: 16), networkImageCapability: evidence, now: Self.now)
        }
    }
}

private final class NetworkImageClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date
    init(_ value: Date) { self.value = value }
    func read() -> Date { lock.withLock { value } }
    func set(_ value: Date) { lock.withLock { self.value = value } }
}

private final class NetworkImageFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Bloomy-Network-Image-Fixture")
        guard mode == "allow" || mode == "payment" else {
            Issue.record("Network image HTTP started before the capability gate")
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        guard request.url?.host == "api.darkbloom.dev", request.url?.scheme == "https",
              request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-consumer"
        else {
            Issue.record("Network image request used an unexpected destination or credential")
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let url = request.url!
        let streaming = request.value(forHTTPHeaderField: "Accept") == "text/event-stream"
        let body: String
        if mode == "payment" {
            body = #"{"error":{"code":"insufficient_funds"}}"#
        } else if url.path == "/v1/models" {
            body = #"{"object":"list","data":[{"id":"synthetic-vision","input_modalities":["text","image"]},{"id":"synthetic-text","input_modalities":["text"]}]}"#
        } else if streaming {
            body = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Synthetic network image reply\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        } else {
            body = #"{"choices":[{"message":{"role":"assistant","content":"Synthetic network image reply"},"finish_reason":"stop"}]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: mode == "payment" ? 402 : 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
