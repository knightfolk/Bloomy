import Foundation

public enum DaemonStateParser {
    public static func parse(_ data: Data) throws -> DaemonState {
        try SchemaValidation.requireSchema1(data, source: "daemon-state.json")
        let raw = try JSONDecoder().decode(RawDaemonState.self, from: data)
        return DaemonState(
            schema: raw.schema,
            version: raw.version,
            currentModel: raw.currentModel ?? "",
            warmModels: raw.warmModels,
            stats: .init(
                tokensGenerated: raw.stats.tokensGenerated,
                requestsServed: raw.stats.requestsServed,
                usageGaps: raw.stats.usageGaps
            ),
            trust: raw.trust.map { trust in
                TrustState(
                level: trust.level,
                status: trust.status,
                reason: trust.reason,
                receivedAt: trust.receivedAt,
                authorization: trust.authorization.map {
                    ProviderAuthorizationStatus(
                        protocolVersion: $0.protocolVersion,
                        appAttestAvailable: $0.appAttestAvailable,
                        path: $0.path,
                        expiresAt: $0.expiresAt,
                        mdmRemovalReady: $0.mdmRemovalReady,
                        reason: $0.reason,
                        sessionIDPresent: $0.sessionID?.isEmpty == false,
                        machineIDPresent: $0.machineID?.isEmpty == false
                    )
                }
            )},
            capacity: raw.capacity.map {
                MemoryCapacity(
                    totalMemoryGB: $0.totalMemoryGB,
                    gpuMemoryActiveGB: $0.gpuMemoryActiveGB,
                    gpuMemoryCacheGB: $0.gpuMemoryCacheGB
                )
            },
            slots: raw.slots.compactMap { slot in
                guard slot.loadError == nil else { return nil }
                return ModelSlot(
                    model: slot.model,
                    mtpEnabled: slot.mtpEnabled,
                    mtpActive: slot.mtpActive,
                    mtpReason: SafeTelemetryReason.mtp(slot.mtpInactiveReason),
                    kvBackend: slot.kvBackend ?? "",
                    requestedKVBackend: slot.requestedKVBackend,
                    kvFallbackReason: SafeTelemetryReason.kv(slot.kvFallbackReason)
                )
            },
            inferenceActive: raw.inferenceActive,
            startedAt: raw.startedAt,
            writtenAt: raw.writtenAt,
            pid: raw.pid,
            processIdentity: .init(
                pid: raw.processIdentity.pid,
                startTimeMicros: raw.processIdentity.startTimeMicros
            ),
            advertisedModels: raw.advertisedModels.map {
                Array($0.compactMap(SafeTelemetryReason.model).prefix(64))
            },
            coordinatorURL: raw.coordinatorURL,
            modelLoadFailures: ModelLoadFailureBuilder.make(
                topLevel: raw.lastModelLoadError,
                slotFailures: raw.slots.compactMap { slot in
                    guard let message = slot.loadError else { return nil }
                    return ModelLoadFailure(
                        model: slot.model,
                        code: SafeTelemetryReason.load(message),
                        occurredAt: nil
                    )
                }
            ),
            lifecycle: raw.lifecycle.map {
                ProviderLifecycleState(
                    outcome: ProviderLifecycleOutcome(rawValue: $0.outcome ?? ""),
                    remainingRequests: $0.remaining,
                    coordinatorAcknowledged: $0.coordinatorAcknowledged
                )
            },
            startupPreloadPendingModels: raw.startupPreloadPendingModels.map {
                Array($0.compactMap(SafeTelemetryReason.model).prefix(64))
            },
            modelSwitch: raw.modelSwitch.map {
                ProviderModelSwitchState(
                    outcome: ProviderModelSwitchOutcome(rawValue: $0.outcome ?? ""),
                    models: Array($0.models.compactMap(SafeTelemetryReason.model).prefix(64)),
                    remainingRequests: $0.remaining
                )
            },
            availability: raw.availability.map {
                ProviderAvailabilityState(
                    phase: ProviderAvailabilityPhase(rawValue: $0.phase ?? ""),
                    nextWindowAt: $0.nextWindowAt
                )
            },
            configPath: boundedPath(raw.configPath),
            runtimeCapabilities: raw.runtimeCapabilities.map {
                Array($0.compactMap(safeCapability).prefix(64))
            }
        )
    }

    private static func boundedPath(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.utf8.count <= 4_096 else { return nil }
        return value
    }

    private static func safeCapability(_ value: String) -> String? {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty, normalized.count <= 100 else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        return normalized.unicodeScalars.allSatisfy(allowed.contains) ? normalized : nil
    }
}

