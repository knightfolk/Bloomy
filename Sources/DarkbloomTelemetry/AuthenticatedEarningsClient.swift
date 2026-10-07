import Foundation

public struct AccountEarningsRequest: CustomStringConvertible, Sendable {
    public let urlRequest: URLRequest

    public var description: String {
        "GET \(urlRequest.url?.absoluteString ?? "invalid-url") (authenticated)"
    }

    public static func make(token: String, limit: Int = 1_000) throws -> Self {
        guard !token.isEmpty else { throw AccountEarningsClientError.missingToken }
        guard limit > 0 else { throw AccountEarningsClientError.invalidHistoryLimit }

        var components = URLComponents(string: "https://api.darkbloom.dev/v1/provider/account-earnings")
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]
        guard let url = components?.url else { throw AccountEarningsClientError.invalidEndpoint }

        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return Self(urlRequest: request)
    }
}

public enum AccountEarningsClientError: Error, LocalizedError, Equatable, Sendable {
    case missingToken
    case invalidHistoryLimit
    case invalidEndpoint
    case unauthorized
    case httpStatus(Int)
    case invalidResponse
    case sessionChanged

    public var errorDescription: String? {
        switch self {
        case .missingToken: "Not logged in — run darkbloom login"
        case .invalidHistoryLimit: "Invalid account earnings history limit"
        case .invalidEndpoint: "Invalid Darkbloom account earnings endpoint"
        case .unauthorized: "Darkbloom login expired — run darkbloom login"
        case .httpStatus(let status): "Darkbloom earnings request returned HTTP \(status)"
        case .invalidResponse: "Darkbloom earnings response was invalid"
        case .sessionChanged: "Darkbloom account changed — refresh earnings"
        }
    }
}

public protocol AccountEarningsFetching: Sendable {
    func modelWorkEarnings(in range: DateInterval, calendar: Calendar) async throws -> [ModelWorkEarnings]
    func fetch(now: Date) async throws -> EarningsPresentationValue
    func jobCompletionSummary(now: Date, calendar: Calendar) async throws -> JobCompletionSummary?
    func todayEarningsSummary(now: Date, calendar: Calendar) async throws -> ObservedEarningsWindow?
    func weekEarningsSummary(now: Date, calendar: Calendar) async throws -> CalendarWeekEarningsSummary?
    func modelEarnings(since: Date) async throws -> [ModelEarnings]
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]?
    func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]?
    func activityModels(in range: DateInterval) async throws -> [String]
    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]?
    func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]?
}

public extension AccountEarningsFetching {
    func modelWorkEarnings(in range: DateInterval, calendar: Calendar) async throws -> [ModelWorkEarnings] { [] }
    func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]? {
        guard model == nil else { return nil }
        return try await activity(in: range, unit: unit, calendar: calendar)
    }
    func activityModels(in range: DateInterval) async throws -> [String] { [] }
    func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? { nil }
    func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]? { nil }
    func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? { nil }
    func jobCompletionSummary(now: Date, calendar: Calendar) async throws -> JobCompletionSummary? {
        nil
    }

    func todayEarningsSummary(now: Date, calendar: Calendar) async throws -> ObservedEarningsWindow? {
        nil
    }

    func weekEarningsSummary(
        now: Date,
        calendar: Calendar
    ) async throws -> CalendarWeekEarningsSummary? {
        nil
    }

    func modelEarnings(since: Date) async throws -> [ModelEarnings] { [] }
}

