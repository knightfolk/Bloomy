import Foundation

/// A weekly schedule uses the Mac's local wall clock.
public enum ProviderScheduleDay: String, CaseIterable, Codable, Sendable {
    case monday = "mon", tuesday = "tue", wednesday = "wed", thursday = "thu"
    case friday = "fri", saturday = "sat", sunday = "sun"
}

public struct ProviderScheduleWindow: Equatable, Sendable {
    public var days: Set<ProviderScheduleDay>
    public var start: String
    public var end: String

    public init(days: Set<ProviderScheduleDay>, start: String, end: String) {
        self.days = days
        self.start = start
        self.end = end
    }

    /// Nominal wall-clock duration; DST changes can affect elapsed time.
    /// Equal endpoints represent a full day, as in Darkbloom's scheduler.
    public var durationMinutes: Int? {
        guard let start = Self.minutes(start), let end = Self.minutes(end) else { return nil }
        return end > start ? end - start : end + 1_440 - start
    }

    private static func minutes(_ value: String) -> Int? {
        let bytes = Array(value.utf8)
        guard bytes.count == 5, bytes[2] == 58,
              [bytes[0], bytes[1], bytes[3], bytes[4]].allSatisfy({ (48...57).contains($0) }) else { return nil }
        let hours = Int(bytes[0] - 48) * 10 + Int(bytes[1] - 48)
        let minutes = Int(bytes[3] - 48) * 10 + Int(bytes[4] - 48)
        guard hours < 24, minutes < 60 else { return nil }
        return hours * 60 + minutes
    }
}

public struct ProviderSchedule: Equatable, Sendable {
    public var enabled: Bool
    public var windows: [ProviderScheduleWindow]

    public init(enabled: Bool, windows: [ProviderScheduleWindow]) {
        self.enabled = enabled
        self.windows = windows
    }

    /// The editor uses the upstream desktop limit and never writes malformed windows.
    public var isValidForEditing: Bool {
        windows.count <= 14 && (!enabled || !windows.isEmpty)
            && windows.allSatisfy { !$0.days.isEmpty && $0.durationMinutes != nil }
    }
}
