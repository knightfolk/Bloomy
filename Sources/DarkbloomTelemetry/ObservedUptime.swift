import Foundation
import SQLite3

public enum ObservedUptimeValue: Equatable, Sendable {
    case warming(observedSeconds: TimeInterval)
    case available(percent: Double, observedSeconds: TimeInterval)
    case unavailable(reason: String)

    public var accessibilityDescription: String {
        switch self {
        case .warming(let observedSeconds):
            "Monitor-observed uptime is warming up with \(Self.coverage(observedSeconds)) of classified coverage."
        case .available(let percent, let observedSeconds):
            "Monitor-observed rolling 24-hour uptime is \(Self.rounded(percent)) percent with \(Self.coverage(observedSeconds)) of classified coverage."
        case .unavailable(let reason):
            "Monitor-observed uptime unavailable: \(reason)."
        }
    }

    public var compactPercent: String? {
        guard case .available(let percent, _) = self else { return nil }
        return "\(Self.rounded(percent))%"
    }

    public var fraction: Double? {
        guard case .available(let percent, _) = self else { return nil }
        return min(max(percent / 100, 0), 1)
    }

    private static func rounded(_ percent: Double) -> Int {
        Int(percent.rounded())
    }

    private static func coverage(_ seconds: TimeInterval) -> String {
        if seconds >= 3_600 {
            return String(format: "%.1f hours", locale: Locale(identifier: "en_US_POSIX"), seconds / 3_600)
        }
        return "\(Int(seconds / 60)) minutes"
    }
}

public enum ObservedUptimeDatabaseError: Error, LocalizedError, Sendable {
    case sqlite(message: String)

    public var errorDescription: String? {
        switch self {
        case .sqlite(let message): "Local observed-uptime database error — \(message)"
        }
    }
}

public protocol ObservedUptimeRecording: Sendable {
    func record(status: MenuPresentationStatus, at date: Date) async throws -> ObservedUptimeValue
}

