import Foundation

public protocol TelemetrySource: Sendable {
    func readDaemonState() async throws -> DaemonState
    func readLoadedModels() async throws -> LoadedModelsState
    func readStatus() async throws -> StatusSnapshot
    func readLegacyEvents(limit: Int) async throws -> [LogEvent]
}

public struct LocalTelemetrySource: TelemetrySource, Sendable {
    public let policy: DarkbloomSourcePolicy
    public let runner: CappedProcessRunner
    private let legacyTail: LegacyLogTailReader

    public init(policy: DarkbloomSourcePolicy, runner: CappedProcessRunner) {
        self.policy = policy
        self.runner = runner
        legacyTail = LegacyLogTailReader(url: policy.legacyLog)
    }

    public func readDaemonState() async throws -> DaemonState {
        try await retryingJSONRead(at: policy.daemonState, parse: DaemonStateParser.parse)
    }

    public func readLoadedModels() async throws -> LoadedModelsState {
        try await retryingJSONRead(at: policy.loadedModels, parse: LoadedModelsParser.parse)
    }

    public func readStatus() async throws -> StatusSnapshot {
        guard let executable = policy.cliCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw ProcessRunnerError.launchFailed("No approved Darkbloom executable was found")
        }

        let result = try await runner.run(
            DarkbloomCommand.status(executable: executable),
            timeout: DarkbloomSourcePolicy.processTimeout,
            outputLimit: DarkbloomSourcePolicy.processOutputByteLimit
        )
        guard let output = String(data: result.standardOutput, encoding: .utf8) else {
            throw LocalTelemetrySourceError.statusOutputWasNotUTF8
        }
        return StatusParser.parse(output)
    }

    public func readLegacyEvents(limit: Int) async throws -> [LogEvent] {
        try await legacyTail.read(limit: limit)
    }

    private func retryingJSONRead<Value>(
        at url: URL,
        parse: (Data) throws -> Value
    ) async throws -> Value {
        do {
            return try parse(Data(contentsOf: url))
        } catch {
            try await Task.sleep(for: .milliseconds(100))
            return try parse(Data(contentsOf: url))
        }
    }
}

private enum LocalTelemetrySourceError: Error {
    case statusOutputWasNotUTF8
}
