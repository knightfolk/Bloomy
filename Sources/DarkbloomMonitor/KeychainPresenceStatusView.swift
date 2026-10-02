import SwiftUI

/// An undecided Keychain result must not send the user through setup again.
struct KeychainPresenceStatusView: View {
    let notice: String
    let isChecking: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            if isChecking {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "key.horizontal")
                    .foregroundStyle(.secondary)
            }
            Text(notice).foregroundStyle(.secondary)
            if !isChecking {
                Spacer()
                Button("Check again", action: refresh)
                    .accessibilityIdentifier("keychain.presence.retry")
            }
        }
        .font(.callout)
        .accessibilityIdentifier("keychain.presence.status")
    }
}
