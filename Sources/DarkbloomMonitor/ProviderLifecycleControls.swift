import DarkbloomTelemetry
import Foundation
import SwiftUI

struct ProviderLifecycleSourceInput: Equatable {
    let daemonState: SourceAvailability<DaemonState>
    let status: SourceAvailability<StatusSnapshot>
    let controlDaemonState: ProviderControlSourceState?
    let currentTime: Date

    var providerKnownRunning: Bool? {
        let runningEvidenceAt = newestRunningEvidenceAt
        if case .available(let status, let statusCapturedAt) = status,
           let statusValue = Self.runningState(from: status.daemon) {
            if !statusValue,
               let runningEvidenceAt,
               runningEvidenceAt > statusCapturedAt {
                return true
            }
            return statusValue
        }
        return runningEvidenceAt == nil ? nil : true
    }

    private var newestRunningEvidenceAt: Date? {
        var evidence: [Date] = []
        if case .available(_, let capturedAt) = daemonState {
            evidence.append(capturedAt)
        }
        if case .fresh(let evidenceAt) = controlDaemonState?.evaluated(
            at: currentTime,
            invalidReason: "Provider activity timestamp is invalid",
            staleReason: "Provider activity is stale",
            futureReason: "Provider activity timestamp is in the future"
        ) {
            evidence.append(evidenceAt)
        }
        return evidence.max()
    }

    private static func runningState(from daemonStatus: String?) -> Bool? {
        guard let daemonStatus else { return nil }
        let normalized = daemonStatus.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.hasPrefix("running") { return true }
        if normalized.hasPrefix("stopped") || normalized.hasPrefix("not running") { return false }
        return nil
    }
}

struct ProviderLifecyclePresentation: Equatable {
    let canStart: Bool
    let canStop: Bool
    let canRestart: Bool
    let unavailableReason: String?

    static func make(
        sourceInput: ProviderLifecycleSourceInput,
        operation: ProviderOperation,
        enabledModels: [String]
    ) -> Self {
        make(
            providerKnownRunning: sourceInput.providerKnownRunning,
            operation: operation,
            enabledModels: enabledModels
        )
    }

    static func make(
        providerKnownRunning: Bool?,
        operation: ProviderOperation,
        enabledModels: [String]
    ) -> Self {
        guard operation == .idle else {
            return Self(
                canStart: false,
                canStop: false,
                canRestart: false,
                unavailableReason: "Another provider action is in progress"
            )
        }
        guard let providerKnownRunning else {
            return Self(
                canStart: false,
                canStop: false,
                canRestart: false,
                unavailableReason: "Provider state is unavailable"
            )
        }
        if providerKnownRunning {
            guard !enabledModels.isEmpty else {
                return Self(
                    canStart: false,
                    canStop: true,
                    canRestart: false,
                    unavailableReason: "Start requires at least one saved enabled model"
                )
            }
            return Self(
                canStart: false,
                canStop: true,
                canRestart: true,
                unavailableReason: nil
            )
        }
        guard !enabledModels.isEmpty else {
            return Self(
                canStart: false,
                canStop: false,
                canRestart: false,
                unavailableReason: "Start requires at least one saved enabled model"
            )
        }
        return Self(
            canStart: true,
            canStop: false,
            canRestart: false,
            unavailableReason: nil
        )
    }

}

struct ProviderLifecycleUnavailableReasonPresentation: Equatable {
    static let systemImage = "exclamationmark.triangle"
    static let accessibilityIdentifier = "provider.lifecycle.unavailable-reason"
    static let maxWidth: CGFloat = 220

    let message: String
    let systemImage: String
    let accessibilityIdentifier: String

    init(
        message: String,
        systemImage: String = Self.systemImage,
        accessibilityIdentifier: String = Self.accessibilityIdentifier
    ) {
        self.message = message
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
    }

    static func make(
        from presentation: ProviderLifecyclePresentation
    ) -> Self? {
        guard let message = presentation.unavailableReason else { return nil }
        return Self(message: message)
    }
}

struct ProviderLifecycleFeedbackPresentation: Equatable {
    let message: String
    let isError: Bool

    static func make(
        operation: ProviderOperation,
        errorMessage: String?
    ) -> Self? {
        if case .lifecycle(let action) = operation {
            let message = switch action {
            case .start: "Starting provider…"
            case .stop: "Stopping provider…"
            case .restart: "Restarting provider…"
            }
            return Self(message: message, isError: false)
        }
        guard let errorMessage else { return nil }
        return Self(message: errorMessage, isError: true)
    }
}

enum ProviderLifecycleControl: CaseIterable {
    case start
    case stop
    case restart

