import DarkbloomTelemetry
import SwiftUI

struct MonitorSettingsView: View {
    var extrasStore: ProviderExtrasStore? = nil
    var controlStore: ProviderControlStore? = nil
    var monitorStore: MonitorStore? = nil
    @AppStorage("menuBarDisplayMode") private var displayModeRaw =
        MenuBarDisplayMode.automatic.rawValue
    @AppStorage(ApplicationAppearance.defaultsKey) private var appearanceModeRaw =
        AppAppearanceMode.system.rawValue
    @State private var supportPacketPreview: SupportPacketPreviewPresentation?
    @State private var isPreparingSupportPacket = false
    @State private var supportPacketPrepareFailed = false
    @State private var supportPacketPrepared = false

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Settings").font(.largeTitle.bold())
                    Text("App preferences apply immediately. Provider settings below show saved choices.")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
            ControlAppUpdateSettings()
            CLIUpdateNoticeView(store: CLIUpdateStatusStore.shared)
            GeneralSettingsView(
                displayModeRaw: $displayModeRaw,
                appearanceModeRaw: $appearanceModeRaw
            )
            Section("iPhone companion") {
                LabeledContent("Signed background helper", value: "Coming soon")
                Text("Secure QR pairing and remote controls will appear here after the helper is packaged, signed, and verified on a physical iPhone. The current app does not enable it automatically.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            supportSection
            if let extrasStore, let controlStore {
                ProviderAdvancedSettingsHost(extras: extrasStore, control: controlStore)
            }
        }
        .formStyle(.grouped)
        .sheet(item: $supportPacketPreview) { presentation in
            SupportPacketPreviewView(snapshot: presentation.snapshot)
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
    @Binding var displayModeRaw: String
    @Binding var appearanceModeRaw: String
    @AppStorage("electricity.usdPerKWh") private var electricityRate = ""
    @AppStorage("electricity.enabled") private var electricityEnabled = false

    var body: some View {
        Group {
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
            Section("Menu bar · Applies immediately") {
                Picker("Displayed metric", selection: displayModeBinding) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.menu)

                Text("Automatic shows Working or today's model average during activity, and today's earnings while idle. An asterisk marks partial-day earnings coverage.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var displayModeBinding: Binding<MenuBarDisplayMode> {
        Binding(
            get: { MenuBarDisplayMode(rawValue: displayModeRaw) ?? .automatic },
            set: { displayModeRaw = $0.rawValue }
        )
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
    var body: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Provider settings").font(.title2.bold())
                    if let capturedAt = extras.snapshot?.capturedAt {
                        Text("Last checked \(capturedAt.formatted(date: .omitted, time: .shortened))")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(extras.isRefreshing ? "Refreshing…" : "Refresh") {
                    Task { await extras.refresh() }
                }
                .disabled(extras.isRefreshing || extras.mutationInFlight)
            }
        }
        if control.draft?.hasChanges == true {
            Section {
                Text("Save or discard your model edits before changing idle-memory or beta settings.")
                    .foregroundStyle(.orange)
            }
        }
        ProviderAdvancedSettingsView(store: extras, performMutation: { label, mutation in
            await control.performSettingsMutation(label, mutation: mutation)
        })
        .disabled(control.operation != .idle
            || control.pendingConfirmation != nil
            || control.draft?.hasChanges == true)
        if let error = control.errorMessage {
            Section { Text(error).foregroundStyle(.orange) }
        }
    }
}
