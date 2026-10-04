import AppKit
import SwiftUI

enum PopupPresentationBudget {
    // Leave room for the popover arrow and the screen edge. The usable frame
    // already excludes the menu bar and Dock.
    static let placementAllowance: CGFloat = 20

    static func maximumContentHeight(visibleFrame: NSRect?, anchorFrame: NSRect?) -> CGFloat? {
        guard let visibleFrame, valid(visibleFrame) else { return nil }
        var available = visibleFrame.height
        if let anchorFrame, valid(anchorFrame) {
            let below = max(0, min(visibleFrame.maxY, anchorFrame.minY) - visibleFrame.minY)
            let above = max(0, visibleFrame.maxY - max(visibleFrame.minY, anchorFrame.maxY))
            // AppKit may flip the preferred edge when the other side has room.
            available = max(below, above)
        }
        return min(visibleFrame.height, max(1, floor(available - placementAllowance)))
    }

    private static func valid(_ rect: NSRect) -> Bool {
        [rect.minX, rect.minY, rect.maxX, rect.maxY, rect.width, rect.height].allSatisfy(\.isFinite)
            && rect.width > 0 && rect.height > 0
    }
}

private struct PopupContentHeightBudgetKey: EnvironmentKey {
    static let defaultValue: CGFloat? = nil
}

extension EnvironmentValues {
    var popupContentHeightBudget: CGFloat? {
        get { self[PopupContentHeightBudgetKey.self] }
        set { self[PopupContentHeightBudgetKey.self] = newValue }
    }
}

@MainActor
final class PopupPresentationLayoutBudget: ObservableObject {
    @Published var maximumContentHeight: CGFloat?
}

struct PopoverFittingRoot<Content: View>: View {
    let content: Content
    @ObservedObject var budget: PopupPresentationLayoutBudget

    var body: some View {
        content.environment(\.popupContentHeightBudget, budget.maximumContentHeight)
    }
}

/// An explicit native document extent is essential when the fixed chrome
/// itself exceeds the viewport. SwiftUI's nested ScrollView can otherwise
/// expose a zero-height AppKit document despite a larger custom Layout.
struct PopupScrollingViewport<Content: View>: NSViewRepresentable {
    let width: CGFloat
    let maximumHeight: CGFloat?
    let content: Content

    init(width: CGFloat, maximumHeight: CGFloat?, @ViewBuilder content: () -> Content) {
        self.width = width
        self.maximumHeight = maximumHeight
        self.content = content()
    }

    func makeNSView(context: Context) -> PopupScrollView<Content> {
        PopupScrollView(content: content, environment: context.environment, width: width, maximumHeight: maximumHeight)
    }

    func updateNSView(_ view: PopupScrollView<Content>, context: Context) {
        view.update(content: content, environment: context.environment, width: width, maximumHeight: maximumHeight)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: PopupScrollView<Content>, context: Context) -> CGSize? {
        nsView.measureDocument()
        return nsView.intrinsicContentSize
    }

    static func dismantleNSView(_ view: PopupScrollView<Content>, coordinator: ()) { view.invalidate() }
}

private struct PopupScrollDocument<Content: View>: View {
    let content: Content?
    let environment: EnvironmentValues
    let width: CGFloat

    var body: some View {
        if let content {
            content.environment(\.self, environment)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: width, alignment: .topLeading)
        }
    }
}

@MainActor
final class PopupScrollView<Content: View>: NSScrollView {
    private let host: PopupScrollDocumentController<Content>
    private var contentWidth: CGFloat
    private var maximumHeight: CGFloat?
    private var documentSize = NSSize.zero
    private var needsInitialScrollPosition = true
    private var pendingMeasurement: Task<Void, Never>?
    private var isInvalidated = false

    init(content: Content, environment: EnvironmentValues, width: CGFloat, maximumHeight: CGFloat?) {
        contentWidth = width
        self.maximumHeight = maximumHeight
        host = PopupScrollDocumentController(rootView: PopupScrollDocument(content: content, environment: environment, width: width))
        super.init(frame: .zero)
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        // Keep the full 528pt document width independently of the Mac's
        // scrollbar preference; this does not change any system setting.
        scrollerStyle = .overlay
        horizontalScrollElasticity = .none
        documentView = host.view
        setAccessibilityIdentifier("popover.outerScroll")
        setAccessibilityLabel("Popup content")
        host.sizeChanged = { [weak self] size in self?.setDocumentSize(size) }
        host.sizingOptions = .preferredContentSize
        measureDocument()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(content:environment:width:maximumHeight:)") }

    func update(content: Content, environment: EnvironmentValues, width: CGFloat, maximumHeight: CGFloat?) {
        guard !isInvalidated else { return }
        let oldSize = intrinsicContentSize
        let widthChanged = contentWidth != width
        contentWidth = width
        self.maximumHeight = maximumHeight
        host.rootView = PopupScrollDocument(content: content, environment: environment, width: width)
        // Several observed sources can arrive in one UI cycle. Fit their latest
        // content once, while keeping width changes and layout requests immediate.
        if widthChanged { measureDocument() } else { scheduleMeasurement() }
        if intrinsicContentSize != oldSize { invalidateIntrinsicContentSize() }
    }

    private func scheduleMeasurement() {
        guard pendingMeasurement == nil else { return }
        pendingMeasurement = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled, let self, !self.isInvalidated else { return }
            self.pendingMeasurement = nil
            self.measureDocument()
        }
    }