public enum LoadedModelsParser {
    public static func parse(_ data: Data) throws -> LoadedModelsState {
        try SchemaValidation.requireSchema1(data, source: "loaded-models.json")
        let raw = try JSONDecoder().decode(RawLoadedModels.self, from: data)
        return LoadedModelsState(schema: raw.schema, models: raw.models, updatedAt: raw.updatedAt)
    }
}

private struct SchemaEnvelope: Decodable {
    let schema: Int
}

private enum SchemaValidation {
    static func requireSchema1(_ data: Data, source: String) throws {
        let found = try JSONDecoder().decode(SchemaEnvelope.self, from: data).schema
        guard found == 1 else {
            throw TelemetryContractError.unsupportedSchema(
                source: source,
                found: found,
                supported: 1
            )
        }
    }
}

private struct RawDaemonState: Decodable {
    let schema: Int
    let stats: RawStats
    let version: String
    let currentModel: String?
    let trust: RawTrust?
    let warmModels: [String]
    let advertisedModels: [String]?
    let coordinatorURL: String?
    let pid: Int32
    let capacity: RawCapacity?
    let slots: [RawSlot]
    let inferenceActive: Bool
    let startedAt: TimeInterval
    let writtenAt: TimeInterval
    let processIdentity: RawProcessIdentity
    let lastModelLoadError: RawModelLoadError?
    let lifecycle: RawLifecycle?
    let startupPreloadPendingModels: [String]?
    let modelSwitch: RawModelSwitch?
    let availability: RawAvailability?
    let configPath: String?
    let runtimeCapabilities: [String]?

    enum CodingKeys: String, CodingKey {
        case schema, stats, version, trust, pid, capacity, slots
        case currentModel = "current_model"
        case warmModels = "warm_models"
        case advertisedModels = "advertised_models"
        case coordinatorURL = "coordinator_url"
        case lastModelLoadError = "last_model_load_error"
        case lifecycle
        case startupPreloadPendingModels = "startup_preload_pending_models"
        case modelSwitch = "model_switch"
        case availability
        case configPath = "config_path"
        case runtimeCapabilities = "runtime_capabilities"
        case inferenceActive = "inference_active"
        case startedAt = "started_at"
        case writtenAt = "written_at"
        case processIdentity = "process_identity"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(Int.self, forKey: .schema)
        stats = try values.decode(RawStats.self, forKey: .stats)
        version = try values.decode(String.self, forKey: .version)
        currentModel = try values.decodeIfPresent(String.self, forKey: .currentModel)
        trust = try values.decodeIfPresent(RawTrust.self, forKey: .trust)
        warmModels = try values.decodeIfPresent([String].self, forKey: .warmModels) ?? []
        advertisedModels = try values.decodeIfPresent([String].self, forKey: .advertisedModels)
        coordinatorURL = try values.decodeIfPresent(String.self, forKey: .coordinatorURL)
        pid = try values.decode(Int32.self, forKey: .pid)
        capacity = try values.decodeIfPresent(RawCapacity.self, forKey: .capacity)
        slots = try values.decodeIfPresent([RawSlot].self, forKey: .slots) ?? []
        inferenceActive = try values.decode(Bool.self, forKey: .inferenceActive)
        startedAt = try values.decode(TimeInterval.self, forKey: .startedAt)
        writtenAt = try values.decode(TimeInterval.self, forKey: .writtenAt)
        processIdentity = try values.decode(RawProcessIdentity.self, forKey: .processIdentity)
        lastModelLoadError = try values.decodeIfPresent(RawModelLoadError.self, forKey: .lastModelLoadError)
        lifecycle = try? values.decode(RawLifecycle.self, forKey: .lifecycle)
        startupPreloadPendingModels = try values.decodeIfPresent([String].self, forKey: .startupPreloadPendingModels)
        modelSwitch = try? values.decode(RawModelSwitch.self, forKey: .modelSwitch)
        availability = try? values.decode(RawAvailability.self, forKey: .availability)
        configPath = try values.decodeIfPresent(String.self, forKey: .configPath)
        runtimeCapabilities = try values.decodeIfPresent([String].self, forKey: .runtimeCapabilities)
    }
}

private struct RawModelSwitch: Decodable {
    let outcome: String?
    let models: [String]
    let remaining: Int?

    enum CodingKeys: String, CodingKey { case outcome, models, remaining }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try? values.decode(String.self, forKey: .outcome)
        models = (try? values.decode([String].self, forKey: .models)) ?? []
        remaining = try? values.decode(Int.self, forKey: .remaining)
    }
}

private struct RawAvailability: Decodable {
    let phase: String?
    let nextWindowAt: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case phase
        case nextWindowAt = "next_window_at"
    }
}

