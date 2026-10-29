import DarkbloomTelemetry
import SwiftUI

struct ProviderScheduleSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    let isVisible: Bool

    var body: some View {
        Section("Availability schedule") {
            TimelineView(VisibilityTimelineSchedule(
                base: .explicit(ProviderSettingsFreshnessPolicy.transitions(for: store.scheduleStatus, at: store.currentDate)),
                isVisible: isVisible
            )) { context in
                content(at: context.date)
            }
            Button("Refresh schedule") { Task { await store.refreshSchedule() } }
                .disabled(store.scheduleRefreshing)
            Text("Saved settings apply after the provider restarts. Times use this Mac’s local time zone: \(TimeZone.current.identifier).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .task { await store.refreshSchedule() }
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        if let source = store.scheduleStatus, let schedule = source.value {
            let fresh = ProviderSettingsFreshnessPolicy.isFresh(source, at: date)
            Text((fresh ? "Saved: " : "Last known: ") + (schedule.enabled ? "Scheduled availability" : "Always available while running"))
                .font(.callout)
                .accessibilityIdentifier("settings.schedule.status")
            if !schedule.windows.isEmpty {
                if !schedule.enabled { Text("Saved windows are off.").font(.caption).foregroundStyle(.secondary) }
                ForEach(Array(schedule.windows.enumerated()), id: \.offset) { _, window in
                    Text("\(days(window.days)) · \(window.start)–\(window.end)\(window.end <= window.start ? " · ends next day" : "")")
                        .font(.callout).fixedSize(horizontal: false, vertical: true)
                }
            }
        } else {
            Text("Saved schedule could not be read. Refresh or check it in Darkbloom.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private func days(_ values: Set<ProviderScheduleDay>) -> String {
        ProviderScheduleDay.allCases.filter { values.contains($0) }
            .map { $0.rawValue.capitalized }.joined(separator: ", ")
    }
}
