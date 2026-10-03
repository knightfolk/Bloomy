import DarkbloomTelemetry
import Foundation

/// Inert clock/command seam for the production settings and watcher UI.
/// No provider command, GPU sampler, endpoint or credential is accessed.
@MainActor
final class FixtureGPUProtectionProof {
    private var instant = Date()
    private(set) var stops = 0
    private(set) var starts = 0
    private let defaults: UserDefaults
    private let output: URL
    lazy var store = HostGPUProtectionStore(defaults: defaults, now: { [weak self] in self?.instant ?? .distantPast },
        pause: { [weak self] in self?.stops += 1; return true },
        resume: { [weak self] in self?.starts += 1; return true }, canAct: { true })

    init(defaults: UserDefaults, directory: URL) {
        self.defaults = defaults
        output = directory.appendingPathComponent("fixture-gpu-protection-proof.json")
    }

    func highIdle() async {
        let steps = Int(ceil(store.settings.breachSeconds / 3)) + 1
        for _ in 0...steps {
            instant.addTimeInterval(3)
            store.observe(sample: .init(percent: 100, capturedAt: instant),
                provider: .init(running: true, idle: true, capturedAt: instant, identity: "synthetic-provider"))
            await Task.yield()
        }
        await Task.yield()
        save()
    }

    func recover() async {
        let seconds = max(store.settings.minimumPausedSeconds, store.settings.recoverySeconds) + 6
        for _ in 0...Int(ceil(seconds / 3)) {
            instant.addTimeInterval(3)
            let running = !store.isHoldingProvider && starts > 0
            store.observe(sample: .init(percent: 0, capturedAt: instant),
                provider: .init(running: running, idle: true, capturedAt: instant,
                    identity: running ? "synthetic-provider" : nil))
            await Task.yield()
        }
        await Task.yield()
        save()
    }

    func save() {
        let result: [String: Any] = ["synthetic": true, "stops": stops, "starts": starts,
            "phase": store.phase.rawValue, "holdingProvider": store.isHoldingProvider,
            "status": store.status]
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: output, options: .atomic)
        }
    }
}
