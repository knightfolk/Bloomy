import Foundation
import Testing
@testable import DarkbloomTelemetry

@Suite("Provider add-on operator control")
struct ProviderAddonControlTests {
    @Test("status uses the qualified bounded command and retains aggregates only")
    func status() async {
        let runner = AddonControlRunner([.output("0.10.4\n"), .output(addonHeldOutput)])
        let result = await client(runner).status()
        #expect(result == .available(.init(hold: .held, machineLockHeld: true, operatorHoldPresent: false)))
        let calls = await runner.calls
        #expect(calls.map(\.command.arguments) == [["--version"], ["addon", "status"]])
        #expect(calls.allSatisfy { $0.command.executable == addonExecutable })
        #expect(calls.allSatisfy { $0.timeout == ProviderAddonControlClient.processTimeout })
        #expect(calls.allSatisfy { $0.outputLimit == ProviderAddonControlClient.outputLimit && !$0.hasOutputCallback })
        #expect(!String(reflecting: result).contains("io.darkbloom.sandbox"))
        #expect(!String(reflecting: result).contains("2027-01-15"))
    }

    @Test("hold confirms the operator and exposes draining without claiming models unloaded")
    func hold() async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonOperatorDrainingOutput), .output(addonOperatorDrainingOutput)])
        let result = await client(runner).hold(leaseSeconds: 45)
        #expect(result == .confirmed(.init(hold: .draining, machineLockHeld: false, operatorHoldPresent: true)))
        #expect(await runner.calls.map(\.command.arguments) == [
            ["--version"], ["addon", "hold", "--lease-seconds", "45"], ["addon", "status"],
        ])
    }

    @Test("a hold from another add-on cannot confirm an operator hold")
    func otherHoldDoesNotConfirm() async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonHeldOutput), .output(addonHeldOutput)])
        #expect(await client(runner).hold(leaseSeconds: 600) == .outcomeUncertain(
            .available(.init(hold: .held, machineLockHeld: true, operatorHoldPresent: false))
        ))
    }

    @Test("lease bounds reject before launching and accept both upstream endpoints", arguments: [29, 601, Int.min, Int.max])
    func invalidLease(_ seconds: Int) async {
        let runner = AddonControlRunner([])
        #expect(await client(runner).hold(leaseSeconds: seconds) == .rejected(.invalidLease))
        #expect(await runner.calls.isEmpty)
    }

    @Test("valid upstream lease endpoints are sent exactly", arguments: [30, 600])
    func leaseEndpoints(_ seconds: Int) async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonOperatorDrainingOutput), .output(addonOperatorDrainingOutput)])
        _ = await client(runner).hold(leaseSeconds: seconds)
        #expect(await runner.calls[1].command.arguments == ["addon", "hold", "--lease-seconds", String(seconds)])
    }

    @Test("release affects all holds and force is dispatched only by explicit caller choice", arguments: [false, true])
    func release(_ force: Bool) async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonNoneOutput), .output(addonNoneOutput)])
        #expect(await client(runner).release(force: force) == .confirmed(.init(hold: .none, machineLockHeld: false, operatorHoldPresent: false)))
        #expect(await runner.calls.map(\.command.arguments) == [
            ["--version"], ["addon", "release"] + (force ? ["--force"] : []), ["addon", "status"],
        ])
    }

    @Test("a remaining third-party hold prevents release confirmation")
    func releaseReadbackHeld() async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonNoneOutput), .output(addonHeldOutput)])
        #expect(await client(runner).release(force: false) == .outcomeUncertain(.available(.init(hold: .held, machineLockHeld: true, operatorHoldPresent: false))))
    }

    @Test("CLI versions and malformed version receipts fail closed", arguments: ["0.10.3", "0.10.5", "0.10.4-beta", "darkbloom 0.10.4", "0.10.4\nprivate-path"])
    func unqualifiedVersion(_ version: String) async {
        let runner = AddonControlRunner([.output(version)])
        #expect(await client(runner).release(force: false) == .rejected(.unsupportedVersion))
        #expect(await runner.calls.count == 1)
    }

    @Test("a missing executable fails without invoking any provider command")
    func missingExecutable() async {
        let runner = AddonControlRunner([])
        let control = ProviderAddonControlClient(
            policy: .init(homeDirectory: URL(fileURLWithPath: "/inert-addon-missing-home"), environmentPath: ""),
            runner: runner
        )
        #expect(await control.status() == .unavailable(.executableUnavailable))
        #expect(await control.release(force: false) == .rejected(.executableUnavailable))
        #expect(await runner.calls.isEmpty)
    }

    @Test("malformed and unknown renderer output never becomes status or confirmation", arguments: [
        "", "Add-on holds:\nMachine lock: free\n", addonNoneOutput + "private-path\n",
        addonNoneOutput.replacingOccurrences(of: "free", with: "unknown"),
        addonHeldOutput.replacingOccurrences(of: ": held since", with: ": future-state since"),
        addonHeldOutput.replacingOccurrences(of: "2027-01-15T08:00:00Z", with: "private-path"),
        addonHeldOutput.replacingOccurrences(of: "  io.darkbloom.sandbox:", with: "  operator: injected:"),
        addonHeldOutput + "\n",
    ])
    func malformedOutput(_ output: String) async {
        #expect(ProviderAddonControlClient.parse(Data(output.utf8)) == nil)
        let runner = AddonControlRunner([.output("0.10.4"), .output(output), .output(addonNoneOutput)])
        #expect(await client(runner).release(force: false) == .outcomeUncertain(.available(.init(hold: .none, machineLockHeld: false, operatorHoldPresent: false))))
    }

    @Test("expired leases may remain held while machine lock is held")
    func expiredLease() {
        let expired = addonHeldOutput.replacingOccurrences(of: "lease expires in 30s", with: "lease expired (kept while the machine lock is held)")
        #expect(ProviderAddonControlClient.parse(Data(expired.utf8)) == .init(hold: .held, machineLockHeld: true, operatorHoldPresent: false))
    }

    @Test("mixed holds aggregate draining while keeping the operator distinct")
    func mixedHolds() {
        let mixed = addonOperatorDrainingOutput.replacingOccurrences(
            of: "Machine lock: free",
            with: "  io.darkbloom.sandbox: held since 2027-01-15T08:00:00Z; lease expires in 30s\nMachine lock: held (add-on VMs may be running)"
        )
        #expect(ProviderAddonControlClient.parse(Data(mixed.utf8)) == .init(hold: .draining, machineLockHeld: true, operatorHoldPresent: true))
    }

    @Test("malformed readback cannot confirm a successful mutation receipt")
    func malformedReadback() async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonNoneOutput), .output("Machine lock: free\n")])
        #expect(await client(runner).release(force: false) == .outcomeUncertain(.unavailable(.unknownStatus)))
    }

    @Test("a cancelled caller still completes independent readback")
    func cancellationReadback() async {
        let runner = AddonControlRunner([.output("0.10.4"), .cancelCaller, .output(addonNoneOutput)])
        let task = Task { await client(runner).release(force: false) }
        #expect(await task.value == .outcomeUncertain(.available(.init(hold: .none, machineLockHeld: false, operatorHoldPresent: false))))
        #expect(await runner.calls.last?.command.arguments == ["addon", "status"])
        #expect(await runner.cancelledOnStatus == false)
    }

    @Test("timeout and cancellation after dispatch reconcile but cannot confirm success", arguments: [AddonControlStep.timeout, .cancel])
    fileprivate func mutationInterrupted(_ failure: AddonControlStep) async {
        let runner = AddonControlRunner([.output("0.10.4"), failure, .output(addonNoneOutput)])
        #expect(await client(runner).release(force: false) == .outcomeUncertain(.available(.init(hold: .none, machineLockHeld: false, operatorHoldPresent: false))))
        #expect(await runner.calls.last?.command.arguments == ["addon", "status"])
    }

    @Test("readback timeout and cancellation cannot confirm a completed command", arguments: [AddonControlStep.timeout, .cancel])
    fileprivate func readbackInterrupted(_ failure: AddonControlStep) async {
        let runner = AddonControlRunner([.output("0.10.4"), .output(addonNoneOutput), failure])
        let expected: ProviderAddonControlFailure = failure == .timeout ? .timedOut : .cancelled
        #expect(await client(runner).release(force: false) == .outcomeUncertain(.unavailable(expected)))
    }

    @Test("status failure and process error prose are reduced to closed failure codes")
    func failureSanitization() async {
        let runner = AddonControlRunner([.output("0.10.4"), .privateFailure, .output(addonHeldOutput)])
        let result = await client(runner).release(force: false)
        #expect(result == .outcomeUncertain(.available(.init(hold: .held, machineLockHeld: true, operatorHoldPresent: false))))
        #expect(!String(reflecting: result).contains("private-secret"))
        let failed = AddonControlRunner([.output("0.10.4"), .nonzero(addonNoneOutput)])
        #expect(await client(failed).status() == .unavailable(.commandFailed))
    }

    @Test("a cancelled caller performs no preflight or mutation")
    func preflightCancellation() async {
        let runner = AddonControlRunner([])
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return await client(runner).hold(leaseSeconds: 45)
        }
        #expect(await task.value == .rejected(.cancelled))
        #expect(await runner.calls.isEmpty)
    }

    @Test("unreadable, oversized and non UTF-8 status receipts fail closed")
    func unsafePayloads() async {
        #expect(ProviderAddonControlClient.parse(Data([0xff, 0xfe])) == nil)
        #expect(ProviderAddonControlClient.parse(Data(repeating: 65, count: ProviderAddonControlClient.outputLimit + 1)) == nil)
        let runner = AddonControlRunner([.output("0.10.4"), .output(String(repeating: "x", count: ProviderAddonControlClient.outputLimit + 1))])
        #expect(await client(runner).status() == .unavailable(.commandFailed))
    }

    private func client(_ runner: AddonControlRunner) -> ProviderAddonControlClient {
        ProviderAddonControlClient(
            policy: .init(homeDirectory: URL(fileURLWithPath: "/inert-addon-home"), environmentPath: ""),
            runner: runner, testOnlyExecutable: addonExecutable
        )
    }
}

