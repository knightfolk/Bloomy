import Foundation

public enum ProviderAutopilotPolicyAction: String, Equatable, Sendable {
    case pause, resume, disable
}

public enum ProviderAutopilotPhase: String, Equatable, Sendable, CaseIterable {
    case off, waiting, waitingInventory = "waiting_inventory", shadow, active, paused, transitioning, recovering
}

/// Fixed, privacy-safe categories for the provider's live busy reasons.
public enum ProviderAutopilotBusyReason: Equatable, Sendable {
    case addOnHold, acceptedWork, modelChange, providerTransition, other

    static func map(_ value: String) -> Self {
        switch value {
        case "addon_hold": .addOnHold
        case "inflight_work": .acceptedWork
        case "startup_preload", "preload", "model_loading", "model_unloading", "model_retiring", "model_switch", "mtp_upgrade", "mtp_staging", "reslice", "load_gate": .modelChange
        case "autopilot_operation", "shutting_down", "draining", "reconnect_after_retirement", "revision_activation", "revision_update", "engine_recovery", "model_advertisement", "pending_advertisement", "native_memory_retained": .providerTransition
        default: .other
        }
    }
    public var explanation: String {
        switch self {
        case .addOnHold: "An add-on is holding the provider."
        case .acceptedWork: "Accepted work is in progress."
        case .modelChange: "The provider is loading or changing models."
        case .providerTransition: "The provider is completing another operation."
        case .other: "The provider reports another busy condition."
        }
    }
}

/// Deliberately excludes session IDs, command IDs, hashes and free-form reasons.
public struct ProviderAutopilotLiveStatus: Equatable, Sendable {
    public let protocolVersion: Int
    public let enabled: Bool
    public let active: Bool
    public let observeOnly: Bool
    public let paused: Bool
    public let cachedOnly: Bool
    public let busyReasons: [ProviderAutopilotBusyReason]
    private let revision: String

    public init(protocolVersion: Int, enabled: Bool, active: Bool, observeOnly: Bool,
                paused: Bool, cachedOnly: Bool, revision: String,
                busyReasons: [ProviderAutopilotBusyReason] = []) {
        self.protocolVersion = protocolVersion; self.enabled = enabled; self.active = active
        self.observeOnly = observeOnly; self.paused = paused; self.cachedOnly = cachedOnly
        self.revision = revision; self.busyReasons = busyReasons
    }

    fileprivate func matches(revision: String) -> Bool { self.revision == revision }
}

public struct AutopilotDownloadPolicy: Equatable, Sendable {
    public let enabled: Bool
    public let maxStorageGB: UInt64?
    public let maxModels: UInt64?
    public let reserveGB: UInt64?
    public init(enabled: Bool, maxStorageGB: UInt64? = nil, maxModels: UInt64? = nil, reserveGB: UInt64? = nil) {
        self.enabled = enabled; self.maxStorageGB = maxStorageGB
        self.maxModels = maxModels; self.reserveGB = reserveGB
    }
}

public struct AutopilotDownloadUsage: Equatable, Sendable {
    public let usedBytes: UInt64
    public let usedModels: UInt64
}

public struct ProviderAutopilotStatus: Equatable, Sendable {
    public let configuredEnabled: Bool
    public let consentRecorded: Bool
    public let configuredPaused: Bool
    public let selectedModels: [String]
    public let pinnedModels: [String]
    public let live: ProviderAutopilotLiveStatus?
    public let phase: ProviderAutopilotPhase?
    /// Nil means this provider did not report a usable download policy.
    public let downloads: AutopilotDownloadPolicy?
    public let downloadUsage: AutopilotDownloadUsage?
    public var downloadsEnabled: Bool? { downloads?.enabled }
    private let configuredRevision: String

    public init(configuredEnabled: Bool, consentRecorded: Bool, configuredPaused: Bool,
                selectedModels: [String], pinnedModels: [String], configuredRevision: String,
                live: ProviderAutopilotLiveStatus? = nil, phase: ProviderAutopilotPhase? = nil,
                downloadsEnabled: Bool? = nil, downloads: AutopilotDownloadPolicy? = nil,
                downloadUsage: AutopilotDownloadUsage? = nil) {
        self.configuredEnabled = configuredEnabled; self.consentRecorded = consentRecorded
        self.configuredPaused = configuredPaused; self.selectedModels = selectedModels
        self.pinnedModels = pinnedModels; self.configuredRevision = configuredRevision
        self.live = live; self.phase = phase
        self.downloads = downloads ?? downloadsEnabled.map { AutopilotDownloadPolicy(enabled: $0) }
        self.downloadUsage = downloadUsage
    }

