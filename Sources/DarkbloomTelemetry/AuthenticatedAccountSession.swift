import CryptoKit
import Darwin
import Foundation

/// Safe to carry through a chart read. Never contains an account ID or token.
public struct AccountEarningsContext: Hashable, Sendable {
    public let accountScope: String
    public let generation: UUID
    /// Constructing a value does not authenticate it; the session validates it.
    public init(accountScope: String, generation: UUID) {
        self.accountScope = accountScope; self.generation = generation
    }
}

public struct AccountEarningsSessionState: Equatable, Sendable {
    public let context: AccountEarningsContext?
    public let ledgerReady: Bool
    public let revision: UUID
    public init(context: AccountEarningsContext?, ledgerReady: Bool, revision: UUID) {
        self.context = context; self.ledgerReady = ledgerReady; self.revision = revision
    }
    public static let unavailable = Self(context: nil, ledgerReady: false,
        revision: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
}

/// Owns authentication identity separately from successful ledger ingestion.
/// Copies of AuthenticatedEarningsClient share this actor, not separate sessions.
actor AuthenticatedAccountSession {
    struct Request: Sendable {
        let id: UUID
        let token: String
    }

    private let tokenURL: URL
    private var fingerprint: SHA256.Digest?
    private var accountID: String?
    private var latestRequest: UUID?
    private var state = AccountEarningsSessionState(context: nil, ledgerReady: false, revision: UUID())
    private var observers: [UUID: AsyncStream<AccountEarningsSessionState>.Continuation] = [:]
    private var monitor: CredentialFileMonitor?
    private var monitoredNodes: [CredentialFileNode] = []
    private var lastStamp: CredentialFileStamp?

    init(tokenURL: URL) { self.tokenURL = tokenURL }

    deinit { for observer in observers.values { observer.finish() } }

    func snapshot() -> AccountEarningsSessionState {
        _ = refreshCredential()
        return state
    }

    func changes() -> AsyncStream<AccountEarningsSessionState> {
        _ = refreshCredential()
        let id = UUID()
        let (stream, continuation) = AsyncStream<AccountEarningsSessionState>.makeStream(bufferingPolicy: .bufferingNewest(1))
        observers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id) }
        }
        return stream
    }

    func beginRequest() throws -> Request {
        guard let token = refreshCredential() else { throw AccountEarningsClientError.missingToken }
        let request = Request(id: UUID(), token: token)
        latestRequest = request.id
        return request
    }

    func require(_ request: Request) throws {
        try Task.checkCancellation()
        guard refreshCredential() != nil, latestRequest == request.id else {
            throw AccountEarningsClientError.sessionChanged
        }
    }

    func authenticate(accountID: String, request: Request) throws -> AccountEarningsContext {
        try require(request)
        let scope = try CreditLedgerPersistence.scope(accountID)
        if self.accountID != accountID || state.context == nil {
            self.accountID = accountID
            let context = AccountEarningsContext(accountScope: scope, generation: UUID())
            publish(AccountEarningsSessionState(context: context, ledgerReady: false, revision: UUID()))
        }
        guard let context = state.context else { throw AccountEarningsClientError.sessionChanged }
        return context
    }

    func didIngest(context: AccountEarningsContext, request: Request) throws {
        try require(request)
        guard state.context == context else { throw AccountEarningsClientError.sessionChanged }
        if !state.ledgerReady {
            publish(AccountEarningsSessionState(context: context, ledgerReady: true, revision: UUID()))
        }
    }

    func reject(_ request: Request) throws {
        // Validation and revocation share this actor turn. Supersession in the
        // caller's require→reject suspension must not be reported as current 401.
        try require(request)
        revoke()
    }

    func identity(for context: AccountEarningsContext) throws -> String {
        try validate(context)
        guard state.ledgerReady, let accountID else { throw AccountEarningsClientError.sessionChanged }
        return accountID
    }

    func validate(_ context: AccountEarningsContext) throws {
        try Task.checkCancellation()
        guard refreshCredential() != nil, state.context == context else {
            throw AccountEarningsClientError.sessionChanged
        }
    }

    private func removeObserver(_ id: UUID) { observers[id] = nil }

    private func publish(_ value: AccountEarningsSessionState) {
        state = value
        for observer in observers.values { observer.yield(value) }
    }

    private func revoke() {
        latestRequest = nil
        accountID = nil
        guard state.context != nil || state.ledgerReady else { return }
        publish(AccountEarningsSessionState(context: nil, ledgerReady: false, revision: UUID()))
    }

    /// Always reread at an API boundary; notifications only accelerate clearing.
    private func refreshCredential() -> String? {
        let credential = Self.readCredential(tokenURL)
        let token = credential?.token
        let current = token.map { SHA256.hash(data: Data($0.utf8)) }
        // Replacing/re-writing even identical bytes is a new local auth
        // boundary. A fast A→B→A replacement must not reuse the old A context.
        if current != fingerprint || (fingerprint != nil && credential?.stamp != lastStamp) {
            fingerprint = current
            revoke()
            // A first credential change can also invalidate an in-flight
            // request before any account has been authenticated.
            latestRequest = nil
        }
        lastStamp = credential?.stamp
        rebuildMonitorIfNeeded()
        return token
    }

    private func credentialEvent(forceRead: Bool) {
        let stamp = CredentialFileStamp(url: tokenURL)
        if forceRead || stamp != lastStamp { _ = refreshCredential() }
        else { rebuildMonitorIfNeeded() }
    }

    private func rebuildMonitorIfNeeded() {
        let urls = [tokenURL, tokenURL.deletingLastPathComponent(), tokenURL.deletingLastPathComponent().deletingLastPathComponent()]
        let nodes = urls.compactMap(CredentialFileNode.init)
        guard monitor == nil || nodes != monitoredNodes else { return }
        monitoredNodes = nodes
        monitor = CredentialFileMonitor(nodes: nodes, tokenURL: tokenURL) { [weak self] forceRead in
            Task { await self?.credentialEvent(forceRead: forceRead) }
        }
    }

    private static func readCredential(_ url: URL) -> (token: String, stamp: CredentialFileStamp)? {
        // Bounded reads also cover replacement with an unexpectedly large file.
        let descriptor = url.path.withCString { open($0, O_RDONLY | O_NONBLOCK | O_CLOEXEC) }
        guard descriptor >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        defer { try? handle.close() }
        var info = stat()
        guard fstat(descriptor, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size >= 0, info.st_size <= 65_536 else { return nil }
        let before = CredentialFileStamp(url: url, info: info)
        guard let data = try? handle.read(upToCount: 65_537), data.count <= 65_536,
              let text = String(data: data, encoding: .utf8) else { return nil }
        guard fstat(descriptor, &info) == 0,
              before == CredentialFileStamp(url: url, info: info),
              before == CredentialFileStamp(url: url), data.count == info.st_size else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.unicodeScalars.contains(where: {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }) else { return nil }
        return (token, before)
    }
}

