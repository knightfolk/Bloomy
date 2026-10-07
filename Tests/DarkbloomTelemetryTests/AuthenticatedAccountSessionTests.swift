import Darwin
import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Authenticated financial sessions")
struct AuthenticatedAccountSessionTests {
    @Test("compatibility financial queries require authentication and stay within the current account")
    func compatibilityReadsAreScoped() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            let b = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-B"
            return try response(request, account: b ? "account-B" : "account-A", amount: b ? 20 : 10)
        }
        #expect(try await client.activity(in: range, unit: .hour, calendar: calendar) == nil)
        #expect(try await client.activityModels(in: range).isEmpty)
        _ = try await client.fetchWithContext(now: captured)
        #expect(try await client.activity(in: range, unit: .hour, calendar: calendar)?.compactMap(\.totals).reduce(0) { $0 + $1.workMicroUSD } == 10)
        #expect(try await client.activityModels(in: range) == ["gemma"])
        #expect(try await client.modelActivity(in: range, unit: .hour, calendar: calendar, model: "gemma")?.compactMap(\.totals).reduce(0) { $0 + $1.jobs } == 1)
        #expect(try await client.activityByModel(in: range, unit: .hour, calendar: calendar)?.first?.workMicroUSD == 10)
        #expect(try await client.modelHourlyEarningsAverages(in: range)?.first?.workMicroUSD == 10)
        #expect(try await client.modelWorkEarnings(in: range, calendar: calendar).first?.workMicroUSD == 10)
        #expect(try await client.todayEarningsSummary(now: captured, calendar: calendar)?.microUSD == 10)
        #expect(try await client.weekEarningsSummary(now: captured, calendar: calendar)?.microUSD == 10)
        #expect(try await client.jobCompletionSummary(now: captured, calendar: calendar)?.completedToday == 1)
        try fixture.token("token-B")
        #expect(try await client.activity(in: range, unit: .hour, calendar: calendar) == nil)
        #expect(try await client.todayEarningsSummary(now: captured, calendar: calendar) == nil)
        #expect(try await client.modelWorkEarnings(in: range, calendar: calendar).isEmpty)
        _ = try await client.fetchWithContext(now: captured)
        #expect(try await client.activity(in: range, unit: .hour, calendar: calendar)?.compactMap(\.totals).reduce(0) { $0 + $1.workMicroUSD } == 20)
        #expect(try await client.todayEarningsSummary(now: captured, calendar: calendar)?.microUSD == 20)
    }

    @Test("default context-bearing fetch binds before suspension and rejects a changed session")
    func defaultFetchDoesNotRelabelOldResults() async throws {
        for throwsTransport in [false, true] {
            let gate = SessionHoldGate()
            let fixture = DefaultScopedFetchFixture(gate: gate, throwsTransport: throwsTransport)
            let read = Task { try await fixture.fetchWithContext(now: captured) }
            let entered: Void? = await next(gate.entered)
            #expect(entered != nil)
            await fixture.changeAccount()
            await gate.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await read.value }
        }
    }

    @Test("a selected model does not read unrelated models through the account-wide range limit")
    func selectedModelHasItsOwnReadBudget() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            let (data, http) = try response(request, account: "account-A", amount: 1)
            var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let row = (json["earnings"] as! [[String: Any]])[0]
            json["earnings"] = (1...129).map { id -> [String: Any] in
                var next = row; next["id"] = id; next["model"] = id == 1 ? "gemma" : "other-\(id)"; return next
            }
            json["count"] = 129; json["recent_count"] = 129; json["total_micro_usd"] = 129
            return (try JSONSerialization.data(withJSONObject: json), http)
        }
        _ = try await client.fetchWithContext(now: captured)
        await #expect(throws: ActivityCalendarError.tooManyBuckets) {
            try await client.activity(in: range, unit: .hour, calendar: calendar)
        }
        let selected = try await client.modelActivity(in: range, unit: .hour, calendar: calendar, model: "gemma")
        #expect(selected?.compactMap(\.totals).reduce(0) { $0 + $1.workMicroUSD } == 1)
        #expect(selected?.compactMap(\.totals).reduce(0) { $0 + $1.jobs } == 1)
        #expect(try await client.modelActivity(in: range, unit: .hour, calendar: calendar, model: "base_reward") == nil)
    }

    @Test("A to B to A creates distinct generations and failed B readiness cannot retain A")
    func accountGenerations() async throws {
        let fixture = try SessionFixture()
        let session = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        let a = try await authorize(session, account: "account-A")
        try fixture.token("token-B")
        #expect(await session.snapshot().context == nil)
        let request = try await session.beginRequest()
        let b = try await session.authenticate(accountID: "account-B", request: request)
        #expect(await session.snapshot().context == b)
        #expect(await session.snapshot().ledgerReady == false)
        await #expect(throws: AccountEarningsClientError.sessionChanged) { try await session.identity(for: a) }
        await #expect(throws: AccountEarningsClientError.sessionChanged) { try await session.identity(for: b) }
        try await session.didIngest(context: b, request: request)
        try fixture.token("token-A")
        let again = try await authorize(session, account: "account-A")
        #expect(again.accountScope == a.accountScope)
        #expect(again.generation != a.generation)
        #expect(again != b)
        await #expect(throws: AccountEarningsClientError.sessionChanged) { try await session.identity(for: a) }
        #expect(!String(reflecting: again).contains("account-A"))
        #expect(!String(reflecting: again).contains("token-A"))
    }

    @Test("same-account refresh preserves generation but rejects superseded request tickets")
    func refreshOrdering() async throws {
        let fixture = try SessionFixture()
        let session = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        let first = try await session.beginRequest()
        let context = try await session.authenticate(accountID: "account-A", request: first)
        try await session.didIngest(context: context, request: first)
        let second = try await session.beginRequest()
        #expect(try await session.authenticate(accountID: "account-A", request: second) == context)
        #expect(try await session.identity(for: context) == "account-A")
        await #expect(throws: AccountEarningsClientError.sessionChanged) { try await session.require(first) }
        await #expect(throws: AccountEarningsClientError.sessionChanged) { try await session.reject(first) }
        #expect(await session.snapshot().context == context)
        try await session.reject(second)
        #expect(await session.snapshot().context == nil)
    }

    @Test("an identical-byte credential replacement invalidates the old session")
    func identicalReplacement() async throws {
        let fixture = try SessionFixture()
        let session = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        let a = try await authorize(session, account: "account-A")
        try fixture.token("token-A")
        #expect(await session.snapshot().context == nil)
        let again = try await authorize(session, account: "account-A")
        #expect(again.accountScope == a.accountScope)
        #expect(again.generation != a.generation)
    }

    @Test("unreadable invalid oversized and nonregular credentials revoke without blocking")
    func invalidCredentials() async throws {
        let fixture = try SessionFixture()
        let session = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        var prior = try await authorize(session, account: "account-A")
        for invalid in [Data(), Data([0xff, 0xfe]), Data("token\nanother".utf8), Data("token\0invalid".utf8), Data(repeating: 65, count: 65_537)] {
            try invalid.write(to: fixture.tokenURL, options: .atomic)
            #expect(await session.snapshot().context == nil)
            await #expect(throws: AccountEarningsClientError.missingToken) { try await session.beginRequest() }
            try fixture.token("token-A")
            let next = try await authorize(session, account: "account-A")
            #expect(next.generation != prior.generation)
            prior = next
        }
        try FileManager.default.removeItem(at: fixture.tokenURL)
        #expect(fixture.tokenURL.path.withCString { mkfifo($0, 0o600) } == 0)
        #expect(await session.snapshot().context == nil)
        await #expect(throws: AccountEarningsClientError.missingToken) { try await session.beginRequest() }
    }

    @Test("filesystem replacement and deletion emit revocation without an API call")
    func filesystemRevocation() async throws {
        let fixture = try SessionFixture()
        let session = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        let a = try await authorize(session, account: "account-A")
        let changes = await session.changes()
        var initial = changes.makeAsyncIterator()
        #expect(await initial.next()?.context == a)
        try fixture.token("token-B")
        let changed = await next(changes)
        #expect(changed?.context == nil)
        #expect(changed != nil)
        _ = try await authorize(session, account: "account-B")
        let deletion = await session.changes()
        var deletionInitial = deletion.makeAsyncIterator()
        _ = await deletionInitial.next()
        try FileManager.default.removeItem(at: fixture.tokenURL)
        let deleted = await next(deletion)
        #expect(deleted != nil)
        #expect(deleted?.context == nil)
    }

    @Test("directory removal recreation and token in-place writes remain observable")
    func directoryRecreation() async throws {
        let fixture = try SessionFixture()
        let session = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        _ = try await authorize(session, account: "account-A")
        let changes = await session.changes()
        var initial = changes.makeAsyncIterator(); _ = await initial.next()
        try FileManager.default.removeItem(at: fixture.tokenURL.deletingLastPathComponent())
        #expect(await next(changes) != nil)
        try fixture.token("token-B")
        let b = try await authorize(session, account: "account-B")
        let writes = await session.changes()
        var writeInitial = writes.makeAsyncIterator(); _ = await writeInitial.next()
        try Data("token-C".utf8).write(to: fixture.tokenURL)
        let changed = await next(writes)
        #expect(changed != nil)
        #expect(changed?.context == nil)
        await #expect(throws: AccountEarningsClientError.sessionChanged) { try await session.identity(for: b) }
    }

    @Test("scoped reports reject old contexts and never read another account")
    func scopedClientReads() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            let b = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-B"
            return try response(request, account: b ? "account-B" : "account-A", amount: b ? 20 : 10)
        }
        let a = try await client.fetchWithContext(now: captured)
        let copied = client
        #expect(await copied.financialSessionState().context == a.context)
        #expect(try await client.financialReport(context: a.context, in: range, unit: .hour, calendar: calendar)?.totals?.workMicroUSD == 10)
        try fixture.token("token-B")
        let b = try await client.fetchWithContext(now: captured)
        await #expect(throws: AccountEarningsClientError.sessionChanged) {
            try await copied.financialReport(context: a.context, in: range, unit: .hour, calendar: calendar)
        }
        #expect(try await client.financialReport(context: b.context, in: range, unit: .hour, calendar: calendar)?.totals?.workMicroUSD == 20)
        try fixture.token("token-A")
        let again = try await client.fetchWithContext(now: captured)
        #expect(again.context.accountScope == a.context.accountScope)
        #expect(again.context.generation != a.context.generation)
    }

    @Test("an account change during SQLite reading rejects the completed old report")
    func heldDatabaseRead() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            let (data, http) = try response(request, account: "account-A", amount: 10)
            var json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            let row = (json["earnings"] as! [[String: Any]])[0]
            json["earnings"] = (1...200).map { id -> [String: Any] in var next = row; next["id"] = id; return next }
            json["count"] = 200; json["recent_count"] = 200; json["total_micro_usd"] = 2_000
            return (try JSONSerialization.data(withJSONObject: json), http)
        }
        let a = try await client.fetchWithContext(now: captured)
        let gate = SessionSQLiteGate()
        let read = Task {
            try await client.financialReport(context: a.context, in: range, unit: .hour,
                calendar: calendar, onReadProgress: { gate.observe() })
        }
        let entered = await Task.detached { gate.waitForEntry() }.value
        do {
            #expect(entered)
            try fixture.token("token-B")
            #expect(await client.financialSessionState().context == nil)
            gate.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await read.value }
        } catch {
            gate.release(); _ = try? await read.value; throw error
        }
    }

    @Test("a held old successful or unauthorized response cannot publish or revoke B")
    func obsoleteResponse() async throws {
        for oldStatus in [200, 401, -1] {
            let fixture = try SessionFixture()
            let gate = SessionHoldGate()
            let client = AuthenticatedEarningsClient(homeDirectory: fixture.home) { request in
                if request.value(forHTTPHeaderField: "Authorization") == "Bearer token-A" {
                    await gate.hold()
                    if oldStatus < 0 { throw URLError(.timedOut) }
                    return try response(request, account: "account-A", amount: 10, status: oldStatus)
                }
                return try response(request, account: "account-B", amount: 20)
            }
            let old = Task { try await client.fetchWithContext(now: captured) }
            let entered: Void? = await next(gate.entered)
            do {
                #expect(entered != nil)
                try fixture.token("token-B")
                let b = try await client.fetchWithContext(now: captured)
                await gate.release()
                await #expect(throws: AccountEarningsClientError.sessionChanged) { try await old.value }
                #expect(await client.financialSessionState().context == b.context)
            } catch {
                await gate.release(); _ = try? await old.value; throw error
            }
        }
    }

    @Test("a held response from the first A session is rejected after A to B to A")
    func heldABAResponse() async throws {
        let fixture = try SessionFixture()
        let gate = SessionHoldGate()
        let counter = SessionRequestCounter()
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home) { request in
            if await counter.advance() == 2 { await gate.hold() }
            let b = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-B"
            return try response(request, account: b ? "account-B" : "account-A", amount: b ? 20 : 10)
        }
        let firstA = try await client.fetchWithContext(now: captured)
        let old = Task { try await client.fetchWithContext(now: captured) }
        let entered: Void? = await next(gate.entered)
        do {
            #expect(entered != nil)
            try fixture.token("token-B")
            let b = try await client.fetchWithContext(now: captured)
            try fixture.token("token-A")
            let a = try await client.fetchWithContext(now: captured)
            #expect(a.context != b.context)
            #expect(a.context.accountScope == firstA.context.accountScope)
            #expect(a.context.generation != firstA.context.generation)
            await gate.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await old.value }
            #expect(await client.financialSessionState().context == a.context)
        } catch {
            await gate.release(); _ = try? await old.value; throw error
        }
    }

    @Test("an authenticated client without storage does not claim ledger readiness")
    func noDatabase() async throws {
        let fixture = try SessionFixture()
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home) { request in
            try response(request, account: "account-A", amount: 10)
        }
        let result = try await client.fetchWithContext(now: captured)
        #expect(result.value == .available(microUSD: 10))
        let state = await client.financialSessionState()
        #expect(state.context == result.context)
        #expect(!state.ledgerReady)
        await #expect(throws: AccountEarningsClientError.sessionChanged) {
            try await client.financialReport(context: result.context, in: range, unit: .hour, calendar: calendar)
        }
    }

    @Test("an obsolete public fallback cannot replace a newer authenticated result")
    func obsoletePublicFallback() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let gate = SessionHoldGate()
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            if request.url?.path == "/v1/leaderboard" {
                await gate.hold()
                return try response(request, account: "unused", amount: 0, status: 403)
            }
            let b = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-B"
            return try response(request, account: b ? "account-B" : "account-A", amount: b ? 20 : 10, count: b ? 1 : 2)
        }
        let old = Task { try await client.fetchWithContext(now: captured) }
        let entered: Void? = await next(gate.entered)
        do {
            #expect(entered != nil)
            try fixture.token("token-B")
            let b = try await client.fetchWithContext(now: captured)
            await gate.release()
            await #expect(throws: AccountEarningsClientError.sessionChanged) { try await old.value }
            #expect(await client.financialSessionState().context == b.context)
        } catch {
            await gate.release(); _ = try? await old.value; throw error
        }
    }

    @Test("session destruction finishes subscribers rather than leaving a retained read waiting")
    func sessionLifetime() async throws {
        let fixture = try SessionFixture()
        var session: AuthenticatedAccountSession? = AuthenticatedAccountSession(tokenURL: fixture.tokenURL)
        let changes = await session!.changes()
        var iterator = changes.makeAsyncIterator()
        #expect(await iterator.next() != nil)
        session = nil
        let finished = await withTaskGroup(of: Bool.self) { group in
            group.addTask { var iterator = changes.makeAsyncIterator(); return await iterator.next() == nil }
            group.addTask { try? await Task.sleep(for: .seconds(3)); return false }
            let value = await group.next() ?? false; group.cancelAll(); return value
        }
        #expect(finished)
    }

    @Test("B identity replaces A before a rejected B ledger page")
    func failedIngestion() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            let b = request.value(forHTTPHeaderField: "Authorization") == "Bearer token-B"
            return try response(request, account: b ? "account-B" : "account-A", amount: b ? 20 : 10, count: b ? -1 : 1)
        }
        let a = try await client.fetchWithContext(now: captured)
        try fixture.token("token-B")
        await #expect(throws: EarningsDatabaseError.self) { try await client.fetchWithContext(now: captured) }
        let state = await client.financialSessionState()
        #expect(state.context != a.context)
        #expect(state.context != nil)
        #expect(!state.ledgerReady)
        await #expect(throws: AccountEarningsClientError.sessionChanged) {
            try await client.financialReport(context: a.context, in: range, unit: .hour, calendar: calendar)
        }
        if let b = state.context {
            await #expect(throws: AccountEarningsClientError.sessionChanged) {
                try await client.financialReport(context: b, in: range, unit: .hour, calendar: calendar)
            }
        }
    }

    @Test("public unauthorized fallback does not revoke authenticated identity")
    func publicFallback() async throws {
        let fixture = try SessionFixture()
        let database = try EarningsDatabase(url: fixture.home.appendingPathComponent("credits.sqlite3"))
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home, database: database) { request in
            if request.url?.path == "/v1/leaderboard" { return try response(request, account: "unused", amount: 0, status: 401) }
            return try response(request, account: "account-A", amount: 10, count: 2)
        }
        await #expect(throws: AccountEarningsClientError.httpStatus(401)) { try await client.fetchWithContext(now: captured) }
        let state = await client.financialSessionState()
        #expect(state.context != nil)
        #expect(state.ledgerReady)
        if let context = state.context {
            #expect(try await client.financialReport(context: context, in: range, unit: .hour, calendar: calendar)?.totals?.workMicroUSD == 10)
        }
    }

    @Test("same-token transport failure preserves identity while current authentication rejection revokes")
    func failureBoundaries() async throws {
        let fixture = try SessionFixture()
        let transport = SessionTestTransport()
        let client = AuthenticatedEarningsClient(homeDirectory: fixture.home) { request in try await transport.read(request) }
        let a = try await client.fetchWithContext(now: captured)
        await transport.setStatus(503)
        await #expect(throws: AccountEarningsClientError.httpStatus(503)) { try await client.fetchWithContext(now: captured) }
        #expect(await client.financialSessionState().context == a.context)
        await transport.setStatus(403)
        await #expect(throws: AccountEarningsClientError.unauthorized) { try await client.fetchWithContext(now: captured) }
        #expect(await client.financialSessionState().context == nil)
    }

    private func authorize(_ session: AuthenticatedAccountSession, account: String) async throws -> AccountEarningsContext {
        let ticket = try await session.beginRequest()
        let context = try await session.authenticate(accountID: account, request: ticket)
        try await session.didIngest(context: context, request: ticket)
        return context
    }
}

