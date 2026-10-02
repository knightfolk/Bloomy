import Foundation
import SQLite3
import Testing
@testable import DarkbloomTelemetry

@Suite("Observed uptime scaling")
struct ObservedUptimeScalingTests {
    // Opt in: BLOOMY_UPTIME_BENCHMARK=1 swift test --jobs 2
    // --filter ObservedUptimeScalingTests/scalingBenchmark
    // Seed the real persisted schema in one transaction, then time actual records.
    // No provider, production database, network, or speed assertions are involved.
    @Test("opt-in persisted-history record benchmark", .enabled(if: ProcessInfo.processInfo.environment["BLOOMY_UPTIME_BENCHMARK"] == "1"))
    func scalingBenchmark() async throws {
        for count in [1_000, 10_000, 106_000] {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("bloomy-uptime-scaling-\(UUID().uuidString).sqlite3")
            defer {
                for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: url.path + suffix) }
            }
            let database = try ObservedUptimeDatabase(url: url)
            try seed(url: url, count: count)
            let step = 86_000.0 / Double(count)
            let first = ContinuousClock.now
            _ = try await database.record(status: .online, at: Date(timeIntervalSince1970: 86_000))
            let bootstrap = milliseconds(first.duration(to: .now))
            var timings: [Double] = []
            for index in 1...50 {
                let start = ContinuousClock.now
                let value = try await database.record(
                    status: index.isMultiple(of: 3) ? .offline : .online,
                    at: Date(timeIntervalSince1970: 86_000 + Double(index) * step)
                )
                timings.append(milliseconds(start.duration(to: .now)))
                guard case .available(_, let seconds) = value else {
                    Issue.record("Expected classified benchmark coverage")
                    return
                }
                #expect(seconds > 300)
            }
            let sorted = timings.sorted()
            print("ObservedUptime benchmark rows=\(count) bootstrapMs=\(bootstrap) medianMs=\(sorted[sorted.count / 2]) p95Ms=\(sorted[Int(Double(sorted.count - 1) * 0.95)])")
        }
    }

    private func milliseconds(_ duration: Duration) -> Double {
        let parts = duration.components
        return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
    }

    private func seed(url: URL, count: Int) throws {
        var pointer: OpaquePointer?
        guard sqlite3_open(url.path, &pointer) == SQLITE_OK, let pointer else { throw SeedError.failed }
        defer { sqlite3_close(pointer) }
        guard sqlite3_exec(pointer, "BEGIN", nil, nil, nil) == SQLITE_OK else { throw SeedError.failed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(pointer, "INSERT INTO uptime_observations VALUES (?, ?)", -1, &statement, nil) == SQLITE_OK,
              let statement else { throw SeedError.failed }
        defer { sqlite3_finalize(statement) }
        for index in 0..<count {
            sqlite3_bind_double(statement, 1, Double(index) * 86_000 / Double(count))
            sqlite3_bind_int(statement, 2, index.isMultiple(of: 3) ? 2 : 1)
            guard sqlite3_step(statement) == SQLITE_DONE else { throw SeedError.failed }
            sqlite3_reset(statement)
        }
        guard sqlite3_exec(pointer, "COMMIT", nil, nil, nil) == SQLITE_OK else { throw SeedError.failed }
    }

    private enum SeedError: Error { case failed }
}
