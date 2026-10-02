import DarkbloomTelemetry
import SwiftUI

struct ProviderThermalPresentation: Equatable {
    enum Freshness: Equatable {
        case current, stale, invalid, unavailable

        var readingQualifier: String? {
            switch self {
            case .current, .unavailable: nil
            case .stale: "Last observed"
            case .invalid: "Unverified"
            }
        }

        static func make(capturedAt: Date, maximumAge: TimeInterval, at now: Date) -> Self {
            let age = now.timeIntervalSince(capturedAt)
            guard age.isFinite, age >= 0 else { return .invalid }
            return age <= maximumAge ? .current : .stale
        }
    }

    enum HelperPosture: Equatable {
        case active, waiting, disabled, notLoaded, unavailable, unverified
        case lastActive, lastWaiting, lastDisabled, lastNotLoaded

        var message: String {
            switch self {
            case .active: "Fan helper is active while the provider is serving."
            case .waiting: "Fan helper is waiting for provider activity."
            case .disabled: "Fan helper is disabled."
            case .notLoaded: "Darkbloom fan helper is not loaded."
            case .unavailable: "Darkbloom fan helper status is unavailable."
            case .unverified: "Fan helper activity is unverified."
            case .lastActive: "Last observed: fan helper was active while the provider was serving."
            case .lastWaiting: "Last observed: fan helper was waiting for provider activity."
            case .lastDisabled: "Last observed: fan helper was disabled."
            case .lastNotLoaded: "Last observed: fan helper was not loaded."
            }
        }
    }

    struct FanReading: Equatable, Identifiable {
        let reading: ProviderFanReading
        let actualRPM: Double
        let freshness: Freshness
        var id: Int { reading.index }
        var index: Int { reading.index }
    }

    let status: ProviderFanStatus
    let cliFreshness: Freshness
    let helperFreshness: Freshness
    let displayedTemperatureCelsius: Double?
    let displayedFans: [FanReading]
    let temperatureFreshness: Freshness
    let readingsAreStale: Bool
    let helperPosture: HelperPosture

    var hasReadings: Bool { displayedTemperatureCelsius != nil || !displayedFans.isEmpty }

    var fanFreshness: Freshness {
        if displayedFans.contains(where: { $0.freshness == .invalid }) { return .invalid }
        if displayedFans.contains(where: { $0.freshness == .stale }) { return .stale }
        return displayedFans.isEmpty ? .unavailable : .current
    }

