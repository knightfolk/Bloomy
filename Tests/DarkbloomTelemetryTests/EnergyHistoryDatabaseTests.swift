import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Incremental energy persistence")
struct EnergyHistoryDatabaseTests {
    @Test func comparesFullLegacyRewriteWithIncrementalJournalAtSixtyThousandIntervals() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("energy.json")
        let rows = (0..<60_000).map { interval(Double($0 * 10)) }
        let history = try EnergyHistory(restoring: rows)
        var legacyMilliseconds: [Double] = []
        for _ in 0..<3 {
            let start = Date()
            try EnergyHistoryFile.write(history, to: legacy)
            legacyMilliseconds.append(Date().timeIntervalSince(start) * 1000)
        }
        let bytes = try FileManager.default.attributesOfItem(atPath: legacy.path)[.size] as? NSNumber
        let database = try EnergyHistoryDatabase(url: EnergyHistoryDatabase.databaseURL(forLegacyFile: legacy), legacyFile: legacy)
        var appendMilliseconds: [Double] = []
        for offset in 0..<20 {
            let start = Date()
            try database.append(interval(Double((60_000 + offset) * 10)))
            appendMilliseconds.append(Date().timeIntervalSince(start) * 1000)
        }
        #expect(try database.history().intervals.count == 60_020)
        print("Energy 60k synthetic benchmark: legacy rewrite median \(legacyMilliseconds.sorted()[1])ms, SQLite interval append median \(appendMilliseconds.sorted()[10])ms, retained JSON \(bytes?.intValue ?? 0)bytes")
    }

    @Test func migrationPreservesLegacyAndImportsOnlyOnce() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("energy-history.json")
        let initial = try EnergyHistory(restoring: [interval(100), interval(110, rate: 0.2)])
        try EnergyHistoryFile.write(initial, to: legacy)
        let backup = try Data(contentsOf: legacy)
        let url = EnergyHistoryDatabase.databaseURL(forLegacyFile: legacy)
        let database = try EnergyHistoryDatabase(url: url, legacyFile: legacy)
        #expect(try database.history().intervals == initial.intervals)
        #expect(try database.append(interval(120, rate: 0.3)))
        #expect(try Data(contentsOf: legacy) == backup)
        // Once imported, later legacy damage cannot erase journaled rows.
        try Data("broken legacy backup".utf8).write(to: legacy)
        let reopened = try EnergyHistoryDatabase(url: url, legacyFile: legacy)
        #expect(try reopened.history().intervals == initial.intervals + [interval(120, rate: 0.3)])
        #expect(try Data(contentsOf: legacy) == Data("broken legacy backup".utf8))
    }

    @Test func invalidLegacyIsPreservedAndCanBeRetried() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("energy.json")
        let invalid = Data("broken".utf8)
        try invalid.write(to: legacy)
        let url = EnergyHistoryDatabase.databaseURL(forLegacyFile: legacy)
        #expect(throws: (any Error).self) { try EnergyHistoryDatabase(url: url, legacyFile: legacy) }
        #expect(try Data(contentsOf: legacy) == invalid)
        try EnergyHistoryFile.write(EnergyHistory(restoring: [interval(100)]), to: legacy)
        #expect(try EnergyHistoryDatabase(url: url, legacyFile: legacy).history().intervals == [interval(100)])
    }

    @Test func failedMigrationRollsBackRowsAndMarker() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacy = directory.appendingPathComponent("energy.json")
        try EnergyHistoryFile.write(EnergyHistory(restoring: [interval(100), interval(110)]), to: legacy)
        let original = try Data(contentsOf: legacy)
        let url = EnergyHistoryDatabase.databaseURL(forLegacyFile: legacy)
        try sql(url, """
            CREATE TABLE energy_intervals (start_at REAL PRIMARY KEY NOT NULL, end_at REAL NOT NULL, payload BLOB NOT NULL);
            CREATE TABLE energy_metadata (key TEXT PRIMARY KEY NOT NULL, value TEXT NOT NULL);
            CREATE TRIGGER reject_second BEFORE INSERT ON energy_intervals WHEN NEW.start_at = 110 BEGIN SELECT RAISE(ABORT, 'fixture'); END;
            """)
        #expect(throws: (any Error).self) { try EnergyHistoryDatabase(url: url, legacyFile: legacy) }
        #expect(try scalar(url, "SELECT COUNT(*) FROM energy_intervals") == 0)
        #expect(try scalar(url, "SELECT COUNT(*) FROM energy_metadata") == 0)
        #expect(try Data(contentsOf: legacy) == original)
        try sql(url, "DROP TRIGGER reject_second")
        #expect(try EnergyHistoryDatabase(url: url, legacyFile: legacy).history().intervals.count == 2)
    }

    @Test func replayConflictRetentionAndPrivateFiles() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("energy.sqlite3")
        let database = try EnergyHistoryDatabase(url: url, maximumIntervals: 3)
        for start in [100.0, 110, 120, 130] { try database.append(interval(start)) }
        #expect(try !database.append(interval(130)))
        #expect(throws: EnergyHistoryDatabaseError.conflictingInterval) { try database.append(interval(130, rate: 0.9)) }
        #expect(throws: EnergyHistoryDatabaseError.conflictingInterval) { try database.append(interval(135)) }
        #expect(try database.history().intervals.map(\.start.timeIntervalSince1970) == [110, 120, 130])
        #expect(try EnergyHistoryDatabase(url: url, maximumIntervals: 3).history().intervals == database.history().intervals)
        for suffix in ["", "-wal", "-shm"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path + suffix)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }

    @Test func corruptDurableRowsBlockStartupWithoutPruningThem() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("energy.sqlite3")
        let database = try EnergyHistoryDatabase(url: url)
        try database.append(interval(100))
        try database.append(interval(110))
        try sql(url, "UPDATE energy_intervals SET payload = X'00' WHERE start_at = 100")
        #expect(throws: EnergyHistoryDatabaseError.corruptRecord) { try EnergyHistoryDatabase(url: url, maximumIntervals: 1) }
        #expect(try scalar(url, "SELECT COUNT(*) FROM energy_intervals") == 2)
        #expect(try scalar(url, "SELECT LENGTH(payload) FROM energy_intervals WHERE start_at = 100") == 1)
    }

    @Test func recorderReopenPreservesActivityTariffsAndGaps() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("energy.json")
        let activity = ModelPowerActivity(modelID: "gemma", inferenceActive: true)
        let recorder = EnergyRecorder(file: legacy) { date in
            .init(date: date, watts: 100, source: "fixture", estimated: true)
        }
        _ = await recorder.sample(enabled: true, rate: 0.1, now: Date(timeIntervalSince1970: 100), modelActivity: activity)
        _ = await recorder.sample(enabled: true, rate: 0.1, now: Date(timeIntervalSince1970: 110), modelActivity: activity)
        _ = await recorder.sample(enabled: true, rate: 0.2, now: Date(timeIntervalSince1970: 120), modelActivity: activity)
        let prior = await recorder.sample(enabled: true, rate: 0.2, now: Date(timeIntervalSince1970: 130), modelActivity: activity)
        let reopened = EnergyRecorder(file: legacy) { date in
            .init(date: date, watts: 100, source: "fixture", estimated: false)
        }
        let resumed = await reopened.sample(enabled: true, rate: 0.2, now: Date(timeIntervalSince1970: 140), modelActivity: activity)
        #expect(resumed.intervals == prior.intervals)
        let next = await reopened.sample(enabled: true, rate: 0.2, now: Date(timeIntervalSince1970: 150), modelActivity: activity)
        #expect(next.issue == nil)
        #expect(next.intervals.map(\.usdPerKWh) == [0.1, 0.2, 0.2])
        #expect(next.intervals.map(\.estimated) == [true, true, false])
        #expect(next.intervals.map(\.activeModelID) == ["gemma", "gemma", "gemma"])
        #expect(next.intervals.map(\.start.timeIntervalSince1970) == [100, 120, 140])
    }

    @Test func recorderFailureDropsUncommittedIntervalsAndRestartsContinuity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let legacy = directory.appendingPathComponent("energy.json")
        let recorder = EnergyRecorder(file: legacy) { date in .init(date: date, watts: 100, source: "fixture", estimated: true) }
        _ = await recorder.sample(enabled: true, rate: 0.1, now: Date(timeIntervalSince1970: 100))
        let url = EnergyHistoryDatabase.databaseURL(forLegacyFile: legacy)
        try sql(url, "CREATE TRIGGER reject_write BEFORE INSERT ON energy_intervals BEGIN SELECT RAISE(ABORT, 'fixture'); END")
        let failed = await recorder.sample(enabled: true, rate: 0.1, now: Date(timeIntervalSince1970: 110))
        #expect(failed.issue == "Energy history could not be saved.")
        #expect(failed.intervals.isEmpty)
        try sql(url, "DROP TRIGGER reject_write")
        let retry = await recorder.sample(enabled: true, rate: 0.1, now: Date(timeIntervalSince1970: 120))
        #expect(retry.intervals.isEmpty)
        let resumed = await recorder.sample(enabled: true, rate: 0.1, now: Date(timeIntervalSince1970: 130))
        #expect(resumed.intervals.map(\.start.timeIntervalSince1970) == [120])
    }

    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("EnergyJournalTests-\(UUID())") }
    private func interval(_ seconds: Double, rate: Double = 0.1) -> EnergyInterval {
        .init(start: Date(timeIntervalSince1970: seconds), end: Date(timeIntervalSince1970: seconds + 10),
              kWh: 0.001, usdPerKWh: rate, source: "fixture", estimated: true,
              activeModelID: "gemma", inferenceActive: true)
    }
    private func sql(_ url: URL, _ sql: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw EnergyHistoryDatabaseError.unavailable }
        defer { sqlite3_close(database) }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else { throw EnergyHistoryDatabaseError.unavailable }
    }
    private func scalar(_ url: URL, _ sql: String) throws -> Int {
        var database: OpaquePointer?
        guard sqlite3_open(url.path, &database) == SQLITE_OK, let database else { throw EnergyHistoryDatabaseError.unavailable }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw EnergyHistoryDatabaseError.unavailable }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw EnergyHistoryDatabaseError.unavailable }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
