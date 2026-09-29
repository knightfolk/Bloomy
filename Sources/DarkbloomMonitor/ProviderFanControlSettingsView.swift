import DarkbloomTelemetry
import SwiftUI

struct ProviderAutoUpdateSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    let performMutation: ProviderExtrasMutationExecutor

    @State private var saveInFlight = false
    @State private var feedback: String?

    var body: some View {
        Section("Provider · Automatic CLI updates") {
            switch store.snapshot?.autoUpdateStatus {
            case .available(let status, _):
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Install signed provider updates automatically")
                            .font(.body.weight(.medium))
                        Text("The provider checks for signed CLI releases after it starts. This does not update Darkbloom Control.")
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
                        .accessibilityIdentifier("settings.provider.autoupdate")
                    }
                }
            case .stale(let status, _, _):
                HStack {
                    Text("Automatic provider updates")
                    Spacer()
                    SettingsStateBadge(status.enabled ? "Last known: Enabled" : "Last known: Disabled")
                }
                Text("Refresh before changing automatic updates.")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .unavailable:
                Text("Automatic-update controls require a newer Darkbloom CLI.")
                    .foregroundStyle(.secondary)
            case nil:
                Text("Automatic-update status is unavailable.")
                    .foregroundStyle(.secondary)
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setEnabled(_ enabled: Bool) {
        guard !saveInFlight, !store.mutationInFlight else { return }
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
    var compactPresentation: Bool

    init(
        store: ProviderExtrasStore,
        performMutation: @escaping ProviderExtrasMutationExecutor,
        isVisible: Bool = true,
        compactPresentation: Bool = false
    ) {
        self.store = store
        self.performMutation = performMutation
        self.isVisible = isVisible
        self.compactPresentation = compactPresentation
    }

    @State private var speedPercent = ProviderFanPolicy.default.speedPercent
    @State private var triggerTemperature = ProviderFanPolicy.default.triggerTemperatureCelsius
    @State private var draftDirty = false
    @State private var selectedPreset: FanPreset?
    @State private var showsPolicyEditor = false
    @State private var showsAdvancedActions = false
    @State private var mutationInFlight = false
    @State private var pendingAction: FanAction?
    @State private var feedback: String?

    var body: some View {
        Section(compactPresentation ? "" : "Provider · Fan control") {
            switch store.snapshot?.fanStatus {
            case .available(let status, let checkedAt):
                fanContent(status: status, fresh: true, checkedAt: checkedAt)
            case .stale(let status, let checkedAt, _):
                fanContent(status: status, fresh: false, checkedAt: checkedAt)
            case .unavailable, nil:
                Text("Fan diagnostics are unavailable. Refresh after updating the Darkbloom CLI.")
                    .foregroundStyle(.secondary)
            }
            if let feedback {
                Text(feedback)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { syncDraft() }
        .onChange(of: store.snapshot?.fanStatus) { _, _ in syncDraft() }
        .task(id: isVisible) {
            guard isVisible else { return }
            while !Task.isCancelled {
                await store.refreshFan()
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
            }
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
            SettingsStateBadge(stateLabel(status))
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
                        else { pendingAction = .disable }
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
                            .disabled(!fresh || !draftDirty || !canSubmitPolicy)
                            .accessibilityIdentifier("settings.provider.fan.save")
                    }
                }
            }
            if status.installed || status.loaded {
                DisclosureGroup("Advanced helper actions", isExpanded: $showsAdvancedActions) {
                    HStack(spacing: 10) {
                        if status.loaded {
                            Button("Disable…", role: .destructive) {
                                pendingAction = .disable
                            }
                            .disabled(mutationInFlight || store.mutationInFlight)
                        }
                        if status.installed {
                            Button("Uninstall Helper…", role: .destructive) {
                                pendingAction = .uninstall
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
        let temperature = status.displayedTemperatureCelsius
        let fans = status.displayedFans
        VStack(alignment: .leading, spacing: 8) {
            Text(fresh ? "Latest readings" : "Last known readings")
                .font(.callout.weight(.semibold))
            Text("Checked \(checkedAt.formatted(date: .omitted, time: .standard))")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            if let helper = status.helper {
                Text(helper.mode == "error" ? "Fan helper needs attention" : (helper.providerActive ? "Provider active" : "Waiting for provider activity"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                if draftDirty {
                    Text("Unsaved")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.orange)
                }
            }
            HStack(spacing: 8) {
                ForEach(FanPreset.allCases) { preset in
                    Button(preset.title) { select(preset) }
                        .buttonStyle(.bordered)
                        .tint(selectedPreset == preset ? .accentColor : .secondary)
                        .accessibilityLabel("Choose \(preset.title) fan policy")
                        .accessibilityValue(selectedPreset == preset ? "Selected" : "Not selected")
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
                    Text(Self.percent(speedPercent))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Slider(value: speedBinding, in: ProviderFanPolicy.speedRange, step: 1)
                    .accessibilityLabel("Fan target")
                    .accessibilityValue(Self.percent(speedPercent))
                    .accessibilityHint("Target fan speed after the trigger temperature is reached")
                    .accessibilityIdentifier("settings.provider.fan.speed")
            }
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("Start at GPU temperature")
                    Spacer()
                    Text(Self.temperature(triggerTemperature))
                        .monospacedDigit()
                        .fontWeight(.semibold)
                }
                Slider(value: temperatureBinding, in: ProviderFanPolicy.triggerTemperatureRange, step: 1)
                    .accessibilityLabel("GPU trigger temperature")
                    .accessibilityValue(Self.temperature(triggerTemperature))
                    .accessibilityHint("GPU temperature where the fan target starts")
                    .accessibilityIdentifier("settings.provider.fan.temperature")
            }
            Label(
                "At \(Self.temperature(triggerTemperature)), target \(Self.percent(speedPercent)) while the provider is active.",
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
        Binding(get: { speedPercent }, set: { speedPercent = $0; draftDirty = true; selectedPreset = nil })
    }

    private var temperatureBinding: Binding<Double> {
        Binding(get: { triggerTemperature }, set: { triggerTemperature = $0; draftDirty = true; selectedPreset = nil })
    }

    private var policy: ProviderFanPolicy? {
        return ProviderFanPolicy(
            speedPercent: speedPercent,
            triggerTemperatureCelsius: triggerTemperature
        )
    }

    private var canSubmitPolicy: Bool {
        policy != nil && !mutationInFlight && !store.mutationInFlight
    }

    private func syncDraft() {
        guard !draftDirty else { return }
        let helper = store.snapshot?.fanStatus.value?.helper
        let policy = helper.flatMap {
            ProviderFanPolicy(
                speedPercent: $0.speedPercent,
                triggerTemperatureCelsius: $0.triggerTemperatureCelsius
            )
        } ?? .default
        speedPercent = policy.speedPercent
        triggerTemperature = policy.triggerTemperatureCelsius
        selectedPreset = FanPreset.allCases.first { $0.policy == policy }
    }

    private func select(_ preset: FanPreset) {
        speedPercent = preset.policy.speedPercent
        triggerTemperature = preset.policy.triggerTemperatureCelsius
        selectedPreset = preset
        draftDirty = true
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
        guard let policy else {
            feedback = ProviderExtrasMutationError.invalidFanPolicy.userMessage
            return
        }
        pendingAction = kind == .enable ? .enable(policy) : .configure(policy)
    }

    private func run(_ action: FanAction) {
        guard !mutationInFlight, !store.mutationInFlight else { return }
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
                    draftDirty = false
                    syncDraft()
                case .disable, .uninstall:
                    break
                }
                feedback = action.successMessage
            } else {
                feedback = store.errorMessage ?? "Darkbloom could not change fan control."
            }
        }
    }

    private func stateLabel(_ status: ProviderFanStatus) -> String {
        guard status.installed else { return "Not installed" }
        guard status.loaded else { return "Disabled" }
        guard let helper = status.helper else { return "Status unavailable" }
        if helper.mode == "error" { return "Needs attention" }
        if !helper.enabled { return "Disabled" }
        if helper.providerActive { return "Enabled · Provider active" }
        return "Enabled · Waiting"
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
