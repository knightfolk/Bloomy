import Foundation
import Testing
@testable import DarkbloomCompanionProtocol

@Suite("Companion alert-history contract")
struct AlertHistoryContractTests {
    @Test("alert pages round-trip closed codes and bounded pagination")
    func roundTrip() throws {
        let hostID = UUID(uuidString: "b2c5b585-30a2-4c81-9245-5666baa133a2")!
        let record = CompanionAlertRecord(
            id: 19,
            code: .providerOffline,
            transition: .raised,
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            observedDurationSeconds: 90,
            observationCount: 8
        )
        let page = try AlertHistoryPage.validated(
            hostID: hostID,
            records: [record],
            nextCursor: 18
        )
        let envelope = Envelope(
            requestID: UUID(uuidString: "af55c7b1-207f-4c08-8f6f-28234247c58d")!,
            payload: .alertHistoryPage(page)
        )
        let bytes = try JSONEncoder().encode(envelope)
        let decoded = try JSONDecoder().decode(Envelope.self, from: bytes)

        #expect(decoded.payload == .alertHistoryPage(page))
        #expect(decoded.messageType == .alertHistoryPage)
        #expect(try AlertHistoryQuery(cursor: nil, maximumRecords: 25).validated().maximumRecords == 25)
    }

    @Test("pages reject excessive rows, duplicate IDs, and invalid cursors")
    func rejectsMalformedPagination() throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let record = CompanionAlertRecord(
            id: 4, code: .modelUnknown, transition: .recovered,
            occurredAt: now, observedDurationSeconds: nil, observationCount: 1
        )
        #expect(throws: (any Error).self) {
            try AlertHistoryQuery(cursor: 0, maximumRecords: 10).validated()
        }
        #expect(throws: (any Error).self) {
            try AlertHistoryQuery(cursor: nil, maximumRecords: 101).validated()
        }
        let excessiveRows = (1...101).reversed().map { id in
            CompanionAlertRecord(
                id: Int64(id), code: .modelUnknown, transition: .recovered,
                occurredAt: now, observedDurationSeconds: nil, observationCount: 1
            )
        }
        #expect(throws: (any Error).self) {
            try AlertHistoryPage.validated(hostID: UUID(), records: excessiveRows, nextCursor: nil)
        }
        #expect(throws: (any Error).self) {
            try AlertHistoryPage.validated(
                hostID: UUID(), records: [record, record], nextCursor: nil
            )
        }
        #expect(throws: (any Error).self) {
            try AlertHistoryPage.validated(
                hostID: UUID(), records: [record], nextCursor: 5
            )
        }
    }

    @Test("alert DTO decoding never re-exports unknown diagnostic text")
    func dropsUnknownDiagnosticFields() throws {
        let page = try AlertHistoryPage.validated(
            hostID: UUID(),
            records: [CompanionAlertRecord(
                id: 3, code: .lifecycleTimedOut, transition: .raised,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                observedDurationSeconds: nil, observationCount: 2
            )],
            nextCursor: nil
        )
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        var records = try #require(json["records"] as? [[String: Any]])
        records[0]["diagnostic"] = "must-not-round-trip-secret-canary"
        json["records"] = records

        let decoded = try JSONDecoder().decode(AlertHistoryPage.self, from: JSONSerialization.data(withJSONObject: json))
        let reencoded = String(decoding: try JSONEncoder().encode(decoded), as: UTF8.self)
        #expect(reencoded.contains("must-not-round-trip-secret-canary") == false)
        #expect(reencoded.contains("lifecycle_timed_out"))
    }
}
