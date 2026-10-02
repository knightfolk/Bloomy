import AppKit
import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Visibility-aware display clocks", .serialized)
@MainActor
struct VisibilityTimelineScheduleTests {
    @Test("hidden display schedules emit only their initial date", arguments: [1.0, 2.0, 5.0, 10.0, 60.0])
    func hiddenIsFinite(interval: TimeInterval) {
        let start = Date(timeIntervalSince1970: 1_003)
        let schedule = VisibilityTimelineSchedule(
            base: PeriodicTimelineSchedule(from: start, by: interval), isVisible: false
        )
        for mode in [TimelineScheduleMode.normal, .lowFrequency] {
            #expect(Array(schedule.entries(from: start, mode: mode)) == [start])
        }
    }

    @Test("visible periodic display clocks keep their existing cadence", arguments: [1.0, 2.0, 5.0, 10.0, 60.0])
    func visibleCadence(interval: TimeInterval) {
        let start = Date(timeIntervalSince1970: 1_003)
        var dates = VisibilityTimelineSchedule(
            base: PeriodicTimelineSchedule(from: start, by: interval), isVisible: true
        ).entries(from: start, mode: .normal)
        #expect(dates.next() == start)
        #expect(dates.next() == start.addingTimeInterval(interval))
        #expect(dates.next() == start.addingTimeInterval(interval * 2))
    }

    @Test("minute-based schedules retain calendar boundaries after an immediate current date")
    func minuteAlignment() throws {
        let start = Date(timeIntervalSince1970: 1_003)
        let base = EveryMinuteTimelineSchedule()
        var original = base.entries(from: start, mode: .normal).makeIterator()
        var wrapped = VisibilityTimelineSchedule(base: base, isVisible: true)
            .entries(from: start, mode: .normal)
        #expect(wrapped.next() == start)
        let initialBoundary = original.next()
        var nextBoundary = try #require(initialBoundary)
        while nextBoundary <= start {
            let followingBoundary = original.next()
            nextBoundary = try #require(followingBoundary)
        }
        #expect(wrapped.next() == nextBoundary)
        #expect(wrapped.next() == original.next())
        #expect(Array(VisibilityTimelineSchedule(base: base, isVisible: false)
            .entries(from: start, mode: .normal)) == [start])
    }

    @Test("hiding ends future entries and restoring starts at a fresh date")
    func hideAndRestore() {
        let originalStart = Date(timeIntervalSince1970: 1_003)
        let hiddenAt = originalStart.addingTimeInterval(17)
        let restoredAt = hiddenAt.addingTimeInterval(120)
        let base = PeriodicTimelineSchedule(from: originalStart, by: 5)
        #expect(Array(VisibilityTimelineSchedule(base: base, isVisible: false)
            .entries(from: hiddenAt, mode: .normal)) == [hiddenAt])
        var restored = VisibilityTimelineSchedule(base: base, isVisible: true)
            .entries(from: restoredAt, mode: .normal)
        #expect(restored.next() == restoredAt)
        // Continue on the original phase, rather than shifting the cadence.
        #expect(restored.next() == originalStart.addingTimeInterval(140))
        #expect(restored.next() == originalStart.addingTimeInterval(145))
    }

    @Test("a retained native hosting view stops scheduled display dates while hidden and resumes on restoration")
    func retainedHostLifecycle() async throws {
        let visibility = DisplayClockVisibility()
        let recorder = DisplayClockRecorder()
        let host = NSHostingView(rootView: DisplayClockProbe(visibility: visibility, recorder: recorder))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 180, height: 60),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderBack(nil)
        defer { window.close() }
        try await waitUntil { recorder.dates.count >= 3 }

        visibility.isVisible = false
        // Allow the mounted tree to replace its old schedule before measuring.
        try await Task.sleep(for: .milliseconds(150))
        let hiddenDates = recorder.dates
        try await Task.sleep(for: .milliseconds(250))
        #expect(recorder.dates == hiddenDates)

        let restoredAt = Date()
        visibility.isVisible = true
        try await waitUntil { recorder.dates.contains(where: { $0 >= restoredAt }) }
        let restoredCount = recorder.dates.count
        try await waitUntil { recorder.dates.count >= restoredCount + 2 }
        #expect(window.contentView === host)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<100 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("Native display clock did not reach the expected lifecycle state")
    }
}

@MainActor
private final class DisplayClockVisibility: ObservableObject {
    @Published var isVisible = true
}

@MainActor
private final class DisplayClockRecorder {
    var dates: Set<Date> = []
    func record(_ date: Date) -> String {
        dates.insert(date)
        return date.formatted(date: .omitted, time: .standard)
    }
}

private struct DisplayClockProbe: View {
    @ObservedObject var visibility: DisplayClockVisibility
    let recorder: DisplayClockRecorder

    var body: some View {
        TimelineView(VisibilityTimelineSchedule(
            base: .periodic(from: .now, by: 0.05), isVisible: visibility.isVisible
        )) { context in
            Text(recorder.record(context.date))
        }
    }
}
