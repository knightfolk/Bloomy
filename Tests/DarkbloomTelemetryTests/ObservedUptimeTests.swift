import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Monitor-observed rolling uptime")
struct ObservedUptimeTests {
    @Test("unknown and unobserved gaps are excluded from uptime")
    func excludesUnknownAndLongGaps() async throws {
        let database = try ObservedUptimeDatabase(
            url: temporaryDatabaseURL(),
            window: 86_400,
            maximumCarry: 10,
            minimumObservedDuration: 0
        )

        _ = try await database.record(status: .online, at: date(0))
        _ = try await database.record(status: .online, at: date(10))
        _ = try await database.record(status: .unavailable, at: date(20))
        _ = try await database.record(status: .offline, at: date(100))
        let result = try await database.record(status: .offline, at: date(110))

        guard case .available(let percent, let observedSeconds) = result else {
            Issue.record("Expected an available uptime value, got \(result)")
            return
        }
        #expect(abs(percent - (200.0 / 3.0)) < 0.0001)
        #expect(observedSeconds == 30)
    }

    @Test("the rolling boundary clips a carried observation")
    func clipsAtRollingBoundary() async throws {
        let database = try ObservedUptimeDatabase(
            url: temporaryDatabaseURL(),
            window: 86_400,
            maximumCarry: 10,
            minimumObservedDuration: 0
        )

        _ = try await database.record(status: .online, at: date(13_595))
        _ = try await database.record(status: .offline, at: date(13_605))
        _ = try await database.record(status: .offline, at: date(13_615))
        let result = try await database.snapshot(at: date(100_000))

        #expect(result == .available(percent: 20, observedSeconds: 25))
    }

    @Test("initial coverage remains warming until five observed minutes")
    func warmsUpBeforePublishingPercent() async throws {
        let database = try ObservedUptimeDatabase(
            url: temporaryDatabaseURL(),
            window: 86_400,
            maximumCarry: 10,
            minimumObservedDuration: 300
        )

        for second in stride(from: 0, through: 290, by: 10) {
            _ = try await database.record(status: .online, at: date(second))
        }
        let warming = try await database.snapshot(at: date(299))
        let available = try await database.record(status: .online, at: date(300))

        #expect(warming == .warming(observedSeconds: 299))
        #expect(available == .available(percent: 100, observedSeconds: 300))
    }

    @Test("timestamped observations survive a database restart")
    func persistsAcrossRestart() async throws {
        let url = temporaryDatabaseURL()
        do {
            let database = try ObservedUptimeDatabase(
                url: url,
                window: 86_400,
                maximumCarry: 10,
                minimumObservedDuration: 300
            )
            for second in stride(from: 0, through: 300, by: 10) {
                _ = try await database.record(status: .online, at: date(second))
            }
        }

        let reopened = try ObservedUptimeDatabase(
            url: url,
            window: 86_400,
            maximumCarry: 10,
            minimumObservedDuration: 300
        )
        let result = try await reopened.snapshot(at: date(300))

        #expect(result == .available(percent: 100, observedSeconds: 300))
    }

    @Test("the local uptime database is private to the user")
    func databasePermissionsArePrivate() throws {
        let url = temporaryDatabaseURL()
        _ = try ObservedUptimeDatabase(url: url)

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }

