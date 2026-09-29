import SwiftUI

/// Sections for the grouped Settings form. The credential draft never leaves
/// this view except when the user explicitly saves it to the watcher Keychain.
struct InactivityNudgeSettingsView: View {
    @ObservedObject var store: InactivityNudgeStore
    @State private var keyDraft = ""
    @State private var keyError: String?
    @State private var isReplacingKey = false

    var body: some View {
        Section("Automatic nudge") {
            Toggle("Automatic nudge", isOn: Binding(
                get: { store.enabled },
                set: { store.setEnabled($0) }
            ))
            .accessibilityIdentifier("settings.inactivityNudge.enabled")
            .disabled(store.isManuallyNudging)

            Picker("After no work for", selection: Binding(
                get: { store.inactivityMinutes },
                set: { store.setInactivityMinutes($0) }
            )) {
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("60 minutes").tag(60)
            }
            .accessibilityIdentifier("settings.inactivityNudge.minutes")
            .disabled(store.isManuallyNudging)

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

            Text("The automatic watcher pauses for busy or stale evidence, missing account data, model switches, or multiple warm models. It waits at least 1 hour between attempts and allows at most 3 attempts in any 24 hours, including failures. Manual nudges use the same key but require a separate tap and fresh idle state. There is no paid fallback or keep-alive loop.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }

        if !store.keyPresent {
            Section { NudgeSetupGuide(store: store) }
        } else {
            Section("Saved nudge key") {
                Label("Saved securely in Keychain", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Manual and automatic nudges use this same key. You do not need to enter it again.")
                    .font(.callout).foregroundStyle(.secondary)

                if isReplacingKey {
                    SecureField("Paste replacement key", text: $keyDraft)
                        .textContentType(.password)
                        .privacySensitive()
                        .accessibilityIdentifier("settings.inactivityNudge.key")
                    HStack {
                        Button("Save replacement") {
                            keyError = store.saveKey(keyDraft)
                            if keyError == nil {
                                keyDraft = ""
                                isReplacingKey = false
                            }
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("settings.inactivityNudge.saveKey")
                        Button("Cancel") { clearKeyDraft() }
                            .accessibilityIdentifier("settings.inactivityNudge.cancelKey")
                    }
                    Text("Your current key stays saved until you save a replacement.")
                        .font(.caption).foregroundStyle(.secondary)
                    if let keyError {
                        Text(keyError).foregroundStyle(.red)
                            .accessibilityIdentifier("settings.inactivityNudge.keyError")
                    }
                } else {
                    Button("Replace key…") { isReplacingKey = true }
                        .accessibilityIdentifier("settings.inactivityNudge.replaceKey")
                }

                DisclosureGroup("Remove saved key") {
                    Text("Manual and automatic nudges will be unavailable until you set up a key again.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Remove key", role: .destructive) {
                        clearKeyDraft()
                        store.removeKey()
                    }
                    .accessibilityIdentifier("settings.inactivityNudge.removeKey")
                }
            }
            .onDisappear { clearKeyDraft() }
        }
    }

    private func clearKeyDraft() {
        keyDraft = ""
        keyError = nil
        isReplacingKey = false
    }
}