    static func make(from source: SourceAvailability<ProviderFanStatus>?, at now: Date) -> Self? {
        let status: ProviderFanStatus
        let cliFreshness: Freshness
        switch source {
        case .available(let value, let capturedAt):
            status = value
            cliFreshness = Freshness.make(capturedAt: capturedAt, maximumAge: ProviderExtrasSnapshot.maximumSourceAge, at: now)
        case .stale(let value, let capturedAt, _):
            status = value
            let timestamp = Freshness.make(capturedAt: capturedAt, maximumAge: ProviderExtrasSnapshot.maximumSourceAge, at: now)
            cliFreshness = timestamp == .invalid ? .invalid : .stale
        case .unavailable, nil:
            return nil
        }
        let helperFreshness = status.helper.map {
            Freshness.make(capturedAt: $0.updatedAt, maximumAge: ProviderFanStatus.maximumHelperAge, at: now)
        } ?? .unavailable
        let helperIsCurrent = helperFreshness == .current && !status.helperErrorPresent && status.loaded
        let diagnosticIsCurrent = cliFreshness == .current && !status.diagnosticErrorPresent
        let temperature: Double?
        let temperatureFreshness: Freshness
        // Select each reading independently. A current diagnostic temperature
        // must not erase a last-known RPM, or vice versa.
        if helperIsCurrent, let value = status.helper?.gpuTemperatureCelsius {
            temperature = value
            temperatureFreshness = cliFreshness
        } else if diagnosticIsCurrent, let value = status.diagnostic.gpuTemperatures.first?.celsius {
            temperature = value
            temperatureFreshness = .current
        } else {
            temperature = status.displayedTemperatureCelsius
            temperatureFreshness = temperature == nil ? .unavailable
                : cliFreshness == .invalid || (status.helper?.gpuTemperatureCelsius != nil && helperFreshness == .invalid) ? .invalid : .stale
        }
        let helperFans = status.helper?.fans ?? []
        let diagnosticFans = status.diagnostic.fans
        let fanIndices = Set(helperFans.map(\.index) + diagnosticFans.map(\.index)).sorted()
        let fans: [FanReading] = fanIndices.compactMap { index in
            let helper = helperFans.first { $0.index == index && usableRPM($0.actualRPM) }
            let diagnostic = diagnosticFans.first { $0.index == index && usableRPM($0.actualRPM) }
            let reading: ProviderFanReading
            let freshness: Freshness
            if helperIsCurrent, let helper {
                reading = helper
                freshness = cliFreshness
            } else if diagnosticIsCurrent, let diagnostic {
                reading = diagnostic
                freshness = .current
            } else if let helper {
                reading = helper
                freshness = cliFreshness == .invalid || helperFreshness == .invalid ? .invalid : .stale
            } else if let diagnostic {
                reading = diagnostic
                freshness = cliFreshness == .invalid ? .invalid : .stale
            } else {
                return nil
            }
            guard let rpm = reading.actualRPM else { return nil }
            return FanReading(reading: reading, actualRPM: rpm, freshness: freshness)
        }
        let readingsAreStale = cliFreshness != .current
            || (temperature != nil && temperatureFreshness != .current)
            || fans.contains(where: { $0.freshness != .current })
        let posture: HelperPosture
        if cliFreshness == .invalid {
            posture = .unverified
        } else if !status.loaded {
            posture = cliFreshness == .current ? .notLoaded : .lastNotLoaded
        } else if status.helperErrorPresent || status.helper == nil {
            posture = cliFreshness == .current ? .unavailable : .unverified
        } else if helperFreshness == .invalid {
            posture = .unverified
        } else if let helper = status.helper {
            let current = cliFreshness == .current && helperIsCurrent
            if !helper.enabled { posture = current ? .disabled : .lastDisabled }
            else if helper.providerActive { posture = current ? .active : .lastActive }
            else { posture = current ? .waiting : .lastWaiting }
        } else {
            posture = .unverified
        }
        return Self(status: status, cliFreshness: cliFreshness, helperFreshness: helperFreshness,
                    displayedTemperatureCelsius: temperature, displayedFans: fans,
                    temperatureFreshness: temperatureFreshness,
                    readingsAreStale: readingsAreStale, helperPosture: posture)
    }

    private static func usableRPM(_ value: Double?) -> Bool {
        guard let value else { return false }
        return value.isFinite && (0...100_000).contains(value)
    }
}

/// Compact read-only temperature and fan readings from the official CLI.
struct ProviderThermalView: View {
    @ObservedObject var store: ProviderExtrasStore
    var isVisible = true