    public func withoutLiveEvidence() -> Self {
        Self(configuredEnabled: configuredEnabled, consentRecorded: consentRecorded,
             configuredPaused: configuredPaused, selectedModels: selectedModels, pinnedModels: pinnedModels,
             configuredRevision: configuredRevision, downloads: downloads, downloadUsage: downloadUsage)
    }

    /// Download settings are independent of consent and its revision.
    public func hasSameEnrollment(as other: Self) -> Bool {
        configuredEnabled == other.configuredEnabled && consentRecorded == other.consentRecorded
            && configuredPaused == other.configuredPaused && configuredRevision == other.configuredRevision
            && selectedModels == other.selectedModels && pinnedModels == other.pinnedModels
    }

    public var isEnrolled: Bool {
        configuredEnabled && consentRecorded && !configuredRevision.isEmpty && !selectedModels.isEmpty
    }
    public var liveMatchesConfiguredRevision: Bool {
        !configuredRevision.isEmpty && live?.matches(revision: configuredRevision) == true
    }
    public var isLiveConfirmed: Bool {
        isEnrolled && liveMatchesConfiguredRevision && live?.protocolVersion == 3 && live?.enabled == true && live?.cachedOnly == true
    }
    public var isActivelyManaging: Bool {
        isLiveConfirmed && !configuredPaused && live?.active == true && live?.observeOnly == false && live?.paused == false
    }
    public func allows(_ action: ProviderAutopilotPolicyAction) -> Bool {
        switch action {
        case .pause: isEnrolled && !configuredPaused
        case .resume: isEnrolled && configuredPaused
        case .disable: configuredEnabled
        }
    }
    public func confirms(_ action: ProviderAutopilotPolicyAction) -> Bool {
        switch action {
        case .pause: isEnrolled && configuredPaused
        case .resume: isEnrolled && !configuredPaused
        case .disable: !configuredEnabled
        }
    }
}

public extension ProviderExtrasParser {
    static func parseAutopilot(_ data: Data) throws -> ProviderAutopilotStatus {
        guard data.count <= 256 * 1_024 else { throw ProviderExtrasParseError.invalidPayload }
        do {
            let payload = try JSONDecoder().decode(AutopilotPayload.self, from: data)
            let configured = payload.configured
            guard boundedRevision(configured.revision), validModels(configured.selected_models),
                  validModels(configured.pinned_models),
                  !(configured.enabled && configured.consent_recorded && (configured.revision.isEmpty || configured.selected_models.isEmpty)) else { throw ProviderExtrasParseError.invalidValue }
            let live = try payload.live.map { live in
                guard live.protocolVersion == 3, boundedRevision(live.revision) else {
                    throw ProviderExtrasParseError.unsupportedValue
                }
                return ProviderAutopilotLiveStatus(protocolVersion: live.protocolVersion,
                    enabled: live.enabled, active: live.active, observeOnly: live.observe_only,
                    paused: live.paused, cachedOnly: live.cached_only, revision: live.revision,
                    busyReasons: live.safeBusyReasons)
            }
            return ProviderAutopilotStatus(configuredEnabled: configured.enabled,
                consentRecorded: configured.consent_recorded, configuredPaused: configured.paused,
                selectedModels: configured.selected_models, pinnedModels: configured.pinned_models,
                configuredRevision: configured.revision, live: live,
                phase: payload.phase.flatMap(ProviderAutopilotPhase.init(rawValue:)),
                downloads: payload.downloads.map { AutopilotDownloadPolicy(enabled: $0.enabled, maxStorageGB: $0.max_storage_gb, maxModels: $0.max_models, reserveGB: $0.reserve_gb) },
                downloadUsage: payload.download_usage.map { AutopilotDownloadUsage(usedBytes: $0.used_bytes, usedModels: $0.used_models) })
        } catch let error as ProviderExtrasParseError { throw error }
        catch { throw ProviderExtrasParseError.invalidPayload }
    }

    private static func boundedRevision(_ value: String) -> Bool {
        value.utf8.count <= 256 && value.unicodeScalars.allSatisfy { $0.value >= 32 && $0.value != 127 }
    }
    private static func validModels(_ values: [String]) -> Bool {
        values.count <= 256 && Set(values).count == values.count && values.allSatisfy {
            !$0.isEmpty && $0.utf8.count <= 256 && $0.unicodeScalars.allSatisfy {
                (48...57).contains($0.value) || (65...90).contains($0.value) || (97...122).contains($0.value)
                    || [45, 46, 47, 95].contains($0.value)
            }
        }
    }
}