public actor ObservedUptimeDatabase: ObservedUptimeRecording {
    public static let rollingWindow: TimeInterval = 24 * 60 * 60
    public static let freshnessCarry: TimeInterval = 10
    public static let warmupDuration: TimeInterval = 5 * 60

    private enum ObservationState: Int32 {
        case unknown = 0
        case online = 1
        case offline = 2

        init(_ status: MenuPresentationStatus) {
            switch status {
            case .online: self = .online
            case .offline: self = .offline
            case .stale, .unavailable: self = .unknown
            }
        }
    }

    private struct Observation {
        let timestamp: TimeInterval
        var state: ObservationState
        var onlineBefore: TimeInterval = 0
        var offlineBefore: TimeInterval = 0
    }

    // Prefix durations close only the preceding observation's interval. The last
    // interval remains open and is clipped to the snapshot time and carry limit.
    // Chronological emissions append one entry and binary-search two endpoints;
    // they never fetch, allocate, or fold the rolling history again.
    private var cachedObservations: [Observation]?
    private var cacheStart = 0
    private var cacheDataVersion: Int64?
    private(set) var aggregationRebuildCount = 0
    var aggregationStorageCount: Int { cachedObservations?.count ?? 0 }

    private let connection: ObservedUptimeSQLiteConnection
    private let window: TimeInterval
    private let maximumCarry: TimeInterval
    private let minimumObservedDuration: TimeInterval

    public init(url: URL) throws {
        try self.init(
            url: url,
            window: Self.rollingWindow,
            maximumCarry: Self.freshnessCarry,
            minimumObservedDuration: Self.warmupDuration
        )
    }

    init(
        url: URL,
        window: TimeInterval,
        maximumCarry: TimeInterval,
        minimumObservedDuration: TimeInterval
    ) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &database,
            SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            if let database { sqlite3_close(database) }
            throw ObservedUptimeDatabaseError.sqlite(message: "could not open database")
        }
        connection = ObservedUptimeSQLiteConnection(pointer: database)
        self.window = window
        self.maximumCarry = maximumCarry
        self.minimumObservedDuration = minimumObservedDuration
        sqlite3_busy_timeout(database, 2_000)

        do {
            try Self.execute(database, sql: "PRAGMA journal_mode=WAL")
            try Self.execute(database, sql: "PRAGMA synchronous=NORMAL")
            try Self.execute(database, sql: """
                CREATE TABLE IF NOT EXISTS uptime_observations (
                    observed_at REAL PRIMARY KEY,
                    state INTEGER NOT NULL CHECK (state BETWEEN 0 AND 2)
                )
                """)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: url.path
            )
        } catch {
            throw error
        }
    }

    public func record(
        status: MenuPresentationStatus,
        at date: Date
    ) throws -> ObservedUptimeValue {
        let timestamp = date.timeIntervalSince1970
        guard timestamp.isFinite else {
            throw ObservedUptimeDatabaseError.sqlite(message: "observation timestamp is not finite")
        }

        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "INSERT OR REPLACE INTO uptime_observations (observed_at, state) VALUES (?, ?)",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, timestamp)
        sqlite3_bind_int(statement, 2, ObservationState(status).rawValue)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }

        let observation = Observation(timestamp: timestamp, state: ObservationState(status))
        if let last = cachedObservations?.last, timestamp < last.timestamp {
            // Replacement/insertion in the middle changes both neighboring
            // intervals. Rebuild from the persisted ordering on this rare path.
            cachedObservations = nil
        } else if cachedObservations != nil {
            if cachedObservations?.last?.timestamp == timestamp {
                cachedObservations![cachedObservations!.count - 1].state = observation.state
            } else {
                appendToCache(observation)
            }
        }
        return try snapshot(at: date)
    }

    public func snapshot(at date: Date) throws -> ObservedUptimeValue {
        let now = date.timeIntervalSince1970
        guard now.isFinite else {
            throw ObservedUptimeDatabaseError.sqlite(message: "snapshot timestamp is not finite")
        }
        do {
            try prune(at: now)
            // Other actors/processes can reopen the same file. SQLite increments
            // this connection-local version for their commits, not our writes.
            let version = try dataVersion()
            if cachedObservations == nil || cacheDataVersion != version {
                try rebuildCache(from: now - window - maximumCarry)
                cacheDataVersion = version
            }
            evictCache(before: now - window - maximumCarry)
        } catch {
            // A write can have succeeded before a later SQLite operation fails.
            // Never publish a partially updated or stale aggregate on retry.
            cachedObservations = nil
            cacheDataVersion = nil
            throw error
        }

        let end = accumulatedDuration(through: now)
        let start = accumulatedDuration(through: now - window)
        let onlineSeconds = max(0, end.online - start.online)
        let offlineSeconds = max(0, end.offline - start.offline)

        let observedSeconds = onlineSeconds + offlineSeconds
        guard observedSeconds >= minimumObservedDuration else {
            return .warming(observedSeconds: observedSeconds)
        }
        let percent = min(max(onlineSeconds / observedSeconds * 100, 0), 100)
        return .available(percent: percent, observedSeconds: observedSeconds)
    }

    private func appendToCache(_ observation: Observation) {
        var entry = observation
        if let previous = cachedObservations?.last {
            entry.onlineBefore = previous.onlineBefore
            entry.offlineBefore = previous.offlineBefore
            let duration = max(0, min(entry.timestamp, previous.timestamp + maximumCarry) - previous.timestamp)
            switch previous.state {
            case .online: entry.onlineBefore += duration
            case .offline: entry.offlineBefore += duration
            case .unknown: break
            }
        }
        cachedObservations!.append(entry)
    }

    private func accumulatedDuration(through timestamp: TimeInterval) -> (online: TimeInterval, offline: TimeInterval) {
        guard let observations = cachedObservations, cacheStart < observations.count else { return (0, 0) }
        var low = cacheStart
        var high = observations.count
        while low < high {
            let middle = low + (high - low) / 2
            if observations[middle].timestamp <= timestamp { low = middle + 1 } else { high = middle }
        }
        guard low > cacheStart else {
            let first = observations[cacheStart]
            return (first.onlineBefore, first.offlineBefore)
        }
        let entry = observations[low - 1]
        let next = low < observations.count ? observations[low].timestamp : timestamp
        let duration = max(0, min(timestamp, next, entry.timestamp + maximumCarry) - entry.timestamp)
        return (
            entry.onlineBefore + (entry.state == .online ? duration : 0),
            entry.offlineBefore + (entry.state == .offline ? duration : 0)
        )
    }

    private func evictCache(before timestamp: TimeInterval) {
        guard cachedObservations != nil else { return }
        var low = cacheStart
        var high = cachedObservations!.count
        while low < high {
            let middle = low + (high - low) / 2
            if cachedObservations![middle].timestamp < timestamp { low = middle + 1 } else { high = middle }
        }
        cacheStart = low
        guard cacheStart > 0 else { return }
        if cacheStart == cachedObservations!.count {
            cachedObservations!.removeAll(keepingCapacity: false)
            cacheStart = 0
        } else if cacheStart >= 4_096 || cacheStart * 2 >= cachedObservations!.count {
            // Amortize allocation/compaction and rebase the prefix totals so
            // years of operation cannot accumulate cancellation error.
            cachedObservations!.removeFirst(cacheStart)
            cacheStart = 0
            let onlineBase = cachedObservations![0].onlineBefore
            let offlineBase = cachedObservations![0].offlineBefore
            for index in cachedObservations!.indices {
                cachedObservations![index].onlineBefore -= onlineBase
                cachedObservations![index].offlineBefore -= offlineBase
            }
        }
    }

    private func rebuildCache(from start: TimeInterval) throws {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "SELECT observed_at, state FROM uptime_observations WHERE observed_at >= ? ORDER BY observed_at",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, start)

        cachedObservations = []
        cacheStart = 0
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw lastError() }
            guard let state = ObservationState(rawValue: sqlite3_column_int(statement, 1)) else { continue }
            appendToCache(Observation(timestamp: sqlite3_column_double(statement, 0), state: state))
        }
        aggregationRebuildCount += 1
    }

    private func dataVersion() throws -> Int64 {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(connection.pointer, "PRAGMA data_version", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw lastError() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw lastError() }
        let version = sqlite3_column_int64(statement, 0)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
        return version
    }

    private func prune(at now: TimeInterval) throws {
        let database = connection.pointer
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(
            database,
            "DELETE FROM uptime_observations WHERE observed_at < ?",
            -1,
            &statement,
            nil
        ) == SQLITE_OK, let statement else {
            throw lastError()
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, now - window - maximumCarry)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw lastError() }
    }

    private func lastError() -> ObservedUptimeDatabaseError {
        .sqlite(message: String(cString: sqlite3_errmsg(connection.pointer)))
    }

    private static func execute(_ database: OpaquePointer, sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite failure"
            sqlite3_free(errorMessage)
            throw ObservedUptimeDatabaseError.sqlite(message: message)
        }
    }
}

private final class ObservedUptimeSQLiteConnection: @unchecked Sendable {
    let pointer: OpaquePointer

    init(pointer: OpaquePointer) {
        self.pointer = pointer
    }

    deinit {
        sqlite3_close(pointer)
    }
}
