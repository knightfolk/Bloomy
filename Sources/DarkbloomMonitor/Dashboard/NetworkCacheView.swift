import DarkbloomTelemetry
import SwiftUI

@MainActor
final class NetworkCacheStore: ObservableObject {
    @Published private(set) var source: SourceAvailability<NetworkCacheSnapshot> = .unavailable(reason: "Waiting for network cache health")
    private let client: any NetworkCacheFetching
    private let sleep: @Sendable (Duration) async throws -> Void
    private var refreshTask: Task<Void, Never>?
    private var failures = 0
    init(client: any NetworkCacheFetching = NetworkCacheClient()) {
        self.client = client
        sleep = { try await Task.sleep(for: $0) }
    }

    init(client: any NetworkCacheFetching, sleep: @escaping @Sendable (Duration) async throws -> Void) {
        self.client = client
        self.sleep = sleep
    }

    func refresh() async {
        guard refreshTask == nil, !Task.isCancelled else { return }
        let task = Task { await performRefresh() }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func performRefresh() async {
        // Clear ownership before the task completes, so a joining observer can
        // immediately start its own read rather than see an obsolete busy flag.
        defer { refreshTask = nil }
        guard !Task.isCancelled else { return }
        do {
            let value = try await client.fetch(at: Date())
            try Task.checkCancellation()
            guard value.isFresh(at: Date()) else { throw NetworkCapacityError.invalidResponse }
            source = .available(value: value, capturedAt: value.capturedAt)
            failures = 0
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            failures = min(failures + 1, 4)
            if let value = source.value {
                source = .stale(value: value, capturedAt: value.capturedAt, reason: "Network cache refresh failed")
            } else {
                source = .unavailable(reason: "Network cache health is unavailable")
            }
        }
    }

    func observeWhileVisible() async {
        // A hidden surface may have cancelled a transport that is still
        // unwinding. Join that read before taking the restored surface's read.
        if let previous = refreshTask, previous.isCancelled { await previous.value }
        while !Task.isCancelled {
            await refresh()
            guard !Task.isCancelled else { return }
            do { try await sleep(.seconds(60 * pow(2, Double(failures)))) }
            catch { return }
        }
    }
}

struct NetworkCacheView: View {
    let isVisible: Bool
    @StateObject private var store = NetworkCacheStore()
    var body: some View {
        TimelineView(VisibilityTimelineSchedule(base: .periodic(from: .now, by: 10), isVisible: isVisible)) { _ in
            let now = Date()
            VStack(alignment: .leading, spacing: 8) {
                Label("Network cache health", systemImage: "externaldrive.connected.to.line.below").font(.headline)
                if let value = store.source.value {
                    let current = isCurrent(value, at: now)
                    HStack(spacing: 20) {
                        Text("Cache routing: \(value.routingMode.rawValue)")
                        if let ready = value.plannerReady {
                            Text(ready ? "Planner ready" : "Planner not ready")
                        }
                        if !current { Text("Last known · stale").foregroundStyle(.orange) }
                    }
                    .font(.callout)
                } else {
                    Text("Network cache health is unavailable").font(.callout).foregroundStyle(.secondary)
                }
                Text("Across the Darkbloom network. This does not measure this Mac's cache hits, disk use, or earnings.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
        }
        .task(id: isVisible) {
            if isVisible { await store.observeWhileVisible() }
        }
    }
    private func isCurrent(_ value: NetworkCacheSnapshot, at now: Date) -> Bool {
        if case .available = store.source { return value.isFresh(at: now) }
        return false
    }
}
