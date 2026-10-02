import DarkbloomTelemetry
import Foundation
import SwiftUI

/// A parent-owned serial mutation closure used by settings surfaces. The
/// closure receives a stable label for logging/coordination and a single
/// operation that may call the extras client. It returns false when the parent
/// refuses or cannot confirm the operation.
typealias ProviderExtrasMutationExecutor = @MainActor @Sendable (
    _ label: String,
    _ operation: @escaping @Sendable () async throws -> Void
) async -> Bool

@MainActor
final class ProviderExtrasStore: ObservableObject {
    @Published private(set) var snapshot: ProviderExtrasSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var mutationInFlight = false
    @Published private(set) var errorMessage: String?

    private let client: any ProviderExtrasProviding
    private let pollingInterval: Duration
    private let staticVerificationInterval: TimeInterval
    private let visibleFanPollingInterval: Duration
    private let now: @Sendable () -> Date
    private var lastStaticRefreshAt: Date?
    private var visibleFanSubscribers: Set<UUID> = []
    private var visibleFanPollingTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var refreshIncludesStatic = false

    var visibleFanSubscriberCount: Int { visibleFanSubscribers.count }

    /// Production initializer. It resolves only the approved Darkbloom CLI
    /// candidates from the shared source policy and performs read-only polling
    /// until a caller explicitly invokes a mutation method.
    init(
        policy: DarkbloomSourcePolicy = .currentUser,
        runner: any ProcessExecuting = CappedProcessRunner(),
        pollingInterval: Duration = .seconds(30),
        staticVerificationInterval: TimeInterval = 300,
        visibleFanPollingInterval: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = ProviderExtrasClient(policy: policy, runner: runner)
        self.pollingInterval = pollingInterval
        self.staticVerificationInterval = staticVerificationInterval
        self.visibleFanPollingInterval = visibleFanPollingInterval
        self.now = now
    }

    init(
        client: any ProviderExtrasProviding,
        pollingInterval: Duration = .seconds(30),
        staticVerificationInterval: TimeInterval = 300,
        visibleFanPollingInterval: Duration = .seconds(2),
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.client = client
        self.pollingInterval = pollingInterval
        self.staticVerificationInterval = staticVerificationInterval
        self.visibleFanPollingInterval = visibleFanPollingInterval
        self.now = now
    }

    func refresh() async {
        await refresh(force: false)
    }

    /// Fan sensors stay fresh for the menu bar while static configuration is
    /// verified less often. An explicit refresh or mutation still reads all sources.
    func refreshBackground() async {
        guard !mutationInFlight else { return }
        let age = lastStaticRefreshAt.map { now().timeIntervalSince($0) }
        let verificationDue = age.map { !$0.isFinite || $0 < 0 || $0 >= staticVerificationInterval } ?? true
        if snapshot == nil || verificationDue || staticSourcesNeedRetry {
            await refresh()
        } else if visibleFanSubscribers.isEmpty {
            await refreshFan()
        }
    }

    private var staticSourcesNeedRetry: Bool {
        guard let snapshot else { return true }
        guard case .available = snapshot.idlePolicy,
              case .available = snapshot.betaFeatures,
              case .available = snapshot.autoUpdateStatus else { return true }
        return false
    }

    /// Native surfaces release their token when they close, independently of
    /// SwiftUI processing the hidden view's next update.
    func beginVisibleFanObservation() -> UUID {
        let token = UUID()
        visibleFanSubscribers.insert(token)
        if visibleFanPollingTask == nil {
            visibleFanPollingTask = Task { @MainActor [weak self] in
                guard let self else { return }
                while !Task.isCancelled {
                    await self.refreshFan()
                    do { try await Task.sleep(for: self.visibleFanPollingInterval) }
                    catch { return }
                }
            }
        }
        return token
    }

    /// Returns the cancelled poller so callers can await its read finishing.
    /// Other visible surfaces retain the shared cadence.
    @discardableResult
    func endVisibleFanObservation(_ token: UUID) -> Task<Void, Never>? {
        guard visibleFanSubscribers.remove(token) != nil,
              visibleFanSubscribers.isEmpty else { return nil }
        let polling = visibleFanPollingTask
        polling?.cancel()
        visibleFanPollingTask = nil
        return polling
    }

    /// SwiftUI settings surfaces retain task-scoped subscriptions.
    func observeVisibleFan() async {
        guard !Task.isCancelled else { return }
        let token = beginVisibleFanObservation()
        while !Task.isCancelled {
            do { try await Task.sleep(for: .seconds(31_536_000)) }
            catch { break }
        }
        let cancelledPoller = endVisibleFanObservation(token)
        await cancelledPoller?.value
    }