    var body: some View {
        TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 5), isVisible: isVisible)) { _ in
            let now = Date()
            Group {
                if let presentation = ProviderThermalPresentation.make(from: store.snapshot?.fanStatus, at: now) {
                    content(presentation)
                } else {
                    Label("Fan telemetry unavailable", systemImage: "thermometer.medium")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func content(_ presentation: ProviderThermalPresentation) -> some View {
        let status = presentation.status
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Label("Thermals", systemImage: "thermometer.medium")
                    .font(.headline)
                if presentation.readingsAreStale {
                    Text("Stale")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                } else if status.diagnostic.supported && presentation.hasReadings {
                    Text("Live")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 14) {
                if let temperature = presentation.displayedTemperatureCelsius {
                    Self.readingLabel(Self.temperature(temperature), systemImage: "flame",
                        accessibilityName: "Temperature", freshness: presentation.temperatureFreshness)
                }
                ForEach(presentation.displayedFans) { fan in
                    Self.readingLabel("Fan \(fan.index + 1) \(Self.rpm(fan.actualRPM))", systemImage: "wind",
                        freshness: fan.freshness)
                }
                if !presentation.hasReadings {
                    Text(status.diagnostic.supported ? "Waiting for sensor readings" : "Unsupported hardware")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            Text(presentation.helperPosture.message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 10))
    }

    private static func temperature(_ value: Double) -> String {
        String(format: "%.1f °C", value)
    }

    private static func rpm(_ value: Double) -> String {
        String(format: "%.0f RPM", value)
    }

    static func readingLabel(_ value: String, systemImage: String, accessibilityName: String = "",
                             freshness: ProviderThermalPresentation.Freshness) -> some View {
        let qualifier = freshness.readingQualifier
        return VStack(alignment: .leading, spacing: 2) {
            Label(value, systemImage: systemImage)
                .monospacedDigit()
                .fixedSize(horizontal: true, vertical: false)
            if let qualifier {
                Text(qualifier).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(accessibilityName.isEmpty ? "" : accessibilityName + " ")\(value)\(qualifier.map { ". \($0) reading." } ?? "")")
    }

}

/// Nonsecret edit buffers for one settings surface. The dashboard retains this
/// object across destination changes; standalone settings and popup controls
/// own independent instances. No tasks, credentials, or saved preferences live here.
@MainActor
final class ProviderSettingsDraftState: ObservableObject {
    @Published private(set) var idleMinutesText = ""
    @Published private(set) var idleDirty = false
    @Published private(set) var fanSpeedPercent = ProviderFanPolicy.default.speedPercent
    @Published private(set) var fanTriggerTemperature = ProviderFanPolicy.default.triggerTemperatureCelsius
    @Published private(set) var fanDirty = false
    @Published private(set) var fanPreset: FanPreset?
    private(set) var idleRevision: UInt64 = 0
    private(set) var fanRevision: UInt64 = 0

    var hasChanges: Bool { idleDirty || fanDirty }

    func editIdle(_ text: String) {
        idleMinutesText = text
        idleDirty = true
        idleRevision &+= 1
    }

    func syncIdle(from source: SourceAvailability<ProviderIdlePolicy>?) {
        guard !idleDirty, case .available(let policy, _) = source else { return }
        idleMinutesText = String(policy.idleTimeoutMinutes)
    }

    /// Discard resets only this edit buffer and invalidates submitted saves.
    /// Last known evidence is useful for a local reset even when it is stale.
    func discardIdle(from source: SourceAvailability<ProviderIdlePolicy>?) {
        idleRevision &+= 1
        idleDirty = false
        idleMinutesText = source?.value.map { String($0.idleTimeoutMinutes) } ?? ""
    }

    func didSaveIdle(revision: UInt64, source: SourceAvailability<ProviderIdlePolicy>?) {
        guard idleRevision == revision else { return }
        idleDirty = false
        syncIdle(from: source)
    }

    func editFanSpeed(_ value: Double) {
        fanSpeedPercent = value
        fanDirty = true
        fanPreset = nil
        fanRevision &+= 1
    }

    func editFanTemperature(_ value: Double) {
        fanTriggerTemperature = value
        fanDirty = true
        fanPreset = nil
        fanRevision &+= 1
    }

    func selectFanPreset(_ preset: FanPreset) {
        fanSpeedPercent = preset.policy.speedPercent
        fanTriggerTemperature = preset.policy.triggerTemperatureCelsius
        fanPreset = preset
        fanDirty = true
        fanRevision &+= 1
    }

    var fanPolicy: ProviderFanPolicy? {
        ProviderFanPolicy(speedPercent: fanSpeedPercent, triggerTemperatureCelsius: fanTriggerTemperature)
    }

    func syncFan(from source: SourceAvailability<ProviderFanStatus>?) {
        guard !fanDirty else { return }
        let helper = source?.value?.helper
        let policy = helper.flatMap {
            ProviderFanPolicy(speedPercent: $0.speedPercent, triggerTemperatureCelsius: $0.triggerTemperatureCelsius)
        } ?? .default
        fanSpeedPercent = policy.speedPercent
        fanTriggerTemperature = policy.triggerTemperatureCelsius
        fanPreset = FanPreset.allCases.first { $0.policy == policy }
    }

    func discardFan(from source: SourceAvailability<ProviderFanStatus>?) {
        fanRevision &+= 1
        fanDirty = false
        syncFan(from: source)
    }

    func didSaveFan(revision: UInt64, source: SourceAvailability<ProviderFanStatus>?) {
        guard fanRevision == revision else { return }
        fanDirty = false
        syncFan(from: source)
    }
}

/// Settings sections for CLI idle-memory, beta, update, and fan controls.
/// Writes are always routed through the parent-provided serial mutation gate.
struct ProviderAdvancedSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    let performMutation: ProviderExtrasMutationExecutor
    let showsAutoUpdate: Bool
    let showsFanControls: Bool

    @StateObject private var draft: ProviderSettingsDraftState
    @State private var idleSaveInFlight = false
    @State private var betaSaveIDs: Set<String> = []
    @State private var feedback: String?

    init(
        store: ProviderExtrasStore,
        performMutation: @escaping ProviderExtrasMutationExecutor,
        showsAutoUpdate: Bool = true,
        showsFanControls: Bool = true,
        draft: ProviderSettingsDraftState? = nil
    ) {
        self.store = store
        self.performMutation = performMutation
        self.showsAutoUpdate = showsAutoUpdate
        self.showsFanControls = showsFanControls
        _draft = StateObject(wrappedValue: draft ?? ProviderSettingsDraftState())
    }

    var body: some View {
        Group {
            Section("Provider · Memory when idle") {
                idleSection
                if draft.idleDirty {
                    Button("Discard idle edit") {
                        draft.discardIdle(from: store.snapshot?.idlePolicy)
                        feedback = nil
                    }
                    .accessibilityIdentifier("settings.provider.idle.discard")
                    .help("Reset this unsaved edit to the latest observed policy")
                }
            }
            Section("Provider · Experimental features") {
                betaSection
            }
            if showsAutoUpdate {
                ProviderAutoUpdateSettingsView(store: store, performMutation: performMutation)
            }
            if showsFanControls {
                ProviderFanControlSettingsView(store: store, performMutation: performMutation, draft: draft)
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { syncIdleDraft() }
        .onChange(of: store.snapshot?.idlePolicy) { _, _ in
            // Refreshes are read-only, and must not overwrite a value the user
            // is currently editing in the idle field.
            syncIdleDraft()
        }
    }

    @ViewBuilder
    private var idleSection: some View {
        switch store.snapshot?.idlePolicy {
        case .available(let policy, _), .stale(let policy, _, _):
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Saved idle policy").font(.headline)
                    Spacer()
                    SettingsStateBadge(policy.idleTimeoutMinutes == 0
                        ? "No idle timeout" : "After \(policy.idleTimeoutMinutes) min")
                }
                Text("Controls timed unloading only. Models can still unload to make room for other work.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("Unload after")
                    TextField("Minutes", text: idleTextBinding)
                        .labelsHidden()
                        .accessibilityLabel("Idle minutes")
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .monospacedDigit()
                    Text("minutes").foregroundStyle(.secondary)
                    Button(idleSaveInFlight ? "Saving…" : "Save") { saveIdle() }
                        .disabled(!canSaveIdle)
                }
                Text(draft.idleDirty ? "Unsaved change · Enter 0 to disable timed unloading, or 1–10,080 minutes." : "Enter 0 to disable timed unloading, or 1–10,080 minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Saved configuration · Applies on restart. The running value is not reported by the CLI.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                if case .stale = store.snapshot?.idlePolicy {
                    Text("Refresh before saving this setting.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        case .unavailable, nil:
            Text("Unable to read the saved idle policy. Refresh to try again.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var betaSection: some View {
        switch store.snapshot?.betaFeatures {
        case .available(let features, _), .stale(let features, _, _):
            Text("Saved choices, not proof a feature is active. Automatic depends on the model and runtime support.")
                .font(.callout).foregroundStyle(.secondary)
            if features.isEmpty {
                Text("No configurable beta features are available in this build.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(features) { feature in
                    betaRow(feature)
                }
                if case .stale = store.snapshot?.betaFeatures {
                    Text("Refresh before changing beta settings.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        case .unavailable, nil:
            Text("Unable to read experimental feature settings. Refresh to try again.")
                .foregroundStyle(.secondary)
        }
    }

    private func betaRow(_ feature: ProviderBetaFeature) -> some View {
        let saving = betaSaveIDs.contains(feature.id)
        let sourceIsFresh = isFresh(store.snapshot?.betaFeatures)
        let canChange = sourceIsFresh
            && ProviderExtrasClient.allowedBetaFeatureIDs.contains(feature.id)
        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(feature.title).font(.body.weight(.medium))
                DisclosureGroup("What this does") {
                    Text(feature.summary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if feature.requiresRestart {
                    Text("Changes apply on restart")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 8) {
                SettingsStateBadge(saving ? "Saving…" : feature.stateLabel)
                if !sourceIsFresh {
                    Text("Last known value").font(.caption).foregroundStyle(.orange)
                }
                if canChange {
                    Menu("Change…") {
                        Button("Enable") { setBeta(feature, enabled: true) }
                            .disabled(feature.state == .on)
                        Button("Disable") { setBeta(feature, enabled: false) }
                            .disabled(feature.state == .off)
                    }
                    .disabled(store.mutationInFlight || saving)
                    .accessibilityLabel("Change \(feature.title), saved \(feature.stateLabel)")
                } else {
                    Text(sourceIsFresh ? "Read-only" : "Needs refresh")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var canSaveIdle: Bool {
        guard !idleSaveInFlight,
              !store.mutationInFlight,
              draft.idleDirty,
              let minutes = Int(draft.idleMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ProviderIdlePolicy.isValid(minutes: minutes),
              isFresh(store.snapshot?.idlePolicy)
        else { return false }
        guard case .available = store.snapshot?.idlePolicy else { return false }
        return true
    }

    private func syncIdleDraft() {
        draft.syncIdle(from: store.snapshot?.idlePolicy)
    }

    private var idleTextBinding: Binding<String> {
        Binding(get: { draft.idleMinutesText }, set: { draft.editIdle($0) })
    }

    private func isFresh<Value>(
        _ source: SourceAvailability<Value>?,
        now: Date = Date()
    ) -> Bool where Value: Equatable & Sendable {
        guard case .available(_, let capturedAt) = source else { return false }
        let age = now.timeIntervalSince(capturedAt)
        return age.isFinite && age >= 0 && age <= ProviderExtrasSnapshot.maximumSourceAge
    }

    private func saveIdle() {
        guard canSaveIdle else { feedback = "Refresh before saving this setting."; return }
        guard let minutes = Int(draft.idleMinutesText.trimmingCharacters(in: .whitespacesAndNewlines)),
              ProviderIdlePolicy.isValid(minutes: minutes)
        else {
            feedback = "Choose 0–10,080 minutes."
            return
        }
        let revision = draft.idleRevision
        idleSaveInFlight = true
        Task { @MainActor in
            let succeeded = await performMutation("idle memory policy") {
                try await store.saveIdle(minutes: minutes)
            }
            idleSaveInFlight = false
            if succeeded {
                draft.didSaveIdle(revision: revision, source: store.snapshot?.idlePolicy)
                feedback = "Saved. Restart Darkbloom to apply the idle policy."
            } else {
                feedback = store.errorMessage ?? "The idle policy was not saved."
            }
        }
    }

    private func setBeta(_ feature: ProviderBetaFeature, enabled: Bool) {
        guard !betaSaveIDs.contains(feature.id), !store.mutationInFlight,
              isFresh(store.snapshot?.betaFeatures),
              ProviderExtrasClient.allowedBetaFeatureIDs.contains(feature.id) else { return }
        betaSaveIDs.insert(feature.id)
        Task { @MainActor in
            let succeeded = await performMutation("beta \(feature.id)") {
                try await store.setBeta(id: feature.id, enabled: enabled)
            }
            betaSaveIDs.remove(feature.id)
            feedback = succeeded
                ? (feature.requiresRestart
                    ? "Saved \(feature.title). Restart Darkbloom to apply it."
                    : "Saved \(feature.title).")
                : (store.errorMessage ?? "The beta setting was not saved.")
        }
    }
}

/// Text remains the primary state cue, including automatic and unknown states.
struct SettingsStateBadge: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.quaternary, in: Capsule())
            .fixedSize()
    }
}
