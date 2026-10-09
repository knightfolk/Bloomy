import DarkbloomTelemetry
import SwiftUI

/// One visible-screen query for all models. Search and card appearance do not
/// initiate storage work; a completed immutable report owns its range and scale.
struct ModelDemandHistoryScope<Content: View>: View {
    let store: NetworkDemandHistoryStore?
    let isVisible: Bool
    @ViewBuilder let content: (ModelDemandHistoryPresentation?) -> Content

    var body: some View {
        if let store {
            ModelDemandHistoryReader(store: store, isVisible: isVisible, content: content)
        } else {
            content(nil)
        }
    }
}

private struct ModelDemandHistoryReadInput: Equatable {
    let revision: UInt64
    let retry: UInt64
    let visible: Bool
}

/// One cadence for the visible scope also advances its time window when the
/// network is unavailable. It does not acquire capacity or run per-card work.
@MainActor
enum ModelDemandHistoryReadLoop {
    static func run(now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping @Sendable (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) },
        read: @escaping @MainActor (DateInterval) async throws -> NetworkDemandHistoryReport,
        publish: @escaping @MainActor (Result<ModelDemandHistoryPresentation, Error>) -> Void) async {
        while !Task.isCancelled {
            let end = now()
            let range = DateInterval(start: end.addingTimeInterval(-86_400), end: end)
            do {
                let report = try await read(range)
                try Task.checkCancellation()
                guard report.range == range else { throw NetworkDemandHistoryDatabaseError.invalidInterval }
                let preparation = Task.detached(priority: .utility) { try ModelDemandHistoryPresentation(report: report) }
                let value = try await withTaskCancellationHandler {
                    try await preparation.value
                } onCancel: { preparation.cancel() }
                try Task.checkCancellation()
                publish(.success(value))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                publish(.failure(error))
            }
            do { try await sleep(NetworkDemandHistoryObservation.bucketSeconds) }
            catch { return }
        }
    }
}

private struct ModelDemandHistoryReader<Content: View>: View {
    @ObservedObject var store: NetworkDemandHistoryStore
    let isVisible: Bool
    let content: (ModelDemandHistoryPresentation?) -> Content
    @State private var completed: ModelDemandHistoryPresentation?
    @State private var failed = false
    @State private var retry: UInt64 = 0

    private var display: ModelDemandHistoryPresentation {
        if var completed {
            if failed { completed.state = .retained }
            return completed
        }
        return failed ? .unavailable : .pending
    }

    var body: some View {
        VStack(spacing: 6) {
            content(display)
            if failed || store.storageError != nil {
                HStack(spacing: 8) {
                    Label(store.storageError ?? "Demand history could not be read.", systemImage: "exclamationmark.circle")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer(minLength: 4)
                    Button("Retry") { retry &+= 1 }.controlSize(.small)
                }.padding(.horizontal, 12)
            }
        }
        .task(id: ModelDemandHistoryReadInput(revision: store.revision, retry: retry, visible: isVisible)) {
            guard isVisible else { completed = nil; failed = false; return }
            await ModelDemandHistoryReadLoop.run(read: { range in
                try await store.report(in: range)
            }, publish: { result in
                switch result {
                case .success(let value): completed = value; failed = false
                case .failure: failed = true
                }
            })
        }
    }
}
