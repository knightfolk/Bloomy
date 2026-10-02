import AppKit

/// Keeps AppKit running until one owned cleanup task has finished.
@MainActor
final class ApplicationTerminationGate {
    private var cleanupTask: Task<Void, Never>?
    private var cleanupCompleted = false

    func requestTermination(
        cleanup: @escaping @MainActor () async -> Void,
        retryTermination: @escaping @MainActor () -> Void
    ) -> NSApplication.TerminateReply {
        if cleanupCompleted { return .terminateNow }
        guard cleanupTask == nil else { return .terminateCancel }

        // Let the invoking MainActor job return. AppKit's terminateLater
        // nested loop can otherwise prevent async cleanup from running.
        cleanupTask = Task { @MainActor in
            await cleanup()
            cleanupCompleted = true
            cleanupTask = nil
            retryTermination()
        }
        return .terminateCancel
    }
}
