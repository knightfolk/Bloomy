import SwiftUI

/// These short decision groups must mount every native control on first entry.
/// A lazy grid can omit offscreen choices from the window's initial key loop.
struct AdaptiveChoiceLayout: Layout {
    let minimumWidth: CGFloat
    let spacing: CGFloat
    var maximumWidth: CGFloat? = nil

    static func columns(width: CGFloat, minimumWidth: CGFloat, spacing: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 1 }
        guard width.isFinite, minimumWidth > 0, spacing >= 0 else { return 1 }
        let fitting = floor((max(0, width) + spacing) / (minimumWidth + spacing))
        return Int(min(CGFloat(count), max(1, fitting)))
    }

    static func choiceWidth(width: CGFloat, columns: Int, spacing: CGFloat, maximumWidth: CGFloat? = nil) -> CGFloat {
        let available = max(0, (width - CGFloat(max(0, columns - 1)) * spacing) / CGFloat(max(1, columns)))
        guard let maximumWidth, maximumWidth.isFinite, maximumWidth > 0 else { return available }
        return min(available, maximumWidth)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? max(0, $0) : nil } ?? minimumWidth
        let rows = measurements(width: width, subviews: subviews)
        return CGSize(width: width, height: rows.heights.reduce(0, +) + CGFloat(max(0, rows.heights.count - 1)) * spacing)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = measurements(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for (row, height) in rows.heights.enumerated() {
            for column in 0..<rows.columns {
                let index = row * rows.columns + column
                guard index < subviews.count else { break }
                subviews[index].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (rows.width + spacing), y: y),
                    anchor: .topLeading, proposal: ProposedViewSize(width: rows.width, height: height))
            }
            y += height + spacing
        }
    }

    private func measurements(width: CGFloat, subviews: Subviews) -> (columns: Int, width: CGFloat, heights: [CGFloat]) {
        let columns = Self.columns(width: width, minimumWidth: minimumWidth, spacing: spacing, count: subviews.count)
        let cardWidth = Self.choiceWidth(width: width, columns: columns, spacing: spacing, maximumWidth: maximumWidth)
        var heights: [CGFloat] = []
        for index in subviews.indices {
            let height = subviews[index].sizeThatFits(ProposedViewSize(width: cardWidth, height: nil)).height
            let row = index / columns
            if row == heights.count { heights.append(height) }
            else { heights[row] = max(heights[row], height) }
        }
        return (columns, cardWidth, heights)
    }
}

/// Existing Hosting groups retain their uncapped, equal-width layout.
typealias HostingChoiceLayout = AdaptiveChoiceLayout
