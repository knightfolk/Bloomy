import Foundation

/// Verified model IDs for one chat route, captured from a successful
/// authenticated `GET /v1/models`. The chat model picker only ever offers
/// IDs from this snapshot; nothing is guessed or carried over between routes.
public struct ChatModelListSnapshot: Equatable, Sendable {
    public static let maximumResponseBytes = 256 * 1_024
    public static let maximumModels = 128

    public let modelIDs: [String]
    public let capturedAt: Date
    /// Bound only by the local client to the normalized endpoint it queried.
    /// Legacy snapshots have no authority to send network images.
    public let localEndpointOrigin: URL?
    /// Only strictly decoded, explicit top-level `input_modalities` values.
    /// Missing or malformed metadata leaves the model absent from this map.
    public let inputModalitiesByModelID: [String: Set<ChatInputModality>]
    private let isNetworkRoute: Bool

    public init(modelIDs: [String], capturedAt: Date, localEndpointOrigin: URL? = nil) {
        self.modelIDs = modelIDs
        self.capturedAt = capturedAt
        self.localEndpointOrigin = localEndpointOrigin
        self.inputModalitiesByModelID = [:]
        self.isNetworkRoute = false
    }

    init(modelIDs: [String], capturedAt: Date, inputModalitiesByModelID: [String: Set<ChatInputModality>], isNetworkRoute: Bool = false) {
        self.modelIDs = modelIDs
        self.capturedAt = capturedAt
        self.localEndpointOrigin = nil
        self.inputModalitiesByModelID = inputModalitiesByModelID
        self.isNetworkRoute = isNetworkRoute
    }

    /// Only the network client's successful fixed-host model read binds this
    /// metadata to the paid route. Local or manually constructed snapshots
    /// cannot authorize a network image request.
    func bindingNetworkRoute() -> Self {
        Self(modelIDs: modelIDs, capturedAt: capturedAt, inputModalitiesByModelID: inputModalitiesByModelID, isNetworkRoute: true)
    }

    public func networkImageCapability(for modelID: String, at now: Date) -> ChatNetworkImageCapability? {
        guard isNetworkRoute, modelIDs.contains(modelID),
              inputModalitiesByModelID[modelID]?.contains(.image) == true
        else { return nil }
        let capability = ChatNetworkImageCapability(modelID: modelID, capturedAt: capturedAt)
        return capability.isValid(for: modelID, at: now) ? capability : nil
    }
}

public enum ChatInputModality: String, Hashable, Sendable, CaseIterable {
    case text, image, audio, video
}

/// Short-lived evidence from the exact model's authenticated network listing.
/// This carries neither credentials nor media. It cannot be constructed from
/// provider status, local model metadata, model names, or price information.
public struct ChatNetworkImageCapability: Equatable, Sendable {
    public static let maximumAge: TimeInterval = 120
    public let modelID: String
    public let capturedAt: Date

    fileprivate init(modelID: String, capturedAt: Date) {
        self.modelID = modelID
        self.capturedAt = capturedAt
    }

    public func isValid(for modelID: String, at now: Date) -> Bool {
        let age = now.timeIntervalSince(capturedAt)
        return self.modelID == modelID && age.isFinite && age >= 0 && age <= Self.maximumAge
    }
}

