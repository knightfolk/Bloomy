import Foundation

/// Aggregate operator diagnostics only. Add-on names, IDs, paths and lease
/// timestamps never enter this value or the app's diagnostic history.
public struct ProviderAddonControlSnapshot: Equatable, Sendable {
    public let hold: ProviderAddonHold
    public let machineLockHeld: Bool
    public let operatorHoldPresent: Bool

    public init(hold: ProviderAddonHold, machineLockHeld: Bool, operatorHoldPresent: Bool) {
        self.hold = hold
        self.machineLockHeld = machineLockHeld
        self.operatorHoldPresent = operatorHoldPresent
    }
}

public enum ProviderAddonControlFailure: Error, Equatable, Sendable {
    case executableUnavailable, unsupportedVersion, invalidLease
    case commandFailed, timedOut, cancelled, unknownStatus
}

public enum ProviderAddonControlStatus: Equatable, Sendable {
    case available(ProviderAddonControlSnapshot)
    case unavailable(ProviderAddonControlFailure)
}

public enum ProviderAddonMutationResult: Equatable, Sendable {
    case confirmed(ProviderAddonControlSnapshot)
    /// Includes the independently reconciled state, when it could be read.
    /// A failed command may already have changed provider admission.
    case outcomeUncertain(ProviderAddonControlStatus)
    /// Validation/preflight failed before a mutation was dispatched.
    case rejected(ProviderAddonControlFailure)
}

public protocol ProviderAddonControlling: Sendable {
    func status() async -> ProviderAddonControlStatus
    func hold(leaseSeconds: Int) async -> ProviderAddonMutationResult
    /// The upstream operator command releases EVERY add-on hold. There is no
    /// operator-only release command. Force must always be a caller decision.
    func release(force: Bool) async -> ProviderAddonMutationResult
}

/// Qualified against the v0.10.4 AddonCommand renderer, not the separate
/// hold.v1 add-on socket contract. Never forwards the CLI's free-form errors.
public struct ProviderAddonControlClient: ProviderAddonControlling, Sendable {
    public static let leaseSecondsRange = 30...600
    public static let processTimeout: Duration = .seconds(15)
    public static let outputLimit = 32 * 1_024

    public let policy: DarkbloomSourcePolicy
    private let runner: any ProcessExecuting
    private let testOnlyExecutable: URL?

    public init(policy: DarkbloomSourcePolicy, runner: any ProcessExecuting = CappedProcessRunner()) {
        self.policy = policy
        self.runner = runner
        testOnlyExecutable = nil
    }

    init(policy: DarkbloomSourcePolicy, runner: any ProcessExecuting, testOnlyExecutable: URL) {
        self.policy = policy
        self.runner = runner
        self.testOnlyExecutable = testOnlyExecutable
    }

    public init(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        environmentPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
        runner: any ProcessExecuting = CappedProcessRunner()
    ) {
        self.init(policy: DarkbloomSourcePolicy(homeDirectory: homeDirectory, environmentPath: environmentPath), runner: runner)
    }

    public func status() async -> ProviderAddonControlStatus {
        switch await qualifiedExecutable() {
        case .success(let executable): return await readStatus(executable: executable)
        case .failure(let failure): return .unavailable(failure)
        }
    }

    public func hold(leaseSeconds: Int) async -> ProviderAddonMutationResult {
        guard Self.leaseSecondsRange.contains(leaseSeconds) else { return .rejected(.invalidLease) }
        return await mutate(arguments: ["addon", "hold", "--lease-seconds", String(leaseSeconds)], isHold: true)
    }

    public func release(force: Bool) async -> ProviderAddonMutationResult {
        await mutate(arguments: ["addon", "release"] + (force ? ["--force"] : []), isHold: false)
    }

    private func mutate(arguments: [String], isHold: Bool) async -> ProviderAddonMutationResult {
        let executable: URL
        switch await qualifiedExecutable() {
        case .success(let value): executable = value
        case .failure(let failure): return .rejected(failure)
        }
        guard !Task.isCancelled else { return .rejected(.cancelled) }

        let response: ProviderAddonControlSnapshot?
        do {
            let result = try await run(executable: executable, arguments: arguments)
            response = result.exitCode == 0 ? Self.parse(result.standardOutput) : nil
        } catch {
            // Launch errors, stderr and arbitrary runner errors are discarded.
            // Conservatively reconcile: an executor may have dispatched before
            // its timeout/cancellation/error reached us.
            response = nil
        }

        // Caller cancellation cannot skip a bounded readback after a command
        // may have changed admission. This task has no output callback/logging.
        let readback = await Task.detached { await self.readStatus(executable: executable) }.value
        guard let response, case .available(let after) = readback,
              confirms(response, isHold: isHold), confirms(after, isHold: isHold)
        else { return .outcomeUncertain(readback) }
        return .confirmed(after)
    }

