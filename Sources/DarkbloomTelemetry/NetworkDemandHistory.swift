import Foundation

/// Whitelisted network observations, separate from local work and earnings.
public struct NetworkDemandHistoryValue: Codable, Equatable, Sendable {
    public let modelID: String
    public let activeRequests: Int
    public let queuedRequests: Int
    public let loadedProviders: Int

    public init(modelID: String, activeRequests: Int, queuedRequests: Int, loadedProviders: Int) {
        self.modelID = modelID
        self.activeRequests = activeRequests
        self.queuedRequests = queuedRequests
        self.loadedProviders = loadedProviders
    }

    public var pressure: Double? {
        guard isValid, loadedProviders > 0 else { return nil }
        return (Double(activeRequests) + Double(queuedRequests)) / Double(loadedProviders)
    }

    public var isValid: Bool {
        !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && modelID.utf8.count <= 512
            && activeRequests >= 0 && queuedRequests >= 0 && loadedProviders >= 0
    }
}

/// Latest accepted observation in a five-minute bucket. Missing models stay
/// missing; neither an absent row nor a zero denominator denotes zero demand.
public struct NetworkDemandHistoryObservation: Codable, Equatable, Sendable {
    public static let bucketSeconds: TimeInterval = 300
    public let capturedAt: Date
    public let models: [NetworkDemandHistoryValue]
    public let isDraining: Bool

    public init(capturedAt: Date, models: [NetworkDemandHistoryValue], isDraining: Bool = false) {
        self.capturedAt = capturedAt
        self.models = models.sorted { $0.modelID < $1.modelID }
        self.isDraining = isDraining
    }

    public init(snapshot: NetworkCapacitySnapshot) {
        self.init(capturedAt: snapshot.capturedAt, models: snapshot.models.map {
            .init(modelID: $0.id, activeRequests: $0.activeRequests,
                queuedRequests: $0.queuedRequests, loadedProviders: $0.warmProviders)
        }, isDraining: snapshot.isDraining)
    }

    public var bucketStart: Date {
        Date(timeIntervalSince1970: floor(capturedAt.timeIntervalSince1970 / Self.bucketSeconds) * Self.bucketSeconds)
    }

    public var isValid: Bool {
        capturedAt.timeIntervalSince1970.isFinite && capturedAt.timeIntervalSince1970 >= 0
            && models.count <= 128 && models.allSatisfy(\.isValid)
            && Set(models.map(\.modelID)).count == models.count
            && (!isDraining || models.isEmpty)
    }
}

public struct NetworkDemandHistoryReport: Equatable, Sendable {
    public let range: DateInterval
    public let readAt: Date
    public let observations: [NetworkDemandHistoryObservation]

    public init(range: DateInterval, readAt: Date, observations: [NetworkDemandHistoryObservation]) {
        self.range = range
        self.readAt = readAt
        self.observations = observations
    }
}
