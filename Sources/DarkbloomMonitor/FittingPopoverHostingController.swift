import AppKit
import SwiftUI

/// Keep AppKit's placement size in step with SwiftUI's ideal content size.
/// Otherwise intrinsic sizing can enlarge the hosted view after the popover
/// has positioned itself, putting the header outside the visible screen.
@MainActor
final class FittingPopoverHostingController<Content: View>: NSHostingController<Content> {
    private weak var popover: NSPopover?

    init(rootView: Content, popover: NSPopover) {
        super.init(rootView: rootView)
        self.popover = popover
        sizingOptions = .preferredContentSize
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(rootView:popover:)") }

    override var preferredContentSize: NSSize {
        didSet { synchronizeSize(preferredContentSize) }
    }

    func prepareForPresentation() {
        view.layoutSubtreeIfNeeded()
        synchronizeSize(sizeThatFits(in: NSSize(width: 560, height: 0)))
    }

    private func synchronizeSize(_ proposed: NSSize) {
        guard proposed.width.isFinite, proposed.height.isFinite,
              proposed.width > 0, proposed.height > 0, let popover else { return }
        let fitted = NSSize(width: ceil(proposed.width), height: ceil(proposed.height))
        guard popover.contentSize != fitted else { return }
        popover.contentSize = fitted
    }
}
