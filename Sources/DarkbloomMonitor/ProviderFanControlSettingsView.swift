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

    @State private var speedText = "80"
    @State private var temperatureText = "45"
    @State private var draftDirty = false
    @State private var mutationInFlight = false
    @State private var pendingAction: FanAction?
    @State private var feedback: String?

    var body: some View {
        Section("Provider · Fan control") {
            switch store.snapshot?.fanStatus {
            case .available(let status, _):
                fanContent(status: status, fresh: true)
            case .stale(let status, _, _):
                fanContent(status: status, fresh: false)
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
    private func fanContent(status: ProviderFanStatus, fresh: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Official Darkbloom fan helper")
                    .font(.body.weight(.medium))
                Text("Uses a fixed 60–90% target only while the signed provider is active and the GPU reaches the trigger temperature.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            SettingsStateBadge(stateLabel(status))
        }

        if let helper = status.helper {
            HStack(spacing: 16) {
                Label(String(format: "%.1f °C", helper.gpuTemperatureCelsius ?? 0), systemImage: "thermometer.medium")
                    .opacity(helper.gpuTemperatureCelsius == nil ? 0 : 1)
                Text("Trigger \(String(format: "%.0f °C", helper.triggerTemperatureCelsius))")
                Text("Target \(String(format: "%.0f%%", helper.speedPercent))")
                Text(helper.mode.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }

        if !fresh {
            Text("Refresh before changing fan control.")
                .font(.caption)
                .foregroundStyle(.orange)
        } else if !status.advertisesOfficialControl {
            Text("This CLI does not advertise the supported fan-helper capability.")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else {
            if status.supportsOfficialControl {
                policyEditor(status: status)
            } else {
                Text("The CLI reports that this Mac does not support fan-policy changes. Recovery actions remain available for an installed helper.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if status.loaded {
                    if status.supportsOfficialControl {
                        Button("Save Policy…") { stagePolicy(.configure) }
                            .disabled(!canSubmitPolicy)
                    }
                    Button("Disable…", role: .destructive) {
                        pendingAction = .disable
                    }
                    .disabled(mutationInFlight || store.mutationInFlight)
                } else if status.supportsOfficialControl {
                    Button(status.installed ? "Enable…" : "Install & Enable…") {
                        stagePolicy(.enable)
                    }
                    .disabled(!canSubmitPolicy)
                }
                if status.installed {
                    Button("Uninstall Helper…", role: .destructive) {
                        pendingAction = .uninstall
                    }
                    .disabled(mutationInFlight || store.mutationInFlight)
                }
            }
            Text("macOS will request administrator approval. Disabling or uninstalling restores automatic fan control.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func policyEditor(status: ProviderFanStatus) -> some View {
        HStack(spacing: 14) {
            Text("Fan target")
            TextField("80", text: speedBinding)
                .frame(width: 58)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .accessibilityLabel("Fan target percent")
                .accessibilityIdentifier("settings.provider.fan.speed")
            Text("%")
                .foregroundStyle(.secondary)
            Text("at")
            TextField("45", text: temperatureBinding)
                .frame(width: 58)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .accessibilityLabel("Fan trigger temperature")
                .accessibilityIdentifier("settings.provider.fan.temperature")
            Text("°C")
                .foregroundStyle(.secondary)
            if draftDirty {
                Text("Unsaved")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Spacer()
        }
        .disabled(!status.supportsOfficialControl || mutationInFlight || store.mutationInFlight)
    }

    private var speedBinding: Binding<String> {
        Binding(get: { speedText }, set: { speedText = $0; draftDirty = true })
    }

    private var temperatureBinding: Binding<String> {
        Binding(get: { temperatureText }, set: { temperatureText = $0; draftDirty = true })
    }

    private var policy: ProviderFanPolicy? {
        guard let speed = Double(speedText.trimmingCharacters(in: .whitespacesAndNewlines)),
              let temperature = Double(temperatureText.trimmingCharacters(in: .whitespacesAndNewlines))
        else { return nil }
        return ProviderFanPolicy(
            speedPercent: speed,
            triggerTemperatureCelsius: temperature
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
        speedText = String(format: "%.0f", policy.speedPercent)
        temperatureText = String(format: "%.0f", policy.triggerTemperatureCelsius)
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
                draftDirty = false
                syncDraft()
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
        if helper.providerActive { return "Enabled · Provider active" }
        return "Enabled · Waiting"
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
            "This immediately restores macOS automatic fan control and stops the helper."
        case .uninstall:
            "This restores macOS automatic fan control and removes the official Darkbloom helper."
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
        case .disable: "Fan control disabled; macOS automatic control restored."
        case .uninstall: "Fan helper removed; macOS automatic control restored."
        }
    }
}
