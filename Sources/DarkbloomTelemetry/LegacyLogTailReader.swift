import CryptoKit
import Foundation

/// One source owns one bounded metadata cache. Raw bytes and fields remain
/// temporary, and the file is reread even when the selected tail is unchanged.
actor LegacyLogTailReader {
    private struct FormatterContext: Equatable {
        let timeZone: TimeZone?
        let calendar: Calendar?
        let behavior: Int
    }
    private struct Cache {
        let digest: SHA256.Digest
        let limit: Int
        let context: FormatterContext
        let positions: [LegacyLogLinePosition]
    }

    private let url: URL
    private let makeFormatter: @Sendable () -> DateFormatter
    private var cache: Cache?
    /// Non-published diagnostics; acquisition never observes or polls them.
    private(set) var parsePassCount = 0
    var retainedPositionCount: Int { cache?.positions.count ?? 0 }

    init(url: URL, makeFormatter: @escaping @Sendable () -> DateFormatter = LegacyLogParser.dateFormatter) {
        self.url = url
        self.makeFormatter = makeFormatter
    }

    func read(limit: Int) throws -> [LogEvent] {
        do {
            let data = try BoundedFileTail.read(url: url, maxBytes: DarkbloomSourcePolicy.legacyLogByteLimit)
            guard limit > 0 else { cache = nil; return [] }
            let formatter = makeFormatter()
            let context = FormatterContext(timeZone: formatter.timeZone, calendar: formatter.calendar,
                                           behavior: Int(formatter.formatterBehavior.rawValue))
            // Public callers can request more than the production 100-row
            // window. Preserve that result without retaining larger metadata.
            guard limit <= 100 else {
                cache = nil
                parsePassCount += 1
                return LegacyLogParser.parse(String(decoding: data, as: UTF8.self), limit: limit, formatter: formatter)
            }
            let digest = SHA256.hash(data: data)
            if let cache, cache.digest == digest, cache.limit == limit, cache.context == context {
                // An unchanged quiet tail needs neither decoding nor scanning.
                if cache.positions.isEmpty { return [] }
                if let events = LegacyLogParser.replay(String(decoding: data, as: UTF8.self), positions: cache.positions) {
                    return events
                }
            }
            parsePassCount += 1
            var positions: [LegacyLogLinePosition] = []
            let events = LegacyLogParser.parse(String(decoding: data, as: UTF8.self), limit: limit,
                                               formatter: formatter, capture: { positions.append($0) })
            cache = Cache(digest: digest, limit: limit, context: context, positions: positions.reversed())
            return events
        } catch {
            cache = nil
            throw error
        }
    }
}
