import DarkbloomCompanionProtocol
import Foundation
import Network

public final class AuthenticatedCompanionServer: @unchecked Sendable {
    public static let defaultAuthenticatedIdleTimeout: TimeInterval = 300
    public typealias Authenticator = @Sendable (SessionAuthentication, SessionChallenge) async -> Bool
    public typealias Handler = @Sendable (UUID, Envelope) async throws -> Envelope
    public typealias BootstrapHandler = @Sendable (Envelope) async throws -> Envelope

    private struct Session {
        let deviceID: UUID?
        let connection: CompanionTLSConnection
        let task: Task<Void, Never>
    }
    private final class State: @unchecked Sendable {
        let lock = NSLock()
        var stopped = false
        var sessions: [UUID: Session] = [:]
    }

    private let state = State()
    private let listener: NWListener
    private let queue = DispatchQueue(label: "darkbloom.companion.authenticated-listener")
    private let authenticate: Authenticator
    private let handler: Handler
    private let bootstrapHandler: BootstrapHandler?
    private let authenticatedIdleTimeout: TimeInterval
    private let now: @Sendable () -> Date
    private let onError: @Sendable (String) -> Void

    public init(
        identity: CompanionIdentity,
        port: UInt16? = nil,
        bindHost: String = "127.0.0.1",
        authenticate: @escaping Authenticator,
        bootstrapHandler: BootstrapHandler? = nil,
        authenticatedIdleTimeout: TimeInterval = AuthenticatedCompanionServer.defaultAuthenticatedIdleTimeout,
        now: @escaping @Sendable () -> Date = Date.init,
        onError: @escaping @Sendable (String) -> Void = { _ in },
        handler: @escaping Handler
    ) throws {
        self.authenticate = authenticate
        self.bootstrapHandler = bootstrapHandler
        guard authenticatedIdleTimeout >= 1, authenticatedIdleTimeout <= 3_600 else {
            throw CompanionTransportError.invalidEndpoint
        }
        self.authenticatedIdleTimeout = authenticatedIdleTimeout
        self.handler = handler
        self.now = now
        self.onError = onError
        let parameters = TLSPolicy.parameters(identity: identity, pin: nil, peerRole: .phone)
        let endpointPort = port.flatMap(NWEndpoint.Port.init(rawValue:)) ?? .any
        parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(bindHost), port: endpointPort)
        listener = try NWListener(using: parameters)
    }

    public var activeConnections: Int { state.lock.withLock { state.sessions.count } }

    public func start() async throws -> UInt16 {
        try await bounded(timeout: 10, abort: { self.listener.cancel() }) { [self] pending in
            self.listener.newConnectionHandler = { [weak self] connection in
                guard let self else { connection.cancel(); return }
                self.accept(connection)
            }
            self.listener.stateUpdateHandler = { [weak self] status in
                switch status {
                case .ready:
                    guard let port = self?.listener.port else {
                        pending.resolve(.failure(CompanionTransportError.invalidEndpoint)); return
                    }
                    pending.resolve(.success(port.rawValue))
                case .failed(let error): pending.resolve(.failure(error))
                case .cancelled: pending.resolve(.failure(CompanionTransportError.cancelled))
                default: break
                }
            }
            self.listener.start(queue: self.queue)
        }
    }

    public func revoke(_ deviceID: UUID) {
        let sessions = state.lock.withLock {
            state.sessions.values.filter { $0.deviceID == deviceID }
        }
        for session in sessions { session.connection.cancel(); session.task.cancel() }
    }

    public func stop() async {
        let sessions = state.lock.withLock {
            state.stopped = true
            return Array(state.sessions.values)
        }
        listener.cancel()
        for session in sessions { session.connection.cancel(); session.task.cancel() }
        for session in sessions { await session.task.value }
    }

    private func accept(_ native: NWConnection) {
        state.lock.withLock {
            guard !state.stopped, state.sessions.count < 8 else { native.cancel(); return }
            let id = UUID()
            let connection = CompanionTLSConnection(native)
            let task = Task {
                var authenticatedDevice: UUID?
                defer {
                    connection.cancel()
                    _ = self.state.lock.withLock { self.state.sessions.removeValue(forKey: id) }
                }
                do {
                    try await connection.start(timeout: 10)
                    let challenge = SessionChallenge(
                        nonce: Self.randomBytes(count: 32),
                        expiresAt: self.now().addingTimeInterval(10)
                    )
                    try await connection.sendEnvelope(.init(
                        requestID: UUID(), payload: .sessionChallenge(challenge)
                    ))
                    let reply = try await connection.receiveEnvelope(timeout: 10)
                    if case .enrollmentProof = reply.payload, let bootstrapHandler = self.bootstrapHandler {
                        try reply.validate(for: .bootstrap)
                        try await connection.sendEnvelope(bootstrapHandler(reply))
                        return
                    }
                    guard self.now() <= challenge.expiresAt,
                          case let .sessionAuthenticate(authentication) = reply.payload,
                          authentication.nonce == challenge.nonce,
                          await self.authenticate(authentication, challenge) else { return }
                    authenticatedDevice = authentication.deviceID
                    self.state.lock.withLock {
                        guard let old = self.state.sessions[id] else { return }
                        self.state.sessions[id] = Session(
                            deviceID: authentication.deviceID,
                            connection: old.connection,
                            task: old.task
                        )
                    }
                    while !Task.isCancelled {
                        let envelope = try await connection.receiveEnvelope(
                            timeout: self.authenticatedIdleTimeout
                        )
                        try envelope.validate(for: .authenticated)
                        let response = try await self.handler(authentication.deviceID, envelope)
                        try await connection.sendEnvelope(response)
                    }
                } catch {
                    self.onError(String(describing: error))
                    _ = authenticatedDevice
                }
            }
            state.sessions[id] = Session(deviceID: nil, connection: connection, task: task)
        }
    }

    private static func randomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}
