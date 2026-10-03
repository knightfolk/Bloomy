import SwiftUI

struct MetricsSegmentedOption<Selection: Hashable & Sendable>: Equatable, Sendable {
    let title: String
    let value: Selection
}

/// Unchanged measurements need not reconfigure a native picker, overwriting
/// its pending keyboard highlight before Space confirms the chosen segment.
struct MetricsSegmentedPicker<Selection: Hashable & Sendable>: View, Equatable {
    let title: String
    let selection: Selection
    @Binding var selectionBinding: Selection
    let options: [MetricsSegmentedOption<Selection>]

    // Compare the immutable value, not two bindings to the same live storage.
    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.title == rhs.title && lhs.selection == rhs.selection && lhs.options == rhs.options
    }

    var body: some View {
        Picker(title, selection: $selectionBinding) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .labelsHidden().pickerStyle(.segmented)
    }
}
