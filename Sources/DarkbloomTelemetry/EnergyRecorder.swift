import Foundation

public struct EnergyRecordingSnapshot: Sendable {
    public let reading: EnergyReading?
    public let intervals: [EnergyInterval]
    public let issue: String?
}

/// One owner serializes acquisition and atomic persistence. No privileged tools.
public actor EnergyRecorder {
    private let file: URL
    private let readPower: @Sendable (Date) -> EnergyReading?
    private var history: EnergyHistory?
    private var database: EnergyHistoryDatabase?

    public init(file: URL, readPower: @escaping @Sendable (Date) -> EnergyReading? = {
        MacAdapterPower.read(now: $0)
    }) {
        self.file = file
        self.readPower = readPower
    }

    public func sample(
        enabled: Bool,
        rate: Double?,
        now: Date,
        modelActivity: ModelPowerActivity? = nil
    ) -> EnergyRecordingSnapshot {
        guard enabled else {
            history?.breakContinuity()
            return .init(reading: nil, intervals: [], issue: nil)
        }
        do {
            if history == nil {
                let database = try EnergyHistoryDatabase(
                    url: EnergyHistoryDatabase.databaseURL(forLegacyFile: file), legacyFile: file
                )
                history = try database.history()
                self.database = database
            }
        } catch {
            return .init(reading: nil, intervals: [], issue: "Energy history could not be read; existing file preserved.")
        }
        guard let rate, rate.isFinite, rate >= 0 else {
            history?.breakContinuity()
            return .init(reading: nil, intervals: [], issue: "Enter a valid electricity price in Settings.")
        }
        guard let reading = readPower(now) else {
            history?.breakContinuity()
            return .init(reading: nil, intervals: history?.intervals ?? [], issue: "Adapter power unavailable; measurement gap.")
        }
        let interval = history?.append(reading, usdPerKWh: rate, modelActivity: modelActivity)
        do {
            if let interval {
                guard let database else { throw EnergyHistoryDatabaseError.unavailable }
                try database.append(interval)
            }
            return .init(reading: reading, intervals: history?.intervals ?? [], issue: nil)
        } catch {
            // Reload only committed measurements before the next attempt.
            // Neither a failed write nor downtime may seed a new sample chain.
            history = nil
            database = nil
            return .init(reading: reading, intervals: [], issue: "Energy history could not be saved.")
        }
    }
}
