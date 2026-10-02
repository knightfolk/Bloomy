import Foundation

public enum ProviderAutopilotPolicyAction: String, Equatable, Sendable {
    case pause, resume, disable
}

public enum ProviderAutopilotPhase: String, Equatable, Sendable, CaseIterable {
    case off, waiting, waitingInventory = "waiting_inventory", shadow, active, paused, transitioning, recovering
}

/// Deliberately excludes session IDs, command IDs, hashes and free-form reasons.
public struct ProviderAutopilotLiveStatus: Equatable, Sendable {
    public let protocolVersion: Int
    public let enabled: Bool
    public let active: Bool
    public let observeOnly: Bool
    public let paused: Bool
    public let cachedOnly: Bool
    private let revision: String

    public init(protocolVersion: Int, enabled: Bool, active: Bool, observeOnly: Bool,
                paused: Bool, cachedOnly: Bool, revision: String) {
        self.protocolVersion = protocolVersion; self.enabled = enabled; self.active = active
        self.observeOnly = observeOnly; self.paused = paused; self.cachedOnly = cachedOnly
        self.revision = revision
    }

    fileprivate func matches(revision: String) -> Bool { self.revision == revision }
}

public struct ProviderAutopilotStatus: Equatable, Sendable {
    public let configuredEnabled: Bool
    public let consentRecorded: Bool
    public let configuredPaused: Bool
    public let selectedModels: [String]
    public let pinnedModels: [String]
    public let live: ProviderAutopilotLiveStatus?
    public let phase: ProviderAutopilotPhase?
    private let configuredRevision: String

    public init(configuredEnabled: Bool, consentRecorded: Bool, configuredPaused: Bool,
                selectedModels: [String], pinnedModels: [String], configuredRevision: String,
                live: ProviderAutopilotLiveStatus? = nil, phase: ProviderAutopilotPhase? = nil) {
        self.configuredEnabled = configuredEnabled; self.consentRecorded = consentRecorded
        self.configuredPaused = configuredPaused; self.selectedModels = selectedModels
        self.pinnedModels = pinnedModels; self.configuredRevision = configuredRevision
        self.live = live; self.phase = phase
    }

    public func withoutLiveEvidence() -> Self {
        Self(configuredEnabled: configuredEnabled, consentRecorded: consentRecorded,
             configuredPaused: configuredPaused, selectedModels: selectedModels, pinnedModels: pinnedModels,
             configuredRevision: configuredRevision)
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
                    paused: live.paused, cachedOnly: live.cached_only, revision: live.revision)
            }
            return ProviderAutopilotStatus(configuredEnabled: configured.enabled,
                consentRecorded: configured.consent_recorded, configuredPaused: configured.paused,
                selectedModels: configured.selected_models, pinnedModels: configured.pinned_models,
                configuredRevision: configured.revision, live: live,
                phase: payload.phase.flatMap(ProviderAutopilotPhase.init(rawValue:)))
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
    enum CodingKeys: String, CodingKey {
        case protocolVersion = "protocol"
        case enabled, active, observe_only, paused, cached_only, revision
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
