import Foundation

/// A quiet, local prompt for a continuously idle provider. It has its own
/// observation window and never starts or consumes an automatic nudge.
public struct MenuBarAttention: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let shortText: String
    public let idleStartedAt: Date

    public init(title: String, detail: String, shortText: String, idleStartedAt: Date) {
        self.title = title
        self.detail = detail
        self.shortText = shortText
        self.idleStartedAt = idleStartedAt
    }
}

public struct MenuBarAttentionPolicy: Sendable {
    public static let defaultsKey = "menu.attention.idleMinutes"
    public static let supportedMinutes = [0, 5, 10, 15, 30]
    public static let defaultIdleMinutes = 5
    public static let defaultIdleThreshold: TimeInterval = 5 * 60
    private static let maximumObservationGap: TimeInterval = 10

    private var idlePolicy = InactivityNudgePolicy()
    private var idleStartedAt: Date?
    private var lastObservedAt: Date?

    public init() {}

    /// Zero disables the prompt; unknown persisted values use the default.
    public static func threshold(for minutes: Int) -> TimeInterval? {
        let selected = supportedMinutes.contains(minutes) ? minutes : defaultIdleMinutes
        return selected == 0 ? nil : TimeInterval(selected * 60)
    }

    @discardableResult
    public mutating func observe(
        _ snapshot: TelemetrySnapshot,
        at now: Date,
        idleThreshold: TimeInterval = defaultIdleThreshold
    ) -> MenuBarAttention? {
        guard let state = Self.freshOnlineState(in: snapshot, at: now),
              idleThreshold.isFinite, idleThreshold > 0 else {
            reset()
            return nil
        }
        if let lastObservedAt {
            let gap = now.timeIntervalSince(lastObservedAt)
            if !gap.isFinite || gap < 0 || gap > Self.maximumObservationGap {
                reset()
            }
        }
        idleStartedAt = idlePolicy.observe(state, at: now, threshold: idleThreshold)
        lastObservedAt = now
        return attention(for: snapshot, at: now, idleThreshold: idleThreshold)
    }

    public func attention(
        for snapshot: TelemetrySnapshot,
        at now: Date,
        idleThreshold: TimeInterval = defaultIdleThreshold
    ) -> MenuBarAttention? {
        guard Self.freshOnlineState(in: snapshot, at: now) != nil,
              let idleStartedAt, let lastObservedAt,
              idleThreshold.isFinite, idleThreshold > 0 else { return nil }
        let observationAge = now.timeIntervalSince(lastObservedAt)
        let idleAge = now.timeIntervalSince(idleStartedAt)
        guard observationAge.isFinite, (0...Self.maximumObservationGap).contains(observationAge),
              idleAge.isFinite, idleAge >= idleThreshold else { return nil }

        let minutes = Int(ceil(idleThreshold / 60))
        return MenuBarAttention(
            title: "Provider idle",
            detail: "No provider work observed for at least \(minutes) minutes. Open Bloomy to review demand or send a manual nudge.",
            shortText: "Idle \(minutes)m",
            idleStartedAt: idleStartedAt
        )
    }

    public mutating func reset() {
        idlePolicy.reset()
        idleStartedAt = nil
        lastObservedAt = nil
    }

    private static func freshOnlineState(in snapshot: TelemetrySnapshot, at now: Date) -> DaemonState? {
        guard snapshot.menuStatus == .online,
              case .available(let state, let capturedAt) = snapshot.state else { return nil }
        let captureAge = now.timeIntervalSince(capturedAt)
        let stateAge = now.timeIntervalSince1970 - state.writtenAt
        guard captureAge.isFinite, (0...10).contains(captureAge),
              stateAge.isFinite, (0...10).contains(stateAge) else { return nil }
        return state
    }
}
