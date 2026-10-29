import DarkbloomTelemetry
import SwiftUI

struct ProviderScheduleSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    @ObservedObject var draft: ProviderSettingsDraftState
    let performMutation: ProviderExtrasMutationExecutor
    let isVisible: Bool
    @State private var submitting = false
    @State private var feedback: String?

    var body: some View {
        Section("Availability schedule") {
            TimelineView(VisibilityTimelineSchedule(
                base: .explicit(ProviderSettingsFreshnessPolicy.transitions(for: store.scheduleStatus, at: store.currentDate)),
                isVisible: isVisible
            )) { context in
                content(at: context.date)
            }
            HStack {
                Button("Edit schedule…") {
                    guard let expected = store.scheduleStatus?.value else { return }
                    draft.scheduleEdit = expected.schedule
                    draft.scheduleExpected = expected
                    feedback = nil
                }
                .disabled(!ProviderSettingsFreshnessPolicy.isFresh(store.scheduleStatus, at: store.currentDate) || store.scheduleRefreshing || store.mutationInFlight || draft.hasChanges)
                .accessibilityIdentifier("settings.schedule.edit")
                Button("Refresh schedule") { Task { await store.refreshSchedule() } }
                    .disabled(store.scheduleRefreshing || submitting)
            }
            Text("Saved settings apply after the provider restarts. Times use this Mac’s local time zone: \(TimeZone.current.identifier).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
        }
        .task { await store.refreshSchedule() }
        .sheet(isPresented: Binding(get: { draft.scheduleExpected != nil }, set: { if !$0 && !draft.scheduleDirty && !submitting { draft.scheduleExpected = nil } })) { editor }
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        if let source = store.scheduleStatus, let schedule = source.value?.schedule {
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

    private var editor: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Availability schedule").font(.title2.bold())
            Toggle("Use a weekly schedule", isOn: $draft.scheduleEdit.enabled).disabled(submitting)
            Text("Times use \(TimeZone.current.identifier). A window ending at or before its start continues into the next day; equal times cover 24 hours.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(draft.scheduleEdit.windows.indices, id: \.self) { index in
                        windowEditor(index)
                    }
                    Button("Add window") {
                        draft.scheduleEdit.windows.append(.init(days: [.monday], start: "09:00", end: "17:00"))
                    }.disabled(submitting || draft.scheduleEdit.windows.count >= 14)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if !draft.scheduleEdit.isValidForEditing {
                Text("Choose at least one day per window and enter times as HH:MM. An enabled schedule needs a window.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if !ProviderSettingsFreshnessPolicy.isFresh(store.scheduleStatus, at: store.currentDate) {
                Button("Refresh schedule") { Task { await store.refreshSchedule() } }
                    .disabled(store.scheduleRefreshing || submitting)
            } else if store.scheduleStatus?.value != draft.scheduleExpected {
                Text("The saved configuration changed. Copy any edits you need, then cancel and reopen the editor.")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Cancel") { draft.scheduleExpected = nil }.keyboardShortcut(.cancelAction).disabled(submitting)
                Spacer()
                Button("Save schedule") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(submitting || !draft.scheduleDirty || !draft.scheduleEdit.isValidForEditing || draft.hasOtherChangesForSchedule || !ProviderSettingsFreshnessPolicy.isFresh(store.scheduleStatus, at: store.currentDate) || store.scheduleStatus?.value != draft.scheduleExpected)
            }
        }
        .padding(24).frame(width: 540, height: 520)
        .interactiveDismissDisabled(draft.scheduleDirty || submitting)
        .accessibilityIdentifier("settings.schedule.editor")
    }

    private func windowEditor(_ index: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Window \(index + 1)").font(.headline)
                Spacer()
                Button("Remove") { draft.scheduleEdit.windows.remove(at: index) }.disabled(submitting)
            }
            HStack {
                ForEach(ProviderScheduleDay.allCases, id: \.self) { day in
                    Toggle(day.rawValue.capitalized, isOn: Binding(
                        get: { draft.scheduleEdit.windows.indices.contains(index) && draft.scheduleEdit.windows[index].days.contains(day) },
                        set: { selected in
                            guard draft.scheduleEdit.windows.indices.contains(index) else { return }
                            if selected { draft.scheduleEdit.windows[index].days.insert(day) }
                            else { draft.scheduleEdit.windows[index].days.remove(day) }
                        }))
                        .toggleStyle(.button).disabled(submitting)
                }
            }
            HStack {
                Text("From")
                TextField("HH:MM", text: timeBinding(index, start: true)).frame(width: 70)
                    .accessibilityLabel("Window \(index + 1) start time")
                Text("to")
                TextField("HH:MM", text: timeBinding(index, start: false)).frame(width: 70)
                    .accessibilityLabel("Window \(index + 1) end time")
            }.disabled(submitting)
        }.padding(10).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }

    private func timeBinding(_ index: Int, start: Bool) -> Binding<String> {
        Binding(get: {
            guard draft.scheduleEdit.windows.indices.contains(index) else { return "" }
            return start ? draft.scheduleEdit.windows[index].start : draft.scheduleEdit.windows[index].end
        }, set: { value in
            guard draft.scheduleEdit.windows.indices.contains(index) else { return }
            if start { draft.scheduleEdit.windows[index].start = value }
            else { draft.scheduleEdit.windows[index].end = value }
        })
    }

    private func submit() {
        guard let expected = draft.scheduleExpected, !submitting, draft.scheduleDirty,
              draft.scheduleEdit.isValidForEditing, !draft.hasOtherChangesForSchedule else { return }
        guard ProviderSettingsFreshnessPolicy.isFresh(store.scheduleStatus, at: store.currentDate) else {
            feedback = "Refresh the saved schedule before saving your edits."
            return
        }
        guard store.scheduleStatus?.value == expected else {
            feedback = "The saved configuration changed. Copy any edits you need, then cancel and reopen the editor."
            return
        }
        let desired = draft.scheduleEdit
        submitting = true; feedback = nil
        Task { @MainActor in
            let confirmed = await performMutation("availability schedule") {
                try await store.saveSchedule(expected: expected, desired: desired)
            }
            submitting = false
            if confirmed { draft.scheduleExpected = nil }
            feedback = confirmed ? "Schedule saved. Restart the provider to apply it."
                : "Schedule could not be confirmed. Your edits remain here; refresh and reopen if settings changed elsewhere."
        }
    }
}
