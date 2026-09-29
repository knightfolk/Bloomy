import Foundation

public enum LocalModelSwapResult: Equatable, Sendable {
    case sent
    case endpointUnavailable
    case modelUnavailable
    case failed
}

/// Returns a loopback unified endpoint only when it belongs to the same
/// provider process. The app supplies the provider-owned discovery check.
public protocol LocalModelSwapEndpointProviding: Sendable {
    func endpoint(expectedProcessIdentity: ProcessIdentity) async -> ChatLocalEndpoint?
}

public protocol LocalModelSwapRequesting: Sendable {
    func request(
        modelID: String,
        expectedProcessIdentity: ProcessIdentity,
        canSend: @escaping @Sendable () async -> Bool
    ) async -> LocalModelSwapResult
}

/// A tiny completion to this Mac's own unified provider endpoint. This is an
/// ordinary inference request, not a configuration or residency command.
/// The caller must verify the resulting local residency separately.
public struct LocalModelSwapClient: LocalModelSwapRequesting, Sendable {
    private let endpointProvider: any LocalModelSwapEndpointProviding
    private let session: URLSession

    public init(
        endpointProvider: any LocalModelSwapEndpointProviding,
        session: URLSession? = nil
    ) {
        self.endpointProvider = endpointProvider
        self.session = session ?? ChatHTTPSession.shared
    }

    public func request(
        modelID: String,
        expectedProcessIdentity: ProcessIdentity,
        canSend: @escaping @Sendable () async -> Bool
    ) async -> LocalModelSwapResult {
        guard let endpoint = await endpointProvider.endpoint(
            expectedProcessIdentity: expectedProcessIdentity
        ), Self.isLoopback(endpoint) else { return .endpointUnavailable }
        do {
            var listing = URLRequest(
                url: endpoint.origin.appendingPathComponent("v1/models"),
                timeoutInterval: 20
            )
            listing.httpMethod = "GET"
            listing.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            listing.setValue("application/json", forHTTPHeaderField: "Accept")
            endpoint.withToken { listing.setValue("Bearer \($0)", forHTTPHeaderField: "Authorization") }
            let models = try await ChatRouteExecutor.execute(
                request: listing,
                session: session,
                successCapacity: ChatModelListSnapshot.maximumResponseBytes
            ) { data in
                try ChatModelListParser.parse(data, capturedAt: Date())
            }
            guard models.modelIDs.contains(modelID) else { return .modelUnavailable }

            // A model list may take time. Recheck this Mac's process and idle
            // state immediately before the one inference request.
            guard !Task.isCancelled,
                  let current = await endpointProvider.endpoint(
                    expectedProcessIdentity: expectedProcessIdentity
                  ),
                  Self.isLoopback(current),
                  current.origin == endpoint.origin else { return .endpointUnavailable }
            guard await canSend() else { return .failed }
            var completion = try ChatCompletionRequest.makeLocal(
                origin: current.origin,
                token: current.withToken { $0 },
                model: modelID,
                messages: [ChatMessagePayload(role: .user, content: "Reply OK.")],
                maxTokens: 8
            ).urlRequest
            completion.timeoutInterval = 90
            _ = try await ChatRouteExecutor.execute(
                request: completion,
                session: session,
                successCapacity: 64 * 1_024
            ) { data in
                try ChatCompletionParser.parse(data)
            }
            return .sent
        } catch is CancellationError {
            return .failed
        } catch {
            return .failed
        }
    }

    private static func isLoopback(_ endpoint: ChatLocalEndpoint) -> Bool {
        guard let host = endpoint.origin.host?.lowercased(),
              endpoint.origin.scheme?.lowercased() == "http" else { return false }
        return host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }
}
