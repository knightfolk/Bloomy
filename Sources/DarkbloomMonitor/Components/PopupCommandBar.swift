import SwiftUI

/// One visual rhythm for the popup's critical commands. The action, guard and
/// confirmation remain owned by each existing control.
struct PopupCommandLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(spacing: 5) {
            configuration.icon.font(.system(size: 17, weight: .medium))
                .frame(height: 19)
            configuration.title.font(.caption2.weight(.medium))
                .lineLimit(1).minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, minHeight: 47)
    }
}

struct PopupCommandButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(maxWidth: .infinity, minHeight: 47)
            .contentShape(RoundedRectangle(cornerRadius: 8))
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.045),
                        in: RoundedRectangle(cornerRadius: 8))
            .opacity(isEnabled ? 1 : 0.45)
    }
}

struct PopupHostingControl: View {
    @ObservedObject var store: HostingSettingsStore
    let isVisible: Bool
    let now: Date
    let coordinator: String?
    let openHosting: () -> Void
    @State private var showsDetails = false
    @State private var opensHostingAfterDismissal = false

    var body: some View {
        Button { showsDetails = true } label: {
            Label("Hosting", systemImage: "network")
        }
        .accessibilityIdentifier("popup.hosting.details")
        .help("Hosting status, connection details and refresh")
        .popover(isPresented: $showsDetails) {
            VStack(alignment: .leading, spacing: 8) {
                PopupHostingSummary(store: store, isVisible: isVisible && showsDetails,
                    now: now, coordinator: coordinator, openHosting: {
                        opensHostingAfterDismissal = true
                        showsDetails = false
                    })
                Button("Done") { showsDetails = false }
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .labelStyle(.titleAndIcon)
            .buttonStyle(.bordered)
            .padding(12).frame(width: 390)
            .onDisappear {
                guard opensHostingAfterDismissal else { return }
                opensHostingAfterDismissal = false
                // Let the child finish dismissal before its parent closes.
                // Otherwise AppKit consumes the parent's close request here.
                Task { @MainActor in
                    await Task.yield()
                    openHosting()
                }
            }
        }
    }
}

struct PopupAdaptiveCommandButtonStyle: PrimitiveButtonStyle {
    let commandTile: Bool

    @ViewBuilder func makeBody(configuration: Configuration) -> some View {
        if commandTile {
            Button(configuration).buttonStyle(PopupCommandButtonStyle())
        } else {
            Button(configuration).buttonStyle(.bordered)
        }
    }
}
