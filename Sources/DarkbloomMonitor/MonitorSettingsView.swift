import DarkbloomTelemetry
import SwiftUI

struct MonitorSettingsView: View {
    var extrasStore: ProviderExtrasStore? = nil
    var controlStore: ProviderControlStore? = nil
    var monitorStore: MonitorStore? = nil
    /// The dashboard supplies its sidebar selection. The standalone Settings
    /// scene uses the same pages with its own native sidebar.
    var selection: SettingsPage? = nil
    private let updateProtection: AppUpdateEditorProtection?
    @AppStorage(ApplicationAppearance.defaultsKey) private var appearanceModeRaw =
        AppAppearanceMode.system.rawValue
    @StateObject private var draft: ProviderSettingsDraftState
    @State private var standaloneSelection: SettingsPage = .appearance
    @State private var supportPacketPreview: SupportPacketPreviewPresentation?
    @State private var isPreparingSupportPacket = false
    @State private var supportPacketPrepareFailed = false
    @State private var supportPacketPrepared = false
    @State private var supportPacketAlertHistoryAvailable: Bool?

    init(
        extrasStore: ProviderExtrasStore? = nil,
        controlStore: ProviderControlStore? = nil,
        monitorStore: MonitorStore? = nil,
        selection: SettingsPage? = nil,
        draft: ProviderSettingsDraftState? = nil,
        updateProtection: AppUpdateEditorProtection? = nil
    ) {
        self.extrasStore = extrasStore
        self.controlStore = controlStore
        self.monitorStore = monitorStore
        self.selection = selection
        self.updateProtection = updateProtection
        _draft = StateObject(wrappedValue: draft ?? ProviderSettingsDraftState())
    }