    var title: String {
        switch self { case .start: "Start"; case .stop: "Stop"; case .restart: "Restart" }
    }

    var progressTitle: String {
        switch self { case .start: "Starting"; case .stop: "Stopping"; case .restart: "Restarting" }
    }

    static func compactControl(running: Bool?, operation: ProviderOperation) -> Self {
        if case .lifecycle(let action) = operation {
            switch action { case .start: return .start; case .stop: return .stop; case .restart: return .restart }
        }
        return running == false ? .start : .stop
    }

    var action: ProviderLifecycleAction {
        switch self {
        case .start: .start
        case .stop: .stop
        case .restart: .restart
        }
    }

    var systemImage: String {
        switch self {
        case .start: "play.fill"
        case .stop: "stop.fill"
        case .restart: "arrow.clockwise"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .start: "Start Darkbloom provider"
        case .stop: "Stop Darkbloom provider"
        case .restart: "Restart Darkbloom provider"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .start: "provider.start"
        case .stop: "provider.stop"
        case .restart: "provider.restart"
        }
    }

    func isActive(in operation: ProviderOperation) -> Bool {
        operation == .lifecycle(action)
    }

    func isEnabled(in presentation: ProviderLifecyclePresentation) -> Bool {
        switch self {
        case .start: presentation.canStart
        case .stop: presentation.canStop
        case .restart: presentation.canRestart
        }
    }
}

struct LifecycleConfirmationPresentation: Equatable {
    let title: String
    let body: String
    let confirmLabel: String

    static func make(_ confirmation: LifecycleConfirmation) -> Self {
        let isStop = confirmation.action == .stop
        let isRestart = confirmation.action == .restart
        let body = switch (confirmation.action, confirmation.risk) {
        case (.stop, .active):
            "Darkbloom will pause new requests, finish accepted requests, and then stop. This may take several minutes."
        case (.stop, .unknown):
            "Activity is unavailable. Darkbloom's native Stop will pause new requests, finish accepted requests, and then stop. This may take several minutes."
        case (.stop, .idle):
            "Darkbloom reports no active customer job. Native Stop will still pause new work before shutting down."
        case (.restart, .active):
            "Darkbloom will pause new requests, finish accepted requests, and then restart with the saved configuration. This may take several minutes."
        case (.restart, .unknown):
            "Activity is unavailable. Darkbloom's native Restart will pause new requests and finish accepted requests when graceful control is available; otherwise it will fail safely without replacing the provider."
        case (.restart, .idle):
            "Darkbloom reports no active customer job. Native Restart still pauses new work before replacing the provider."
        case (.start, _):
            "Darkbloom will start with the saved configuration."
        }
        let confirmLabel = isStop ? "Drain & Stop" : (isRestart ? "Drain & Restart" : "Start")
        if case .restartSelection(_, let comparison) = confirmation {
            let advertised = comparison.advertised.map { $0.joined(separator: ", ") } ?? "not currently verified"
            return Self(title: "Restart applies the saved model selection",
                        body: body + "\n\nAdvertised now: " + advertised
                            + "\nSaved selection: " + comparison.saved.joined(separator: ", ")
                            + "\n\nRestart will apply the saved selection. Unsaved edits are not applied.",
                        confirmLabel: "Restart with Saved Models")
        }
        return Self(
            title: isStop ? "Drain and stop the provider?" : (isRestart ? "Drain and restart the provider?" : "Start the provider?"),
            body: body,
            confirmLabel: confirmLabel
        )
    }
}

extension LifecycleConfirmation: Identifiable {
    var id: ProviderLifecycleAction { action }
}

@MainActor
final class LifecycleConfirmationDismissalCoordinator {
    private var generation: UInt64 = 0
    private var confirmationInProgress = false

    func beginConfirmation() {
        generation &+= 1
        confirmationInProgress = true
    }

    func endConfirmation() {
        confirmationInProgress = false
    }

    @discardableResult
    func scheduleCancellation(
        isPending: @escaping @MainActor () -> Bool,
        cancel: @escaping @MainActor () -> Void
    ) -> Task<Void, Never> {
        generation &+= 1
        let scheduledGeneration = generation
        return Task { @MainActor in
            await Task.yield()
            guard generation == scheduledGeneration,
                  !confirmationInProgress,
                  isPending()
            else { return }
            cancel()
        }
    }
}

@MainActor
struct ProviderLifecycleControls: View {
    @ObservedObject var store: ProviderControlStore
    @State private var dismissalCoordinator = LifecycleConfirmationDismissalCoordinator()
    let snapshot: TelemetrySnapshot
    let currentTime: Date?
    var compact = false
    var commandTile = false

