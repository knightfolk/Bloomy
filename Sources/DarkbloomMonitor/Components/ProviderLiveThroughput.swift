import DarkbloomTelemetry
import Foundation

/// Counter-derived throughput is provider-wide, even while one current model
/// is named. This presentation never claims exclusive per-model attribution.
struct ProviderLiveThroughput: Equatable, Sendable {
    enum State: Equatable, Sendable { case measured, idle, waiting, stale, unavailable }
    let value: Double?
    let age: TimeInterval?
    let state: State

    static func make(snapshot: TelemetrySnapshot, now: Date) -> Self {
        guard let daemon = snapshot.state.value else {
            return .init(value: nil, age: nil, state: .unavailable)
        }
        let age = now.timeIntervalSince1970 - daemon.writtenAt
        let captureAge = now.timeIntervalSince(snapshot.capturedAt)
        guard age.isFinite, captureAge.isFinite, age >= 0, captureAge >= 0 else {
            return .init(value: nil, age: nil, state: .unavailable)
        }
        let value: Double?
        if case .available(let rate, _) = snapshot.tokenRate, rate.isFinite, rate >= 0 {
            value = rate
        } else { value = nil }
        guard case .available = snapshot.state, age <= 10, captureAge <= 10 else {
            return .init(value: daemon.inferenceActive ? value : nil, age: age, state: .stale)
        }
        guard daemon.inferenceActive else {
            return .init(value: nil, age: age, state: .idle)
        }
        return .init(value: value, age: age, state: value == nil ? .waiting : .measured)
    }

    var reading: LiveTelemetryReading {
        .init(value: value, unit: .tokensPerSecond, age: age,
            freshness: state == .stale ? .stale : state == .unavailable ? .unavailable : .current,
            status: state == .idle ? .idle : state == .waiting ? .waiting : .measured)
    }

    var detail: String {
        switch state {
        case .measured: "Provider-wide token progress"
        case .idle: "Idle · no current rate"
        case .waiting: "Serving · waiting for token progress"
        case .stale: "Last observation · current rate unknown"
        case .unavailable: "Provider telemetry unavailable"
        }
    }
}

/// A single bounded scalar from accepted observations; no per-card state or
/// polling. The peak resets for a different provider process and is not a
/// hardware capacity, target speed, daily average or historic earning estimate.
struct ProviderThroughputPeak: Equatable, Sendable {
    private(set) var identity: ProcessIdentity?
    private(set) var value: Double?

    mutating func observe(_ snapshot: TelemetrySnapshot, now: Date) {
        guard case .available(let daemon, _) = snapshot.state,
              daemon.processIdentity.pid > 0, daemon.processIdentity.startTimeMicros >= 0 else { return }
        let age = now.timeIntervalSince1970 - daemon.writtenAt
        guard age.isFinite, (0...10).contains(age) else { return }
        if identity != daemon.processIdentity {
            identity = daemon.processIdentity
            value = nil
        }
        let reading = ProviderLiveThroughput.make(snapshot: snapshot, now: now)
        guard reading.state == .measured, let next = reading.value, next > 0 else { return }
        value = max(value ?? next, next)
    }
}