public enum ChatModelListParser {
    /// Parses the OpenAI-compatible `{"object": "list", "data": [{"id": …}]}`
    /// shape served by both the local endpoint and the Darkbloom network.
    /// `object` is validated when present; per-model display fields beyond
    /// `id` do not affect text listing. Image capability requires strict explicit
    /// `input_modalities`; unknown or malformed metadata grants no capability.
    /// Unknown, blank, duplicated or oversized IDs fail the
    /// parse so a picker can never offer an unverified model.
    public static func parse(_ data: Data, capturedAt: Date) throws -> ChatModelListSnapshot {
        guard data.count <= ChatModelListSnapshot.maximumResponseBytes else {
            throw ChatClientError.responseTooLarge
        }
        struct Envelope: Decodable {
            struct Entry: Decodable {
                let id: String?
                let object: String?
                let inputModalities: [String]?
                enum CodingKeys: String, CodingKey { case id, object, inputModalities = "input_modalities" }

                init(from decoder: any Decoder) throws {
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    id = try container.decodeIfPresent(String.self, forKey: .id)
                    object = try container.decodeIfPresent(String.self, forKey: .object)
                    // Bad optional capability metadata must not remove an
                    // otherwise valid text model from the existing picker.
                    inputModalities = try? container.decode([String].self, forKey: .inputModalities)
                }
            }
            let object: String?
            let data: [Entry]?
        }
        let envelope: Envelope
        do {
            envelope = try JSONDecoder().decode(Envelope.self, from: data)
        } catch {
            throw ChatClientError.invalidResponse
        }
        if let object = envelope.object, object != "list" {
            throw ChatClientError.invalidResponse
        }
        guard let entries = envelope.data else { throw ChatClientError.invalidResponse }
        guard entries.count <= ChatModelListSnapshot.maximumModels else {
            throw ChatClientError.invalidResponse
        }
        var ids: [String] = []
        var modalities: [String: Set<ChatInputModality>] = [:]
        for entry in entries {
            guard let id = entry.id,
                  !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  id.utf8.count <= 512,
                  !ids.contains(id)
            else { throw ChatClientError.invalidResponse }
            ids.append(id)
            if let values = entry.inputModalities, !values.isEmpty, values.count <= ChatInputModality.allCases.count {
                let known = values.compactMap(ChatInputModality.init(rawValue:))
                if known.count == values.count, Set(known).count == values.count {
                    modalities[id] = Set(known)
                }
            }
        }
        return ChatModelListSnapshot(modelIDs: ids, capturedAt: capturedAt, inputModalitiesByModelID: modalities)
    }
}

/// One turn in a chat completion request. Text-only content preserves the
/// original string wire shape. Images use bounded inline content parts.
public struct ChatMessagePayload: Equatable, Sendable, Codable {
    public enum Role: String, Sendable, Codable {
        case system, user, assistant
    }

    public let role: Role
    public let content: String
    public let images: [ChatImageAttachment]

    public init(role: Role, content: String, images: [ChatImageAttachment] = []) {
        self.role = role
        self.content = content
        self.images = images
    }

    private enum CodingKeys: String, CodingKey { case role, content }
    private enum PartKeys: String, CodingKey { case type, text, image_url, url }

    public func encode(to encoder: any Encoder) throws {
        try ChatImageAttachment.validate(images)
        guard images.isEmpty || role == .user else { throw ChatImageError.imagesRequireUserRole }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(role, forKey: .role)
        if images.isEmpty {
            try container.encode(content, forKey: .content)
        } else {
            var parts = container.nestedUnkeyedContainer(forKey: .content)
            if !content.isEmpty {
                var part = parts.nestedContainer(keyedBy: PartKeys.self)
                try part.encode("text", forKey: .type)
                try part.encode(content, forKey: .text)
            }
            for image in images {
                var part = parts.nestedContainer(keyedBy: PartKeys.self)
                try part.encode("image_url", forKey: .type)
                var value = part.nestedContainer(keyedBy: PartKeys.self, forKey: .image_url)
                try value.encode(image.dataURI, forKey: .url)
            }
        }
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let role = try container.decode(Role.self, forKey: .role)
        if let text = try? container.decode(String.self, forKey: .content) {
            self.init(role: role, content: text)
            return
        }
        var parts = try container.nestedUnkeyedContainer(forKey: .content)
        guard let count = parts.count, count <= ChatImageAttachment.maximumImagesPerRequest + 1 else {
            throw ChatImageError.tooManyImages
        }
        var text = ""
        var images: [ChatImageAttachment] = []
        var hasText = false
        while !parts.isAtEnd {
            let part = try parts.nestedContainer(keyedBy: PartKeys.self)
            switch try part.decode(String.self, forKey: .type) {
            case "text":
                guard !hasText else { throw ChatClientError.invalidResponse }
                text = try part.decode(String.self, forKey: .text)
                hasText = true
            case "image_url":
                let image = try part.nestedContainer(keyedBy: PartKeys.self, forKey: .image_url)
                images.append(try ChatImageAttachment.decodeDataURI(image.decode(String.self, forKey: .url)))
            default: throw ChatClientError.invalidResponse
            }
        }
        guard images.isEmpty || role == .user else { throw ChatImageError.imagesRequireUserRole }
        try ChatImageAttachment.validate(images)
        self.init(role: role, content: text, images: images)
    }
}