private struct CredentialFileNode: Equatable {
    let url: URL
    let device: Int32
    let inode: UInt64
    init?(url: URL) {
        var info = stat()
        guard url.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) == 0 else { return nil }
        let kind = info.st_mode & S_IFMT
        guard kind == S_IFREG || kind == S_IFDIR else { return nil }
        self.url = url; device = info.st_dev; inode = info.st_ino
    }
    init(url: URL, info: stat) { self.url = url; device = info.st_dev; inode = info.st_ino }
}

private struct CredentialFileStamp: Equatable {
    let node: CredentialFileNode
    let size: Int64
    let seconds: Int
    let nanoseconds: Int
    init?(url: URL) {
        var info = stat()
        guard url.path.withCString({ fstatat(AT_FDCWD, $0, &info, 0) }) == 0 else { return nil }
        self.init(url: url, info: info)
    }
    init(url: URL, info: stat) {
        node = CredentialFileNode(url: url, info: info); size = info.st_size
        seconds = info.st_mtimespec.tv_sec; nanoseconds = info.st_mtimespec.tv_nsec
    }
}

/// Sources own their descriptors until cancellation completes. No timer/poller.
private final class CredentialFileMonitor: @unchecked Sendable {
    private let sources: [DispatchSourceFileSystemObject]
    init(nodes: [CredentialFileNode], tokenURL: URL, onChange: @escaping @Sendable (Bool) -> Void) {
        sources = nodes.compactMap { node in
            let descriptor = node.url.path.withCString { open($0, O_EVTONLY | O_NONBLOCK | O_CLOEXEC) }
            guard descriptor >= 0 else { return nil }
            var info = stat()
            guard fstat(descriptor, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFREG || (info.st_mode & S_IFMT) == S_IFDIR else {
                close(descriptor); return nil
            }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor,
                eventMask: [.write, .delete, .rename, .attrib, .revoke], queue: .global(qos: .utility))
            let isToken = node.url == tokenURL
            source.setEventHandler { onChange(isToken) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
    }
    deinit { for source in sources { source.cancel() } }
}
