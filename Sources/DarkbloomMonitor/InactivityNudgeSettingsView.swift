import SwiftUI

/// Sections for the grouped Settings form. The credential draft never leaves
/// this view except when the user explicitly saves it to the watcher Keychain.
struct InactivityNudgeSettingsView: View {
    @ObservedObject var store: InactivityNudgeStore
    @State private var keyDraft = ""
    @State private var keyError: String?

    var body: some View {
        Section("Automatic nudge") {
            Toggle("Automatic nudge", isOn: Binding(
                get: { store.enabled },
                set: { store.setEnabled($0) }
            ))
            .accessibilityIdentifier("settings.inactivityNudge.enabled")

            Picker("After no work for", selection: Binding(
                get: { store.inactivityMinutes },
                set: { store.setInactivityMinutes($0) }
            )) {
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("60 minutes").tag(60)
            }
            .accessibilityIdentifier("settings.inactivityNudge.minutes")

            LabeledContent("Status", value: store.status)
                .accessibilityIdentifier("settings.inactivityNudge.status")
            if let lastAttempt = store.lastAttempt {
                LabeledContent("Last attempt") {
                    Text(lastAttempt, format: .dateTime.month(.abbreviated).day().hour().minute())
                }
            }

            Text("When Bloomy is open, it may send one tiny exclusive self-route request through your own advertised warm model after the selected idle period. The request is capped at 8 output tokens. It does not restart or reconfigure models, and public jobs are never guaranteed.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("The watcher pauses for busy or stale evidence, missing account data, model switches, or multiple warm models. It waits at least 1 hour between attempts and allows at most 3 attempts in any 24 hours, including failures. There is no paid fallback or keep-alive loop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        Section("Nudge setup") {
            Text("Use a Darkbloom consumer key restricted to “my machine only.” Bloomy stores it in the macOS Keychain as a dedicated watcher credential, separate from provider and local API tokens.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Watcher key", value: store.keyPresent ? "Saved in Keychain" : "Not saved")

            SecureField("Paste consumer key", text: $keyDraft)
                .textContentType(.password)
                .privacySensitive()
                .accessibilityIdentifier("settings.inactivityNudge.key")

            HStack {
                Button("Save key") {
                    keyError = store.saveKey(keyDraft)
                    if keyError == nil {
                        keyDraft = ""
                    }
                }
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.inactivityNudge.saveKey")

                if !keyDraft.isEmpty {
                    Button("Cancel") {
                        keyDraft = ""
                        keyError = nil
                    }
                    .accessibilityIdentifier("settings.inactivityNudge.cancelKey")
                }

                Spacer()

                Button("Remove key", role: .destructive) {
                    keyDraft = ""
                    keyError = nil
                    store.removeKey()
                }
                .disabled(!store.keyPresent)
                .accessibilityIdentifier("settings.inactivityNudge.removeKey")
            }

            if let keyError {
                Text(keyError)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("settings.inactivityNudge.keyError")
            }

            Text("Activity is checked against account-wide earnings. Work from another Mac can keep this watcher idle. Billing can post late, so a quiet period does not prove the whole account had no work.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .onDisappear {
            keyDraft = ""
            keyError = nil
        }
    }
}
