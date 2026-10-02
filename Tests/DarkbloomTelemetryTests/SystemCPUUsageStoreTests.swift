import Foundation
import Testing
@testable import DarkbloomMonitor
@testable import DarkbloomTelemetry

@MainActor
struct SystemCPUUsageStoreTests {
    @Test("CPU store publishes measured host-wide changes and clears on a counter reset")
    func publishesMeasuredSystemUtilization() {
        let sample = CPUSampleBox()
        let store = SystemCPUUsageStore(read: { sample.current })

        store.refresh()
        #expect(store.percentage == nil)
        sample.current = SystemCPUTimes(user: 115, system: 55, nice: 0, idle: 930)
        store.refresh()
        #expect(store.percentage == 20)
        #expect(store.sampledAt != nil)

        sample.current = SystemCPUTimes(user: 1, system: 1, nice: 0, idle: 1)
        store.refresh()
        #expect(store.percentage == nil)
        #expect(store.sampledAt == nil)
    }

    @Test("macOS host sampler reads real cumulative CPU counters")
    func readsHostCounters() {
        #expect(MacHostCPUSampler.read() != nil)
    }

    @Test("stopping before the sampler task begins prevents its initial read")
    func cancelledQueuedStartDoesNotRead() async throws {
        var reads = 0
        let store = SystemCPUUsageStore(interval: .milliseconds(25), read: {
            reads += 1
            return SystemCPUTimes(user: 1, system: 0, nice: 0, idle: 1)
        })
        store.start()
        store.stop()
        try await Task.sleep(for: .milliseconds(100))
        #expect(reads == 0)
        #expect(store.percentage == nil)
        #expect(store.sampledAt == nil)
    }
}

@MainActor
private final class CPUSampleBox {
    var current = SystemCPUTimes(user: 100, system: 50, nice: 0, idle: 850)
}
