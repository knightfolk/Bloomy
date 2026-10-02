import DarkbloomTelemetry
import SwiftUI

/// Configuration consent and observed control are deliberately separate states.
struct ProviderAutopilotPresentation {
    let status: ProviderAutopilotStatus?
    let isFresh: Bool
    let transitions: [Date]

    init(source: SourceAvailability<ProviderAutopilotStatus>?, at date: Date) {
        status = source?.value
        isFresh = ProviderSettingsFreshnessPolicy.isFresh(source, at: date)
        transitions = ProviderSettingsFreshnessPolicy.transitions(for: source, at: date)
    }

    var stateTitle: String {
        let title: String
        guard let status else { return "Status unavailable" }
        if !status.configuredEnabled {
            title = acceptedWorkMayBeFinishing ? "Leaving Autopilot" : "Off"
        } else if !status.isEnrolled {
            title = "Setup incomplete"
        } else if !status.isLiveConfirmed {
            title = "Enrolled · awaiting confirmation"
        } else if status.configuredPaused {
            title = status.live?.paused == true ? "Paused" : "Pause requested"
        } else if status.live?.paused == true {
            title = "Resume requested"
        } else if status.isActivelyManaging && status.phase == .active {
            title = "Actively managing"
        } else if status.live?.observeOnly == true && status.phase == .shadow {
            title = "Observing · shadow mode"
        } else {
            switch status.phase {
            case .waitingInventory: title = "Waiting for inventory"
            case .waiting: title = "Waiting for coordinator"
            case .transitioning: title = "Changing models"
            case .recovering: title = "Recovering"
            default: title = "Enrolled · mode unconfirmed"
            }
        }
        return isFresh ? title : "Last known: \(title)"
    }

    var explanation: String {
        guard isFresh else { return "Refresh to check Autopilot before changing it." }
        guard let status else { return "Autopilot status could not be checked. Use a supported provider version and refresh." }
        if !status.configuredEnabled {
            return acceptedWorkMayBeFinishing
                ? "Leaving is saved. An accepted model change may still finish."
                : "Let the network choose among cached models to improve utilization. Enrollment is optional."
        }
        if !status.isEnrolled { return "Saved setup is incomplete. Enable Autopilot again to record consent and verify cached models." }
        if !status.isLiveConfirmed { return "Enrollment is saved; the running provider has not confirmed these settings." }
        if !status.configuredPaused && status.live?.paused == true {
            return "Resume is saved; the provider still reports a pause. Live control remains the coordinator’s decision."
        }
        if status.configuredPaused {
            return "Pause stops new automatic choices. An accepted change may still finish, and retired models may unload."
        }
        if status.isActivelyManaging && status.phase == .active {
            return "The coordinator is controlling model choices within the provider’s memory and slot limits."
        }
        if status.live?.observeOnly == true && status.phase == .shadow {
            return "Proposed changes are recorded only. The coordinator decides when live control becomes available."
        }
        return "Enrollment does not guarantee live control. The provider is waiting or completing a transition."
    }

    private var acceptedWorkMayBeFinishing: Bool {
        status?.live != nil && (status?.live?.active == true
            || status?.phase == .transitioning || status?.phase == .recovering)
    }
    var canEnroll: Bool {
        isFresh && status != nil && status?.isEnrolled == false && !acceptedWorkMayBeFinishing
    }
    func canPerform(_ action: ProviderAutopilotPolicyAction) -> Bool {
        isFresh && status?.allows(action) == true
    }
}

struct ProviderAutopilotSettingsView: View {
    @ObservedObject var store: ProviderExtrasStore
    @ObservedObject var control: ProviderControlStore
    let performMutation: ProviderExtrasMutationExecutor
    let isVisible: Bool
    @ObservedObject var draft: ProviderSettingsDraftState
    @State private var showsConsent = false
    @State private var showsLeaveConfirmation = false
    @State private var isSubmitting = false
    @State private var feedback: String?
    @State private var consentIssue: String?

    private var evidence: ProviderAutopilotPresentation {
        .init(source: store.snapshot?.autopilotStatus, at: store.currentDate)
    }
    private var isBusy: Bool { isSubmitting || store.mutationInFlight || control.operation != .idle }
    var hasUnsavedSettings: Bool { draft.hasChanges }
    var enrollmentReason: String? {
        hasUnsavedSettings ? "Save or discard your provider settings edits first."
            : control.autopilotEnrollmentUnavailableReason
    }

