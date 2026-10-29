import Foundation
import Testing
@testable import DarkbloomTelemetry

/// Synthetic inline fixtures only. No file reads, provider calls, or inference.
@Suite("Chat image contract")
struct ChatImageContractTests {
    private static let png = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAAAXNSR0IArs4c6QAAAERl"
        + "WElmTU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAAB"
        + "AAAAAaADAAQAAAABAAAAAQAAAAD5Ip3+AAAADElEQVQIHWP4z8AAAAMBAQBb2/lEAAAA"
        + "AElFTkSuQmCC")!

    private func image() throws -> ChatImageAttachment {
        try ChatImageAttachment(data: Self.png, mimeType: "image/png")
    }

    private func local(_ messages: [ChatMessagePayload], stream: Bool = false) throws -> URLRequest {
        try ChatCompletionRequest.makeLocal(
            origin: URL(string: "http://127.0.0.1:8123")!, token: "synthetic-local",
            model: "synthetic-vision", messages: messages, stream: stream
        ).urlRequest
    }

    @Test("text-only messages retain the string content wire shape and decode")
    func textCompatibility() throws {
        let message = ChatMessagePayload(role: .user, content: "hello")
        let data = try JSONEncoder().encode(message)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(body.count == 2)
        #expect(body["content"] as? String == "hello")
        #expect(try JSONDecoder().decode(ChatMessagePayload.self, from: data) == message)
    }

    @Test("local streaming and normal requests use verified inline image parts")
    func imageParts() throws {
        let attachment = try image()
        let message = ChatMessagePayload(role: .user, content: "What is shown?", images: [attachment])
        for streaming in [false, true] {
            let request = try local([message], stream: streaming)
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let messages = try #require(body["messages"] as? [[String: Any]])
            let parts = try #require(messages.first?["content"] as? [[String: Any]])
            #expect(parts.count == 2)
            #expect(parts[0]["type"] as? String == "text")
            #expect(parts[0]["text"] as? String == message.content)
            #expect(parts[1]["type"] as? String == "image_url")
            #expect((parts[1]["image_url"] as? [String: String])?["url"] == "data:image/png;base64," + Self.png.base64EncodedString())
            #expect(body["stream"] as? Bool == streaming)
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-local")
            #expect(try JSONDecoder().decode(ChatMessagePayload.self, from: JSONEncoder().encode(message)) == message)
        }
    }

    @Test("image-only turns have no empty text part")
    func imageOnly() throws {
        let request = try local([ChatMessagePayload(role: .user, content: "", images: [try image()])])
        let data = try #require(request.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let parts = try #require((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])
        #expect(parts.count == 1)
        #expect(parts[0]["type"] as? String == "image_url")
    }

    @Test("network builders and both client paths refuse images before reading credentials")
    func networkFailsClosed() async throws {
        let messages = [ChatMessagePayload(role: .user, content: "image", images: [try image()])]
        for streaming in [false, true] {
            #expect(throws: ChatImageError.networkImagesUnsupported) {
                _ = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: "m", messages: messages, stream: streaming)
            }
        }
        let client = NetworkChatClient(consumerKeyProvider: { Issue.record("Network image request read credentials"); return nil })
        await #expect(throws: ChatImageError.networkImagesUnsupported) {
            _ = try await client.complete(model: "m", messages: messages)
        }
        await #expect(throws: ChatImageError.networkImagesUnsupported) {
            _ = try await client.completeStreaming(model: "m", messages: messages) { _ in }
        }
    }

    @Test("attachment bytes, MIME and image metadata are validated")
    func imageValidation() throws {
        #expect(try image().pixelCount == 1)
        #expect(throws: ChatImageError.unsupportedMIMEType) { _ = try ChatImageAttachment(data: Self.png, mimeType: "image/svg+xml") }
        #expect(throws: ChatImageError.unsupportedMIMEType) { _ = try ChatImageAttachment(data: Self.png, mimeType: "image/png;bad") }
        #expect(throws: ChatImageError.invalidImage) { _ = try ChatImageAttachment(data: Self.png, mimeType: "image/jpeg") }
        #expect(throws: ChatImageError.invalidImage) { _ = try ChatImageAttachment(data: Data(), mimeType: "image/png") }
        #expect(throws: ChatImageError.invalidImage) { _ = try ChatImageAttachment(data: Data("synthetic invalid image".utf8), mimeType: "image/png") }
        #expect(throws: ChatImageError.attachmentTooLarge) {
            _ = try ChatImageAttachment(data: Data(repeating: 0, count: ChatImageAttachment.maximumBytes + 1), mimeType: "image/png")
        }
        let attachment = try image()
        #expect(!String(reflecting: attachment).contains(Self.png.base64EncodedString()))
    }

    @Test("remote URLs, file URLs, unsupported parts and noncanonical base64 cannot enter image payloads", arguments: [
        "https://example.invalid/private.png", "file:///private/secret.png",
        "data:image/png;base64,!!!", "data:image/png;base64,AAAA\n", "data:image/svg+xml;base64,AAAA"
    ])
    func forbiddenImageReferences(_ reference: String) throws {
        let data = try JSONSerialization.data(withJSONObject: ["role": "user", "content": [["type": "image_url", "image_url": ["url": reference]]]])
        #expect(throws: (any Error).self) { _ = try JSONDecoder().decode(ChatMessagePayload.self, from: data) }
    }

    @Test("request image limits include history and reject non-user media")
    func aggregateBounds() throws {
        let attachment = try image()
        let messages = (0..<5).map { _ in ChatMessagePayload(role: .user, content: "image", images: [attachment]) }
        #expect(throws: ChatImageError.tooManyImages) { _ = try local(messages) }
        for role in [ChatMessagePayload.Role.system, .assistant] {
            #expect(throws: ChatImageError.imagesRequireUserRole) { _ = try local([ChatMessagePayload(role: role, content: "", images: [attachment])]) }
        }
        var padded = Self.png
        padded.append(Data(repeating: 0, count: ChatImageAttachment.maximumBytes - padded.count))
        let large = try ChatImageAttachment(data: padded, mimeType: "image/png")
        #expect(throws: ChatImageError.totalAttachmentsTooLarge) {
            _ = try local([ChatMessagePayload(role: .user, content: "", images: [large, large, large])])
        }
        let request = try local([ChatMessagePayload(role: .user, content: "", images: [large])])
        let data = try #require(request.httpBody)
        #expect(data.count > ChatCompletionRequest.maximumBodyBytes)
        #expect(data.count <= ChatCompletionRequest.maximumLocalImageBodyBytes)
    }

    @Test("text-only local requests keep their original smaller total-body cap")
    func textBodyCap() {
        let message = ChatMessagePayload(role: .user, content: String(repeating: "a", count: ChatCompletionRequest.maximumMessageCharacters))
        #expect(throws: ChatClientError.requestTooLarge) { _ = try local(Array(repeating: message, count: 16)) }
    }

    struct ImageEndpointProvider: ChatLocalEndpointProviding {
        let value: ChatLocalEndpoint?
        func endpoint() async -> ChatLocalEndpoint? { value }
    }

    private func fixtureSession(allowHTTP: Bool) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ChatImageFixtureURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-Bloomy-Image-Fixture": allowHTTP ? "allow" : "must-not-start"]
        return URLSession(configuration: configuration)
    }

    @Test("local models bind origin without credentials and matching image sends succeed")
    func verifiedOrigin() async throws {
        let endpoint = try #require(ChatLocalEndpoint.make(baseURL: "http://127.0.0.1:8123/v1", token: "synthetic-private-token"))
        let session = fixtureSession(allowHTTP: true)
        defer { session.invalidateAndCancel() }
        let client = LocalChatClient(endpointProvider: ImageEndpointProvider(value: endpoint), session: session)
        let snapshot = try await client.models(now: Date())
        #expect(snapshot.localEndpointOrigin == endpoint.origin)
        #expect(!String(reflecting: snapshot).contains("synthetic-private-token"))
        #expect(!String(reflecting: endpoint).contains("synthetic-private-token"))
        let messages = [ChatMessagePayload(role: .user, content: "", images: [try image()])]
        let result = try await client.complete(model: "synthetic-vision", messages: messages, imageEndpointOrigin: snapshot.localEndpointOrigin)
        #expect(result.content == "Synthetic image reply")
        let streamed = try await client.completeStreaming(model: "synthetic-vision", messages: messages, imageEndpointOrigin: snapshot.localEndpointOrigin) { _ in }
        #expect(streamed.content == "Synthetic image reply")
    }

    @Test("missing or changed local origin prevents HTTP for image-bearing history")
    func changedOrigin() async throws {
        let endpoint = try #require(ChatLocalEndpoint.make(baseURL: "http://127.0.0.1:8123", token: "synthetic"))
        let session = fixtureSession(allowHTTP: false)
        defer { session.invalidateAndCancel() }
        let client = LocalChatClient(endpointProvider: ImageEndpointProvider(value: endpoint), session: session)
        let messages = [ChatMessagePayload(role: .user, content: "old image", images: [try image()]), ChatMessagePayload(role: .assistant, content: "reply"), ChatMessagePayload(role: .user, content: "follow-up")]
        for origin in [nil, URL(string: "http://127.0.0.1:9999"), URL(string: "http://192.0.2.1:8123")] {
            await #expect(throws: ChatImageError.localImageEndpointChanged) {
                _ = try await client.complete(model: "m", messages: messages, imageEndpointOrigin: origin)
            }
            await #expect(throws: ChatImageError.localImageEndpointChanged) {
                _ = try await client.completeStreaming(model: "m", messages: messages, imageEndpointOrigin: origin) { _ in }
            }
        }
        await #expect(throws: ChatImageError.localImageEndpointChanged) { _ = try await client.complete(model: "m", messages: messages) }
        await #expect(throws: ChatImageError.localImageEndpointChanged) { _ = try await client.completeStreaming(model: "m", messages: messages) { _ in } }
        let missing = LocalChatClient(endpointProvider: ImageEndpointProvider(value: nil), session: session)
        await #expect(throws: ChatClientError.localEndpointUnavailable) {
            _ = try await missing.complete(model: "m", messages: messages, imageEndpointOrigin: endpoint.origin)
        }
    }

    @Test("legacy client conformance remains text-compatible and fails closed for images")
    func legacyConformance() async throws {
        struct Legacy: ChatCompleting {
            func complete(model: String, messages: [ChatMessagePayload]) async throws -> ChatCompletionOutcome { .init(content: "legacy") }
        }
        let client: any ChatCompleting = Legacy()
        let origin = URL(string: "http://127.0.0.1:8123")!
        let text = [ChatMessagePayload(role: .user, content: "hello")]
        #expect(try await client.complete(model: "m", messages: text, imageEndpointOrigin: nil).content == "legacy")
        #expect(try await client.completeStreaming(model: "m", messages: text, imageEndpointOrigin: nil) { _ in }.content == "legacy")
        let messages = [ChatMessagePayload(role: .user, content: "", images: [try image()])]
        await #expect(throws: ChatImageError.localImageEndpointChanged) {
            _ = try await client.complete(model: "m", messages: messages, imageEndpointOrigin: origin)
        }
        await #expect(throws: ChatImageError.localImageEndpointChanged) {
            _ = try await client.completeStreaming(model: "m", messages: messages, imageEndpointOrigin: origin) { _ in }
        }
    }
}

private final class ChatImageFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard request.value(forHTTPHeaderField: "X-Bloomy-Image-Fixture") == "allow" else {
            Issue.record("Image transport started HTTP before checking the verified origin")
            client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
            return
        }
        let url = request.url!
        let streaming = request.value(forHTTPHeaderField: "Accept") == "text/event-stream"
        let body: String
        if url.path == "/v1/models" {
            body = #"{"object":"list","data":[{"id":"synthetic-vision"}]}"#
        } else if streaming {
            body = "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Synthetic image reply\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
        } else {
            body = #"{"choices":[{"message":{"role":"assistant","content":"Synthetic image reply"},"finish_reason":"stop"}]}"#
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": streaming ? "text/event-stream" : "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