private let captured = Date(timeIntervalSince1970: 2_000_000)
private let range = DateInterval(start: captured.addingTimeInterval(-3_600), end: captured)
private let calendar: Calendar = { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }()

private func response(_ request: URLRequest, account: String, amount: Int64, count: Int64 = 1, status: Int = 200) throws -> (Data, URLResponse) {
    let object: [String: Any] = ["account_id": account, "count": count, "history_limit": 1000,
        "recent_count": 1, "total_micro_usd": amount, "available_balance_micro_usd": amount,
        "withdrawable_balance_micro_usd": amount,
        "earnings": [["id": 1, "provider_id": "provider-fixture", "provider_key": "unused-fixture",
            "model": "gemma", "amount_micro_usd": amount, "prompt_tokens": 1, "completion_tokens": 2,
            "created_at": "1970-01-24T03:32:20Z"]]]
    return (try JSONSerialization.data(withJSONObject: object), HTTPURLResponse(url: request.url!, statusCode: status,
        httpVersion: "HTTP/1.1", headerFields: [:])!)
}

private final class SessionFixture: @unchecked Sendable {
    let home: URL
    var tokenURL: URL { home.appendingPathComponent(".darkbloom/auth_token") }
    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("bloomy-auth-session-\(UUID())", isDirectory: true)
        try token("token-A")
    }
    func token(_ text: String) throws {
        try FileManager.default.createDirectory(at: tokenURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: tokenURL, options: .atomic)
    }
    deinit { try? FileManager.default.removeItem(at: home) }
}