/// The validated text completion request. The URL is fixed by the
/// route; the body is bounded before transmission.
public struct ChatCompletionRequest: CustomStringConvertible, Sendable {
    public static let maximumBodyBytes = 256 * 1_024
    public static let maximumLocalImageBodyBytes = 8 * 1_024 * 1_024
    public static let maximumNetworkImageBodyBytes = 8 * 1_024 * 1_024
    public static let maximumMessages = 64
    public static let maximumMessageCharacters = 16_384
    public static let networkTimeoutInterval: TimeInterval = 300
    public static let localTimeoutInterval: TimeInterval = 300

    public let urlRequest: URLRequest

    public var description: String {
        "POST \(urlRequest.url?.absoluteString ?? "invalid-url") (chat completion)"
    }

    /// Builds the request for the Darkbloom network route. The host is fixed;
    /// there is no redirect following and no route derivation from user text.
    public static func makeNetwork(
        consumerKey: String,
        model: String,
        messages: [ChatMessagePayload],
        stream: Bool = false,
        networkImageCapability: ChatNetworkImageCapability? = nil,
        now: Date = Date()
    ) throws -> Self {
        try validateNetworkImageCapability(model: model, messages: messages, capability: networkImageCapability, now: now)
        let request = try make(
            url: URL(string: "https://api.darkbloom.dev/v1/chat/completions")!,
            token: consumerKey,
            model: model,
            messages: messages,
            timeout: networkTimeoutInterval,
            stream: stream
        )
        guard (request.urlRequest.httpBody?.count ?? 0) <= maximumNetworkImageBodyBytes else {
            throw ChatClientError.requestTooLarge
        }
        return request
    }

    static func validateNetworkImageCapability(model: String, messages: [ChatMessagePayload], capability: ChatNetworkImageCapability?, now: Date) throws {
        guard messages.contains(where: { !$0.images.isEmpty }) else { return }
        guard let capability, capability.isValid(for: model, at: now) else {
            throw ChatImageError.networkImagesUnsupported
        }
    }

    /// One tiny owner-only inference after a model switch. The mandatory self
    /// header prevents a fallback to paid fleet routing; no caller can change
    /// the endpoint or request size.
    public static func makeSelfRouteWarmup(consumerKey: String, model: String) throws -> Self {
        guard ConsumerAPIKey.isValid(consumerKey) else { throw ChatClientError.missingConsumerKey }
        var request = try make(
            url: URL(string: "https://api.darkbloom.dev/v1/chat/completions")!,
            token: consumerKey,
            model: model,
            messages: [ChatMessagePayload(role: .user, content: "Reply OK.")],
            timeout: 90,
            maxTokens: 8
        ).urlRequest
        request.setValue("self", forHTTPHeaderField: "X-Darkbloom-Route")
        return Self(urlRequest: request)
    }

    /// Builds the request for the local hosting endpoint. `origin` must be a
    /// normalized `ChatLocalEndpoint` origin (`scheme://host[:port]`, no
    /// path); a URL carrying a path is rejected so `/v1` can never be
    /// doubled. `token` nil means an explicitly unauthenticated endpoint and
    /// omits the Authorization header; a non-nil token must be usable. The
    /// only base-URL normalization lives in `ChatLocalEndpoint.make`.
    public static func makeLocal(
        origin: URL,
        token: String?,
        model: String,
        messages: [ChatMessagePayload],
        maxTokens: Int? = nil,
        stream: Bool = false
    ) throws -> Self {
        if let token {
            guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  token.utf8.count <= 256
            else { throw ChatClientError.invalidEndpoint }
        }
        guard let components = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "http" || components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.path.isEmpty || components.path == "/",
              components.user == nil, components.password == nil,
              components.query == nil, components.fragment == nil,
              let url = URL(string: origin.absoluteString + "/v1/chat/completions")
        else { throw ChatClientError.invalidEndpoint }
        return try make(
            url: url, token: token, model: model, messages: messages,
            timeout: localTimeoutInterval, maxTokens: maxTokens, stream: stream
        )
    }

