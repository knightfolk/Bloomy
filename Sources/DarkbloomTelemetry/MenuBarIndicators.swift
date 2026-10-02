import Foundation

/// Values for the three fixed menu-bar indicators. Host GPU and fan activity
/// describe the whole Mac; neither is attributed to the selected model.
public struct MenuBarIndicators: Equatable, Sendable {
    public enum Freshness: Equatable, Sendable { case current, stale, unavailable }

    public struct Reading: Equatable, Sendable {
        public let value: Double?
        public let freshness: Freshness
        public let sampledAt: Date?

        public init(value: Double?, freshness: Freshness, sampledAt: Date? = nil) {
            self.value = value.flatMap { $0.isFinite ? $0 : nil }
            self.freshness = self.value == nil ? .unavailable : freshness
            self.sampledAt = sampledAt
        }

        public static let unavailable = Self(value: nil, freshness: .unavailable)
        public var progress: Double { min(1, max(0, (value ?? 0) / 100)) }
    }

    public let modelIsActive: Bool
    public let gpu: Reading
    public let fanSpeed: Reading
    public let temperature: Reading
    /// One-shot invalidation, rather than a display timer while idle.
    public let nextFreshnessChange: Date?

    public init(
        modelIsActive: Bool = false,
        gpu: Reading = .unavailable,
        fanSpeed: Reading = .unavailable,
        temperature: Reading = .unavailable,
        nextFreshnessChange: Date? = nil
    ) {
        self.modelIsActive = modelIsActive
        self.gpu = gpu
        self.fanSpeed = fanSpeed
        self.temperature = temperature
        self.nextFreshnessChange = nextFreshnessChange
    }

    public var temperatureTint: MenuBarGPURing.Tint {
        guard temperature.freshness == .current else { return .neutral }
        return MenuBarGPURing.tint(for: temperature.value, thresholds: .standard)
    }

    public var accessibilityDetail: String {
        let model = modelIsActive ? "Model inference active." : "Model inference idle or unavailable."
        return [model, detail(gpu, name: "Whole-Mac GPU use", unit: "percent"),
                detail(fanSpeed, name: "Fan speed", unit: "percent of reported maximum RPM"),
                detail(temperature, name: "GPU temperature", unit: "degrees Celsius")].joined(separator: " ")
    }

    /// The selected resident family remains visible between requests. Loading
    /// or residency establishes the logo, never the spinning activity arc.
    public static func modelFamily(snapshot: TelemetrySnapshot, now: Date) -> ModelFamilyIcon {
        guard snapshot.menuStatus == .online, case .available(let state, _) = snapshot.state,
              fresh(Date(timeIntervalSince1970: state.writtenAt), age: 10, now: now) else { return .darkbloom }
        let activityFamily = ModelFamilyIcon.select(snapshot: snapshot, now: now)
        if state.inferenceActive || activityFamily != .darkbloom { return activityFamily }
        if state.warmModels.contains(state.currentModel) {
            return ModelFamilyIcon.select(status: .online, activeModel: state.currentModel)
        }
        if state.warmModels.count == 1 {
            return ModelFamilyIcon.select(status: .online, activeModel: state.warmModels[0])
        }
        return .darkbloom
    }

