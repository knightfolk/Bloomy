import DarkbloomTelemetry
import SwiftUI

struct MonitorSettingsView: View {
    var extrasStore: ProviderExtrasStore? = nil
    var controlStore: ProviderControlStore? = nil
    var monitorStore: MonitorStore? = nil
    /// The dashboard supplies its sidebar selection. The standalone Settings
    /// scene uses the same pages with its own native sidebar.
    var selection: SettingsPage? = nil
    @AppStorage(ApplicationAppearance.defaultsKey) private var appearanceModeRaw =
        AppAppearanceMode.system.rawValue
    @State private var standaloneSelection: SettingsPage = .appearance
    @State private var supportPacketPreview: SupportPacketPreviewPresentation?
    @State private var isPreparingSupportPacket = false
    @State private var supportPacketPrepareFailed = false
    @State private var supportPacketPrepared = false

    var body: some View {
        Group {
            if let selection {
                pages(selected: selection)
            } else {
                NavigationSplitView {
                    List(selection: $standaloneSelection) {
                        ForEach(SettingsPage.allCases) { page in
                            Label(page.rawValue, systemImage: page.symbol)
                                .tag(page)
                        }
                    }
                    .navigationTitle("Settings")
                    .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
                } detail: {
                    pages(selected: standaloneSelection)
                }
            }
        }
        .sheet(item: $supportPacketPreview) { presentation in
            SupportPacketPreviewView(snapshot: presentation.snapshot)
        }
    }

    /// Keep each page mounted while navigating. The idle-memory and fan views
    /// own edit buffers that should survive a trip to another Settings page.
    private func pages(selected: SettingsPage) -> some View {
        ZStack {
            ForEach(SettingsPage.allCases) { page in
                pageForm(page, isVisible: selected == page)
                    .opacity(selected == page ? 1 : 0)
                    .allowsHitTesting(selected == page)
                    .disabled(selected != page)
                    .accessibilityHidden(selected != page)
            }
        }
    }

