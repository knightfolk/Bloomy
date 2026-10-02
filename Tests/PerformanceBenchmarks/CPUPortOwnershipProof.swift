// Finite, own-process resource proof. Compile with the production
// SystemCPUUsageStore.swift and DarkbloomTelemetry; no app, provider, defaults,
// network, repeating task, or timer is started.
import Darwin
import Foundation

@main
enum CPUPortOwnershipProof {
    @MainActor
    static func main() {
        let result = run()
        do {
            var data = try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
            data.append(10)
            try FileHandle.standardOutput.write(contentsOf: data)
        } catch {
            let message = "CPU port ownership proof could not write its result.\n"
            try? FileHandle.standardError.write(contentsOf: Data(message.utf8))
            Darwin.exit(1)
        }
        Darwin.exit(result["passed"] as? Bool == true ? 0 : 1)
    }

    @MainActor
    private static func run() -> [String: Any] {
        let expectedReads = 512
        var completedReads = 0
        var warmReads = 0
        var before: mach_port_urefs_t = 0
        var after: mach_port_urefs_t = 0
        var failures: [String] = []
        var beforeStatus: kern_return_t = KERN_FAILURE
        var afterStatus: kern_return_t = KERN_FAILURE

        // Keep one owned reference alive while counting the production
        // sampler's acquisitions of the same host port. This defer executes
        // before main emits the result and exits, including every failure.
        let host = mach_host_self()
        defer { mach_port_deallocate(mach_task_self_, host) }
        if host == MACH_PORT_NULL || host == mach_port_t.max {
            failures.append("The proof could not acquire its baseline host port.")
        } else {
            warmReads += 1
            guard MacHostCPUSampler.read() != nil else {
                failures.append("The production sampler's warm read returned no CPU counters.")
                return failureResult(expectedReads: expectedReads, warmReads: warmReads, failures: failures)
            }
            beforeStatus = mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &before)
            if beforeStatus != KERN_SUCCESS {
                failures.append("The initial host send-right reference count could not be read.")
            } else {
                for index in 0..<expectedReads {
                    guard MacHostCPUSampler.read() != nil else {
                        failures.append("Production CPU read \(index + 1) returned no counters.")
                        break
                    }
                    completedReads += 1
                }
                afterStatus = mach_port_get_refs(mach_task_self_, host, mach_port_right_t(MACH_PORT_RIGHT_SEND), &after)
                if afterStatus != KERN_SUCCESS {
                    failures.append("The final host send-right reference count could not be read.")
                } else if after != before {
                    failures.append("Production reads changed the host send-right reference count.")
                }
            }
        }
        let passed = failures.isEmpty && completedReads == expectedReads
            && beforeStatus == KERN_SUCCESS && afterStatus == KERN_SUCCESS && after == before
        return ["proof": "cpu-host-port-ownership", "terminal": true, "passed": passed,
                "processID": Int(getpid()), "expectedReadCount": expectedReads,
                "completedReadCount": completedReads, "warmReadCount": warmReads,
                "referencesBefore": Int(before), "referencesAfter": Int(after),
                "referenceGrowth": Int(after) - Int(before),
                "beforeKernelStatus": Int(beforeStatus), "afterKernelStatus": Int(afterStatus),
                "failures": failures]
    }

    private static func failureResult(expectedReads: Int, warmReads: Int, failures: [String]) -> [String: Any] {
        ["proof": "cpu-host-port-ownership", "terminal": true, "passed": false,
         "processID": Int(getpid()), "expectedReadCount": expectedReads, "completedReadCount": 0,
         "warmReadCount": warmReads, "referencesBefore": 0, "referencesAfter": 0,
         "referenceGrowth": 0, "beforeKernelStatus": Int(KERN_FAILURE), "afterKernelStatus": Int(KERN_FAILURE),
         "failures": failures]
    }
}
