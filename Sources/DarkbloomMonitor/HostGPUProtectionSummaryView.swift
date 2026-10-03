import SwiftUI

struct HostGPUProtectionSummaryView: View {
    @ObservedObject var protection: HostGPUProtectionStore
    var slowdownWarning: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if [.warning, .pausing, .paused, .resuming, .error].contains(protection.phase) {
                Label(protection.status, systemImage: protection.isHoldingProvider ? "pause.circle" : "exclamationmark.triangle")
                    .accessibilityIdentifier("gpuProtection.attention")
            }
            if let slowdownWarning {
                Label(slowdownWarning, systemImage: "speedometer")
                    .accessibilityIdentifier("gpuProtection.slowdown")
            }
        }
        .font(.caption).foregroundStyle(.orange)
        .fixedSize(horizontal: false, vertical: true)
    }
}