private struct RawLifecycle: Decodable {
    let outcome: String?
    let remaining: Int?
    let coordinatorAcknowledged: Bool?

    enum CodingKeys: String, CodingKey {
        case outcome, remaining
        case coordinatorAcknowledged = "coordinator_acknowledged"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outcome = try? values.decode(String.self, forKey: .outcome)
        remaining = try? values.decode(Int.self, forKey: .remaining)
        coordinatorAcknowledged = try? values.decode(Bool.self, forKey: .coordinatorAcknowledged)
    }
}

private struct RawStats: Decodable {
    let tokensGenerated: Int64
    let requestsServed: Int64
    let usageGaps: Int64

    enum CodingKeys: String, CodingKey {
        case tokensGenerated = "tokens_generated"
        case requestsServed = "requests_served"
        case usageGaps = "usage_gaps"
    }
}

private struct RawTrust: Decodable {
    let level: String
    let status: String
    let reason: String
    let receivedAt: TimeInterval
    let authorization: RawAuthorization?

    enum CodingKeys: String, CodingKey {
        case level = "trust_level"
        case status, reason, authorization
        case receivedAt = "received_at"
    }
}

private struct RawAuthorization: Decodable {
    let protocolVersion: Int
    let appAttestAvailable: Bool
    let path: String
    let expiresAt: TimeInterval?
    let mdmRemovalReady: Bool
    let reason: String?
    let sessionID: String?
    let machineID: String?

    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case protocolVersionAlternate = "protocol_version"
        case appAttestAvailable = "app_attest_available"
        case appAttestAvailableAlternate = "appAttestAvailable"
        case path, expiresAt = "expires_at", expiresAtAlternate = "expiresAt"
        case mdmRemovalReady = "mdm_removal_ready"
        case mdmRemovalReadyAlternate = "mdmRemovalReady"
        case reason
        case sessionID = "session_id"
        case sessionIDAlternate = "sessionID"
        case machineID = "machine_id"
        case machineIDAlternate = "machineID"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decodeIfPresent(Int.self, forKey: .protocolVersion)
            ?? values.decodeIfPresent(Int.self, forKey: .protocolVersionAlternate) ?? 0
        appAttestAvailable = try values.decodeIfPresent(Bool.self, forKey: .appAttestAvailable)
            ?? values.decodeIfPresent(Bool.self, forKey: .appAttestAvailableAlternate) ?? false
        path = try values.decodeIfPresent(String.self, forKey: .path) ?? ""
        expiresAt = try values.decodeIfPresent(TimeInterval.self, forKey: .expiresAt)
            ?? values.decodeIfPresent(TimeInterval.self, forKey: .expiresAtAlternate)
        mdmRemovalReady = try values.decodeIfPresent(Bool.self, forKey: .mdmRemovalReady)
            ?? values.decodeIfPresent(Bool.self, forKey: .mdmRemovalReadyAlternate) ?? false
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
        sessionID = try values.decodeIfPresent(String.self, forKey: .sessionID)
            ?? values.decodeIfPresent(String.self, forKey: .sessionIDAlternate)
        machineID = try values.decodeIfPresent(String.self, forKey: .machineID)
            ?? values.decodeIfPresent(String.self, forKey: .machineIDAlternate)
    }
}

private struct RawCapacity: Decodable {
    let totalMemoryGB: Double
    let gpuMemoryActiveGB: Double
    let gpuMemoryCacheGB: Double

    enum CodingKeys: String, CodingKey {
        case totalMemoryGB = "total_memory_gb"
        case gpuMemoryActiveGB = "gpu_memory_active_gb"
        case gpuMemoryCacheGB = "gpu_memory_cache_gb"
    }
}

private struct RawSlot: Decodable {
    let loadError: String?
    let model: String
    let mtpActive: Bool
    let kvBackend: String?
    let requestedKVBackend: String
    let mtpEnabled: Bool
    let mtpInactiveReason: String?
    let kvFallbackReason: String?