private actor SessionTestTransport {
    var status = 200
    func setStatus(_ value: Int) { status = value }
    func read(_ request: URLRequest) throws -> (Data, URLResponse) {
        try response(request, account: "account-A", amount: 10, status: status)
    }
}

private actor DefaultScopedFetchFixture: AccountEarningsFetching {
    let gate: SessionHoldGate
    let throwsTransport: Bool
    var context = AccountEarningsContext(accountScope: "synthetic-A", generation: UUID())
    init(gate: SessionHoldGate, throwsTransport: Bool) { self.gate = gate; self.throwsTransport = throwsTransport }
    func changeAccount() { context = AccountEarningsContext(accountScope: "synthetic-B", generation: UUID()) }
    func financialSessionState() -> AccountEarningsSessionState {
        .init(context: context, ledgerReady: true, revision: context.generation)
    }
    func fetch(now: Date) async throws -> EarningsPresentationValue {
        await gate.hold()
        if throwsTransport { throw URLError(.timedOut) }
        return .unavailable(reason: "synthetic held result")
    }
}

private actor SessionRequestCounter {
    private var count = 0
    func advance() -> Int { count += 1; return count }
}

private actor SessionHoldGate {
    nonisolated let entered: AsyncStream<Void>
    private let notification: AsyncStream<Void>.Continuation
    private var waits: [CheckedContinuation<Void, Never>] = []
    private var released = false
    init() { (entered, notification) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1)) }
    func hold() async {
        notification.yield(())
        if released { return }
        await withCheckedContinuation { waits.append($0) }
    }
    func release() {
        released = true; for wait in waits { wait.resume() }; waits.removeAll(); notification.finish()
    }
}

private final class SessionSQLiteGate: @unchecked Sendable {
    private let entered = DispatchSemaphore(value: 0)
    private let continued = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var first = true
    func observe() {
        let hold = lock.withLock { let hold = first; first = false; return hold }
        if hold { entered.signal(); _ = continued.wait(timeout: .now() + 10) }
    }
    func waitForEntry() -> Bool { entered.wait(timeout: .now() + 10) == .success }
    func release() { continued.signal() }
}

private func next<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { var iterator = stream.makeAsyncIterator(); return await iterator.next() }
        group.addTask { try? await Task.sleep(for: .seconds(3)); return nil }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}