    private func confirms(_ status: ProviderAddonControlSnapshot, isHold: Bool) -> Bool {
        if isHold {
            return status.operatorHoldPresent && (status.hold == .held || status.hold == .draining)
        }
        return status.hold == .none && !status.operatorHoldPresent
    }

    private func qualifiedExecutable() async -> Result<URL, ProviderAddonControlFailure> {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        guard let executable = testOnlyExecutable ?? policy.cliCandidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else { return .failure(.executableUnavailable) }
        do {
            let result = try await run(executable: executable, arguments: ["--version"])
            guard result.exitCode == 0,
                  String(data: result.standardOutput, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) == "0.10.4"
            else { return .failure(.unsupportedVersion) }
            return .success(executable)
        } catch { return .failure(Self.failure(for: error)) }
    }

    private func readStatus(executable: URL) async -> ProviderAddonControlStatus {
        do {
            let result = try await run(executable: executable, arguments: ["addon", "status"])
            guard result.exitCode == 0 else { return .unavailable(.commandFailed) }
            guard let status = Self.parse(result.standardOutput) else { return .unavailable(.unknownStatus) }
            return .available(status)
        } catch { return .unavailable(Self.failure(for: error)) }
    }

    private func run(executable: URL, arguments: [String]) async throws -> CommandResult {
        let result = try await runner.run(
            ProcessCommand(executable: executable, arguments: arguments),
            timeout: Self.processTimeout, outputLimit: Self.outputLimit, onOutput: nil
        )
        guard result.standardOutput.count <= Self.outputLimit,
              result.standardError.count <= Self.outputLimit - result.standardOutput.count
        else { throw ProcessRunnerError.outputLimitExceeded(limit: Self.outputLimit) }
        return result
    }

    private static func failure(for error: any Error) -> ProviderAddonControlFailure {
        if error is CancellationError { return .cancelled }
        if let error = error as? ProcessRunnerError, error == .timedOut { return .timedOut }
        return .commandFailed
    }

    /// Requires the entire known renderer shape. A partial header, an unknown
    /// state or an extra line cannot turn into a successful mutation receipt.
    static func parse(_ data: Data) -> ProviderAddonControlSnapshot? {
        guard data.count <= outputLimit, var output = String(data: data, encoding: .utf8) else { return nil }
        if output.hasSuffix("\n") { output.removeLast() }
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 2, lines.count <= 66 else { return nil }
        let lockHeld: Bool
        switch lines.last {
        case "Machine lock: free": lockHeld = false
        case "Machine lock: held (add-on VMs may be running)": lockHeld = true
        default: return nil
        }
        if lines.first == "Add-on holds: none; the provider serves normally." {
            guard lines.count == 2 else { return nil }
            return .init(hold: .none, machineLockHeld: lockHeld, operatorHoldPresent: false)
        }
        guard lines.first == "Add-on holds:", lines.count >= 3,
              let row = try? NSRegularExpression(pattern: #"^  [A-Za-z0-9][A-Za-z0-9._-]{0,254}: (draining|held) since ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z); (lease expires in ([1-9][0-9]*)s|lease expired \(kept while the machine lock is held\))$"#)
        else { return nil }
        var draining = false
        var operatorPresent = false
        let formatter = ISO8601DateFormatter()
        for line in lines.dropFirst().dropLast() {
            let range = NSRange(line.startIndex..<line.endIndex, in: line)
            guard let match = row.firstMatch(in: line, range: range), match.range == range,
                  let dateRange = Range(match.range(at: 2), in: line),
                  let date = formatter.date(from: String(line[dateRange])),
                  formatter.string(from: date) == String(line[dateRange])
            else { return nil }
            if let leaseRange = Range(match.range(at: 4), in: line), Int(line[leaseRange]) == nil { return nil }
            draining = draining || line.contains(": draining since ")
            operatorPresent = operatorPresent || line.hasPrefix("  operator: ")
        }
        return .init(hold: draining ? .draining : .held, machineLockHeld: lockHeld, operatorHoldPresent: operatorPresent)
    }
}
