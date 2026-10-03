import DarkbloomTelemetry
import SwiftUI

struct HostGPUProtectionSettingsView: View {
    @ObservedObject var store: HostGPUProtectionStore
    var slowdownWarning: String?

    var body: some View {
        Section("Host GPU protection") {
            Picker("When GPU use stays high while idle", selection: setting(\.mode)) {
                Text("Off").tag(HostGPUProtectionMode.off)
                Text("Warn").tag(HostGPUProtectionMode.warn)
                Text("Automatically pause").tag(HostGPUProtectionMode.automaticPause)
            }
            .accessibilityIdentifier("gpuProtection.mode")
            if store.settings.mode != .off {
                percent("GPU ceiling", value: \.ceilingPercent, range: 10...100)
                seconds("Time above ceiling", value: \.breachSeconds, range: 3...600)
                if store.settings.mode == .automaticPause {
                    percent("Resume below", value: \.resumePercent,
                        range: 0...max(0, store.settings.ceilingPercent - 1))
                    seconds("Recovery time", value: \.recoverySeconds, range: 3...3_600)
                    seconds("Minimum pause", value: \.minimumPausedSeconds, range: 0...3_600)
                }
                percent("Speed warning below model baseline", value: \.throughputFloorPercent, range: 10...90)
                seconds("Slowdown warning time", value: \.slowdownSeconds, range: 15...600)
            }
            Label(store.status, systemImage: store.phase == .warning || store.phase == .error
                ? "exclamationmark.triangle" : "cpu")
                .font(.callout)
                .foregroundStyle(store.phase == .warning || store.phase == .error ? Color.orange : Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("gpuProtection.status")
            if let slowdownWarning {
                Label(slowdownWarning, systemImage: "speedometer")
                    .font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if store.phase == .error {
                Button("Retry protection") { store.retry() }
            }
            Text("Uses whole-Mac GPU readings while inference is idle; it cannot identify which app is using the GPU. Speed warnings compare the same model’s recorded baseline and do not interrupt accepted work.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if store.settings.mode == .automaticPause {
                Text("Pause drains and stops the provider. Recovery restarts only Bloomy’s own stop with unchanged settings; models may reload. Manual actions, turning protection off, or quitting Bloomy end automatic restart ownership.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func setting<T>(_ key: WritableKeyPath<HostGPUProtectionSettings, T>) -> Binding<T> {
        Binding(get: { store.settings[keyPath: key] }, set: { value in
            var settings = store.settings
            settings[keyPath: key] = value
            if settings.resumePercent >= settings.ceilingPercent {
                settings.resumePercent = max(0, settings.ceilingPercent - 10)
            }
            store.updateSettings(settings)
        })
    }

    private func percent(_ title: String, value: WritableKeyPath<HostGPUProtectionSettings, Double>, range: ClosedRange<Double>) -> some View {
        Stepper(value: setting(value), in: range, step: 1) {
            LabeledContent(title, value: "\(Int(store.settings[keyPath: value]))%")
                .monospacedDigit()
        }
    }

    private func seconds(_ title: String, value: WritableKeyPath<HostGPUProtectionSettings, Double>, range: ClosedRange<Double>) -> some View {
        Stepper(value: setting(value), in: range, step: 3) {
            LabeledContent(title, value: "\(Int(store.settings[keyPath: value])) sec")
                .monospacedDigit()
        }
    }
}