    var body: some View {
        Group {
            if let selection {
                pages(selected: selection)
            } else {
                NavigationSplitView {
                    List(selection: $standaloneSelection) {
                        ForEach(SettingsPage.allCases) { page in
                            Label(page.sidebarTitle, systemImage: page.symbol)
                                .help(page.rawValue)
                                .accessibilityLabel(page.rawValue)
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
        .task(id: "\((selection ?? standaloneSelection).rawValue):\(monitorStore?.dashboardVisible ?? true)") {
            let selected = selection ?? standaloneSelection
            guard monitorStore?.dashboardVisible ?? true, let extrasStore,
                  selected == .provider || selected == .updates || selected == .fans else { return }
            await extrasStore.refresh()
            // Editable static settings keep their existing 45-second freshness
            // guarantee only while their page is visible.
            guard selected == .provider || selected == .updates else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) }
                catch { return }
                guard !extrasStore.mutationInFlight else { continue }
                await extrasStore.refresh()
            }
        }
        .sheet(item: $supportPacketPreview) { presentation in
            SupportPacketPreviewView(snapshot: presentation.snapshot)
        }
    }

    /// Mount only the selected page. Draft state outlives these views without
    /// retaining their controls, polling tasks, or unrelated local edit buffers.
    private func pages(selected: SettingsPage) -> some View {
        pageForm(selected, isVisible: monitorStore?.dashboardVisible ?? true)
            .id(selected)
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
                    InactivityNudgeSettingsView(store: inactivityNudge, updateProtection: updateProtection)
                }
            case .companion:
                Section("iPhone companion") {
                    LabeledContent("Availability", value: "Coming soon")
                    Text("iPhone pairing and remote controls aren’t available in this version.")
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
                isVisible: isVisible,
                draft: draft
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
        case .support: "Review a support report before saving or sharing."
        }
    }

    private var supportSection: some View {
        Section("Support") {
            Text("Create a report with provider status, recognized model identifiers, recent alerts, and recommendations. Review its contents before saving or sharing.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(isPreparingSupportPacket ? "Preparing…" : "Review support report…") {
                prepareSupportPacket()
            }
            .accessibilityIdentifier("settings.supportPacket.preview")
            .disabled(monitorStore == nil || isPreparingSupportPacket)

            if supportPacketPrepareFailed {
                Text("The support report could not be prepared. Try again after status refreshes.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else if supportPacketPrepared, supportPacketAlertHistoryAvailable == false {
                Text("Local alert history was unavailable when this report was prepared. Saved alerts aren’t included.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func prepareSupportPacket() {
        guard let monitorStore else { return }
        supportPacketPrepareFailed = false
        supportPacketPrepared = false
        supportPacketAlertHistoryAvailable = nil
        isPreparingSupportPacket = true
        Task { @MainActor in
            defer { isPreparingSupportPacket = false }
            do {
                let snapshot = try await monitorStore.makeSupportPacketPreview()
                supportPacketAlertHistoryAvailable = snapshot.alertHistoryAvailable
                supportPacketPreview = SupportPacketPreviewPresentation(snapshot: snapshot)
                supportPacketPrepared = true
            } catch {
                supportPacketPrepareFailed = true
            }
        }
    }
}

@MainActor
enum MenuBarIdleAlertSelection {
    static func binding(to storedMinutes: Binding<Int>) -> Binding<Int> {
        Binding(
            get: { MenuBarAttentionPolicy.effectiveIdleMinutes(for: storedMinutes.wrappedValue) },
            set: { minutes in
                guard MenuBarAttentionPolicy.supportedMinutes.contains(minutes) else { return }
                storedMinutes.wrappedValue = minutes
            }
        )
    }
}

/// Recording requires a known price, including an explicitly entered zero.
/// Keep this aligned with EnergyRecorder rather than treating enabled as ready.
enum ElectricitySettingsRecordingState: Equatable {
    case disabled, waitingForPrice, invalidPrice, ready

    init(enabled: Bool, price: String) {
        if !enabled { self = .disabled }
        else if ElectricityCost.rate(price) != nil { self = .ready }
        else if price.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self = .waitingForPrice }
        else { self = .invalidPrice }
    }

    var status: String {
        switch self {
        case .disabled: "Off · Not recording"
        case .waitingForPrice, .invalidPrice: "On · Waiting for a valid price"
        case .ready: "On · Records available readings locally"
        }
    }

    var validation: String? {
        switch self {
        case .waitingForPrice: "Enter a price to begin recording, such as 0.15."
        case .invalidPrice: "Enter a non-negative dollar amount, such as 0.15."
        case .disabled, .ready: nil
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
                let recording = ElectricitySettingsRecordingState(enabled: electricityEnabled, price: electricityRate)
                Section("Electricity") {
                    Toggle(isOn: $electricityEnabled) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Estimate electricity use")
                            Text(recording.status)
                                .font(.callout).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityLabel("Estimate electricity use")
                    .accessibilityIdentifier("settings.electricity.enabled")
                    TextField("Price (USD / kWh)", text: $electricityRate, prompt: Text("0.15"))
                        .accessibilityIdentifier("settings.electricity.rate")
                        .help("Your price in dollars per kilowatt-hour. Zero is valid; a blank price is unknown.")
                        .disabled(!electricityEnabled)
                    if let validation = recording.validation {
                        Text(validation)
                            .font(.callout)
                            .foregroundStyle(recording == .invalidPrice ? Color.red : Color.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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

                    Picker("Idle alert", selection: MenuBarIdleAlertSelection.binding(to: $idleAlertMinutes)) {
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
    let draft: ProviderSettingsDraftState
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
                    showsFanControls: false,
                    isVisible: isVisible,
                    draft: draft
                )
            case .updates:
                ProviderAutoUpdateSettingsView(
                    store: extras,
                    performMutation: performMutation,
                    isVisible: isVisible
                )
            case .fans:
                ProviderFanControlSettingsView(
                    store: extras,
                    performMutation: performMutation,
                    isVisible: isVisible,
                    draft: draft
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
