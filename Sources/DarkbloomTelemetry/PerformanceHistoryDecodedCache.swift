import CryptoKit
import Foundation

/// Decoded values only: payload bytes never outlive the current SQLite row.
/// Each read builds a separate bounded generation, leaving the previous one
/// immutable until that read finishes successfully.
enum PerformanceHistoryDecodedCache {
    static let maximumRows = 32_768
    static let maximumBytes = 16 * 1_024 * 1_024

    struct Entry {
        let digest: SHA256.Digest
        let sample: PerformanceSample
        let accountedBytes: Int

        init(digest: SHA256.Digest, sample: PerformanceSample, accountedBytes: Int? = nil) {
            self.digest = digest
            self.sample = sample
            self.accountedBytes = accountedBytes ?? Self.cost(of: sample)
        }

        // Allow for overallocated dictionary buckets, value storage and allocator
        // overhead. Strings/arrays are charged independently even when shared
        // with the returned result or previous generation.
        static var minimumBytes: Int {
            MemoryLayout<Self>.stride * 2 + MemoryLayout<UUID>.stride * 2 + 128
        }

        static func cost(of sample: PerformanceSample) -> Int {
            func stringBytes(_ value: String?) -> Int {
                value.map { 64 + $0.utf8.count * 2 } ?? 0
            }
            func arrayBytes(_ values: [String]) -> Int {
                guard !values.isEmpty else { return 0 }
                return 128 + values.count * MemoryLayout<String>.stride * 2
                    + values.reduce(0) { $0 + stringBytes($1) }
            }
            return Self.minimumBytes + stringBytes(sample.model)
                + stringBytes(sample.providerSession) + stringBytes(sample.autopilotPhase)
                + arrayBytes(sample.residentModels) + arrayBytes(sample.advertisedModels)
        }
    }

    struct Generation {
        let entries: [UUID: Entry]
        let accountedBytes: Int
        static let empty = Generation(entries: [:], accountedBytes: 0)
    }

    struct Diagnostics: Equatable {
        let rows: Int
        let accountedBytes: Int
        let hits: Int
        let misses: Int
        let hashedRows: Int
        let peakAccountedBytes: Int
        static let empty = Diagnostics(rows: 0, accountedBytes: 0, hits: 0, misses: 0, hashedRows: 0, peakAccountedBytes: 0)
    }

    /// Rows arrive newest first. Once full, later rows are decoded for the
    /// caller but cannot churn this generation's retained prefix.
    final class Builder {
        private var entries: [UUID: Entry] = [:]
        private var accountedBytes: Int
        private let maximumBytes: Int
        private let maximumRows: Int
        var peakAccountedBytes: Int { accountedBytes }

        init(maximumRows: Int = PerformanceHistoryDecodedCache.maximumRows,
             maximumBytes: Int = PerformanceHistoryDecodedCache.maximumBytes) {
            self.maximumBytes = min(max(maximumBytes, 0), PerformanceHistoryDecodedCache.maximumBytes)
            self.maximumRows = min(max(maximumRows, 0), PerformanceHistoryDecodedCache.maximumRows)
            accountedBytes = min(self.maximumBytes, 256)
        }

        /// Do the cheap capacity check before walking any model strings. The
        /// returned estimate can be reused by Entry instead of computing twice.
        func admissionCost(of sample: PerformanceSample) -> Int? {
            guard entries.count < maximumRows,
                  maximumBytes - accountedBytes >= Entry.minimumBytes else { return nil }
            let cost = Entry.cost(of: sample)
            return cost <= maximumBytes - accountedBytes ? cost : nil
        }

        func insert(_ entry: Entry) {
            guard entries.count < maximumRows,
                  entry.accountedBytes <= maximumBytes - accountedBytes,
                  entries[entry.sample.id] == nil else { return }
            entries[entry.sample.id] = entry
            accountedBytes += entry.accountedBytes
        }

        func finish() -> Generation {
            Generation(entries: entries, accountedBytes: accountedBytes)
        }
    }
}
