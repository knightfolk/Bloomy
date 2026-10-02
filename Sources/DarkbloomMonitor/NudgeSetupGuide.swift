import SwiftUI

/// Shown until a dedicated nudge key is saved. Setup never sends a request
/// or opts the user into automatic nudges.
struct NudgeSetupGuide: View {
    @ObservedObject var store: InactivityNudgeStore
    var updateProtection: AppUpdateEditorProtection? = nil
    @State private var editorOwner = UUID()
    @State private var keyDraft = ""
    @State private var keyError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Set up Nudge").font(.title2.bold())
            Text("Connect a key once to use manual or automatic nudges.")
                .foregroundStyle(.secondary)

            step("1", title: "Open your Darkbloom account") {
                Text("Sign in to the API console and find API Keys. Create a separate key for Bloomy.")
                Link("Open Darkbloom API Keys ↗", destination: URL(string: "https://console.darkbloom.dev/api-console")!)
                    .accessibilityIdentifier("nudge.setup.openConsole")
            }
            step("2", title: "Choose “my machine only”") {
                Text("Restrict the key to your own machines, then copy it. Use a consumer API key, not your provider token.")
            }
            step("3", title: "Save it securely") {
                SecureField("Paste your nudge key", text: protectedKeyBinding)
                    .textFieldStyle(.roundedBorder)
                    .privacySensitive()
                    .accessibilityIdentifier("nudge.setup.key")
                Text("Stored in macOS Keychain. Bloomy never displays the saved key.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Save key and continue") {
                    keyError = store.saveKey(keyDraft)
                    if keyError == nil { clearKeyDraft() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("nudge.setup.save")
                if !keyDraft.isEmpty {
                    Button("Discard") { clearKeyDraft() }
                        .accessibilityIdentifier("nudge.setup.discard")
                }
                if let keyError {
                    Text(keyError).foregroundStyle(.red)
                        .accessibilityIdentifier("nudge.setup.error")
                }
            }
            Text("Saving does not send a request or turn on automatic nudges. After setup, choose Send nudge when one model is warm and idle. Key access is checked when you send.")
                .font(.callout).foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .onDisappear { clearKeyDraft() }
    }

    private var protectedKeyBinding: Binding<String> {
        Binding(get: { keyDraft }, set: {
            keyDraft = $0
            updateProtection?.setBlocked(!$0.isEmpty, owner: editorOwner)
        })
    }

    private func clearKeyDraft() {
        keyDraft = ""
        keyError = nil
        updateProtection?.endEditing(owner: editorOwner)
    }

    private func step<Content: View>(
        _ number: String, title: String, @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number).font(.headline)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                content().font(.callout)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
