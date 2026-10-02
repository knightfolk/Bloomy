import DarkbloomTelemetry
import SwiftUI

struct ProviderAutoUpdateSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    let performMutation: ProviderExtrasMutationExecutor
    var isVisible = true

    @State private var saveInFlight = false
    @State private var feedback: String?

    var body: some View {
        Section("Provider · Automatic CLI updates") {
            TimelineView(VisibilityTimelineSchedule(
                base: .explicit(ProviderSettingsFreshnessPolicy.transitions(for: store.snapshot?.autoUpdateStatus, at: store.currentDate)),
                isVisible: isVisible
            )) { _ in
                VStack(alignment: .leading, spacing: 8) {
                    switch store.snapshot?.autoUpdateStatus {
                    case .available(let status, _) where store.autoUpdateEvidenceIsFresh:
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Install signed provider updates automatically")
                                    .font(.body.weight(.medium))
                                Text("The provider checks for signed CLI releases after it starts. This does not update Bloomy.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 8) {
                                SettingsStateBadge(status.enabled ? "Enabled" : "Disabled")
                                Button(saveInFlight ? "Saving…" : (status.enabled ? "Disable" : "Enable")) {
                                    setEnabled(!status.enabled)
                                }
                                .disabled(saveInFlight || store.mutationInFlight)
                                .accessibilityLabel(saveInFlight ? "Saving automatic provider updates" : (status.enabled ? "Disable automatic provider updates" : "Enable automatic provider updates"))
                                .accessibilityIdentifier("settings.provider.autoupdate")
                            }
                        }
                    case .available(let status, _), .stale(let status, _, _):
                        HStack {
                            Text("Automatic provider updates")
                            Spacer()
                            SettingsStateBadge(status.enabled ? "Last known: Enabled" : "Last known: Disabled")
                        }
                        Text("Refresh before changing automatic updates.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    case .unavailable, nil:
                        Text("Automatic-update status is unavailable. Refresh to try again.")
                            .foregroundStyle(.secondary)
                    }
                    if let feedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard !saveInFlight, !store.mutationInFlight else { return }
        guard store.autoUpdateEvidenceIsFresh else {
            feedback = ProviderSettingsEvidenceError.refreshRequired.userMessage
            return
        }
        saveInFlight = true
        Task { @MainActor in
            let succeeded = await performMutation("automatic provider updates") {
                try await store.setAutoUpdate(enabled: enabled)
            }
            saveInFlight = false
            feedback = succeeded
                ? "Saved. The provider will use this setting on its next start."
                : (store.errorMessage ?? "The automatic-update setting was not saved.")
        }
    }
}

struct ProviderFanControlSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    let performMutation: ProviderExtrasMutationExecutor
    var isVisible: Bool
    var ownsVisibleFanPolling: Bool
    var compactPresentation: Bool

    init(
        store: ProviderExtrasStore,
        performMutation: @escaping ProviderExtrasMutationExecutor,
        isVisible: Bool = true,
        ownsVisibleFanPolling: Bool = true,
        compactPresentation: Bool = false,
        draft: ProviderSettingsDraftState? = nil
    ) {
        self.store = store
        self.performMutation = performMutation
        self.isVisible = isVisible
        self.ownsVisibleFanPolling = ownsVisibleFanPolling
        self.compactPresentation = compactPresentation
        _draft = StateObject(wrappedValue: draft ?? ProviderSettingsDraftState())
    }

    @StateObject private var draft: ProviderSettingsDraftState
    @State private var showsPolicyEditor = false
    @State private var showsAdvancedActions = false
    @State private var mutationInFlight = false
    @State private var pendingAction: FanAction?
    @State private var feedback: String?
    @State private var manuallyRefreshing = false

    var body: some View {
        Section(compactPresentation ? "" : "Provider · Fan control") {
            TimelineView(VisibilityTimelineSchedule(base: .explicit(freshnessTransitions), isVisible: isVisible)) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Fan readings").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button("Refresh readings", systemImage: "arrow.clockwise") {
                            Task {
                                manuallyRefreshing = true
                                await store.refreshFan()
                                manuallyRefreshing = false
                            }
                        }
                        .disabled(manuallyRefreshing || mutationInFlight || store.mutationInFlight)
                        .accessibilityIdentifier("settings.provider.fan.refresh")
                        .accessibilityValue(manuallyRefreshing ? "Refreshing" : "Ready")
                    }
                    switch store.snapshot?.fanStatus {
                    case .available(let status, let checkedAt):
                        fanContent(status: status, fresh: store.fanEvidenceIsFresh, checkedAt: checkedAt)
                    case .stale(let status, let checkedAt, _):
                        fanContent(status: status, fresh: false, checkedAt: checkedAt)
                    case .unavailable, nil:
                        Text("Fan diagnostics are unavailable. Refresh to try again.")
                            .foregroundStyle(.secondary)
                    }
                    if let feedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { syncDraft() }
        .onChange(of: store.snapshot?.fanStatus) { _, _ in syncDraft() }
        .task(id: isVisible && ownsVisibleFanPolling) {
            guard isVisible && ownsVisibleFanPolling else { return }
            await store.observeVisibleFan()
        }
        .alert(item: $pendingAction) { action in
            Alert(
                title: Text(action.title),
                message: Text(action.message),
                primaryButton: action.destructive
                    ? .destructive(Text(action.buttonTitle)) { run(action) }
                    : .default(Text(action.buttonTitle)) { run(action) },
                secondaryButton: .cancel()
            )
        }
    }

    private var freshnessTransitions: [Date] {
        let source = store.snapshot?.fanStatus
        let now = store.currentDate
        var dates = ProviderSettingsFreshnessPolicy.transitions(for: source, at: now)
        if case .available(let status, _) = source, let helper = status.helper {
            dates += ProviderSettingsFreshnessPolicy.transitions(capturedAt: helper.updatedAt,
                maximumAge: ProviderFanStatus.maximumHelperAge, at: now)
        }
        return Array(Set(dates)).sorted()
    }

    @ViewBuilder
    private func fanContent(status: ProviderFanStatus, fresh: Bool, checkedAt: Date) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if !compactPresentation { Text("Fan control").font(.headline) }
                Text(compactPresentation ? "Automatic cooling while you host." : "Turn Darkbloom's fan helper on or off. Readings update while this page is open.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            SettingsStateBadge(stateLabel(status, fresh: fresh))
        }

        readings(status: status, fresh: fresh, checkedAt: checkedAt)

        if !fresh {
            Text("These are the last known readings. Refresh before changing fan control.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if !status.advertisesOfficialControl {
            Text("This Darkbloom installation does not offer fan control.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            if let toggleIsOn = Self.toggleState(status) {
                Toggle("Use Darkbloom fan control", isOn: Binding(
                    get: { toggleIsOn },
                    set: { requestedOn in
                        if requestedOn { stagePolicy(.enable) }
                        else { stage(.disable) }
                    }
                ))
                .disabled(!fresh || !status.supportsOfficialControl || mutationInFlight || store.mutationInFlight)
                .accessibilityIdentifier("settings.provider.fan.enabled")
            } else {
                Text("The helper's on/off status is unavailable. Refresh to try again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if !status.supportsOfficialControl {
                Text("This Mac does not support changing the fan policy.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                DisclosureGroup("Fan policy", isExpanded: $showsPolicyEditor) {
                    policyEditor(status: status)
                    if status.loaded {
                        Button("Save Fan Policy…") { stagePolicy(.configure) }
                            .disabled(!fresh || !draft.fanDirty || !canSubmitPolicy)
                            .accessibilityIdentifier("settings.provider.fan.save")
                    }
                }
            }
            if status.installed || status.loaded {
                DisclosureGroup("Advanced helper actions", isExpanded: $showsAdvancedActions) {
                    HStack(spacing: 10) {
                        if status.loaded {
                            Button("Disable…", role: .destructive) {
                                stage(.disable)
                            }
                            .disabled(mutationInFlight || store.mutationInFlight)
                        }
                        if status.installed {
                            Button("Uninstall Helper…", role: .destructive) {
                                stage(.uninstall)
                            }
                            .disabled(mutationInFlight || store.mutationInFlight)
                        }
                    }
                    Text("These actions stop this helper and release any fans it controls.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text("Changing fan control asks for macOS administrator approval.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func readings(status: ProviderFanStatus, fresh: Bool, checkedAt: Date) -> some View {
        let helperIsFresh = status.helperIsFresh(at: store.currentDate)
        let readingStatus = Self.readingStatus(status, at: store.currentDate)
        let readingsAreFresh = fresh && (helperIsFresh
            || !status.diagnostic.fans.isEmpty || !status.diagnostic.gpuTemperatures.isEmpty)
        let temperature = readingStatus.displayedTemperatureCelsius
        let fans = readingStatus.displayedFans
        VStack(alignment: .leading, spacing: 8) {
            Text(readingsAreFresh ? "Latest readings" : "Last known readings")
                .font(.callout.weight(.semibold))
            Text("CLI checked \(checkedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !readingsAreFresh, let helper = readingStatus.helper {
                Text("Helper sample \(helper.updatedAt.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if fresh && !helperIsFresh {
                    Text("Helper readings did not refresh. Refresh to try again.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("GPU temperature").font(.caption).foregroundStyle(.secondary)
                    Text(temperature.map { String(format: "%.1f °C", $0) } ?? "Not reported")
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                }
                if let fan = fans.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Fan speed").font(.caption).foregroundStyle(.secondary)
                        Text(Self.rpm(fan.actualRPM))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Target speed").font(.caption).foregroundStyle(.secondary)
                        Text(Self.rpm(fan.targetRPM))
                            .font(.title3.weight(.semibold))
                            .monospacedDigit()
                    }
                }
            }
            if fans.count > 1 {
                ForEach(fans.dropFirst()) { fan in
                    Text("Fan \(fan.index + 1): \(Self.rpm(fan.actualRPM)) · target \(Self.rpm(fan.targetRPM))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if fans.isEmpty {
                Text("Fan speed is not reported by this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let helper = readingStatus.helper {
                let posture = helper.mode == "error" ? "Fan helper needs attention" : (helper.providerActive ? "Provider active" : "Waiting for provider activity")
                Text(fresh && helperIsFresh ? posture : "Last known: \(posture)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Fresh CLI diagnostics take precedence over an expired helper journal.
    /// With no diagnostic sample, retain the helper values as last known.
    static func readingStatus(_ status: ProviderFanStatus, at date: Date) -> ProviderFanStatus {
        if !status.helperIsFresh(at: date),
           !status.diagnostic.fans.isEmpty || !status.diagnostic.gpuTemperatures.isEmpty {
            return status.withoutHelper()
        }
        return status
    }

    static func toggleState(_ status: ProviderFanStatus) -> Bool? {
        guard status.loaded else { return false }
        return status.helper?.enabled
    }

    private func policyEditor(status: ProviderFanStatus) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Choose a starting point")
                    .font(.body.weight(.medium))
                Spacer()
                if draft.fanDirty {
                    Text("Unsaved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                ForEach(FanPreset.allCases) { preset in
                    Button(preset.title) { select(preset) }
                        .buttonStyle(.bordered)
                        .tint(draft.fanPreset == preset ? .accentColor : .secondary)
                        .accessibilityLabel("Choose \(preset.title) fan policy")
                        .accessibilityValue(draft.fanPreset == preset ? "Selected" : "Not selected")
                        .accessibilityIdentifier("settings.provider.fan.preset.\(preset.rawValue)")
                }
            }
            Text("Starting points only. Adjust either slider before saving.")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Fan target")
                    Spacer()
                    Text(Self.percent(draft.fanSpeedPercent))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Slider(value: speedBinding, in: ProviderFanPolicy.speedRange, step: 1)
                    .accessibilityLabel("Fan target")
                    .accessibilityValue(Self.percent(draft.fanSpeedPercent))
                    .accessibilityHint("Target fan speed after the trigger temperature is reached")
                    .accessibilityIdentifier("settings.provider.fan.speed")
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Start at GPU temperature")
                    Spacer()
                    Text(Self.temperature(draft.fanTriggerTemperature))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Slider(value: temperatureBinding, in: ProviderFanPolicy.triggerTemperatureRange, step: 1)
                    .accessibilityLabel("GPU trigger temperature")
                    .accessibilityValue(Self.temperature(draft.fanTriggerTemperature))
                    .accessibilityHint("GPU temperature where the fan target starts")
                    .accessibilityIdentifier("settings.provider.fan.temperature")
            }
            Label(
                "At \(Self.temperature(draft.fanTriggerTemperature)), target \(Self.percent(draft.fanSpeedPercent)) while the provider is active.",
                systemImage: "fanblades"
            )
            .font(.callout.weight(.medium))
            Text("This policy has one temperature trigger and one fan target.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .disabled(!status.supportsOfficialControl || mutationInFlight || store.mutationInFlight)
    }

    private var speedBinding: Binding<Double> {
        Binding(get: { draft.fanSpeedPercent }, set: { draft.editFanSpeed($0) })
    }

    private var temperatureBinding: Binding<Double> {
        Binding(get: { draft.fanTriggerTemperature }, set: { draft.editFanTemperature($0) })
    }

    private var policy: ProviderFanPolicy? { draft.fanPolicy }

    private var canSubmitPolicy: Bool {
        policy != nil && !mutationInFlight && !store.mutationInFlight
    }

    private func syncDraft() {
        draft.syncFan(from: store.snapshot?.fanStatus)
    }

    private func select(_ preset: FanPreset) {
        draft.selectFanPreset(preset)
    }

    private static func percent(_ value: Double) -> String {
        String(format: "%.0f%%", value)
    }

    private static func temperature(_ value: Double) -> String {
        String(format: "%.0f °C", value)
    }

    private static func rpm(_ value: Double?) -> String {
        guard let value else { return "Not reported" }
        return String(format: "%.0f RPM", value)
    }

    private func stagePolicy(_ kind: FanAction.Kind) {
        guard store.fanEvidenceIsFresh else {
            feedback = ProviderSettingsEvidenceError.refreshRequired.userMessage
            return
        }
        guard let policy else {
            feedback = ProviderExtrasMutationError.invalidFanPolicy.userMessage
            return
        }
        stage(kind == .enable ? .enable(policy) : .configure(policy))
    }

    private func stage(_ action: FanAction) {
        guard store.fanEvidenceIsFresh else {
            feedback = ProviderSettingsEvidenceError.refreshRequired.userMessage
            return
        }
        pendingAction = action
    }

    private func run(_ action: FanAction) {
        guard !mutationInFlight, !store.mutationInFlight else { return }
        guard store.fanEvidenceIsFresh else {
            feedback = ProviderSettingsEvidenceError.refreshRequired.userMessage
            return
        }
        let revision = draft.fanRevision
        mutationInFlight = true
        Task { @MainActor in
            let succeeded = await performMutation(action.operationLabel) {
                switch action {
                case .enable(let policy): try await store.enableFan(policy: policy)
                case .configure(let policy): try await store.configureFan(policy: policy)
                case .disable: try await store.disableFan()
                case .uninstall: try await store.uninstallFan()
                }
            }
            mutationInFlight = false
            if succeeded {
                switch action {
                case .enable, .configure:
                    draft.didSaveFan(revision: revision, source: store.snapshot?.fanStatus)
                case .disable, .uninstall:
                    break
                }
                feedback = action.successMessage
            } else {
                feedback = store.errorMessage ?? "Darkbloom could not change fan control."
            }
        }
    }

    private func stateLabel(_ status: ProviderFanStatus, fresh: Bool) -> String {
        let label: String
        let usesHelperState = status.installed && status.loaded && status.helper != nil
        if !status.installed { label = "Not installed" }
        else if !status.loaded { label = "Disabled" }
        else if let helper = status.helper {
            if helper.mode == "error" { label = "Needs attention" }
            else if !helper.enabled { label = "Disabled" }
            else if helper.providerActive { label = "Enabled · Provider active" }
            else { label = "Enabled · Waiting" }
        } else { label = "Status unavailable" }
        let lastKnown = !fresh || (usesHelperState && !status.helperIsFresh(at: store.currentDate))
        return lastKnown ? "Last known: \(label)" : label
    }
}

enum FanPreset: String, CaseIterable, Identifiable {
    case quiet
    case balanced
    case cooling

    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var policy: ProviderFanPolicy {
        switch self {
        case .quiet: ProviderFanPolicy(speedPercent: 60, triggerTemperatureCelsius: 45)!
        case .balanced: ProviderFanPolicy(speedPercent: 75, triggerTemperatureCelsius: 45)!
        case .cooling: ProviderFanPolicy(speedPercent: 90, triggerTemperatureCelsius: 40)!
        }
    }
}

private enum FanAction: Identifiable {
    enum Kind { case enable, configure }

    case enable(ProviderFanPolicy)
    case configure(ProviderFanPolicy)
    case disable
    case uninstall

    var id: String {
        switch self {
        case .enable: "enable"
        case .configure: "configure"
        case .disable: "disable"
        case .uninstall: "uninstall"
        }
    }

    var title: String {
        switch self {
        case .enable: "Enable Darkbloom fan control?"
        case .configure: "Change the fan policy?"
        case .disable: "Disable Darkbloom fan control?"
        case .uninstall: "Uninstall the Darkbloom fan helper?"
        }
    }

    var message: String {
        switch self {
        case .enable(let policy), .configure(let policy):
            "Darkbloom will target \(String(format: "%.0f%%", policy.speedPercent)) when the GPU reaches \(String(format: "%.0f °C", policy.triggerTemperatureCelsius)). macOS will request administrator approval."
        case .disable:
            "This stops the helper and releases any fans it controls."
        case .uninstall:
            "This removes the Darkbloom helper and releases any fans it controls."
        }
    }

    var buttonTitle: String {
        switch self {
        case .enable: "Enable"
        case .configure: "Save Policy"
        case .disable: "Disable"
        case .uninstall: "Uninstall"
        }
    }

    var destructive: Bool {
        switch self {
        case .disable, .uninstall: true
        case .enable, .configure: false
        }
    }

    var operationLabel: String { "fan control \(id)" }

    var successMessage: String {
        switch self {
        case .enable: "Fan control enabled."
        case .configure: "Fan policy updated."
        case .disable: "Darkbloom fan helper disabled."
        case .uninstall: "Darkbloom fan helper removed."
        }
    }
}
