import Foundation
import Testing
@testable import DarkbloomTelemetry
@testable import DarkbloomMonitor

@Suite("Chat streaming")
struct ChatStreamingTests {
    private let messages = [ChatMessagePayload(role: .user, content: "synthetic prompt")]

    private func parse(_ text: String) throws -> (ChatCompletionOutcome, [String]) {
        var parser = ChatStreamingParser()
        var deltas: [String] = []
        for byte in text.utf8 {
            if let delta = try parser.append(byte) { deltas.append(delta) }
        }
        return (try parser.outcome(), deltas)
    }

    @Test("streaming is explicit and normal completion and warmup stay non-streaming")
    func requestContract() throws {
        let stream = try ChatCompletionRequest.makeNetwork(consumerKey: "synthetic", model: "m", messages: messages, stream: true).urlRequest
        let streamBody = try #require(stream.httpBody)
        let body = try #require(JSONSerialization.jsonObject(with: streamBody) as? [String: Any])
        #expect(body["stream"] as? Bool == true)
        #expect((body["stream_options"] as? [String: Bool])?["include_usage"] == true)
        #expect(stream.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let ordinary = try ChatCompletionRequest.makeLocal(origin: URL(string: "http://127.0.0.1:8123")!, token: nil, model: "m", messages: messages).urlRequest
        let ordinaryBody = try #require(ordinary.httpBody)
        let plainBody = try #require(JSONSerialization.jsonObject(with: ordinaryBody) as? [String: Any])
        #expect(plainBody["stream"] as? Bool == false)
        #expect(plainBody["stream_options"] == nil)
        #expect(ordinary.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test("byte-split UTF-8 content, CRLF, keepalives and usage preserve only visible answer")
    func fragmentedContract() throws {
        let fixture = ": keepalive\r\n\r\n" +
            "data: {\"object\":\"chat.completion.chunk\",\"model\":\"served-m\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"reasoning_content\":\"private reasoning\"}}]}\r\n\r\n" +
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi 🐕\"}}]}\r\n\r\n" +
            "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"!\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":3,\"completion_tokens\":2}}\r\n\r\n" +
            "data: [DONE]\r\n\r\n"
        let (outcome, deltas) = try parse(fixture)
        #expect(deltas == ["Hi 🐕", "!"])
        #expect(outcome == ChatCompletionOutcome(content: "Hi 🐕!", model: "served-m", finishReason: "stop", promptTokens: 3, completionTokens: 2))
    }

    @Test("separate usage-only event and multi-line data are accepted")
    func usageEvent() throws {
        let fixture = "data: {\"choices\":\ndata: [{\"index\":0,\"delta\":{\"content\":\"ok\"},\"finish_reason\":\"length\"}]}\n\n" +
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":4}}\n\n" +
            "data: [DONE]\n\n"
        let (outcome, _) = try parse(fixture)
        #expect(outcome.content == "ok")
        #expect(outcome.finishReason == "length")
        #expect(outcome.completionTokens == 4)
    }

    @Test("truncated, malformed, error, wrong role and unsupported tool streams never complete", arguments: [
        "data: [DONE]\n\n",
        "data: not-json\n\n",
        "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"},\"finish_reason\":\"stop\"}]}\n\n",
        "data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\"partial\"}}]}\n\n",
        "data: {\"error\":{\"message\":\"secret synthetic key\"},\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"error\"}]}\n\n",
        "data: {\"choices\":[{\"index\":0,\"delta\":{\"role\":\"user\",\"content\":\"bad\"}}]}\n\n",
        "data: {\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"function\":{\"name\":\"unexpected\"}}]}}]}\n\n",
        "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":-1}}\n\n",
        "data: {\"choices\":[{\"index\":1,\"delta\":{}}]}\n\n"
    ])
    func invalidStream(_ fixture: String) {
        #expect(throws: ChatClientError.invalidResponse) { _ = try parse(fixture) }
    }

    @Test("an unterminated SSE event is bounded before JSON decoding")
    func boundedEvent() {
        var parser = ChatStreamingParser()
        #expect(throws: ChatClientError.responseTooLarge) {
            for _ in 0...ChatStreamingParser.maximumEventBytes { _ = try parser.append(32) }
        }
    }

    @Test("streaming local client preserves endpoint auth and final provenance")
    func localTransport() async throws {
        let client = LocalChatClient(endpointProvider: StreamingEndpointFixture(), session: session(mode: "success"))
        let received = StreamingDeltaRecorder()
        let outcome = try await client.completeStreaming(model: "m", messages: messages) { await received.append($0) }
        #expect(await received.values == ["first", " second"])
        #expect(outcome.content == "first second")
        #expect(outcome.model == "served-m")
    }

    @Test("network HTTP errors remain authoritative with no streamed text or retry", arguments: [401, 402, 404])
    func transportErrors(_ status: Int) async {
        let client = NetworkChatClient(consumerKeyProvider: { "synthetic-consumer" }, session: session(mode: String(status)))
        let expected: ChatClientError = status == 401 ? .consumerKeyRejected : status == 402 ? .paymentRequired : .modelNotFound
        await #expect(throws: expected) {
            _ = try await client.completeStreaming(model: "m", messages: messages) { _ in Issue.record("Error response emitted text") }
        }
    }

    @Test("a malformed or truncated transport preserves prior deltas but throws", arguments: ["truncated", "late-error", "wrong-mime"])
    func transportFailure(_ mode: String) async {
        let received = StreamingDeltaRecorder()
        let client = LocalChatClient(endpointProvider: StreamingEndpointFixture(), session: session(mode: mode))
        await #expect(throws: ChatClientError.invalidResponse) {
            _ = try await client.completeStreaming(model: "m", messages: messages) { await received.append($0) }
        }
        #expect(await received.values == (mode == "wrong-mime" ? [] : ["first"]))
    }

    @Test("cancellation during a delivered delta stops the transport")
    func cancelledTransport() async throws {
        let client = LocalChatClient(endpointProvider: StreamingEndpointFixture(), session: session(mode: "success"))
        let task = Task {
            try await client.completeStreaming(model: "m", messages: messages) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }

    private func session(mode: String) -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StreamingFixtureURLProtocol.self]
        config.httpAdditionalHeaders = ["X-Streaming-Fixture": mode]
        return URLSession(configuration: config)
    }
}