private struct AutopilotPayload: Decodable {
    let configured: AutopilotConfiguredPayload
    let live: AutopilotLivePayload?
    let phase: String?
    let downloads: AutopilotDownloadsPayload?
    let download_usage: AutopilotDownloadUsagePayload?
}
private struct AutopilotDownloadsPayload: Decodable {
    let enabled: Bool
    let max_storage_gb: UInt64?
    let max_models: UInt64?
    let reserve_gb: UInt64?
}
private struct AutopilotDownloadUsagePayload: Decodable {
    let used_bytes: UInt64
    let used_models: UInt64
}
private struct AutopilotConfiguredPayload: Decodable {
    let enabled: Bool
    let consent_recorded: Bool
    let paused: Bool
    let selected_models: [String]
    let pinned_models: [String]
    let revision: String
}
private struct AutopilotLivePayload: Decodable {
    let protocolVersion: Int
    let enabled: Bool
    let active: Bool
    let observe_only: Bool
    let paused: Bool
    let cached_only: Bool
    let revision: String
    let safeBusyReasons: [ProviderAutopilotBusyReason]
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case enabled, active, observe_only, paused, cached_only, revision, busy_reasons, busy_reason
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        protocolVersion = try values.decode(Int.self, forKey: .protocolVersion)
        enabled = try values.decode(Bool.self, forKey: .enabled)
        active = try values.decode(Bool.self, forKey: .active)
        observe_only = try values.decode(Bool.self, forKey: .observe_only)
        paused = try values.decode(Bool.self, forKey: .paused)
        cached_only = try values.decode(Bool.self, forKey: .cached_only)
        revision = try values.decode(String.self, forKey: .revision)
        if values.contains(.busy_reasons), (try? values.decodeNil(forKey: .busy_reasons)) != true {
            if let raw = try? values.decode([String].self, forKey: .busy_reasons), raw.count <= 32 {
                safeBusyReasons = raw.map(ProviderAutopilotBusyReason.map).reduce(into: []) { result, item in
                    if !result.contains(item) { result.append(item) }
                }
            } else { safeBusyReasons = [.other] }
        } else if values.contains(.busy_reason), (try? values.decodeNil(forKey: .busy_reason)) != true {
            safeBusyReasons = [(try? values.decode(String.self, forKey: .busy_reason)).map(ProviderAutopilotBusyReason.map) ?? .other]
        } else { safeBusyReasons = [] }
    }
}

public struct ProviderAutopilotEnrollmentCompletion: Equatable, Sendable {
    public let controls: ProviderMutationCompletion
    public let status: SourceAvailability<ProviderAutopilotStatus>
    public let commandSucceeded: Bool
    public let savedPolicyPreserved: Bool
    public var savedEnrollmentConfirmed: Bool {
        guard savedPolicyPreserved, case .available(let status, let capturedAt) = status else { return false }
        let age = Date().timeIntervalSince(capturedAt)
        return age.isFinite && age >= 0 && age <= ProviderExtrasSnapshot.maximumSourceAge && status.isEnrolled
    }
    public var liveEnrollmentConfirmed: Bool {
        savedEnrollmentConfirmed && status.value?.isLiveConfirmed == true
    }
    public init(controls: ProviderMutationCompletion, status: SourceAvailability<ProviderAutopilotStatus>,
                commandSucceeded: Bool, savedPolicyPreserved: Bool) {
        self.controls = controls; self.status = status
        self.commandSucceeded = commandSucceeded; self.savedPolicyPreserved = savedPolicyPreserved
    }
}

/// Mirrors upstream's model-specific embedded requirements; unknown nonempty
/// capabilities must be established by current runtime evidence.
enum ProviderAutopilotModelPreflight {
    static func isEligible(_ model: CatalogModel, runtimeCapabilities: [String]?) -> Bool {
        var required = Set(model.requiredProviderCapabilities ?? [])
        if ["EigenLabs/Qwen3.8-27B-4bit", "EigenLabs/Qwen3.8-27B-4bit-mtp"].contains(model.id) {
            required.formUnion(["apple_m5", "mlx_nax"])
        }
        return model.active && (required.isEmpty || required.isSubset(of: Set(runtimeCapabilities ?? [])))
    }
}