    public static func make(
        snapshot: TelemetrySnapshot,
        utilization: Double?,
        sampledAt: Date?,
        utilizationIsCurrent: Bool = true,
        fanStatus: SourceAvailability<ProviderFanStatus>?,
        now: Date
    ) -> Self {
        var deadlines: [Date] = []
        let active: Bool
        if snapshot.menuStatus == .online, case .available(let state, _) = snapshot.state,
           fresh(Date(timeIntervalSince1970: state.writtenAt), age: 10, now: now) {
            active = state.inferenceActive
            deadlines.append(Date(timeIntervalSince1970: state.writtenAt + 10.01))
        } else { active = false }

        let gpu: Reading
        if let value = utilization, value.isFinite, (0...100).contains(value),
           let sampledAt, sampledAt <= now {
            let current = utilizationIsCurrent && fresh(sampledAt, age: MenuBarGPURing.maximumUtilizationAge, now: now)
            gpu = Reading(value: value, freshness: current ? .current : .stale, sampledAt: sampledAt)
            if current { deadlines.append(sampledAt.addingTimeInterval(MenuBarGPURing.maximumUtilizationAge + 0.01)) }
        } else { gpu = .unavailable }

        var fan: Reading = .unavailable
        var temperature: Reading = .unavailable
        let sourceDate: Date? = switch fanStatus {
        case .available(_, let date), .stale(_, let date, _): date
        case .unavailable, nil: nil
        }
        if let fanStatus, let status = fanStatus.value, let capturedAt = sourceDate, capturedAt <= now {
            let sourceCurrent: Bool
            if case .available = fanStatus {
                sourceCurrent = fresh(capturedAt, age: ProviderExtrasSnapshot.maximumSourceAge, now: now)
            } else { sourceCurrent = false }
            if sourceCurrent {
                deadlines.append(capturedAt.addingTimeInterval(ProviderExtrasSnapshot.maximumSourceAge + 0.01))
                if let helper = status.helper, status.helperIsFresh(at: now) {
                    deadlines.append(helper.updatedAt.addingTimeInterval(ProviderFanStatus.maximumHelperAge + 0.01))
                }
            }
            // Fresh helper measurements take priority. Expired journals fall
            // back to a diagnostic from the independently dated CLI command.
            let currentStatus = status.helperIsFresh(at: now) ? status : status.withoutHelper()
            let helperPercent = currentStatus.helper.flatMap { highestFanPercentage($0.fans) }
            let fanPercent = helperPercent ?? highestFanPercentage(currentStatus.diagnostic.fans)
            if let fanPercent {
                let fanDate = helperPercent != nil ? currentStatus.helper?.updatedAt ?? capturedAt : capturedAt
                fan = Reading(value: fanPercent, freshness: sourceCurrent ? .current : .stale, sampledAt: fanDate)
            } else if let lastPercent = highestFanPercentage(status.displayedFans) {
                fan = Reading(value: lastPercent, freshness: .stale,
                              sampledAt: status.helper?.updatedAt ?? capturedAt)
            }
            if let value = MenuBarGPURing.freshTemperatureCelsius(from: fanStatus, now: now) {
                temperature = Reading(value: value, freshness: .current,
                                      sampledAt: currentStatus.helper?.gpuTemperatureCelsius == value ? currentStatus.helper?.updatedAt : capturedAt)
            } else {
                // A retained reading is explicitly old, has no thermal tint,
                // and is never used to sustain the inference animation.
                let historical = SourceAvailability.available(value: status, capturedAt: capturedAt)
                if let value = MenuBarGPURing.freshTemperatureCelsius(from: historical, now: capturedAt) {
                    temperature = Reading(value: value, freshness: .stale, sampledAt: capturedAt)
                }
            }
        }
        return Self(modelIsActive: active, gpu: gpu, fanSpeed: fan, temperature: temperature,
                    nextFreshnessChange: deadlines.filter { $0 > now }.min())
    }

    /// Actual hardware RPM only. Policy targets and helper speedPercent are
    /// settings, so neither can establish measured fan utilization.
    public static func highestFanPercentage(_ fans: [ProviderFanReading]) -> Double? {
        fans.compactMap { fan -> Double? in
            guard let actual = fan.actualRPM, actual.isFinite, actual >= 0,
                  let maximum = fan.maximumRPM, maximum.isFinite, maximum > 0 else { return nil }
            return min(100, max(0, actual / maximum * 100))
        }.max()
    }

    private static func fresh(_ date: Date, age: TimeInterval, now: Date) -> Bool {
        let elapsed = now.timeIntervalSince(date)
        return elapsed.isFinite && (0...age).contains(elapsed)
    }

    private func detail(_ reading: Reading, name: String, unit: String) -> String {
        guard let value = reading.value else { return "\(name) unavailable." }
        let number = value.formatted(.number.precision(.fractionLength(0)))
        if reading.freshness == .stale {
            let captured = reading.sampledAt.map { ", captured \($0.formatted(date: .abbreviated, time: .standard))" } ?? ""
            return "\(name), last sample \(number) \(unit)\(captured)."
        }
        return "\(name) \(number) \(unit)."
    }
}