    /// Shares the refresh gate with full polling and mutations. No policy is
    /// written by live readings.
    func refreshFan() async {
        guard !Task.isCancelled, !mutationInFlight else { return }
        guard snapshot != nil else { await refresh(); return }
        if let previous = refreshTask { await previous.value; return }
        isRefreshing = true
        refreshIncludesStatic = false
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let client = self.client
        let task = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            let fan = await client.refreshFan()
            guard let self, !Task.isCancelled, self.refreshGeneration == generation,
                  let current = self.snapshot else { return }
            self.snapshot = ProviderExtrasSnapshot(
                capturedAt: current.capturedAt,
                idlePolicy: current.idlePolicy,
                betaFeatures: current.betaFeatures,
                fanStatus: Self.retainLastGood(fan, previous: current.fanStatus,
                    reason: "Darkbloom fan status refresh failed"),
                autoUpdateStatus: current.autoUpdateStatus
            )
        }
        refreshTask = task
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
        if refreshGeneration == generation {
            refreshTask = nil
            isRefreshing = false
        }
    }

    private func refresh(force: Bool) async {
        if let previous = refreshTask {
            let previousIncludedStatic = refreshIncludesStatic
            let previousGeneration = refreshGeneration
            if force { previous.cancel() }
            await previous.value
            if !force && previousIncludedStatic { return }
            // A full settings refresh must follow a fan-only read. Another
            // waiter may already have started that full read while we resumed.
            if refreshTask != nil && refreshGeneration != previousGeneration {
                await refresh(force: force)
                return
            }
        }
        let client = self.client
        isRefreshing = true
        errorMessage = nil
        refreshIncludesStatic = true
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let task = Task { @MainActor [weak self] in
            let refreshed = await client.refresh()
            guard let self, !Task.isCancelled, self.refreshGeneration == generation else { return }
            self.snapshot = Self.merge(refreshed, with: self.snapshot)
            self.lastStaticRefreshAt = self.now()
        }
        refreshTask = task
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
        if refreshGeneration == generation {
            refreshTask = nil
            isRefreshing = false
        }
    }

    /// Begin explicit read-only polling. No setting is written by this loop.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.refreshBackground()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: self.pollingInterval)
                } catch {
                    return
                }
                await self.refreshBackground()
            }
        }
    }

    func stop() async {
        let visiblePolling = visibleFanPollingTask
        visiblePolling?.cancel()
        let polling = pollingTask
        polling?.cancel()
        let refresh = refreshTask
        refresh?.cancel()
        await visiblePolling?.value
        await polling?.value
        await refresh?.value
        visibleFanPollingTask = nil
        pollingTask = nil
        refreshTask = nil
        isRefreshing = false
    }

    func saveIdle(minutes: Int) async throws {
        guard !mutationInFlight else {
            throw ProviderExtrasMutationError.mutationInProgress
        }
        mutationInFlight = true
        errorMessage = nil
        defer { mutationInFlight = false }
        do {
            try await client.saveIdle(minutes: minutes)
            await refresh(force: true)
        } catch let error as ProviderExtrasMutationError {
            errorMessage = error.userMessage
            throw error
        } catch {
            errorMessage = ProviderExtrasMutationError.commandFailed.userMessage
            throw ProviderExtrasMutationError.commandFailed
        }
    }

    func setBeta(id: String, enabled: Bool) async throws {
        try await performMutation {
            try await self.client.setBeta(id: id, enabled: enabled)
        }
    }

    func setAutoUpdate(enabled: Bool) async throws {
        try await performMutation {
            try await self.client.setAutoUpdate(enabled: enabled)
        }
    }

    func enableFan(policy: ProviderFanPolicy) async throws {
        try await performMutation {
            try await self.client.enableFan(policy: policy)
        }
    }

    func configureFan(policy: ProviderFanPolicy) async throws {
        try await performMutation {
            try await self.client.configureFan(policy: policy)
        }
    }

    func disableFan() async throws {
        try await performMutation {
            try await self.client.disableFan()
        }
    }

    func uninstallFan() async throws {
        try await performMutation {
            try await self.client.uninstallFan()
        }
    }

    private func performMutation(
        _ mutation: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard !mutationInFlight else {
            throw ProviderExtrasMutationError.mutationInProgress
        }
        mutationInFlight = true
        errorMessage = nil
        defer { mutationInFlight = false }
        do {
            try await mutation()
            await refresh(force: true)
        } catch let error as ProviderExtrasMutationError {
            errorMessage = error.userMessage
            throw error
        } catch {
            errorMessage = ProviderExtrasMutationError.commandFailed.userMessage
            throw ProviderExtrasMutationError.commandFailed
        }
    }

    private static func merge(
        _ refreshed: ProviderExtrasSnapshot,
        with previous: ProviderExtrasSnapshot?
    ) -> ProviderExtrasSnapshot {
        ProviderExtrasSnapshot(
            capturedAt: refreshed.capturedAt,
            idlePolicy: retainLastGood(
                refreshed.idlePolicy,
                previous: previous?.idlePolicy,
                reason: "Darkbloom idle policy refresh failed"
            ),
            betaFeatures: retainLastGood(
                refreshed.betaFeatures,
                previous: previous?.betaFeatures,
                reason: "Darkbloom beta feature refresh failed"
            ),
            fanStatus: retainLastGood(
                refreshed.fanStatus,
                previous: previous?.fanStatus,
                reason: "Darkbloom fan status refresh failed"
            ),
            autoUpdateStatus: mergeOptional(
                refreshed.autoUpdateStatus,
                previous: previous?.autoUpdateStatus,
                reason: "Darkbloom automatic-update status refresh failed"
            )
        )
    }

    private static func mergeOptional<Value>(
        _ refreshed: SourceAvailability<Value>?,
        previous: SourceAvailability<Value>?,
        reason: String
    ) -> SourceAvailability<Value>? where Value: Equatable & Sendable {
        guard let refreshed else {
            return stale(previous: previous, reason: reason)
        }
        return retainLastGood(refreshed, previous: previous, reason: reason)
    }

    private static func retainLastGood<Value>(
        _ refreshed: SourceAvailability<Value>,
        previous: SourceAvailability<Value>?,
        reason: String
    ) -> SourceAvailability<Value> where Value: Equatable & Sendable {
        guard case .unavailable = refreshed else { return refreshed }
        return stale(previous: previous, reason: reason) ?? refreshed
    }

    private static func stale<Value>(
        previous: SourceAvailability<Value>?,
        reason: String
    ) -> SourceAvailability<Value>? where Value: Equatable & Sendable {
        guard let previous else { return nil }
        switch previous {
        case .available(let value, let capturedAt), .stale(let value, let capturedAt, _):
            return .stale(value: value, capturedAt: capturedAt, reason: reason)
        case .unavailable:
            return nil
        }
    }
}