    func measureDocument() {
        guard !isInvalidated else { return }
        pendingMeasurement?.cancel()
        pendingMeasurement = nil
        setDocumentSize(host.sizeThatFits(in: NSSize(width: contentWidth, height: 0)))
    }

    private func setDocumentSize(_ proposed: NSSize) {
        guard proposed.height.isFinite, proposed.height > 0, contentWidth.isFinite, contentWidth > 0 else { return }
        let size = NSSize(width: contentWidth, height: ceil(proposed.height))
        guard documentSize != size else { return }
        documentSize = size
        host.view.frame = NSRect(origin: .zero, size: size)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: contentWidth, height: min(documentSize.height, maximumHeight ?? documentSize.height))
    }

    override func layout() {
        super.layout()
        if needsInitialScrollPosition, contentView.bounds.height > 0, documentSize.height > 0 {
            let y = host.view.isFlipped ? 0 : max(0, documentSize.height - contentView.bounds.height)
            contentView.scroll(to: NSPoint(x: 0, y: y))
            reflectScrolledClipView(contentView)
            needsInitialScrollPosition = false
        }
    }

    func invalidate() {
        isInvalidated = true
        pendingMeasurement?.cancel()
        pendingMeasurement = nil
        host.sizeChanged = nil
        host.sizingOptions = []
        // Release the hosted SwiftUI subtree even if AppKit retains this view.
        host.rootView = PopupScrollDocument(content: nil, environment: host.rootView.environment, width: contentWidth)
        documentView = nil
    }
}

@MainActor
private final class PopupScrollDocumentController<Content: View>: NSHostingController<PopupScrollDocument<Content>> {
    var sizeChanged: ((NSSize) -> Void)?
    override var preferredContentSize: NSSize { didSet { sizeChanged?(preferredContentSize) } }
}

/// Keep AppKit's placement size in step with SwiftUI's ideal content size.
/// Otherwise intrinsic sizing can enlarge the hosted view after the popover
/// has positioned itself, putting the header outside the visible screen.
@MainActor
final class FittingPopoverHostingController<Content: View>: NSHostingController<PopoverFittingRoot<Content>> {
    private weak var popover: NSPopover?
    private weak var presentationAnchor: NSView?
    private let layoutBudget: PopupPresentationLayoutBudget
    private var injectedMaximumContentHeight: CGFloat?

    var content: Content {
        get { rootView.content }
        set { rootView = PopoverFittingRoot(content: newValue, budget: layoutBudget) }
    }

    init(rootView: Content, popover: NSPopover) {
        let budget = PopupPresentationLayoutBudget()
        layoutBudget = budget
        super.init(rootView: PopoverFittingRoot(content: rootView, budget: budget))
        self.popover = popover
        sizingOptions = .preferredContentSize
        NotificationCenter.default.addObserver(self, selector: #selector(screenBudgetChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(rootView:popover:)") }

    override var preferredContentSize: NSSize {
        didSet { synchronizeSize(preferredContentSize) }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func prepareForPresentation(anchorView: NSView? = nil, maximumContentHeight: CGFloat? = nil) {
        if let anchorView {
            presentationAnchor = anchorView
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeScreenNotification, object: nil)
            if let window = anchorView.window {
                NotificationCenter.default.addObserver(self, selector: #selector(screenBudgetChanged),
                    name: NSWindow.didChangeScreenNotification, object: window)
            }
        }
        injectedMaximumContentHeight = maximumContentHeight.flatMap { $0.isFinite && $0 > 0 ? max(1, floor($0)) : nil }
        updateHeightBudget()
        view.layoutSubtreeIfNeeded()
        synchronizeSize(sizeThatFits(in: NSSize(width: 560, height: 0)))
    }

    @objc private func screenBudgetChanged() {
        updateHeightBudget()
        view.layoutSubtreeIfNeeded()
        synchronizeSize(sizeThatFits(in: NSSize(width: 560, height: 0)))
    }

    private func updateHeightBudget() {
        let window = presentationAnchor?.window
        let anchorFrame: NSRect?
        if let anchor = presentationAnchor, let window {
            anchorFrame = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        } else {
            anchorFrame = nil
        }
        let height = injectedMaximumContentHeight ?? PopupPresentationBudget.maximumContentHeight(
            visibleFrame: window?.screen?.visibleFrame, anchorFrame: anchorFrame)
        if layoutBudget.maximumContentHeight != height { layoutBudget.maximumContentHeight = height }
    }

    private func synchronizeSize(_ proposed: NSSize) {
        guard proposed.width.isFinite, proposed.height.isFinite,
              proposed.width > 0, proposed.height > 0, let popover else { return }
        let fitted = NSSize(width: ceil(proposed.width), height: ceil(proposed.height))
        guard popover.contentSize != fitted else { return }
        popover.contentSize = fitted
    }
}