public struct AuthenticatedEarningsClient: AccountEarningsFetching, Sendable {
    public func modelWorkEarnings(in range: DateInterval, calendar: Calendar) async throws -> [ModelWorkEarnings] {
        guard let database else { return [] }
        let models = try await database.activityModels(in: range)
        var values: [ModelWorkEarnings] = []
        for model in models {
            try Task.checkCancellation()
            values.append(try await database.modelWorkEarnings(model: model, in: range, calendar: calendar))
        }
        return values
    }
    public func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]? {
        try await database?.activity(in: range, unit: unit, calendar: calendar, model: model)
    }
    public func activityModels(in range: DateInterval) async throws -> [String] {
        try await database?.activityModels(in: range) ?? []
    }
    public func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        try await database?.activityByModel(in: range, unit: unit, calendar: calendar)
    }
    public func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]? {
        try await database?.modelHourlyEarningsAverages(in: range)
    }
    public func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        try await database?.activity(in: range, unit: unit, calendar: calendar)
    }

    private let tokenURL: URL
    private let requestData: @Sendable (URLRequest) async throws -> (Data, URLResponse)
    private let historyLimit: Int
    private let database: EarningsDatabase?
    private let observeAccount: (@Sendable (AccountEarningsResponse, Date) async -> Void)?
    private let accountSession: AuthenticatedAccountSession

    public init(
        homeDirectory: URL,
        session: URLSession = .shared,
        historyLimit: Int = 1_000,
        database: EarningsDatabase? = nil,
        observeAccount: (@Sendable (AccountEarningsResponse, Date) async -> Void)? = nil
    ) {
        self.init(homeDirectory: homeDirectory, historyLimit: historyLimit,
            database: database, observeAccount: observeAccount,
            requestData: { try await session.data(for: $0) })
    }

    // Synthetic transport seam; the public initializer always uses URLSession.
    init(homeDirectory: URL, historyLimit: Int = 1_000, database: EarningsDatabase? = nil,
         observeAccount: (@Sendable (AccountEarningsResponse, Date) async -> Void)? = nil,
         requestData: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        tokenURL = homeDirectory.appendingPathComponent(".darkbloom/auth_token")
        accountSession = AuthenticatedAccountSession(tokenURL: tokenURL)
        self.requestData = requestData
        self.historyLimit = historyLimit
        self.database = database
        self.observeAccount = observeAccount
    }

    /// Fresh account rows only: no leaderboard or persisted-history fallback.
    public func nudgeEvidence(since: Date) async -> NudgeEarningsEvidence {
        do {
            let token = try String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            var request = try AccountEarningsRequest.make(token: token, limit: historyLimit).urlRequest
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
            return try await ChatRouteExecutor.execute(
                request: request, session: ChatHTTPSession.shared, successCapacity: 2 * 1_024 * 1_024
            ) { data in
                NudgeEarningsEvidence.evaluate(try AccountEarningsParser.parse(data), since: since, now: Date())
            }
        } catch { return .unavailable }
    }

    public func fetch(now: Date) async throws -> EarningsPresentationValue {
        try await fetchWithContext(now: now).value
    }

    public func financialSessionState() async -> AccountEarningsSessionState {
        await accountSession.snapshot()
    }

    public func financialSessionChanges() async -> AsyncStream<AccountEarningsSessionState> {
        await accountSession.changes()
    }

    public func financialReport(context: AccountEarningsContext, providerID: String? = nil,
        model: String? = nil, in range: DateInterval, unit: ActivityCalendarUnit,
        calendar: Calendar) async throws -> AccountCreditReport? {
        try await financialReport(context: context, providerID: providerID, model: model,
            in: range, unit: unit, calendar: calendar, onReadProgress: nil)
    }

    func financialReport(context: AccountEarningsContext, providerID: String? = nil,
        model: String? = nil, in range: DateInterval, unit: ActivityCalendarUnit,
        calendar: Calendar, onReadProgress: (@Sendable () -> Void)?) async throws -> AccountCreditReport? {
        let accountID = try await accountSession.identity(for: context)
        do {
            let report = try await database?.accountCreditReport(accountID: accountID,
                providerID: providerID, model: model, in: range, unit: unit, calendar: calendar,
                onReadProgress: onReadProgress)
            _ = try await accountSession.identity(for: context)
            return report
        } catch {
            _ = try await accountSession.identity(for: context)
            throw error
        }
    }

    public func fetchWithContext(now: Date) async throws -> AccountEarningsFetchResult {
        let ticket = try await accountSession.beginRequest()
        let request = try AccountEarningsRequest.make(token: ticket.token, limit: historyLimit)
        let (data, response) = try await read(request.urlRequest, ticket: ticket)
        try await accountSession.require(ticket)
        do { try validate(response) }
        catch AccountEarningsClientError.unauthorized {
            try await accountSession.reject(ticket)
            throw AccountEarningsClientError.unauthorized
        }
        let account = try AccountEarningsParser.parse(data)
        let context = try await accountSession.authenticate(accountID: account.accountID, request: ticket)
        // Identity changes before ingestion: a failed B page must never leave A
        // as the current authenticated account.
        if let database {
            do { try await database.ingest(account, capturedAt: now) }
            catch {
                try await accountSession.require(ticket)
                throw error
            }
            try await accountSession.didIngest(context: context, request: ticket)
        }
        await observeAccount?(account, now)
        try await accountSession.require(ticket)

        let recentHistory = AccountEarningsParser.rolling24Hours(account, now: now)
        if case .available = recentHistory {
            return AccountEarningsFetchResult(context: context, value: recentHistory)
        }

        let leaderboardRequest = AccountLeaderboardRequest.make()
        let (leaderboardData, leaderboardResponse) = try await read(leaderboardRequest, ticket: ticket)
        try await accountSession.require(ticket)
        // This public request is not evidence that the authenticated login expired.
        try validate(leaderboardResponse, authenticated: false)
        let leaderboard = try AccountLeaderboardParser.rolling24Hours(
            leaderboardData,
            accountID: account.accountID
        )
        if case .available = leaderboard {
            return AccountEarningsFetchResult(context: context, value: leaderboard)
        }
        // A lifetime balance delta may reflect corrections and is not an income
        // rate. Do not fall back to old global balance observations as earnings.
        try await accountSession.require(ticket)
        return AccountEarningsFetchResult(context: context, value: leaderboard)
    }

    public func jobCompletionSummary(
        now: Date,
        calendar: Calendar
    ) async throws -> JobCompletionSummary? {
        try await database?.jobCompletionSummary(now: now, calendar: calendar)
    }

    public func todayEarningsSummary(
        now: Date,
        calendar: Calendar
    ) async throws -> ObservedEarningsWindow? {
        try await database?.todayEarningsSummary(now: now, calendar: calendar)
    }

    public func weekEarningsSummary(
        now: Date,
        calendar: Calendar
    ) async throws -> CalendarWeekEarningsSummary? {
        try await database?.weekEarningsSummary(now: now, calendar: calendar)
    }

    public func modelEarnings(since: Date) async throws -> [ModelEarnings] {
        try await database?.earningsByModel(since: since) ?? []
    }

    private func validate(_ response: URLResponse, authenticated: Bool = true) throws {
        guard let http = response as? HTTPURLResponse else {
            throw AccountEarningsClientError.invalidResponse
        }
        if authenticated && (http.statusCode == 401 || http.statusCode == 403) {
            throw AccountEarningsClientError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw AccountEarningsClientError.httpStatus(http.statusCode)
        }
    }

    private func read(_ request: URLRequest, ticket: AuthenticatedAccountSession.Request) async throws -> (Data, URLResponse) {
        do {
            let value = try await requestData(request)
            try await accountSession.require(ticket)
            return value
        } catch {
            // A transport failure from an old request cannot justify retaining
            // data after the credentials changed during that suspension.
            try await accountSession.require(ticket)
            throw error
        }
    }
}

public struct AccountEarningsFetchResult: Equatable, Sendable {
    public let context: AccountEarningsContext
    public let value: EarningsPresentationValue
}
