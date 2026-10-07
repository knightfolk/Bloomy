import DarkbloomTelemetry
import SwiftUI

/// Observe the existing journal only while this surface is mounted. There is no
/// second recorder, query loop or provider command owned by the chart.
struct RecordedModelVisitTimeline: View {
    @ObservedObject var history: ActionHistoryStore
    let data: ModelVisitTimelineData
    let activity: PerformanceActivityHistory?
    let model: String?
    let withoutWorkOnly: Bool
    let isVisible: Bool
    @State private var completed: ActionTimelineRead?

    private var query: ActionTimelineQuery {
        .init(events: history.events, range: data.range, model: model, isVisible: isVisible)
    }

    var body: some View {
        let requested = query
        let shown = completed?.presentation(for: requested)
        ModelVisitTimeline(data: data, withoutWorkOnly: withoutWorkOnly, activity: activity,
            actions: shown ?? ActionTimelineData(events: [], range: data.range, model: model),
            actionNotice: history.storageError ?? (shown == nil ? "Reading retained actions…" : nil),
            actionModel: model)
            .task(id: requested) {
                guard requested.isVisible else { completed = nil; return }
                let worker = Task.detached(priority: .utility) { () -> ActionTimelineData? in
                    guard !Task.isCancelled else { return nil }
                    let data = ActionTimelineData(events: requested.events, range: requested.range, model: requested.model)
                    return Task.isCancelled ? nil : data
                }
                let result = await withTaskCancellationHandler {
                    await worker.value
                } onCancel: { worker.cancel() }
                guard let result, !Task.isCancelled else { return }
                completed = .init(query: requested, data: result)
            }
    }
}

struct ActionTimelineQuery: Equatable, Sendable {
    let events: [ActionHistoryEvent]
    let range: DateInterval
    let model: String?
    let isVisible: Bool
}

struct ActionTimelineRead {
    let query: ActionTimelineQuery
    let data: ActionTimelineData

    /// Never relabel another period/model or an obsolete same-ID outcome as
    /// current evidence. Clock expiry alone does not rebuild action geometry.
    func presentation(for requested: ActionTimelineQuery) -> ActionTimelineData? {
        guard requested.isVisible, requested == query else { return nil }
        return data
    }
}