    var body: some View {
        Section("Autopilot · Experimental") {
            TimelineView(VisibilityTimelineSchedule(base: .explicit(evidence.transitions), isVisible: isVisible)) { context in
                content(at: context.date)
            }
            if let feedback {
                Text(feedback).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if feedback == nil, store.snapshot?.autopilotStatus?.value?.isEnrolled == true,
               let message = control.autopilotEnrollmentMessage {
                Text(message).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $showsConsent) { consentSheet }
        .alert("Leave Autopilot?", isPresented: $showsLeaveConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Leave Autopilot") { submit(.disable) }
        } message: {
            Text("This removes enrollment and restores ordinary provider behavior. An accepted model change may still finish. You can opt in again from Bloomy.")
        }
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        let presentation = ProviderAutopilotPresentation(source: store.snapshot?.autopilotStatus, at: date)
        VStack(alignment: .leading, spacing: 10) {
            Label(presentation.stateTitle, systemImage: "sparkles")
                .font(.headline)
                .accessibilityIdentifier("settings.autopilot.status")
            Text(presentation.explanation).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ViewThatFits(in: .horizontal) {
                actions(presentation).fixedSize(horizontal: true, vertical: false)
                actions(presentation, vertical: true)
            }
            if hasUnsavedSettings {
                Text("Save or discard your provider settings edits before changing Autopilot.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if presentation.canEnroll, let reason = enrollmentReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 4)
    }

    private func actions(_ presentation: ProviderAutopilotPresentation, vertical: Bool = false) -> some View {
        let layout = vertical ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            if presentation.status?.isEnrolled == true {
                let action: ProviderAutopilotPolicyAction = presentation.status?.configuredPaused == true ? .resume : .pause
                Button(action == .pause ? "Pause Autopilot" : "Resume Autopilot") { submit(action) }
                    .disabled(isBusy || hasUnsavedSettings || !presentation.canPerform(action))
                    .accessibilityIdentifier("settings.autopilot.pauseResume")
            } else {
                Button("Enable Autopilot…") { feedback = nil; consentIssue = nil; showsConsent = true }
                    .disabled(isBusy || !presentation.canEnroll || enrollmentReason != nil)
                    .accessibilityIdentifier("settings.autopilot.enable")
            }
            if presentation.status?.configuredEnabled == true {
                Button("Leave Autopilot…") { showsLeaveConfirmation = true }
                    .disabled(isBusy || hasUnsavedSettings || !presentation.canPerform(.disable))
                    .accessibilityIdentifier("settings.autopilot.leave")
            }
            Button("Refresh Autopilot") { Task { await store.refreshAutopilot() } }
                .disabled(isBusy || store.isRefreshing)
                .accessibilityIdentifier("settings.autopilot.refresh")
        }
    }

    private var consentSheet: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Label("Enable experimental Autopilot", systemImage: "sparkles")
                        .font(.title2.bold())
                    Text("Opt in to let Darkbloom report downloaded network models and choose among those cached models when live control is available.")
                    Label("Shadow mode records proposals. Enrollment does not activate live control.", systemImage: "eye")
                    Label("Downloaded files stay on disk. Your startup selection, memory, schedule, hosting and slot settings are preserved.", systemImage: "internaldrive")
                    Label("Bloomy checks cached models and restarts the provider once. Accepted requests can finish first.", systemImage: "arrow.triangle.2.circlepath")
                    Text("You can pause or leave Autopilot in these settings at any time.")
                        .foregroundStyle(.secondary)
                    if let consentIssue { Text(consentIssue).foregroundStyle(.orange) }
                    if let reason = enrollmentReason {
                        Text(reason).foregroundStyle(.orange)
                    } else if !evidence.canEnroll {
                        Text("Autopilot status changed. Refresh and review it before enabling.")
                            .foregroundStyle(.orange)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(24)
            }
            Divider()
            HStack {
                Button("Cancel") { showsConsent = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Enable Autopilot") { enroll() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBusy || !evidence.canEnroll || enrollmentReason != nil)
                    .accessibilityIdentifier("settings.autopilot.consent.enable")
            }
            .padding(16)
        }
        .frame(width: 480, height: 460)
        .accessibilityIdentifier("settings.autopilot.consent")
    }

    private func enroll() {
        guard !isBusy, evidence.canEnroll, enrollmentReason == nil else {
            consentIssue = enrollmentReason ?? "Autopilot status changed. Refresh and review it before enabling."
            return
        }
        showsConsent = false
        isSubmitting = true
        feedback = nil
        Task { @MainActor in
            let confirmed = await control.enrollAutopilot()
            await store.refreshAutopilot()
            isSubmitting = false
            if !confirmed && control.autopilotEnrollmentMessage == nil {
                feedback = control.errorMessage
                    ?? "Autopilot could not be confirmed. Refresh to check the saved and running state."
            }
        }
    }

    private func submit(_ action: ProviderAutopilotPolicyAction) {
        guard !isBusy, !hasUnsavedSettings, evidence.canPerform(action) else { return }
        isSubmitting = true
        feedback = nil
        Task { @MainActor in
            let confirmed = await performMutation("Autopilot \(action.rawValue)") {
                try await store.setAutopilotPolicy(action)
            }
            isSubmitting = false
            if confirmed {
                feedback = switch action {
                case .pause: "Pause saved. An accepted change may still finish."
                case .resume: "Resume saved. Live control remains the coordinator’s decision."
                case .disable: "Leaving is saved. Check the status above for any remaining transition."
                }
            } else {
                feedback = "The change could not be confirmed. Refresh Autopilot before trying again."
            }
        }
    }
}
