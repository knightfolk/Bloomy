import Foundation
import SwiftUI

/// One screen-level buffered signal. Revisions during a read are coalesced,
/// and an obsolete view task cannot disconnect its replacement's stream.
@MainActor
final class PerformanceMetricsRefreshEvents: ObservableObject {
    private var connection: UUID?
    private var continuation: AsyncStream<Void>.Continuation?

    func connect() -> (id: UUID, stream: AsyncStream<Void>) {
        continuation?.finish()
        let id = UUID()
        let (stream, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        connection = id
        self.continuation = continuation
        continuation.yield(())
        return (id, stream)
    }

    func requestRefresh(connection id: UUID? = nil) {
        guard id == nil || id == connection else { return }
        continuation?.yield(())
    }
    func stop(connection id: UUID? = nil) {
        guard id == nil || id == connection else { return }
        continuation?.finish()
        continuation = nil
        connection = nil
    }
}

@MainActor
enum PerformanceMetricsRevisionRefreshLoop {
    static func run(events: PerformanceMetricsRefreshEvents, cadence: Duration = .seconds(30),
                    minimumSpacing: Duration = .seconds(2), read: @MainActor () async -> Void) async {
        let connection = events.connect()
        let ticker = Task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: cadence) } catch { return }
                guard !Task.isCancelled else { return }
                events.requestRefresh(connection: connection.id)
            }
        }
        defer {
            events.stop(connection: connection.id)
        }
        for await _ in connection.stream {
            guard !Task.isCancelled else { break }
            await read()
            guard !Task.isCancelled else { break }
            // This is a rate limit after a signal, not a polling interval.
            // With no journal changes the loop sleeps until the 30s check.
            do { try await Task.sleep(for: minimumSpacing) } catch { break }
        }
        ticker.cancel()
        await ticker.value
    }
}
