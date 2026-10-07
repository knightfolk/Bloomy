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
    func financialSessionState() async -> AccountEarningsSessionState
    func financialSessionChanges() async -> AsyncStream<AccountEarningsSessionState>
    func fetchWithContext(now: Date) async throws -> AccountEarningsFetchResult
    func validateFinancialContext(_ context: AccountEarningsContext) async throws
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport?
    /// Must validate local-provider attribution across the complete requested
    /// range, including reconnects, before returning and after suspended reads.
    /// Attribution changes must publish a new financial-session revision so
    /// consumers invalidate cached local reports and pending automation.
    func localProviderFinancialReport(context: AccountEarningsContext,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> LocalProviderCreditReport?
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
    func financialSessionState() async -> AccountEarningsSessionState { .unavailable }
    func financialSessionChanges() async -> AsyncStream<AccountEarningsSessionState> {
        AsyncStream { $0.finish() }
    }
    func validateFinancialContext(_ context: AccountEarningsContext) async throws {
        try Task.checkCancellation()
        guard await financialSessionState().context == context else { throw AccountEarningsClientError.sessionChanged }
    }
    func fetchWithContext(now: Date) async throws -> AccountEarningsFetchResult {
        guard let context = await financialSessionState().context else { throw AccountEarningsClientError.sessionChanged }
        try await validateFinancialContext(context)
        do {
            let value = try await fetch(now: now)
            try await validateFinancialContext(context)
            return AccountEarningsFetchResult(context: context, value: value)
        } catch {
            try await validateFinancialContext(context)
            throw error
        }
    }
    func financialReport(context: AccountEarningsContext, providerID: String?, model: String?,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> AccountCreditReport? { nil }
    // The production API currently supplies account-wide credits, without a
    // verified association to this Mac. Do not infer one from filtered rows.
    func localProviderFinancialReport(context: AccountEarningsContext,
        in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> LocalProviderCreditReport? { nil }
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
        try await currentReport(in: range, unit: .hour, calendar: calendar)?.modelWorkEarnings(calendar: calendar) ?? []
    }
    public func modelActivity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar, model: String?) async throws -> [ActivityBucket]? {
        guard model != "base_reward" else { return nil }
        return try await currentReport(in: range, unit: unit, calendar: calendar, model: model)?.activityBuckets(model: model)
    }
    public func activityModels(in range: DateInterval) async throws -> [String] {
        try await currentReport(in: range, unit: .day, calendar: .current)?.models ?? []
    }
    public func activityByModel(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ModelActivityBucket]? {
        try await currentReport(in: range, unit: unit, calendar: calendar)?.modelActivity
    }
    public func modelHourlyEarningsAverages(in range: DateInterval) async throws -> [ModelHourlyEarningsAverage]? {
        try await currentReport(in: range, unit: .day, calendar: .current)?.hourlyEarningsAverages
    }
    public func activity(in range: DateInterval, unit: ActivityCalendarUnit, calendar: Calendar) async throws -> [ActivityBucket]? {
        try await currentReport(in: range, unit: unit, calendar: calendar)?.activityBuckets()
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

    public func validateFinancialContext(_ context: AccountEarningsContext) async throws {
        try await accountSession.validate(context)
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
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -7, to: today),
              let report = try await currentReport(in: DateInterval(start: start, end: now),
                  unit: .day, calendar: calendar),
              let capturedAt = report.observation?.balance.capturedAt,
              calendar.startOfDay(for: capturedAt) == today else { return nil }
        let past = report.buckets.filter { $0.interval.end <= today }
        let current = report.buckets.first { $0.interval.start == today }
        guard let currentCount = current?.totals?.workCreditCount else { return nil }
        let complete = report.reconciliation == .matched
            && capturedAt.timeIntervalSince1970 >= now.timeIntervalSince1970
        let pastCount = past.reduce(Int64(0)) { $0 + ($1.totals?.workCreditCount ?? 0) }
        // Compatibility type: these are observed work credit records. They do
        // not independently establish completed serving requests.
        return JobCompletionSummary(completedToday: currentCount,
            averagePerDay: complete ? Double(pastCount) / 7 : nil,
            averagingDays: 7, dayStart: today, capturedAt: capturedAt)
    }

    public func todayEarningsSummary(
        now: Date,
        calendar: Calendar
    ) async throws -> ObservedEarningsWindow? {
        try await currentReport(in: DateInterval(start: calendar.startOfDay(for: now), end: now),
            unit: .hour, calendar: calendar)?.observedEarningsWindow(calendar: calendar)
    }

    public func weekEarningsSummary(
        now: Date,
        calendar: Calendar
    ) async throws -> CalendarWeekEarningsSummary? {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        return try await currentReport(in: DateInterval(start: start, end: now),
            unit: .day, calendar: calendar)?.calendarWeekSummary(calendar: calendar)
    }

    public func modelEarnings(since: Date) async throws -> [ModelEarnings] {
        let capture = await financialSessionState()
        guard let context = capture.context, capture.ledgerReady else { return [] }
        let end = Date()
        guard since.timeIntervalSince1970.isFinite, since <= end else { throw ActivityCalendarError.invalidInterval }
        // The compatibility API asks for an observed subtotal, not completeness
        // through wall-clock now. It cannot read unattributed legacy aggregates.
        let report = try await financialReport(context: context, in: DateInterval(start: since, end: end),
            unit: .day, calendar: .current)
        return report?.recentModelEarnings() ?? []
    }

    private func currentReport(in range: DateInterval, unit: ActivityCalendarUnit,
        calendar: Calendar, model: String? = nil) async throws -> AccountCreditReport? {
        let state = await financialSessionState()
        guard let context = state.context, state.ledgerReady else { return nil }
        return try await financialReport(context: context, model: model, in: range, unit: unit, calendar: calendar)
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
