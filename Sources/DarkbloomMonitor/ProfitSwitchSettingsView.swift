import DarkbloomTelemetry
import SwiftUI

struct ProfitSwitchSettingsView: View {
    @ObservedObject var store: ProfitSwitchStore

    var body: some View {
        Section("Automatic profit switching") {
            Toggle("Switch to a better earning model", isOn: Binding(
                get: { store.enabled },
                set: { store.setEnabled($0) }
            ))
            .accessibilityIdentifier("settings.profitSwitch.enabled")

            LabeledContent("Status", value: store.status)
                .accessibilityIdentifier("settings.profitSwitch.status")
            if let lastAttempt = store.lastAttempt {
                LabeledContent("Last attempt") {
                    Text(lastAttempt, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
            }

            Text("Off by default. When enabled, Bloomy can select only downloaded models you can already serve that fit this Mac. It waits for fresh network demand, measured earning and electricity estimates, and an idle single-model state.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("When will it switch?") {
                Text("A candidate must show at least 30% and $0.05 more estimated net earnings over the next hour after allowing at least \(store.timing.loadAllowanceMinutes) min to load. That lead must last \(store.timing.confirmationMinutes) min. Bloomy holds the current model at least \(store.timing.minimumHoldMinutes) min, avoids the departed model for \(store.timing.returnCooldownMinutes) min, and allows at most 3 attempts in 24 hours, including failures.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text("This estimate calibrates account earnings against activity observed on this Mac; it is not a promise of work or income. Customer prices are not used. Bloomy does not download models or use a paid fallback.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        Section("Switch timing") {
            Stepper(value: confirmationMinutes, in: 5...60, step: 5) {
                LabeledContent("Confirm better estimate", value: "\(store.timing.confirmationMinutes) min")
            }
            .accessibilityIdentifier("settings.profitSwitch.confirmationMinutes")

            Stepper(value: minimumHoldMinutes, in: 30...240, step: 15) {
                LabeledContent("Keep selected model", value: "\(store.timing.minimumHoldMinutes) min")
            }
            .accessibilityIdentifier("settings.profitSwitch.minimumHoldMinutes")

            Stepper(value: returnCooldownMinutes, in: 60...1440, step: 30) {
                LabeledContent("Wait before returning", value: "\(store.timing.returnCooldownMinutes) min")
            }
            .accessibilityIdentifier("settings.profitSwitch.returnCooldownMinutes")

            Stepper(value: loadAllowanceMinutes, in: 1...30, step: 1) {
                LabeledContent("Allow for loading", value: "\(store.timing.loadAllowanceMinutes) min")
            }
            .accessibilityIdentifier("settings.profitSwitch.loadAllowanceMinutes")

            Text("The return wait is always at least as long as the hold. A longer measured load time takes precedence over the allowance.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confirmationMinutes: Binding<Int> {
        Binding(get: { store.timing.confirmationMinutes }, set: { updateTiming(confirmation: $0) })
    }

    private var minimumHoldMinutes: Binding<Int> {
        Binding(get: { store.timing.minimumHoldMinutes }, set: { updateTiming(hold: $0) })
    }

    private var returnCooldownMinutes: Binding<Int> {
        Binding(get: { store.timing.returnCooldownMinutes }, set: { updateTiming(returnCooldown: $0) })
    }

    private var loadAllowanceMinutes: Binding<Int> {
        Binding(get: { store.timing.loadAllowanceMinutes }, set: { updateTiming(loadAllowance: $0) })
    }

    private func updateTiming(
        confirmation: Int? = nil,
        hold: Int? = nil,
        returnCooldown: Int? = nil,
        loadAllowance: Int? = nil
    ) {
        let current = store.timing
        store.updateTiming(ProfitSwitchTiming(
            confirmationMinutes: confirmation ?? current.confirmationMinutes,
            minimumHoldMinutes: hold ?? current.minimumHoldMinutes,
            returnCooldownMinutes: returnCooldown ?? current.returnCooldownMinutes,
            loadAllowanceMinutes: loadAllowance ?? current.loadAllowanceMinutes
        ))
    }
}