    private func pageForm(_ page: SettingsPage, isVisible: Bool) -> some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(page.rawValue, systemImage: page.symbol)
                        .font(.largeTitle.bold())
                    Text(pageDescription(page))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            switch page {
            case .appearance, .menuBar, .electricity:
                GeneralSettingsView(
                    page: page,
                    appearanceModeRaw: $appearanceModeRaw
                )
            case .updates:
                ControlAppUpdateSettings()
                CLIUpdateNoticeView(store: CLIUpdateStatusStore.shared)
                providerSection(for: .updates, isVisible: isVisible)
            case .provider, .fans:
                providerSection(for: page, isVisible: isVisible)
                if page == .provider, let profitSwitch = monitorStore?.profitSwitch {
                    ProfitSwitchSettingsView(store: profitSwitch)
                }
                if page == .provider, let inactivityNudge = monitorStore?.inactivityNudge {
                    InactivityNudgeSettingsView(store: inactivityNudge)
                }
            case .companion:
                Section("iPhone companion") {
                    LabeledContent("Signed background helper", value: "Coming soon")
                    Text("Secure QR pairing and remote controls will appear here after the helper is packaged, signed, and verified on a physical iPhone. The current app does not enable it automatically.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            case .support:
                supportSection
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func providerSection(for page: SettingsPage, isVisible: Bool) -> some View {
        if let extrasStore, let controlStore {
            ProviderAdvancedSettingsHost(
                extras: extrasStore,
                control: controlStore,
                page: page,
                isVisible: isVisible
            )
        } else {
            Section("Provider") {
                Text("Open the dashboard to manage provider settings.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func pageDescription(_ page: SettingsPage) -> String {
        switch page {
        case .appearance: "Choose how Bloomy looks. Changes apply immediately."
        case .menuBar: "Three circles show your model, GPU usage, and cooling. Changes apply immediately."
        case .electricity: "Track electricity estimates and set your local price."
        case .updates: "App, CLI, and provider update preferences."
        case .provider: "Saved idle-memory and experimental feature choices."
        case .fans: "Fan helper status and controls from the official CLI."
        case .companion: "Companion availability and setup."
        case .support: "Review a sanitized support packet before saving or sharing."
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Text("Prepare a frozen packet with fixed provider status, allowlisted model identifiers, and sanitized alert history. Review it before saving or sharing.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isPreparingSupportPacket ? "Preparing…" : "Review support packet…") {
                prepareSupportPacket()
            }
            .accessibilityIdentifier("settings.supportPacket.preview")
            .disabled(monitorStore == nil || isPreparingSupportPacket)

            if supportPacketPrepareFailed {
                Text("The support packet could not be prepared. Try again after telemetry refreshes.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if supportPacketPrepared, monitorStore?.alertHistoryAvailable == false {
                Text("Local alert history is unavailable. The packet contains the current sanitized snapshot only.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prepareSupportPacket() {
        guard let monitorStore else { return }
        supportPacketPrepareFailed = false
        supportPacketPrepared = false
        isPreparingSupportPacket = true
        Task { @MainActor in
            defer { isPreparingSupportPacket = false }
            do {
                let snapshot = try await monitorStore.makeSupportPacketPreview()
                supportPacketPreview = SupportPacketPreviewPresentation(snapshot: snapshot)
                supportPacketPrepared = true
            } catch {
                supportPacketPrepareFailed = true
            }
        }
    }
}

private struct GeneralSettingsView: View {
    let page: SettingsPage
    @Binding var appearanceModeRaw: String
    @AppStorage("electricity.usdPerKWh") private var electricityRate = ""
    @AppStorage("electricity.enabled") private var electricityEnabled = false
    @AppStorage(MenuBarAttentionPolicy.defaultsKey) private var idleAlertMinutes = MenuBarAttentionPolicy.defaultIdleMinutes

    var body: some View {
        Group {
            if page == .appearance {
                Section("Appearance · Applies immediately") {
                    Picker("Color scheme", selection: appearanceModeBinding) {
                        ForEach(AppAppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("System follows the Mac appearance automatically. Light and Dark keep the selected look until you change it.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if page == .electricity {
                Section("Electricity") {
                    Toggle(isOn: $electricityEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Estimate electricity use")
                            Text(electricityEnabled ? "On · Records available readings locally" : "Off · Not recording")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Estimate electricity use")
                    .accessibilityIdentifier("settings.electricity.enabled")
                    TextField("Price (USD / kWh)", text: $electricityRate)
                        .accessibilityIdentifier("settings.electricity.rate")
                        .disabled(!electricityEnabled)
                    if !electricityRate.isEmpty && ElectricityCost.rate(electricityRate) == nil {
                        Text("Enter a non-negative dollar amount, such as 0.15.")
                            .foregroundStyle(.red)
                    }
                    DisclosureGroup("About electricity estimates") {
                        Text("Enter dollars, not cents. Estimates cover the whole Mac’s DC adapter input, not wall power or Darkbloom alone. Readings are stored locally every 10 seconds. Unplugged or missing readings leave gaps; net earnings require matching coverage.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if page == .menuBar {
                Section("Menu bar · Applies immediately") {
                    Label("Model · GPU · Cooling", systemImage: "circle.grid.3x1")
                    Text("The model ring spins during work. The model and cooling rings use green, yellow, or red for GPU temperature. The GPU ring shows whole-Mac usage. The cooling ring shows the highest fan speed percentage of its reported maximum RPM. Hover for readings and details.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Picker("Idle alert", selection: $idleAlertMinutes) {
                        Text("Off").tag(0)
                        ForEach(MenuBarAttentionPolicy.supportedMinutes.filter { $0 > 0 }, id: \.self) { minutes in
                            Text("After \(minutes) minutes").tag(minutes)
                        }
                    }
                    .accessibilityIdentifier("settings.menuBar.idleAlert")
                    Text("A ! appears on the model indicator when a warm provider stays idle. The alert clears when work resumes. This reminder does not send a nudge or change automatic nudge timing.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Unavailable readings use a neutral ring. Motion follows your Mac’s Reduce Motion setting. Earnings and model averages remain available in the popup.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var appearanceModeBinding: Binding<AppAppearanceMode> {
        Binding(
            get: { AppAppearanceMode(storedValue: appearanceModeRaw) },
            set: { mode in
                appearanceModeRaw = mode.rawValue
                ApplicationAppearance.apply(mode)
            }
        )
    }
}


private struct ProviderAdvancedSettingsHost: View {
    @ObservedObject var extras: ProviderExtrasStore
    @ObservedObject var control: ProviderControlStore
    let page: SettingsPage
    let isVisible: Bool
    @State private var isManuallyRefreshing = false

    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider settings").font(.headline)
                    if let capturedAt = lastChecked {
                        Text("Last checked \(capturedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button("Refresh") {
                    isManuallyRefreshing = true
                    Task {
                        await extras.refresh()
                        isManuallyRefreshing = false
                    }
                }
                .disabled(isManuallyRefreshing || extras.mutationInFlight)
            }
        }
        if control.draft?.hasChanges == true {
            Section {
                Text("Save or discard your model edits before changing provider settings.")
                    .foregroundStyle(.orange)
            }
        }
        Group {
            switch page {
            case .provider:
                ProviderAdvancedSettingsView(
                    store: extras,
                    performMutation: performMutation,
                    showsAutoUpdate: false,
                    showsFanControls: false
                )
            case .updates:
                ProviderAutoUpdateSettingsView(
                    store: extras,
                    performMutation: performMutation
                )
            case .fans:
                ProviderFanControlSettingsView(
                    store: extras,
                    performMutation: performMutation,
                    isVisible: isVisible
                )
            default:
                EmptyView()
            }
        }
        .disabled(control.operation != .idle
            || control.pendingConfirmation != nil
            || control.draft?.hasChanges == true)
        if let error = control.errorMessage {
            Section { Text(error).foregroundStyle(.orange) }
        }
    }

    private var lastChecked: Date? {
        guard page == .fans else { return extras.snapshot?.capturedAt }
        switch extras.snapshot?.fanStatus {
        case .available(_, let date), .stale(_, let date, _): return date
        default: return nil
        }
    }

    private func performMutation(
        _ label: String,
        _ mutation: @escaping @Sendable () async throws -> Void
    ) async -> Bool {
        await control.performSettingsMutation(label, mutation: mutation)
    }
}