    enum CodingKeys: String, CodingKey {
        case loadError = "load_error"
        case model
        case mtpActive = "mtp_active"
        case kvBackend = "kv_backend"
        case requestedKVBackend = "kv_backend_requested"
        case mtpEnabled = "mtp_enabled"
        case mtpInactiveReason = "mtp_inactive_reason"
        case mtpReasonAlternate = "mtp_reason"
        case kvFallbackReason = "kv_backend_fallback_reason"
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        model = try values.decode(String.self, forKey: .model)
        loadError = try values.decodeIfPresent(String.self, forKey: .loadError)
        if loadError != nil {
            mtpActive = try values.decodeIfPresent(Bool.self, forKey: .mtpActive) ?? false
            mtpEnabled = try values.decodeIfPresent(Bool.self, forKey: .mtpEnabled) ?? false
            requestedKVBackend = try values.decodeIfPresent(String.self, forKey: .requestedKVBackend) ?? "auto"
            kvBackend = try values.decodeIfPresent(String.self, forKey: .kvBackend)
        } else {
            mtpActive = try values.decode(Bool.self, forKey: .mtpActive)
            mtpEnabled = try values.decode(Bool.self, forKey: .mtpEnabled)
            requestedKVBackend = try values.decode(String.self, forKey: .requestedKVBackend)
            kvBackend = try values.decode(String.self, forKey: .kvBackend)
        }
        mtpInactiveReason = try values.decodeIfPresent(String.self, forKey: .mtpInactiveReason)
            ?? values.decodeIfPresent(String.self, forKey: .mtpReasonAlternate)
        kvFallbackReason = try values.decodeIfPresent(String.self, forKey: .kvFallbackReason)
    }
}

private struct RawModelLoadError: Decodable {
    let model: String
    let message: String
    let at: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case model, message, at
    }
}

private struct RawProcessIdentity: Decodable {
    let pid: Int32
    let startTimeMicros: Int64

    enum CodingKeys: String, CodingKey {
        case pid
        case startTimeMicros = "start_time_micros"
    }
}

private struct RawLoadedModels: Decodable {
    let models: [String]
    let schema: Int
    let updatedAt: TimeInterval

    enum CodingKeys: String, CodingKey {
        case models, schema
        case updatedAt = "updated_at"
    }
}

private enum SafeTelemetryReason {
    private static let mtpCodes: Set<String> = [
        "config_disabled", "kill_switch_disabled", "target_unsupported",
        "local_artifact_invalid", "catalog_disabled", "catalog_unavailable",
        "catalog_model_missing", "metadata_missing", "metadata_malformed",
        "artifact_not_cached", "manifest_fetch_failed", "manifest_malformed",
        "manifest_digest_mismatch", "manifest_binding_mismatch", "artifact_oversize",
        "file_count_invalid", "file_type_disallowed", "path_invalid",
        "file_download_failed", "file_digest_mismatch", "warm_artifact_corrupt",
        "publication_failed", "assistant_load_failed", "assistant_target_incompatible",
        "assistant_memory_unavailable", "assistant_reslice_floor",
        "assistant_post_build_headroom", "engine_inactive", "inline_artifact_invalid",
        "inert_kv_unsupported"
    ]

    static func mtp(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return mtpCodes.contains(code) ? code : "unknown"
    }

    static func model(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 200,
              !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~"),
              !trimmed.contains("..") else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._/@:+-~"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    static func kv(_ value: String?) -> String? {
        guard let value else { return nil }
        let code = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !code.isEmpty else { return nil }
        let known = [
            "kill_switch", "crash_loop_guard", "kernel_preflight",
            "physical_capacity", "ineligible", "pool_construction_capacity",
            "invalid_dtype"
        ]
        if known.contains(code) { return code }
        if let prefix = known.first(where: { code.hasPrefix($0 + ":") }) { return prefix }
        return "unknown"
    }

    static func load(_ value: String) -> ModelLoadFailureCode {
        let text = value.lowercased()
        if ["memory", "out of memory", "capacity", "headroom", "oom"].contains(where: text.contains) {
            return .insufficientMemory
        }
        if ["not found", "missing", "not installed", "no model"].contains(where: text.contains) {
            return .modelUnavailable
        }
        if ["unsupported", "ineligible", "not eligible"].contains(where: text.contains) {
            return .unsupported
        }
        if ["integrity", "hash", "digest", "corrupt"].contains(where: text.contains) {
            return .integrityFailure
        }
        if ["timeout", "timed out"].contains(where: text.contains) {
            return .timedOut
        }
        if ["backend", "engine", "mlx", "kv"].contains(where: text.contains) {
            return .backendUnavailable
        }
        return .unknown
    }
}

private enum ModelLoadFailureBuilder {
    static func make(
        topLevel: RawModelLoadError?,
        slotFailures: [ModelLoadFailure]
    ) -> [ModelLoadFailure] {
        var result: [ModelLoadFailure] = []
        if let topLevel {
            result.append(ModelLoadFailure(
                model: topLevel.model,
                code: SafeTelemetryReason.load(topLevel.message),
                occurredAt: topLevel.at
            ))
        }
        for failure in slotFailures {
            guard result.count < 64 else { break }
            guard !result.contains(where: { $0.model == failure.model && $0.code == failure.code }) else {
                continue
            }
            result.append(failure)
        }
        return result
    }
}
