import AppKit

enum DumpScrollSupport {
    static func makeColumn() -> DumpColumnView {
        DumpColumnView(scrollView: makeScrollView(usesPredominantAxisScrolling: true))
    }

    static func makeTextColumn() -> DumpColumnView {
        DumpColumnView(scrollView: makeScrollView(usesPredominantAxisScrolling: true))
    }

    static func makeScrollView(usesPredominantAxisScrolling: Bool) -> DumpScrollView {
        let clip = DumpClipView()
        clip.drawsBackground = true
        clip.backgroundColor = .textBackgroundColor
        clip.clipsToBounds = true

        let scrollView = DumpScrollView()
        scrollView.contentView = clip
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor
        scrollView.horizontalScrollElasticity = .none
        scrollView.verticalScrollElasticity = .automatic
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.scrollerInsets = NSEdgeInsets()
        scrollView.hasVerticalRuler = false
        scrollView.hasHorizontalRuler = false
        scrollView.rulersVisible = false
        scrollView.clipsToBounds = true
        scrollView.usesPredominantAxisScrolling = usesPredominantAxisScrolling
        scrollView.allowsMagnification = false
        return scrollView
    }
}

final class DumpColumnView: NSView {
    let scrollView: DumpScrollView
    private(set) weak var gutterView: DumpLineNumberGutterView?

    init(scrollView: DumpScrollView) {
        self.scrollView = scrollView
        super.init(frame: .zero)
        addSubview(scrollView)
        clipsToBounds = true
        setContentHuggingPriority(.init(1), for: .horizontal)
        setContentHuggingPriority(.init(1), for: .vertical)
        setContentCompressionResistancePriority(.init(1), for: .horizontal)
        setContentCompressionResistancePriority(.init(1), for: .vertical)
    }

    func attachGutter(_ gutter: DumpLineNumberGutterView) {
        gutterView?.removeFromSuperview()
        gutterView = gutter
        addSubview(gutter)
        needsLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard bounds.contains(point) else { return nil }
        return super.hitTest(point)
    }

    override func layout() {
        super.layout()
        let gutterWidth = gutterView?.ruleThickness ?? 0
        gutterView?.frame = NSRect(x: 0, y: 0, width: gutterWidth, height: bounds.height)
        scrollView.frame = NSRect(
            x: gutterWidth,
            y: 0,
            width: max(0, bounds.width - gutterWidth),
            height: bounds.height
        )
    }
}

final class DumpScrollView: NSScrollView {
    var intrinsicDocumentSize: NSSize = .zero {
        didSet { tileDocument() }
    }

    var maxOriginX: CGFloat {
        guard let document = documentView else { return 0 }
        return max(0, document.frame.width - contentView.bounds.width)
    }

    override var automaticallyAdjustsContentInsets: Bool {
        get { false }
        set { super.automaticallyAdjustsContentInsets = false }
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        automaticallyAdjustsContentInsets = false
        contentInsets = NSEdgeInsets()
        scrollerInsets = NSEdgeInsets()
        horizontalScrollElasticity = .none
        clipsToBounds = true
        contentView.clipsToBounds = true
        if intrinsicDocumentSize != .zero {
            tileDocument()
        }
    }

    private var isHandlingScrollWheel = false

    override func scrollWheel(with event: NSEvent) {
        handleScrollWheel(event)
    }

    func handleScrollWheel(_ event: NSEvent) {
        if isHandlingScrollWheel { return }
        isHandlingScrollWheel = true
        defer { isHandlingScrollWheel = false }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let horizontalIntent = abs(deltaX) > abs(deltaY)

        if horizontalIntent {
            guard maxOriginX > 0 else { return }
            super.scrollWheel(with: event)
            clampHorizontal()
            return
        }

        // Vertical-dominant wheel/trackpad gestures keep the horizontal origin fixed.
        let lockedX = contentView.bounds.origin.x
        super.scrollWheel(with: event)
        let origin = contentView.bounds.origin
        if origin.x != lockedX {
            contentView.scroll(to: NSPoint(x: lockedX, y: origin.y))
            reflectScrolledClipView(contentView)
        }
    }

    override func reflectScrolledClipView(_ clipView: NSClipView) {
        super.reflectScrolledClipView(clipView)
    }

    func tileDocument() {
        guard let document = documentView else { return }
        let clip = contentView.bounds.size
        let size = NSSize(
            width: max(intrinsicDocumentSize.width, clip.width, 1),
            height: max(intrinsicDocumentSize.height, clip.height, 1)
        )
        document.setFrameSize(size)
        if document.frame.origin.x != 0 {
            document.setFrameOrigin(NSPoint(x: 0, y: document.frame.origin.y))
        }
        hasHorizontalScroller = maxOriginX > 0
    }

    func clampHorizontal() {
        let origin = contentView.bounds.origin
        let clampedX = min(max(0, origin.x), maxOriginX)
        if origin.x != clampedX {
            contentView.scroll(to: NSPoint(x: clampedX, y: origin.y))
        }
    }
}

/// Flipped clip view so (0, 0) is the top-left of NSTextView / NSTableView.
/// Only horizontal origin is clamped; do not override `bounds` (that hides the document).
final class DumpClipView: NSClipView {
    override var isFlipped: Bool { true }

    private var maxOriginX: CGFloat {
        guard let document = documentView else { return 0 }
        return max(0, document.frame.width - bounds.width)
    }

    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        rect.origin.x = min(max(0, rect.origin.x), maxOriginX)
        return rect
    }
}