    init(
        store: ProviderControlStore,
        snapshot: TelemetrySnapshot,
        currentTime: Date? = nil,
        compact: Bool = false,
        commandTile: Bool = false
    ) {
        self.store = store
        self.snapshot = snapshot
        self.currentTime = currentTime
        self.compact = compact
        self.commandTile = commandTile
    }

    private func presentation(currentTime: Date) -> ProviderLifecyclePresentation {
        .make(
            sourceInput: ProviderLifecycleSourceInput(
                daemonState: snapshot.state,
                status: snapshot.status,
                controlDaemonState: store.snapshot?.sources.daemon,
                currentTime: currentTime
            ),
            operation: store.operation,
            enabledModels: store.draft?.original.enabled
                ?? store.snapshot?.draft.original.enabled
                ?? []
        )
    }

    var body: some View {
        Group {
            if let currentTime {
                controls(currentTime: currentTime)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let now = Date()
                    controls(currentTime: now)
                }
            }
        }
        .alert(item: confirmation) { confirmation in
            let alert = LifecycleConfirmationPresentation.make(confirmation)
            return Alert(
                title: Text(alert.title),
                message: Text(alert.body),
                primaryButton: .destructive(Text(alert.confirmLabel)) {
                    dismissalCoordinator.beginConfirmation()
                    Task {
                        defer { dismissalCoordinator.endConfirmation() }
                        await store.confirmPendingLifecycle()
                    }
                },
                secondaryButton: .cancel {
                    store.cancelPendingLifecycle()
                }
            )
        }
    }

    private func controls(currentTime: Date) -> some View {
        let presentation = presentation(currentTime: currentTime)
        let running = ProviderLifecycleSourceInput(daemonState: snapshot.state, status: snapshot.status,
            controlDaemonState: store.snapshot?.sources.daemon, currentTime: currentTime).providerKnownRunning
        let compactControl = ProviderLifecycleControl.compactControl(running: running, operation: store.operation)
        return VStack(alignment: .trailing, spacing: 4) {
            if !compact, case .lifecycle(let action) = store.operation {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(action == .stop ? "Stopping…" : action == .restart ? "Restarting…" : "Starting…")
                        .font(.callout.weight(.semibold))
                }
                Text(action == .stop
                    ? "Pausing new requests and draining accepted work. This can take several minutes."
                    : "Waiting for the provider. Models may take a moment to load.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 6) {
                ForEach(compact ? [compactControl] : ProviderLifecycleControl.allCases, id: \.self) { control in
                    Button {
                        Task { await store.request(control.action) }
                    } label: {
                        if commandTile {
                            Label(control.isActive(in: store.operation) ? control.progressTitle : control.title,
                                  systemImage: control.isActive(in: store.operation) ? "hourglass" : control.systemImage)
                        } else {
                            HStack(spacing: 5) {
                                Group {
                                    if control.isActive(in: store.operation) {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: control.systemImage)
                                    }
                                }
                                .frame(width: 14, height: 14)
                                if compact {
                                    Text(control.isActive(in: store.operation) ? control.progressTitle : control.title)
                                        .font(.caption.weight(.medium))
                                }
                            }
                        }
                    }
                    .buttonStyle(PopupAdaptiveCommandButtonStyle(commandTile: commandTile))
                    .controlSize(.small)
                    .disabled(!control.isEnabled(in: presentation))
                    .help(presentation.unavailableReason ?? control.accessibilityLabel)
                    .accessibilityLabel(control.accessibilityLabel)
                    .accessibilityHint(presentation.unavailableReason ?? "")
                    .accessibilityIdentifier(control.accessibilityIdentifier)
                    .modifier(PopupKeyboardReveal())
                }
            }

            if !compact, store.operation == .idle, let reason = ProviderLifecycleUnavailableReasonPresentation.make(
                from: presentation
            ) {
                Label(reason.message, systemImage: reason.systemImage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.8)
                    .frame(
                        maxWidth: ProviderLifecycleUnavailableReasonPresentation.maxWidth,
                        alignment: .trailing
                    )
                    .help(reason.message)
                    .accessibilityLabel(reason.message)
                    .accessibilityIdentifier(reason.accessibilityIdentifier)
            }

        }
        .frame(
            maxWidth: compact ? nil : ProviderLifecycleUnavailableReasonPresentation.maxWidth,
            alignment: .trailing
        )
    }

    private var confirmation: Binding<LifecycleConfirmation?> {
        Binding(
            get: { store.pendingConfirmation },
            set: { confirmation in
                guard confirmation == nil else { return }
                dismissalCoordinator.scheduleCancellation(
                    isPending: { store.pendingConfirmation != nil },
                    cancel: { store.cancelPendingLifecycle() }
                )
            }
        )
    }
}
