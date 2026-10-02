import Foundation

public struct EnergyReading: Codable, Equatable, Sendable {
    public let date: Date
    public let watts: Double
    public let source: String
    public let estimated: Bool

    public init(date: Date, watts: Double, source: String, estimated: Bool) {
        self.date = date
        self.watts = watts
        self.source = source
        self.estimated = estimated
    }
}

public struct EnergyInterval: Codable, Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let kWh: Double
    public let usdPerKWh: Double
    public let source: String
    public let estimated: Bool
    /// Provider model attributed to the beginning of this measured interval, when fresh.
    public let activeModelID: String?
    /// Whether that provider model was generating during this measured interval.
    /// `nil` means the provider state was unavailable or stale.
    public let inferenceActive: Bool?
    public var costUSD: Double { kWh * usdPerKWh }

    public init(
        start: Date,
        end: Date,
        kWh: Double,
        usdPerKWh: Double,
        source: String,
        estimated: Bool,
        activeModelID: String? = nil,
        inferenceActive: Bool? = nil
    ) {
        self.start = start
        self.end = end
        self.kWh = kWh
        self.usdPerKWh = usdPerKWh
        self.source = source
        self.estimated = estimated
        self.activeModelID = activeModelID
        self.inferenceActive = inferenceActive
    }
}

public struct ModelPowerActivity: Equatable, Sendable {
    public let modelID: String?
    public let inferenceActive: Bool

    public init(modelID: String?, inferenceActive: Bool) {
        let cleaned = modelID?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.modelID = cleaned?.isEmpty == false ? cleaned : nil
        self.inferenceActive = inferenceActive
    }
}

/// Bounded measured intervals. A new process starts a new sample chain, never
/// interpolating across downtime. Each interval preserves the rate used then.
public struct EnergyHistory: Sendable {
    public private(set) var intervals: [EnergyInterval] = []
    private var previous: EnergyReading?
    private var previousRate: Double?
    private var previousActivity: ModelPowerActivity?
    public static let maximumIntervals = 60_480

    public init() {}

    public init(restoring intervals: [EnergyInterval]) throws {
        guard intervals.count <= Self.maximumIntervals else { throw EnergyHistoryError.invalidHistory }
        var end: Date?
        for interval in intervals {
            let duration = interval.end.timeIntervalSince(interval.start)
            guard interval.start.timeIntervalSince1970.isFinite,
                  interval.end.timeIntervalSince1970.isFinite,
                  duration > 0, duration <= 30,
                  end.map({ interval.start >= $0 }) ?? true,
                  interval.kWh.isFinite, interval.kWh >= 0,
                  interval.usdPerKWh.isFinite, interval.usdPerKWh >= 0,
                  interval.costUSD.isFinite, !interval.source.isEmpty,
                  interval.activeModelID?.utf8.count ?? 0 <= 512,
                  interval.inferenceActive != true || interval.activeModelID?.isEmpty == false else {
                throw EnergyHistoryError.invalidHistory
            }
            end = interval.end
        }
        self.intervals = intervals
    }

    public mutating func breakContinuity() {
        previous = nil
        previousRate = nil
        previousActivity = nil
    }

    @discardableResult
    public mutating func append(
        _ reading: EnergyReading,
        usdPerKWh: Double,
        modelActivity: ModelPowerActivity? = nil
    ) -> EnergyInterval? {
        guard reading.date.timeIntervalSince1970.isFinite, reading.watts.isFinite,
              reading.watts >= 0, usdPerKWh.isFinite, usdPerKWh >= 0,
              !reading.source.isEmpty else { breakContinuity(); return nil }
        // A clock correction must not charge for time already recorded. Drop
        // the chain until the clock catches up, including after restoration.
        guard intervals.last.map({ reading.date >= $0.end }) ?? true,
              previous.map({ reading.date > $0.date }) ?? true else {
            breakContinuity()
            return nil
        }
        defer {
            previous = reading
            previousRate = usdPerKWh
            previousActivity = modelActivity
        }
        guard let last = previous, previousRate == usdPerKWh,
              last.source == reading.source, last.estimated == reading.estimated,
              let energy = ElectricityCost.kilowattHours(startWatts: last.watts,
                  endWatts: reading.watts, seconds: reading.date.timeIntervalSince(last.date)),
              (energy * usdPerKWh).isFinite else { return nil }
        let interval = EnergyInterval(
            start: last.date,
            end: reading.date,
            kWh: energy,
            usdPerKWh: usdPerKWh,
            source: reading.source,
            estimated: reading.estimated,
            activeModelID: previousActivity?.modelID,
            inferenceActive: previousActivity?.inferenceActive
        )
        intervals.append(interval)
        if intervals.count > Self.maximumIntervals {
            intervals.removeFirst(intervals.count - Self.maximumIntervals)
        }
        return interval
    }

    /// Entirely covered intervals only; no invented allocation at day boundaries.
    public func intervals(in period: DateInterval) -> [EnergyInterval] {
        intervals.filter { $0.start >= period.start && $0.end <= period.end }
    }

    /// Select from the validated chronological sequence without scanning older
    /// history. Include boundary fragments for proportional electricity cost.
    public static func overlapping(_ intervals: [EnergyInterval], with period: DateInterval) -> [EnergyInterval] {
        var lower = 0
        var upper = intervals.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if intervals[middle].end <= period.start { lower = middle + 1 }
            else { upper = middle }
        }
        let start = lower
        upper = intervals.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if intervals[middle].start < period.end { lower = middle + 1 }
            else { upper = middle }
        }
        return Array(intervals[start..<lower])
    }
}

public enum EnergyHistoryError: Error {
    case invalidHistory
    case unsupportedSchema
    case tooLarge
}
