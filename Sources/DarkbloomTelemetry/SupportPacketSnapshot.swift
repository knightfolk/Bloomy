import Foundation

public enum SupportPacketSnapshotError: Error, Equatable, Sendable {
    case invalidTimestamp
    case invalidAlert
    case responseTooLarge
}

/// Immutable, deterministic export bytes. The document is assembled from a
/// fixed field allowlist; arbitrary status text, diagnostics, logs, paths,
/// process identity, URLs, and account fields are never traversed.
public struct SupportPacketSnapshot: Sendable {
    public static let maximumBytes = 256 * 1_024
    private static let maximumAlertCandidates = 10_000
    private static let maximumModelIDs = 128

    public let data: Data
    public let alertCount: Int
    public let omittedAlertCount: Int

    public var previewText: String { String(decoding: data, as: UTF8.self) }

    public static func make(
        snapshot: TelemetrySnapshot,
        alerts: [AlertRecord],
        allowlistedModelIDs: Set<String>,
        createdAt: Date
    ) throws -> Self {
        guard Self.isExportableDate(snapshot.capturedAt),
              Self.isExportableDate(createdAt),
              alerts.allSatisfy({ Self.isExportableDate($0.occurredAt) }) else {
            throw SupportPacketSnapshotError.invalidTimestamp
        }
        guard alerts.allSatisfy(Self.isValidAlert) else {
            throw SupportPacketSnapshotError.invalidAlert
        }
        switch snapshot.state {
        case .available(_, let date), .stale(_, let date, _):
            guard Self.isExportableDate(date) else { throw SupportPacketSnapshotError.invalidTimestamp }
        case .unavailable:
            break
        }

        let source = sourceFacts(snapshot)
        let allowedModels = Set(
            allowlistedModelIDs
                .filter(isExportableModelID)
                .sorted()
                .prefix(512)
        )
        let rawModels = source.daemon.map(Self.boundedModelCandidates) ?? []
        let loadedModels: [String]
        switch snapshot.loadedModels {
        case .available(let value, _), .stale(let value, _, _):
            loadedModels = Array(value.models.prefix(512))
        case .unavailable:
            loadedModels = []
        }
        let exportableModels = Set((rawModels + loadedModels).filter {
            isExportableModelID($0) && allowedModels.contains($0)
        }).sorted()
        let modelIDs = Array(exportableModels.prefix(maximumModelIDs))

        let orderedAlerts = alerts
            .sorted {
                if $0.occurredAt != $1.occurredAt { return $0.occurredAt < $1.occurredAt }
                if $0.code != $1.code { return $0.code.rawValue < $1.code.rawValue }
                if $0.kind != $1.kind { return $0.kind.rawValue < $1.kind.rawValue }
                if $0.observedDurationSeconds != $1.observedDurationSeconds {
                    return ($0.observedDurationSeconds ?? -1) < ($1.observedDurationSeconds ?? -1)
                }
                if $0.observationCount != $1.observationCount {
                    return $0.observationCount < $1.observationCount
                }
                return $0.id < $1.id
            }
        let alertCandidates = Array(orderedAlerts.suffix(maximumAlertCandidates))
        let inputOmittedCount = orderedAlerts.count - alertCandidates.count
        let document = Document(
            schema: 1,
            createdAt: createdAt,
            snapshotCapturedAt: snapshot.capturedAt,
            providerStatus: statusCode(snapshot.menuStatus),
            stateAvailability: source.availability,
            stateCapturedAt: source.capturedAt,
            stateAgeSeconds: source.ageSeconds,
            currentModelID: source.daemon.flatMap { allowlistedModel($0.currentModel, in: allowedModels) },
            modelIDs: modelIDs,
            omittedModelCount: max(0, exportableModels.count - modelIDs.count),
            modelLoadFailureCodes: source.daemon.map {
                Array(Set($0.modelLoadFailures.prefix(256).map(\.code.rawValue))).sorted()
            } ?? [],
            lifecycleOutcome: source.daemon?.lifecycle.map { lifecycleCode($0.outcome) },
            requestsServed: source.daemon?.stats.requestsServed.boundedNonnegativeCounter,
            tokensGenerated: source.daemon?.stats.tokensGenerated.boundedNonnegativeCounter,
            alerts: [],
            omittedAlertCount: 0
        )

        func encode(_ alertCount: Int) throws -> Data {
            let selected = alertCount == 0 ? [] : Array(alertCandidates.suffix(alertCount))
            let packet = document.withAlerts(
                selected.map(PacketAlert.init),
                omittedAlertCount: inputOmittedCount + alertCandidates.count - alertCount
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return try encoder.encode(packet)
        }

        // Find the largest suffix of whole history rows that fits. This keeps
        // the most recent evidence and avoids repeated one-row re-encoding.
        var low = 0
        var high = alertCandidates.count
        while low < high {
            let middle = low + (high - low + 1) / 2
            if try encode(middle).count <= maximumBytes {
                low = middle
            } else {
                high = middle - 1
            }
        }
        let data = try encode(low)
        guard data.count <= maximumBytes else { throw SupportPacketSnapshotError.responseTooLarge }
        return Self(
            data: data,
            alertCount: low,
            omittedAlertCount: inputOmittedCount + alertCandidates.count - low
        )
    }

    private static func sourceFacts(_ snapshot: TelemetrySnapshot) -> SourceFacts {
        let availability: String
        let capturedAt: Date?
        let daemon: DaemonState?
        switch snapshot.state {
        case .available(let value, let date):
            availability = "available"
            capturedAt = date
            daemon = value
        case .stale(let value, let date, _):
            availability = "stale"
            capturedAt = date
            daemon = value
        case .unavailable:
            availability = "unavailable"
            capturedAt = nil
            daemon = nil
        }
        let validCapturedAt = capturedAt.flatMap { isExportableDate($0) ? $0 : nil }
        let age: Int? = capturedAt.flatMap { date in
            let seconds = snapshot.capturedAt.timeIntervalSince(date)
            guard seconds.isFinite, (0...86_400).contains(seconds) else { return nil }
            return Int(seconds.rounded(.down))
        }
        return SourceFacts(availability: availability, capturedAt: validCapturedAt, ageSeconds: age, daemon: daemon)
    }

    private static func boundedModelCandidates(_ daemon: DaemonState) -> [String] {
        let values = Array(daemon.warmModels.prefix(512))
            + Array((daemon.advertisedModels ?? []).prefix(512))
            + [daemon.currentModel]
        return values.filter(isExportableModelID)
    }

    private static func isValidAlert(_ alert: AlertRecord) -> Bool {
        (1...1_000_000).contains(alert.observationCount)
            && (alert.observedDurationSeconds.map { (0...86_400).contains($0) } ?? true)
    }

    private static func statusCode(_ status: MenuPresentationStatus) -> String {
        switch status {
        case .online: "online"
        case .stale: "stale"
        case .offline: "offline"
        case .unavailable: "unavailable"
        }
    }

    private static func lifecycleCode(_ outcome: ProviderLifecycleOutcome) -> String {
        switch outcome {
        case .serving: "serving"
        case .draining: "draining"
        case .drained: "drained"
        case .stopped: "stopped"
        case .timedOut: "timed_out"
        case .forced: "forced"
        case .busy: "busy"
        case .unknown: "unknown"
        }
    }

    private static func allowlistedModel(_ candidate: String, in allowlist: Set<String>) -> String? {
        allowlist.contains(candidate) && isExportableModelID(candidate) ? candidate : nil
    }

    private static func isExportableDate(_ date: Date) -> Bool {
        let seconds = date.timeIntervalSince1970
        return seconds.isFinite && (-62_135_596_800...253_402_300_799).contains(seconds)
    }

    private static func isExportableModelID(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 128,
              value != ".", value != "..",
              !value.hasPrefix("/"), !value.hasPrefix("~"),
              !value.contains(".."), !value.contains("://") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:/+-")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private struct SourceFacts {
        let availability: String
        let capturedAt: Date?
        let ageSeconds: Int?
        let daemon: DaemonState?
    }

    private struct Document: Encodable {
        let schema: Int
        let createdAt: Date
        let snapshotCapturedAt: Date
        let providerStatus: String
        let stateAvailability: String
        let stateCapturedAt: Date?
        let stateAgeSeconds: Int?
        let currentModelID: String?
        let modelIDs: [String]
        let omittedModelCount: Int
        let modelLoadFailureCodes: [String]
        let lifecycleOutcome: String?
        let requestsServed: Int64?
        let tokensGenerated: Int64?
        let alerts: [PacketAlert]
        let omittedAlertCount: Int

        enum CodingKeys: String, CodingKey {
            case schema
            case createdAt = "created_at"
            case snapshotCapturedAt = "snapshot_captured_at"
            case providerStatus = "provider_status"
            case stateAvailability = "state_availability"
            case stateCapturedAt = "state_captured_at"
            case stateAgeSeconds = "state_age_seconds"
            case currentModelID = "current_model_id"
            case modelIDs = "model_ids"
            case omittedModelCount = "omitted_model_count"
            case modelLoadFailureCodes = "model_load_failure_codes"
            case lifecycleOutcome = "lifecycle_outcome"
            case requestsServed = "requests_served"
            case tokensGenerated = "tokens_generated"
            case alerts
            case omittedAlertCount = "omitted_alert_count"
        }

        func withAlerts(_ alerts: [PacketAlert], omittedAlertCount: Int) -> Self {
            Self(
                schema: schema,
                createdAt: createdAt,
                snapshotCapturedAt: snapshotCapturedAt,
                providerStatus: providerStatus,
                stateAvailability: stateAvailability,
                stateCapturedAt: stateCapturedAt,
                stateAgeSeconds: stateAgeSeconds,
                currentModelID: currentModelID,
                modelIDs: modelIDs,
                omittedModelCount: omittedModelCount,
                modelLoadFailureCodes: modelLoadFailureCodes,
                lifecycleOutcome: lifecycleOutcome,
                requestsServed: requestsServed,
                tokensGenerated: tokensGenerated,
                alerts: alerts,
                omittedAlertCount: omittedAlertCount
            )
        }
    }

    private struct PacketAlert: Encodable {
        let code: OperationalAlertCode
        let transition: AlertTransitionKind
        let occurredAt: Date
        let observedDurationSeconds: Int?
        let observationCount: Int

        enum CodingKeys: String, CodingKey {
            case code
            case transition
            case occurredAt = "occurred_at"
            case observedDurationSeconds = "observed_duration_seconds"
            case observationCount = "observation_count"
        }

        init(_ record: AlertRecord) {
            code = record.code
            transition = record.kind
            occurredAt = record.occurredAt
            observedDurationSeconds = record.observedDurationSeconds
            observationCount = record.observationCount
        }
    }
}

private extension Int64 {
    var boundedNonnegativeCounter: Int64? {
        self >= 0 ? Swift.min(self, 1_000_000_000_000_000) : nil
    }
}
