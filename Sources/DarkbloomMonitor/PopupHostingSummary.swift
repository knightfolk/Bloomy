import DarkbloomTelemetry
import Foundation
import SwiftUI

/// Discovery is a point-in-time CLI report, never a reachability claim.
@MainActor
struct PopupHostingPresentation: Equatable {
    static let freshnessInterval: TimeInterval = 30
    let selection: String
    let status: String
    let address: String?
    let detail: String

    static func make(options: HostingOptions, discovery: LocalEndpointAvailability?,
                     checkedAt: Date?, now: Date) -> Self {
        let selection: String
        switch options.mode {
        case .off: selection = "Selected: Fleet only"
        case .unified: selection = "Selected: Fleet + local"
        case .standalone: selection = "Selected: Local only"
        }
        let fresh = checkedAt.map { (0...freshnessInterval).contains(now.timeIntervalSince($0)) } ?? false
        if case .live(let record) = discovery, let checkedAt, checkedAt.timeIntervalSince1970.isFinite {
            let authentication = record.hasBearerToken ? "API key required" : "No API key required"
            return Self(selection: selection,
                        status: fresh ? "Local-only listener reported" : "Local-only report expired",
                        address: safeAddress(record.baseURL),
                        detail: "\(authentication) · Checked \(checkedAt.formatted(date: .omitted, time: .standard))")
        }
        if options.mode == .unified {
            return Self(selection: selection, status: "Local API configured · unverified",
                        address: options.isValid ? HostingSettingsStore.endpointURL(from: options) : nil,
                        detail: "\(options.requiresAuthentication ? "API key required" : "No API key required") after Apply")
        }
        return Self(selection: selection,
                    status: fresh ? "No local-only listener discovered" : "Local API status unknown",
                    address: nil,
                    detail: "Discovery does not check Fleet + local listeners.")
    }

    /// Defense in depth for injected records; never render URL credentials,
    /// query strings, fragments, or arbitrary paths from discovery.
    private static func safeAddress(_ value: String) -> String? {
        guard value.utf8.count <= 256, let parts = URLComponents(string: value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              ["", "/", "/v1", "/v1/"].contains(parts.path) else { return nil }
        return parts.string
    }

    static func coordinatorHost(_ value: String?) -> String? {
        guard let value, value.utf8.count <= 512, let parts = URLComponents(string: value),
              ["http", "https", "ws", "wss"].contains(parts.scheme?.lowercased() ?? ""),
              let host = parts.host, !host.isEmpty,
              parts.user == nil, parts.password == nil else { return nil }
        return parts.port.map { "\(host):\($0)" } ?? host
    }
}

struct PopupHostingSummary: View {
    @ObservedObject var store: HostingSettingsStore
    let isVisible: Bool
    let now: Date
    let coordinator: String?
    let openHosting: () -> Void

    private var presentation: PopupHostingPresentation {
        // A discovery publication can arrive after the parent's timeline tick.
        // Evaluate at render time so a newly checked report never flashes unknown.
        .make(options: store.options, discovery: store.endpointDetails,
              checkedAt: store.endpointDetailsCheckedAt, now: Date())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Button(action: openHosting) {
                    Label("Hosting", systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .help("Open hosting settings and connection details")
                .accessibilityIdentifier("popover.hosting.open")
                .modifier(PopupKeyboardReveal())
                Spacer(minLength: 8)
                Text(presentation.selection).font(.caption).foregroundStyle(.secondary)
                    .help("Saved hosting preference. Apply changes before assuming the running provider uses it.")
                Button {
                    guard !store.isFetchingEndpointDetails else { return }
                    Task { await store.fetchEndpointDetails() }
                } label: {
                    Image(systemName: store.isFetchingEndpointDetails ? "hourglass" : "arrow.clockwise")
                        .frame(width: 14)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Refresh hosting connection")
                .accessibilityValue(store.isFetchingEndpointDetails ? "Checking" : "Ready")
                .help("Read local-only endpoint discovery from the CLI")
                .accessibilityIdentifier("popover.hosting.refresh")
                .modifier(PopupKeyboardReveal())
            }
            if let coordinator = PopupHostingPresentation.coordinatorHost(coordinator) {
                Label("Coordinator · \(coordinator)", systemImage: "antenna.radiowaves.left.and.right")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    .help("Coordinator reported by the current provider snapshot. This is not a connection test.")
            }
            Text(presentation.status).font(.caption)
                .accessibilityIdentifier("popover.hosting.status")
            if let address = presentation.address {
                Text(address).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).lineLimit(1).truncationMode(.middle).help(address)
                    .accessibilityIdentifier("popover.hosting.address")
            }
            Text(presentation.detail).font(.caption).foregroundStyle(.secondary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .task(id: isVisible) {
            guard isVisible, !store.isFetchingEndpointDetails else { return }
            if let checkedAt = store.endpointDetailsCheckedAt,
               (0...PopupHostingPresentation.freshnessInterval).contains(Date().timeIntervalSince(checkedAt)) { return }
            await store.fetchEndpointDetails()
        }
    }
}
