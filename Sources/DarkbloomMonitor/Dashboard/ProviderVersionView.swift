import DarkbloomTelemetry
import SwiftUI

struct ProviderVersionView: View {
    let snapshot: TelemetrySnapshot
    let now: Date
    var body: some View {
        let installed = installedVersion
        let reported = reportedVersion
        VStack(alignment: .leading, spacing: 8) {
            Text("Provider version").font(.headline)
            if installed != nil || reported != nil {
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                    if let installed {
                        versionRow("Installed CLI", value: installed)
                    }
                    if let reported {
                        versionRow("Daemon snapshot", value: reported)
                    }
                }
                if let installed, let reported, installed != reported {
                    Label("CLI and daemon snapshot versions differ", systemImage: "arrow.clockwise")
                        .font(.caption).foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Current version details unavailable")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func versionRow(_ title: String, value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private var installedVersion: String? {
        guard case .available(let status, let capturedAt) = snapshot.status,
              (0...60).contains(now.timeIntervalSince(capturedAt)) else { return nil }
        return status.version
    }
    private var reportedVersion: String? {
        guard case .available(let state, _) = snapshot.state,
              (0...10).contains(now.timeIntervalSince1970 - state.writtenAt) else { return nil }
        return state.version
    }
}