private let addonExecutable = URL(fileURLWithPath: "/inert-addon-cli")
private let addonNoneOutput = "Add-on holds: none; the provider serves normally.\nMachine lock: free\n"
private let addonHeldOutput = "Add-on holds:\n  io.darkbloom.sandbox: held since 2027-01-15T08:00:00Z; lease expires in 30s\nMachine lock: held (add-on VMs may be running)\n"
private let addonOperatorDrainingOutput = "Add-on holds:\n  operator: draining since 2027-01-15T08:00:00Z; lease expires in 45s\nMachine lock: free\n"

fileprivate enum AddonControlStep: Equatable, Sendable {
    case output(String), nonzero(String), timeout, cancel, cancelCaller, privateFailure
}

private actor AddonControlRunner: ProcessExecuting {
    struct Call: Sendable {
        let command: ProcessCommand
        let timeout: Duration
        let outputLimit: Int
        let hasOutputCallback: Bool
    }
    private var steps: [AddonControlStep]
    private(set) var calls: [Call] = []
    private(set) var cancelledOnStatus = false
    init(_ steps: [AddonControlStep]) { self.steps = steps }

    func run(_ command: ProcessCommand, timeout: Duration, outputLimit: Int, onOutput: (@Sendable (ProcessOutputChunk) -> Void)?) async throws -> CommandResult {
        calls.append(.init(command: command, timeout: timeout, outputLimit: outputLimit, hasOutputCallback: onOutput != nil))
        if command.arguments == ["addon", "status"] { cancelledOnStatus = Task.isCancelled }
        guard !steps.isEmpty else { throw ProcessRunnerError.launchFailed("unexpected fixture call") }
        switch steps.removeFirst() {
        case .output(let output): return .init(exitCode: 0, standardOutput: Data(output.utf8), standardError: Data())
        case .nonzero(let output): return .init(exitCode: 1, standardOutput: Data(output.utf8), standardError: Data("private-secret".utf8))
        case .timeout: throw ProcessRunnerError.timedOut
        case .cancel: throw CancellationError()
        case .cancelCaller:
            withUnsafeCurrentTask { $0?.cancel() }
            throw CancellationError()
        case .privateFailure: throw ProcessRunnerError.nonzeroExit(code: 64, message: "private-secret /private/path add-on-id")
        }
    }
}
