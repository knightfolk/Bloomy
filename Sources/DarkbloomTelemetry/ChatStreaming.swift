import Foundation

/// Bounded SSE framing for the v0.10.4 OpenAI text-chat contract. Parse bytes
/// before decoding UTF-8 so transport boundaries can split a scalar safely.
/// Reasoning and other additive fields never become visible answer text.
struct ChatStreamingParser {
    static let maximumResponseBytes = 1_048_576
    static let maximumEventBytes = 256 * 1_024

    private var totalBytes = 0
    private var line = Data()
    private var event = Data()
    private var content = ""
    private var model: String?
    private var finishReason: String?
    private var promptTokens: Int?
    private var completionTokens: Int?
    private(set) var isDone = false

    mutating func append(_ byte: UInt8) throws -> String? {
        guard totalBytes < Self.maximumResponseBytes else { throw ChatClientError.responseTooLarge }
        totalBytes += 1
        if byte != 10 {
            guard line.count + event.count < Self.maximumEventBytes else { throw ChatClientError.responseTooLarge }
            line.append(byte)
            return nil
        }
        if line.last == 13 { line.removeLast() }
        defer { line.removeAll(keepingCapacity: true) }
        if line.isEmpty {
            guard !event.isEmpty else { return nil }
            defer { event.removeAll(keepingCapacity: true) }
            return try parseEvent(event)
        }
        // Ignore comments and SSE transport metadata such as id/event/retry.
        if line.starts(with: Data("data:".utf8)) {
            var value = line.dropFirst(5)
            if value.first == 32 { value = value.dropFirst() }
            if !event.isEmpty { event.append(10) }
            event.append(contentsOf: value)
        }
        return nil
    }

    func outcome() throws -> ChatCompletionOutcome {
        // EOF, even after a finish chunk, is not proof of completed delivery.
        guard isDone, finishReason != nil else { throw ChatClientError.invalidResponse }
        return ChatCompletionOutcome(content: content, model: model, finishReason: finishReason,
                                     promptTokens: promptTokens, completionTokens: completionTokens)
    }

    private mutating func parseEvent(_ data: Data) throws -> String? {
        guard !isDone else { throw ChatClientError.invalidResponse }
        if data == Data("[DONE]".utf8) {
            guard finishReason != nil else { throw ChatClientError.invalidResponse }
            isDone = true
            return nil
        }
        struct Chunk: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable {
                    let role: String?
                    let content: String?
                    let tool_calls: [JSONIgnoredTool]?
                }
                let index: Int
                let delta: Delta?
                let finish_reason: String?
            }
            struct Usage: Decodable {
                let prompt_tokens: Int?
                let completion_tokens: Int?
            }
            // Only detect presence; server error text is never retained.
            struct Failure: Decodable {}
            let object: String?
            let model: String?
            let choices: [Choice]?
            let usage: Usage?
            let error: Failure?
        }
        let chunk: Chunk
        do { chunk = try JSONDecoder().decode(Chunk.self, from: data) }
        catch { throw ChatClientError.invalidResponse }
        guard chunk.error == nil else { throw ChatClientError.invalidResponse }
        if let object = chunk.object, object != "chat.completion.chunk" { throw ChatClientError.invalidResponse }
        if let reported = chunk.model {
            guard reported.utf8.count <= 512, model == nil || model == reported else { throw ChatClientError.invalidResponse }
            model = reported
        }
        if let usage = chunk.usage {
            guard (usage.prompt_tokens ?? 0) >= 0, (usage.completion_tokens ?? 0) >= 0 else {
                throw ChatClientError.invalidResponse
            }
            promptTokens = usage.prompt_tokens ?? promptTokens
            completionTokens = usage.completion_tokens ?? completionTokens
        }
        guard let choices = chunk.choices else { throw ChatClientError.invalidResponse }
        if choices.isEmpty {
            guard chunk.usage != nil else { throw ChatClientError.invalidResponse }
            return nil
        }
        guard choices.count == 1, let choice = choices.first, choice.index == 0,
              finishReason == nil else { throw ChatClientError.invalidResponse }
        if let role = choice.delta?.role, role != "assistant" { throw ChatClientError.invalidResponse }
        // This surface sends text only and does not execute or invent tools.
        guard choice.delta?.tool_calls?.isEmpty != false else { throw ChatClientError.invalidResponse }
        if let reason = choice.finish_reason {
            guard !reason.isEmpty, reason.utf8.count <= 64, reason != "error", reason != "tool_calls" else {
                throw ChatClientError.invalidResponse
            }
            finishReason = reason
        }
        let text = choice.delta?.content ?? ""
        guard content.utf8.count + text.utf8.count <= Self.maximumResponseBytes else { throw ChatClientError.responseTooLarge }
        content.append(text)
        return text.isEmpty ? nil : text
    }
}

private struct JSONIgnoredTool: Decodable {}

/// One request, no retries or route fallback. The underlying URLSession task
/// is cancelled on every exit, including malformed streams and cancellation.
enum ChatStreamingExecutor {
    static func execute(
        request: URLRequest, session: URLSession,
        onText: @escaping @Sendable (String) async -> Void
    ) async throws -> ChatCompletionOutcome {
        try Task.checkCancellation()
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw ChatClientError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let data: Data
            do { data = try await ChatBoundedBody.collect(bytes, maximumBytes: ChatRouteExecutor.errorBodyCap) }
            catch ChatClientError.responseTooLarge {
                throw ChatHTTPStatusMapper.error(for: http.statusCode, code: nil)
            }
            throw ChatHTTPStatusMapper.error(for: http.statusCode, code: ChatErrorCodeReader.code(from: data))
        }
        guard http.mimeType?.lowercased() == "text/event-stream" else { throw ChatClientError.invalidResponse }
        guard response.expectedContentLength <= Int64(ChatStreamingParser.maximumResponseBytes) else {
            throw ChatClientError.responseTooLarge
        }
        var parser = ChatStreamingParser()
        for try await byte in bytes {
            try Task.checkCancellation()
            if let delta = try parser.append(byte) {
                await onText(delta)
                try Task.checkCancellation()
            }
            if parser.isDone { return try parser.outcome() }
        }
        try Task.checkCancellation()
        return try parser.outcome()
    }
}
