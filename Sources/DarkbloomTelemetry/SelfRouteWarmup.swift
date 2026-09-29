import Foundation

public enum SelfRouteWarmupResult: Equatable, Sendable {
    case sent
    case missingKey
    case modelUnavailable
    case keyRejected
    case failed
}

public protocol SelfRouteWarmupProbing: Sendable {
    func warm(modelID: String, family: String) async -> SelfRouteWarmupResult
}

/// Sends one bounded, free self-route completion after a confirmed CLI switch.
/// This can load the selected model; it cannot make the public scheduler send
/// jobs. Nothing retries or falls back to the paid network route.
public struct SelfRouteWarmupClient: SelfRouteWarmupProbing, Sendable {
    private let keyStore: any ConsumerKeyReading
    private let session: URLSession
    private let canSend: @Sendable () async -> Bool

    public init(
        keyStore: any ConsumerKeyReading,
        session: URLSession? = nil,
        canSend: @escaping @Sendable () async -> Bool = { true }
    ) {
        self.keyStore = keyStore
        self.session = session ?? ChatHTTPSession.shared
        self.canSend = canSend
    }

    public func warm(modelID: String, family: String) async -> SelfRouteWarmupResult {
        guard let listingRequest = keyStore.withConsumerKey({ key -> URLRequest? in
            guard ConsumerAPIKey.isValid(key) else { return nil }
            var request = URLRequest(url: NetworkChatClient.modelsURL, timeoutInterval: 20)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("self", forHTTPHeaderField: "X-Darkbloom-Route")
            return request
        }) ?? nil else { return .missingKey }

        do {
            let models = try await ChatRouteExecutor.execute(
                request: listingRequest,
                session: session,
                successCapacity: ChatModelListSnapshot.maximumResponseBytes
            ) { data in
                try ChatModelListParser.parse(data, capturedAt: Date())
            }
            let alias: String
            if models.modelIDs.contains(modelID) {
                alias = modelID
            } else if !family.isEmpty && models.modelIDs.contains(family) {
                alias = family
            } else {
                return .modelUnavailable
            }
            // The models request can take long enough for a real job or a
            // provider action to begin. Recheck immediately before POST.
            guard !Task.isCancelled, await canSend() else { return .failed }
            guard let completionRequest = try keyStore.withConsumerKey({ key -> ChatCompletionRequest? in
                guard ConsumerAPIKey.isValid(key) else { return nil }
                return try ChatCompletionRequest.makeSelfRouteWarmup(consumerKey: key, model: alias)
            }) ?? nil else { return .missingKey }
            _ = try await ChatRouteExecutor.execute(
                request: completionRequest.urlRequest,
                session: session,
                successCapacity: 64 * 1_024
            ) { data in
                try ChatCompletionParser.parse(data)
            }
            return .sent
        } catch ChatClientError.unauthorized {
            return .keyRejected
        } catch ChatClientError.consumerKeyRejected {
            return .keyRejected
        } catch is CancellationError {
            return .failed
        } catch {
            return .failed
        }
    }
}
