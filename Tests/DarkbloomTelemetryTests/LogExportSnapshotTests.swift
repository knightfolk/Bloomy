import Foundation
import Testing
@testable import DarkbloomTelemetry

struct LogExportSnapshotTests {
    @Test("exports retain newest-first tied rows and omit the oldest ties at the byte limit")
    func tiedOrder() throws {
        for length in [0, 1_280] {
            let events = (0..<100).reversed().map {
                event(message: "event \($0) " + String(repeating: "\\", count: length))
            }
            let snapshot = try LogExportSnapshot.make(events: events, sourceCapturedAt: Date(),
                sourceIsStale: false, createdAt: Date())
            let object = try #require(JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])
            let records = try #require(object["events"] as? [[String: Any]])
            #expect(records.compactMap { $0["message"] as? String } == Array(events.prefix(snapshot.eventCount)).map(\.message))
            #expect(snapshot.data.count <= LogExportSnapshot.maximumBytes)
            #expect(snapshot.omittedCount == 100 - snapshot.eventCount)
            if length == 0 { #expect(snapshot.eventCount == 100) }
            else { #expect(snapshot.eventCount > 0 && snapshot.eventCount < 100) }
        }
    }

    @Test("export re-filters sensitive text, omits process identifiers and records stale provenance")
    func privacyAndProvenance() throws {
        let snapshot = try LogExportSnapshot.make(events: [event(message: "Authorization: Bearer fixture-secret")],
            sourceCapturedAt: Date(timeIntervalSince1970: 0), sourceIsStale: true,
            createdAt: Date(timeIntervalSince1970: 60))
        let object = try #require(JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])
        let records = try #require(object["events"] as? [[String: Any]])
        #expect(object["schema"] as? Int == 1)
        #expect(object["source_status"] as? String == "last-known")
        #expect(object["source_captured_at"] as? String == "1970-01-01T00:00:00Z")
        #expect(snapshot.eventCount == 1)
        #expect(snapshot.omittedCount == 0)
        #expect(!snapshot.previewText.contains("fixture-secret"))
        #expect(records.first?["processID"] == nil)
        #expect(records.first?["processImage"] == nil)
        #expect(!snapshot.previewText.contains("fixture-user"))
        #expect(records.first?["severity"] as? String == "warning")
    }

    @Test("JSON escaping cannot exceed the export byte cap and only whole events are retained")
    func byteCap() throws {
        let events = (0..<100).map { event(message: String(repeating: "\\", count: 1_280), timestamp: Double($0)) }
        let snapshot = try LogExportSnapshot.make(events: events, sourceCapturedAt: Date(), sourceIsStale: false, createdAt: Date())
        #expect(snapshot.data.count <= 256 * 1_024)
        #expect(snapshot.eventCount > 0)
        #expect(snapshot.eventCount < 100)
        #expect(snapshot.omittedCount == 100 - snapshot.eventCount)
        let object = try #require(JSONSerialization.jsonObject(with: snapshot.data) as? [String: Any])
        let records = try #require(object["events"] as? [[String: Any]])
        #expect(records.count == snapshot.eventCount)
        #expect(records.allSatisfy { ($0["message"] as? String)?.count == 1_280 })
    }

    @Test("invalid export timestamps fail before producing an artifact")
    func invalidDate() {
        #expect(throws: LogExportError.invalidTimestamp) {
            try LogExportSnapshot.make(events: [], sourceCapturedAt: Date(timeIntervalSince1970: .nan),
                                       sourceIsStale: false, createdAt: Date())
        }
    }

    private func event(message: String, timestamp: Double = 0) -> LogEvent {
        LogEvent(timestamp: Date(timeIntervalSince1970: timestamp), severity: .warning, category: "Inference",
                 message: message, source: .legacy, processID: 42, processImage: "/Users/fixture-user/provider")
    }
}