private actor StreamingDeltaRecorder {
    var values: [String] = []
    func append(_ text: String) { values.append(text) }
}

private struct StreamingEndpointFixture: ChatLocalEndpointProviding {
    func endpoint() async -> ChatLocalEndpoint? {
        ChatLocalEndpoint.make(baseURL: "http://127.0.0.1:8123/v1", token: "synthetic-local")
    }
}

private final class StreamingFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let mode = request.value(forHTTPHeaderField: "X-Streaming-Fixture") ?? "success"
        #expect(request.url?.path == "/v1/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Accept") == "text/event-stream")
        let local = request.url?.host == "127.0.0.1"
        #expect(request.value(forHTTPHeaderField: "Authorization") == (local ? "Bearer synthetic-local" : "Bearer synthetic-consumer"))
        let status = Int(mode) ?? 200
        let mime = mode == "wrong-mime" ? "application/json" : "text/event-stream"
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": mime])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if status != 200 {
            let data = status == 402 ? Data(repeating: 32, count: 8_192) : Data("{\"error\":{\"code\":\"model_not_found\",\"message\":\"secret fixture text\"}}".utf8)
            client?.urlProtocol(self, didLoad: data)
        } else {
            let first = "data: {\"model\":\"served-m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"first\"}}]}\n\n"
            // Fragment the UTF-8 transport independently from event boundaries.
            for fragment in [first.prefix(11), first.dropFirst(11)] { client?.urlProtocol(self, didLoad: Data(fragment.utf8)) }
            if mode == "late-error" {
                client?.urlProtocol(self, didLoad: Data("data: {\"error\":{\"message\":\"secret fixture text\"},\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"error\"}]}\n\n".utf8))
            } else if mode != "truncated" {
                client?.urlProtocol(self, didLoad: Data("data: {\"choices\":[{\"index\":0,\"delta\":{\"content\":\" second\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n".utf8))
            }
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Chat streamed store")
@MainActor
struct ChatStreamedStoreTests {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func store(client: ControlledStreamingChatClient) async -> ChatStore {
        let store = ChatStore(localClient: client, networkClient: FakeChatRouteClient(), balanceClient: FakeBalanceClient(), pricingClient: FakePricingClient(), keyStore: FakeConsumerKeyStore(), now: { Date(timeIntervalSince1970: 1_800_000_000) })
        await store.refreshKeyStatus()
        store.startConversation(route: .local)
        await wait { store.canSend }
        return store
    }

    private func wait(_ condition: @MainActor () async -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        Issue.record("Timed out waiting for streaming fixture")
    }

    @Test("partial text is visible during a request and finalized only on success")
    func incrementalAndFinish() async {
        let client = ControlledStreamingChatClient()
        let store = await store(client: client)
        #expect(store.send("first prompt"))
        await wait { await client.isPending }
        await client.emit("hello")
        #expect(store.isSending)
        #expect(store.conversation?.entries.last?.text == "hello")
        #expect(store.conversation?.entries.last?.phase == .sending)
        #expect(store.conversation?.entries.last?.provenance == nil)
        await client.emit(" world")
        await client.release(.success(ChatCompletionOutcome(content: "hello world", model: "served-m", finishReason: "stop")))
        await wait { !store.isSending }
        #expect(store.conversation?.entries.last?.text == "hello world")
        #expect(store.conversation?.entries.last?.phase == .complete)
        #expect(store.conversation?.entries.last?.provenance?.modelID == "served-m")
    }

    @Test("failure retains partial text and excludes its whole exchange from future history")
    func partialFailure() async {
        let client = ControlledStreamingChatClient()
        let store = await store(client: client)
        #expect(store.send("failed prompt"))
        await wait { await client.isPending }
        await client.emit("unfinished")
        await client.release(.failure(ChatClientError.invalidResponse))
        await wait { !store.isSending }
        #expect(store.conversation?.entries.last?.text == "unfinished")
        #expect(store.conversation?.entries.last?.phase.isFailure == true)
        #expect(store.send("next prompt"))
        await wait { await client.isPending }
        #expect(await client.latestHistory == [ChatMessagePayload(role: .user, content: "next prompt")])
        await client.release(.success(ChatCompletionOutcome(content: "done")))
        await wait { !store.isSending }
    }

    @Test("cancel retains partial text and discards late deltas and success")
    func partialCancellation() async {
        let client = ControlledStreamingChatClient()
        let store = await store(client: client)
        #expect(store.send("cancel prompt"))
        await wait { await client.isPending }
        await client.emit("partial")
        store.cancelSend()
        #expect(!store.isSending)
        #expect(store.conversation?.entries.last?.phase == .cancelled)
        await client.emit(" late")
        await client.release(.success(ChatCompletionOutcome(content: "late final")))
        await Task.yield()
        #expect(store.conversation?.entries.last?.text == "partial")
        #expect(store.conversation?.entries.last?.phase == .cancelled)
        #expect(store.conversation?.entries.last?.provenance == nil)
    }
}

private actor ControlledStreamingChatClient: LocalChatRouteClient {
    var latestHistory: [ChatMessagePayload] = []
    private var onText: (@Sendable (String) async -> Void)?
    private var pending: CheckedContinuation<ChatCompletionOutcome, Error>?
    var isPending: Bool { pending != nil }
    func models(now: Date) async throws -> ChatModelListSnapshot { ChatModelListSnapshot(modelIDs: ["m"], capturedAt: now) }
    func complete(model: String, messages: [ChatMessagePayload]) async throws -> ChatCompletionOutcome { throw ChatClientError.invalidResponse }
    func completeStreaming(model: String, messages: [ChatMessagePayload], onText: @escaping @Sendable (String) async -> Void) async throws -> ChatCompletionOutcome {
        latestHistory = messages
        self.onText = onText
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    func emit(_ text: String) async { await onText?(text) }
    func release(_ outcome: Result<ChatCompletionOutcome, Error>) {
        let continuation = pending
        pending = nil
        continuation?.resume(with: outcome)
    }
}
