import SwiftUI
import Testing
@testable import DarkbloomMonitor

@Suite("Metrics native picker ownership")
@MainActor
struct MetricsSegmentedPickerTests {
    @Test("confirmed visit changes invalidate retained configuration despite shared live binding")
    func visitSelectionBinding() {
        checkBinding(initial: false, changed: true)
    }

    @Test("confirmed period changes invalidate retained configuration despite shared live binding")
    func periodSelectionBinding() {
        checkBinding(initial: PerformanceMetricsPeriod.last24Hours, changed: .last7Days)
    }

    private func checkBinding<Value: Hashable & Sendable>(initial: Value, changed: Value) {
        let owner = SelectionOwner(initial)
        let binding = Binding(get: { owner.value }, set: { owner.value = $0 })
        let options: [MetricsSegmentedOption<Value>] = [
            .init(title: "First", value: initial), .init(title: "Second", value: changed),
        ]
        let retained = MetricsSegmentedPicker(title: "Metrics", selection: owner.value,
            selectionBinding: binding, options: options)
        binding.wrappedValue = changed
        let updated = MetricsSegmentedPicker(title: "Metrics", selection: owner.value,
            selectionBinding: binding, options: options)
        // Both live bindings already see the new value; comparing them would
        // incorrectly skip the native update that commits the new selection.
        #expect(retained.selectionBinding == changed)
        #expect(updated.selectionBinding == changed)
        #expect(retained != updated)
        #expect(retained.selection == initial)
        updated.selectionBinding = initial
        #expect(owner.value == initial)
        #expect(retained == MetricsSegmentedPicker(title: "Metrics", selection: owner.value,
            selectionBinding: binding, options: options))
    }
}

@MainActor
private final class SelectionOwner<Value> {
    var value: Value
    init(_ value: Value) { self.value = value }
}
