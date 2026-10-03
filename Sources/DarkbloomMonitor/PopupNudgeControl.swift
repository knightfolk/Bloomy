import SwiftUI

/// A deliberate, one-request entry point. Opening the sheet never sends a
/// request; the separate Send action checks fresh eligibility at click time.
struct PopupNudgeControl: View {
    @ObservedObject var store: InactivityNudgeStore
    var updateProtection: AppUpdateEditorProtection? = nil
    @State private var showsSheet = false

    var body: some View {
        Button("Nudge", systemImage: "hand.tap") {
            showsSheet = true
        }
        .help("Send one optional self-route request through a warm model")
        .accessibilityIdentifier("popup.nudge.open")
        .modifier(PopupKeyboardReveal())
        .sheet(isPresented: $showsSheet) {
            sheetContent
        }
    }

    private var sheetContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Nudge a warm model").font(.title2.bold())
                Spacer()
                Button("Done") { showsSheet = false }
                    .accessibilityIdentifier("popup.nudge.close")
            }

            if let notice = store.keyStatusNotice {
                KeychainPresenceStatusView(notice: notice, isChecking: store.keyPresence == nil) {
                    Task { await store.refreshKeyStatus() }
                }
                Spacer()
            } else if !store.keyPresent {
                ScrollView { NudgeSetupGuide(store: store, updateProtection: updateProtection).padding(.vertical, 4) }
            } else {
            Label("Setup complete · Key saved", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("nudge.setup.complete")
            Text("Send one free, exclusive self-route request capped at 8 output tokens. It may reach another owned machine serving the same model. A response does not guarantee public work.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 12) {
                Button(store.isManuallyNudging ? "Sending…" : "Send nudge") {
                    Task { await store.nudgeNow() }
                }
                .disabled(store.manualUnavailableReason != nil)
                .accessibilityIdentifier("popup.nudge.send")

                VStack(alignment: .leading, spacing: 4) {
                    if let manualStatus = store.manualStatus {
                        Text(manualStatus)
                            .accessibilityIdentifier("popup.nudge.status")
                    }
                    if let reason = store.manualUnavailableReason,
                       !store.isManuallyNudging {
                        Text(reason)
                            .accessibilityIdentifier("popup.nudge.unavailable")
                    }
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Divider()
            Text("Automatic nudge and key settings")
                .font(.headline)
            Form {
                InactivityNudgeSettingsView(store: store, updateProtection: updateProtection)
            }
            .formStyle(.grouped)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
        .accessibilityIdentifier("popup.nudge.sheet")
    }
}
