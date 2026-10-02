import DarkbloomTelemetry
import SwiftUI

/// Own this store with the monitor and call `start()`/`stop()` with the app
/// lifecycle. `start()` also performs the initial read-only check and then
/// polls infrequently; no update is installed or restarted automatically.
@MainActor
final class CLIUpdateStatusStore: ObservableObject {
    static let shared = CLIUpdateStatusStore()

    @Published private(set) var status: SourceAvailability<CLIUpdateStatus> = .unavailable(
        reason: "Darkbloom CLI update status has not been checked"
    )
    @Published private(set) var isRefreshing = false

    private let client: any CLIUpdateProviding
    private let pollingInterval: Duration
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        policy: DarkbloomSourcePolicy = .currentUser,
        runner: any ProcessExecuting = CappedProcessRunner(),
        pollingInterval: Duration = .seconds(6 * 60 * 60)
    ) {
        self.client = CLIUpdateClient(policy: policy, runner: runner)
        self.pollingInterval = pollingInterval
    }

    init(
        client: any CLIUpdateProviding,
        pollingInterval: Duration = .seconds(6 * 60 * 60)
    ) {
        self.client = client
        self.pollingInterval = pollingInterval
    }

    func refresh() async {
        if let refreshTask {
            await withTaskCancellationHandler {
                await refreshTask.value
            } onCancel: {
                refreshTask.cancel()
            }
            return
        }

        isRefreshing = true
        generation &+= 1
        let refreshGeneration = generation
        let client = self.client
        let task = Task { @MainActor [weak self] in
            let refreshed = await client.checkForUpdate()
            guard let self,
                  !Task.isCancelled,
                  self.generation == refreshGeneration
            else {
                return
            }
            self.status = Self.merge(refreshed, with: self.status)
        }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if generation == refreshGeneration {
            refreshTask = nil
            isRefreshing = false
        }
    }

    /// Start one immediate check, followed by read-only checks every six hours.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.pollingInterval)
                } catch {
                    return
                }
                await self.refresh()
            }
        }
    }

    func stop() async {
        let polling = pollingTask
        polling?.cancel()
        let refresh = refreshTask
        refresh?.cancel()
        await polling?.value
        await refresh?.value
        pollingTask = nil
        refreshTask = nil
        isRefreshing = false
    }

    private static func merge(
        _ refreshed: SourceAvailability<CLIUpdateStatus>,
        with previous: SourceAvailability<CLIUpdateStatus>
    ) -> SourceAvailability<CLIUpdateStatus> {
        switch refreshed {
        case .available, .stale:
            return refreshed
        case .unavailable(let reason):
            switch previous {
            case .available(let value, let capturedAt), .stale(let value, let capturedAt, _):
                return .stale(value: value, capturedAt: capturedAt, reason: reason)
            case .unavailable:
                return refreshed
            }
        }
    }
}

struct CLIUpdateNoticePresentation: Equatable {
    let headline: String
    let explanation: String
    let guidance: String?
    let symbol: String
    let isStale: Bool

    var detail: String { [explanation, guidance].compactMap { $0 }.joined(separator: " ") }

    static func checkedAtLabel(_ date: Date) -> String {
        "Last checked \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func make(status: CLIUpdateStatus, isStale: Bool) -> Self {
        switch status {
        case .upToDate(let version):
            return Self(
                headline: isStale ? "Last check: Darkbloom CLI was up to date" : "Darkbloom CLI is up to date",
                explanation: isStale ? "Version \(version) was current at that check." : "Version \(version) is current.",
                guidance: nil, symbol: "checkmark.circle", isStale: isStale)
        case .updateAvailable(let current, let latest):
            return Self(
                headline: isStale ? "Last check: Darkbloom CLI update was available" : "Darkbloom CLI update available",
                explanation: isStale
                    ? "Version \(latest) was available; the CLI reported \(current) at that check."
                    : "Version \(latest) is available; the current CLI reports \(current).",
                guidance: isStale ? nil : "Review the update in Darkbloom when ready.",
                symbol: "arrow.down.circle", isStale: isStale)
        case .restartRequired(let current, let installed):
            return Self(
                headline: isStale ? "Last check: Darkbloom CLI needed a restart" : "Darkbloom CLI restart required",
                explanation: isStale
                    ? "Version \(installed) was installed, while the CLI process reported \(current) at that check."
                    : "Version \(installed) is installed, while the current CLI process is \(current).",
                guidance: isStale ? nil : "Restart Darkbloom to activate it.",
                symbol: "arrow.clockwise.circle", isStale: isStale)
        case .quarantined(let version):
            return Self(
                headline: isStale ? "Last check: Darkbloom release was quarantined" : "Darkbloom release quarantined",
                explanation: isStale
                    ? "Darkbloom reported release \(version) was quarantined on this machine at that check. No change was made."
                    : "Darkbloom reports release \(version) is quarantined on this machine. No change was made.",
                guidance: nil, symbol: "exclamationmark.triangle", isStale: isStale)
        }
    }
}

/// Read-only CLI update information for inclusion as a section in a SwiftUI
/// Form. Parent app lifecycle code should start and stop the shared store; this
/// view starts it as a fallback when used on its own.
struct CLIUpdateNoticeView: View {
    @ObservedObject var store: CLIUpdateStatusStore

    init(store: CLIUpdateStatusStore = .shared) {
        self.store = store
    }

    var body: some View {
        Section("Darkbloom CLI · Update notices only") {
            statusContent
            Text("Bloomy checks for newer CLI releases but never installs them.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Spacer()
                if store.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Checking for Darkbloom CLI updates")
                }
                Button(store.isRefreshing ? "Checking…" : "Check for updates") {
                    Task { await store.refresh() }
                }
                .disabled(store.isRefreshing)
                .accessibilityIdentifier("settings.cli-update.check")
            }
        }
        .task { store.start() }
    }

    @ViewBuilder
    private var statusContent: some View {
        switch store.status {
        case .available(let value, let capturedAt):
            notice(for: value, checkedAt: capturedAt, isStale: false)
        case .stale(let value, let capturedAt, _):
            notice(for: value, checkedAt: capturedAt, isStale: true)
        case .unavailable:
            VStack(alignment: .leading, spacing: 4) {
                Label("Could not check for CLI updates", systemImage: "questionmark.circle")
                    .font(.headline)
                Text("No update status is available. Try checking again.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func notice(
        for value: CLIUpdateStatus,
        checkedAt: Date,
        isStale: Bool
    ) -> some View {
        let presentation = CLIUpdateNoticePresentation.make(status: value, isStale: isStale)
        VStack(alignment: .leading, spacing: 4) {
            Label(presentation.headline, systemImage: presentation.symbol)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if presentation.isStale {
                Text("The latest check failed. This status may have changed.")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(CLIUpdateNoticePresentation.checkedAtLabel(checkedAt))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
