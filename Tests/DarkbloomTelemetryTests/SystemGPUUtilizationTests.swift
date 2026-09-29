import Foundation
import Testing
@testable import DarkbloomMonitor

@Suite("System GPU utilization")
struct SystemGPUUtilizationTests {
    @Test("reads a numeric IOAccelerator device utilization percentage")
    func parsesDevicePercentage() {
        #expect(SystemGPUUtilization.devicePercentage(from: ["Device Utilization %": NSNumber(value: 72)]) == 72)
    }

    @Test("rejects missing, boolean, and out-of-range utilization values")
    func rejectsInvalidValues() {
        #expect(SystemGPUUtilization.devicePercentage(from: [:]) == nil)
        #expect(SystemGPUUtilization.devicePercentage(from: ["Device Utilization %": NSNumber(value: true)]) == nil)
        #expect(SystemGPUUtilization.devicePercentage(from: ["Device Utilization %": NSNumber(value: -1)]) == nil)
        #expect(SystemGPUUtilization.devicePercentage(from: ["Device Utilization %": NSNumber(value: 101)]) == nil)
        #expect(SystemGPUUtilization.validPercentage(.nan) == nil)
        #expect(SystemGPUUtilization.validPercentage(.infinity) == nil)
    }

    @Test("averages valid GPU readings and reports unavailable when none are valid")
    func averagesAvailableDevices() {
        #expect(SystemGPUUtilization.average([25, 75, 101, .nan]) == 50)
        #expect(SystemGPUUtilization.average([]) == nil)
        #expect(SystemGPUUtilization.average([-2, 101]) == nil)
    }

    @Test("GPU usage store retains a captured last sample through failed reads without presenting it as current")
    @MainActor
    func storeRefreshes() throws {
        let sample = GPUReadingBox(value: 48)
        let store = SystemGPUUsageStore(read: { sample.value })

        store.refresh()
        #expect(store.percentage == 48)
        let firstCapturedAt = try #require(store.sampledAt)
        #expect(store.reading() == .current(percentage: 48, sampledAt: firstCapturedAt))

        sample.value = nil
        store.refresh()
        #expect(store.percentage == nil)
        #expect(store.sampledAt == nil)
        #expect(store.lastGoodPercentage == 48)
        #expect(store.lastGoodSampledAt == firstCapturedAt)
        #expect(store.reading() == .stale(percentage: 48, sampledAt: firstCapturedAt))
        #expect(store.reading(at: firstCapturedAt.addingTimeInterval(11)) == .stale(
            percentage: 48, sampledAt: firstCapturedAt
        ))

        sample.value = 64
        store.refresh()
        #expect(store.percentage == 64)
        #expect(store.lastGoodPercentage == 64)
        #expect(store.lastGoodSampledAt == store.sampledAt)

        store.stop()
        #expect(store.reading() == .unavailable)
    }
}

@MainActor
private final class GPUReadingBox {
    var value: Double?

    init(value: Double?) {
        self.value = value
    }
}