    @Test("mixed timestamps, snapshots, pruning and reopening match the original interval fold")
    func randomizedReferenceParity() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(url) }
        var database = try ObservedUptimeDatabase(url: url, window: 125, maximumCarry: 10, minimumObservedDuration: 15)
        var reference = UptimeReference(window: 125, carry: 10, warmup: 15)
        var random = SeededRandom(state: 0xB100_0124)
        let statuses: [MenuPresentationStatus] = [.online, .offline, .stale, .unavailable]
        var now = 2_000_000_000.0
        for index in 0..<1_000 {
            // Binary fractional seconds exercise clipping without a tolerance
            // hiding classification or five-minute threshold differences.
            now += Double(random.next() % 49) / 4
            let mode = random.next() % 10
            let timestamp = mode == 0 ? now - Double(random.next() % 150)
                : mode == 1 ? now + 40
                : mode == 2 ? now.rounded(.down)
                : now
            if mode == 3 || mode == 4 {
                let actual = try await database.snapshot(at: Date(timeIntervalSince1970: timestamp))
                #expect(actual == reference.snapshot(at: timestamp))
            } else {
                let status = statuses[Int(random.next() % 4)]
                let actual = try await database.record(status: status, at: Date(timeIntervalSince1970: timestamp))
                #expect(actual == reference.record(status: status, at: timestamp))
            }
            if index.isMultiple(of: 137) {
                database = try ObservedUptimeDatabase(url: url, window: 125, maximumCarry: 10, minimumObservedDuration: 15)
            }
        }
    }

    @Test("newest duplicates and earlier replacements preserve neighboring intervals and future rows")
    func replacementsAndRollback() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(url) }
        let database = try ObservedUptimeDatabase(url: url, window: 100, maximumCarry: 10, minimumObservedDuration: 1)
        var reference = UptimeReference(window: 100, carry: 10, warmup: 1)
        for (timestamp, status) in [(0.0, MenuPresentationStatus.online), (5, .offline), (5, .online),
                                    (30, .offline), (3, .unavailable), (30, .online), (7, .offline)] {
            #expect(try await database.record(status: status, at: Date(timeIntervalSince1970: timestamp))
                    == reference.record(status: status, at: timestamp))
        }
        for timestamp in [4.0, 10, 35, 150, 5, 170] {
            #expect(try await database.snapshot(at: Date(timeIntervalSince1970: timestamp))
                    == reference.snapshot(at: timestamp))
        }
        // Moving backward cannot recover observations already removed by the
        // forward snapshot; a new historical row is persisted normally.
        #expect(try await database.record(status: .online, at: date(6)) == reference.record(status: .online, at: 6))
        #expect(try await database.snapshot(at: date(12)) == reference.snapshot(at: 12))
    }

    @Test("external database writers invalidate cached intervals")
    func externalWriterInvalidatesCache() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(url) }
        let first = try ObservedUptimeDatabase(url: url, window: 100, maximumCarry: 10, minimumObservedDuration: 1)
        let second = try ObservedUptimeDatabase(url: url, window: 100, maximumCarry: 10, minimumObservedDuration: 1)
        _ = try await first.record(status: .online, at: date(0))
        #expect(try await first.snapshot(at: date(10)) == .available(percent: 100, observedSeconds: 10))
        _ = try await second.record(status: .offline, at: date(0))
        #expect(try await first.snapshot(at: date(10)) == .available(percent: 0, observedSeconds: 10))
        _ = try await second.record(status: .online, at: date(5))
        #expect(try await first.record(status: .offline, at: date(10)) == .available(percent: 50, observedSeconds: 10))
        #expect(await first.aggregationRebuildCount == 3)
    }

    @Test("chronological records use one bootstrap and prune bounded cache storage")
    func incrementalMechanismAndCompaction() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(url) }
        let database = try ObservedUptimeDatabase(url: url, window: 50, maximumCarry: 10, minimumObservedDuration: 1)
        var reference = UptimeReference(window: 50, carry: 10, warmup: 1)
        for second in 0..<5_000 {
            let status: MenuPresentationStatus = second.isMultiple(of: 3) ? .offline : .online
            let expected = reference.record(status: status, at: Double(second))
            #expect(try await database.record(status: status, at: date(second)) == expected)
        }
        #expect(await database.aggregationRebuildCount == 1)
        #expect(await database.aggregationStorageCount <= 122)
        #expect(try await database.snapshot(at: date(6_000)) == .warming(observedSeconds: 0))
        #expect(await database.aggregationStorageCount == 0)
        #expect(try await database.record(status: .offline, at: date(0)) == .warming(observedSeconds: 0))
        #expect(try await database.snapshot(at: date(10)) == .available(percent: 0, observedSeconds: 10))
    }

    @Test("non-finite dates and SQLite failures remain visible after cache bootstrap")
    func errorsRemainVisible() async throws {
        let url = temporaryDatabaseURL()
        defer { removeDatabase(url) }
        let database = try ObservedUptimeDatabase(url: url)
        _ = try await database.record(status: .online, at: date(0))
        await #expect(throws: ObservedUptimeDatabaseError.self) {
            try await database.snapshot(at: Date(timeIntervalSince1970: .infinity))
        }
        await #expect(throws: ObservedUptimeDatabaseError.self) {
            try await database.record(status: .offline, at: Date(timeIntervalSince1970: .infinity))
        }
        var pointer: OpaquePointer?
        #expect(sqlite3_open(url.path, &pointer) == SQLITE_OK)
        defer { sqlite3_close(pointer) }
        #expect(sqlite3_exec(pointer, "DROP TABLE uptime_observations", nil, nil, nil) == SQLITE_OK)
        await #expect(throws: ObservedUptimeDatabaseError.self) { try await database.snapshot(at: date(10)) }
        await #expect(throws: ObservedUptimeDatabaseError.self) { try await database.record(status: .online, at: date(10)) }
    }

    private struct UptimeReference {
        let window: Double
        let carry: Double
        let warmup: Double
        var observations: [Double: MenuPresentationStatus] = [:]

        mutating func record(status: MenuPresentationStatus, at timestamp: Double) -> ObservedUptimeValue {
            observations[timestamp] = status
            return snapshot(at: timestamp)
        }

        mutating func snapshot(at now: Double) -> ObservedUptimeValue {
            observations = observations.filter { $0.key >= now - window - carry }
            let rows = observations.filter { $0.key <= now }.sorted { $0.key < $1.key }
            var online = 0.0
            var offline = 0.0
            for (index, row) in rows.enumerated() {
                let next = index + 1 < rows.count ? rows[index + 1].key : now
                let start = max(row.key, now - window)
                let end = min(next, row.key + carry, now)
                guard end > start else { continue }
                switch row.value {
                case .online: online += end - start
                case .offline: offline += end - start
                case .stale, .unavailable: break
                }
            }
            let observed = online + offline
            guard observed >= warmup else { return .warming(observedSeconds: observed) }
            return .available(percent: min(max(online / observed * 100, 0), 100), observedSeconds: observed)
        }
    }

    private struct SeededRandom {
        var state: UInt64
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return state
        }
    }

    private func removeDatabase(_ url: URL) {
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
    }

    private func temporaryDatabaseURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("darkbloom-uptime-tests-\(UUID().uuidString).sqlite3")
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }
}
