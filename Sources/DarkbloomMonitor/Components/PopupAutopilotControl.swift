import DarkbloomTelemetry
import SwiftUI

/// Opens the existing guarded controls; opening this entry never changes enrollment.
struct PopupAutopilotControl: View {
    @ObservedObject var extras: ProviderExtrasStore
    @ObservedObject var control: ProviderControlStore
    @ObservedObject var draft: ProviderSettingsDraftState
    let isVisible: Bool
    @State private var showsControls = false

    var body: some View {
        let state = ProviderAutopilotPresentation(source: extras.snapshot?.autopilotStatus, at: Date())
        Button { showsControls = true } label: {
            Label("Pilot · \(state.compactStateTitle)", systemImage: "sparkles")
        }
        .help("Autopilot · \(state.stateTitle). \(state.explanation)")
        .accessibilityLabel("Autopilot, \(state.stateTitle). Open controls")
        .accessibilityIdentifier("popup.autopilot.open")
        .modifier(PopupKeyboardReveal())
        .popover(isPresented: $showsControls) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Autopilot", systemImage: "sparkles").font(.headline)
                    Spacer()
                    Button("Done") { showsControls = false }
                }
                Form {
                    ProviderAutopilotSettingsView(store: extras, control: control,
                        performMutation: { label, mutation in
                            await control.performSettingsMutation(label, mutation: mutation)
                        }, isVisible: showsControls && isVisible, draft: draft, compactActions: true)
                }.formStyle(.grouped)
            }.labelStyle(.titleAndIcon).buttonStyle(.bordered).padding(16).frame(width: 420)
        }
    }
}