    private static func make(
        url: URL,
        token: String?,
        model: String,
        messages: [ChatMessagePayload],
        timeout: TimeInterval,
        maxTokens: Int? = nil,
        stream: Bool = false
    ) throws -> Self {
        try validate(model: model, messages: messages)
        let body = try Self.encode(model: model, messages: messages, maxTokens: maxTokens, stream: stream)
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(stream ? "text/event-stream" : "application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return Self(urlRequest: request)
    }

    static func validate(model: String, messages: [ChatMessagePayload]) throws {
        guard !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              model.utf8.count <= 512
        else { throw ChatClientError.missingModelID }
        guard (1...maximumMessages).contains(messages.count) else {
            throw ChatClientError.requestTooLarge
        }
        var images: [ChatImageAttachment] = []
        for message in messages {
            guard message.content.utf8.count <= maximumMessageCharacters else { throw ChatClientError.requestTooLarge }
            guard message.images.isEmpty || message.role == .user else { throw ChatImageError.imagesRequireUserRole }
            images.append(contentsOf: message.images)
            try ChatImageAttachment.validate(images)
        }
    }

    static func encode(model: String, messages: [ChatMessagePayload], maxTokens: Int? = nil, stream: Bool = false) throws -> Data {
        struct Body: Encodable {
            let model: String
            let messages: [ChatMessagePayload]
            let stream: Bool
            let max_tokens: Int?
            let stream_options: StreamOptions?
        }
        struct StreamOptions: Encodable {
            let include_usage = true
        }
        let data = try JSONEncoder().encode(Body(model: model, messages: messages, stream: stream, max_tokens: maxTokens, stream_options: stream ? StreamOptions() : nil))
        let limit = messages.contains(where: { !$0.images.isEmpty }) ? maximumLocalImageBodyBytes : maximumBodyBytes
        guard data.count <= limit else { throw ChatClientError.requestTooLarge }
        return data
    }
}

/// The outcome of one successful non-streaming completion. `content` is the
/// assistant's visible text; usage counters are optional because the local
/// endpoint may omit them.
public struct ChatCompletionOutcome: Equatable, Sendable {
    public let content: String
    public let model: String?
    public let finishReason: String?
    public let promptTokens: Int?
    public let completionTokens: Int?

    public init(
        content: String,
        model: String? = nil,
        finishReason: String? = nil,
        promptTokens: Int? = nil,
        completionTokens: Int? = nil
    ) {
        self.content = content
        self.model = model
        self.finishReason = finishReason
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
    }
}

public enum ChatCompletionParser {
    public static func parse(_ data: Data) throws -> ChatCompletionOutcome {
        struct Response: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable {
                    let role: String?
                    let content: String?
                }
                let message: Message?
                let finishReason: String?

                enum CodingKeys: String, CodingKey {
                    case message
                    case finishReason = "finish_reason"
                }
            }
            struct Usage: Decodable {
                let promptTokens: Int?
                let completionTokens: Int?

                enum CodingKeys: String, CodingKey {
                    case promptTokens = "prompt_tokens"
                    case completionTokens = "completion_tokens"
                }
            }
            let model: String?
            let choices: [Choice]?
            let usage: Usage?
        }
        let response: Response
        do {
            response = try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw ChatClientError.invalidResponse
        }
        guard let choice = response.choices?.first,
              let message = choice.message,
              let content = message.content
        else { throw ChatClientError.invalidResponse }
        if let role = message.role, role != "assistant" {
            throw ChatClientError.invalidResponse
        }
        if let usage = response.usage {
            let valid = { (value: Int?) in value == nil || value! >= 0 }
            guard valid(usage.promptTokens), valid(usage.completionTokens) else {
                throw ChatClientError.invalidResponse
            }
        }
        if let model = response.model, model.utf8.count > 512 {
            throw ChatClientError.invalidResponse
        }
        if let finishReason = choice.finishReason, finishReason.utf8.count > 64 {
            throw ChatClientError.invalidResponse
        }
        return ChatCompletionOutcome(
            content: content,
            model: response.model,
            finishReason: choice.finishReason,
            promptTokens: response.usage?.promptTokens,
            completionTokens: response.usage?.completionTokens
        )
    }
}
