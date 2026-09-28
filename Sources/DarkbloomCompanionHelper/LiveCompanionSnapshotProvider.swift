import DarkbloomCompanionHost
import DarkbloomCompanionProtocol
import DarkbloomTelemetry
import Foundation

public protocol HelperTelemetrySnapshotProviding: Sendable {
    func currentSnapshot() async -> TelemetrySnapshot
}

public actor RefreshingTelemetrySource: HelperTelemetrySnapshotProviding {
    private let refresh: @Sendable () async -> TelemetrySnapshot

    public init(refresh: @escaping @Sendable () async -> TelemetrySnapshot) {
        self.refresh = refresh
    }

    public func currentSnapshot() async -> TelemetrySnapshot { await refresh() }
}

/// Constructs the wire DTO from an explicit field allowlist. Strings from
/// diagnostics, logs, status text, config paths, and process identity are never
/// read by this adapter.
public actor LiveCompanionSnapshotProvider: CompanionSnapshotProviding {
    private let hostID: UUID
    private let runtimeEpoch: UUID
    private let telemetry: any HelperTelemetrySnapshotProviding
    private let now: @Sendable () -> Date
    private var sequence: UInt64 = 0

    public init(
        hostID: UUID, runtimeEpoch: UUID,
        telemetry: any HelperTelemetrySnapshotProviding,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.hostID = hostID
        self.runtimeEpoch = runtimeEpoch
        self.telemetry = telemetry
        self.now = now
    }

    public func snapshot(for deviceID: UUID, capabilities: Set<Capability>) async throws -> CompanionSnapshot {
        let source = await telemetry.currentSnapshot()
        let generatedAt = now()
        sequence &+= 1
        var observations: [MetricObservation] = []
        if case let .available(state, capturedAt) = source.state {
            let rawAge = generatedAt.timeIntervalSince(capturedAt)
            if rawAge.isFinite, (-5...10).contains(rawAge) {
                let age = max(0, rawAge)
                if state.stats.requestsServed >= 0 {
                    observations.append(.init(
                        metric: .requestsServed, value: Double(state.stats.requestsServed),
                        unit: .count, scope: .localProvider, provenance: .direct,
                        capturedAt: capturedAt, sourceAgeSeconds: age, availability: .available, reason: nil
                    ))
                }
                if state.stats.tokensGenerated >= 0 {
                    observations.append(.init(
                        metric: .tokensGenerated, value: Double(state.stats.tokensGenerated),
                        unit: .count, scope: .localProvider, provenance: .direct,
                        capturedAt: capturedAt, sourceAgeSeconds: age, availability: .available, reason: nil
                    ))
                }
            }
        }

        let providerState: RuntimeState
        switch source.menuStatus {
        case .online: providerState = .running
        case .offline: providerState = .stopped
        case .stale, .unavailable: providerState = .unavailable
        }
        let states = RuntimeStates(
            provider: .init(state: providerState, observedAt: generatedAt,
                            reason: providerState == .unavailable ? .sourceStale : nil),
            macApp: .init(state: .unknown, observedAt: generatedAt, reason: .unsupported),
            helper: .init(state: .running, observedAt: generatedAt),
            connection: .init(state: .connected, observedAt: generatedAt)
        )
        return try .validated(
            hostID: hostID, runtimeEpoch: runtimeEpoch, sequence: sequence,
            generatedAt: generatedAt, observations: observations,
            models: Self.safeModels(from: source), states: states,
            capabilities: capabilities.intersection([.monitor, .history, .settingsRead,
                                                       .settingsWrite, .providerLifecycle,
                                                       .providerLiveSwitch, .appLifecycle,
                                                       .deviceManagement])
        )
    }

    private static func safeModels(from snapshot: TelemetrySnapshot) -> [ModelSummary] {
        guard case let .available(loaded, _) = snapshot.loadedModels else { return [] }
        let current: String?
        let warm: Set<String>
        let advertised: Set<String>
        if case let .available(state, _) = snapshot.state {
            current = state.currentModel
            warm = Set(state.warmModels)
            advertised = Set(state.advertisedModels ?? [])
        } else {
            current = nil
            warm = []
            advertised = []
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-/:")
        return Array(Set(loaded.models)).sorted().filter { id in
            !id.isEmpty && id.utf8.count <= 128
                && id.unicodeScalars.allSatisfy { allowed.contains($0) }
        }.prefix(32).map { id in
            ModelSummary(
                id: id, name: id, enabled: true, advertised: advertised.contains(id),
                resident: warm.contains(id), active: current == id
            )
        }
    }
}
