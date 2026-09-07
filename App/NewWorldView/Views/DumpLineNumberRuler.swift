import AppKit

final class DumpLineNumberGutterView: NSView {
    enum Source {
        case text(NSTextView)
        case table(NSTableView, rowHeight: CGFloat)
    }

    private(set) var source: Source
    weak var scrollView: NSScrollView?
    var ruleThickness: CGFloat = 44
    private var boundsObserver: NSObjectProtocol?
    private var lineStartOffsets: [Int] = [0]
    private var pendingRedraw = false

    private static let numberFont = NSFont.monospacedSystemFont(ofSize: 10, weight: .regular)
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .font: numberFont,
        .foregroundColor: NSColor.secondaryLabelColor
    ]

    override var isFlipped: Bool { true }

    init(source: Source, scrollView: NSScrollView) {
        self.source = source
        self.scrollView = scrollView
        super.init(frame: .zero)
        // macOS 14+ defaults clipsToBounds to false; without this the dirty rect
        // handed to draw(_:) can span the sibling scroll view and the background
        // fill paints over the text.
        clipsToBounds = true
        observeScrollBounds(scrollView.contentView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil, let boundsObserver {
            NotificationCenter.default.removeObserver(boundsObserver)
            self.boundsObserver = nil
        }
        super.viewWillMove(toWindow: newWindow)
    }

    func refresh(lineCount: Int, lineStartOffsets: [Int]? = nil) {
        if let lineStartOffsets {
            self.lineStartOffsets = lineStartOffsets
        }
        let digits = max(3, String(max(1, lineCount)).count)
        ruleThickness = CGFloat(digits * 8 + 20)
        superview?.needsLayout = true
        setNeedsDisplay(bounds)
    }

    override func draw(_ dirtyRect: NSRect) {
        let fillRect = bounds.intersection(dirtyRect)
        guard !fillRect.isEmpty else { return }

        NSColor.controlBackgroundColor.setFill()
        fillRect.fill()

        let separatorX = bounds.maxX - 0.5
        NSColor.separatorColor.setStroke()
        let path = NSBezierPath()
        path.move(to: NSPoint(x: separatorX, y: fillRect.minY))
        path.line(to: NSPoint(x: separatorX, y: fillRect.maxY))
        path.lineWidth = 1
        path.stroke()

        switch source {
        case .text(let textView):
            drawTextLineNumbers(textView, separatorX: separatorX, clipRect: fillRect)
        case .table(let tableView, let rowHeight):
            drawTableLineNumbers(tableView, rowHeight: rowHeight, separatorX: separatorX, clipRect: fillRect)
        }
    }

    private func drawTextLineNumbers(_ textView: NSTextView, separatorX: CGFloat, clipRect: NSRect) {
        guard let layoutManager = textView.layoutManager, let textContainer = textView.textContainer else {
            return
        }

        let inset = textView.textContainerInset
        let visibleRect = scrollView?.contentView.documentVisibleRect ?? .zero
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: visibleRect.insetBy(dx: 0, dy: -inset.height),
            in: textContainer
        )

        var lineNumber = 1
        var started = false
        layoutManager.enumerateLineFragments(forGlyphRange: glyphRange) { fragmentRect, _, _, glyphRange, _ in
            if !started {
                let characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
                lineNumber = self.lineNumber(for: characterRange.location)
                started = true
            }
            let y = fragmentRect.minY + inset.height - visibleRect.origin.y
                + (fragmentRect.height - Self.numberFont.boundingRectForFont.height) / 2
            guard y + Self.numberFont.boundingRectForFont.height >= clipRect.minY,
                  y <= clipRect.maxY else {
                lineNumber += 1
                return
            }
            self.drawLabel("\(lineNumber)", xRight: separatorX, y: y)
            lineNumber += 1
        }
    }

    private func drawTableLineNumbers(
        _ tableView: NSTableView,
        rowHeight: CGFloat,
        separatorX: CGFloat,
        clipRect: NSRect
    ) {
        let visible = scrollView?.contentView.documentVisibleRect ?? .zero
        let firstRow = max(0, Int(floor(visible.origin.y / rowHeight)))
        let lastRow = min(max(tableView.numberOfRows - 1, 0), Int(floor(visible.maxY / rowHeight)))
        guard firstRow <= lastRow else { return }
        for row in firstRow...lastRow {
            let y = CGFloat(row) * rowHeight - visible.origin.y
                + (rowHeight - Self.numberFont.boundingRectForFont.height) / 2
            guard y + Self.numberFont.boundingRectForFont.height >= clipRect.minY,
                  y <= clipRect.maxY else { continue }
            drawLabel("\(row + 1)", xRight: separatorX, y: y)
        }
    }

    private func drawLabel(_ text: String, xRight: CGFloat, y: CGFloat) {
        let label = text as NSString
        let size = label.size(withAttributes: Self.labelAttributes)
        label.draw(at: NSPoint(x: xRight - size.width - 6, y: y), withAttributes: Self.labelAttributes)
    }

    private func lineNumber(for location: Int) -> Int {
        guard !lineStartOffsets.isEmpty else { return 1 }
        var low = 0
        var high = lineStartOffsets.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lineStartOffsets[mid] <= location {
                low = mid
            } else {
                high = mid - 1
            }
        }
        return low + 1
    }

    private func observeScrollBounds(_ clipView: NSClipView) {
        clipView.postsBoundsChangedNotifications = true
        boundsObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification,
            object: clipView,
            queue: .main
        ) { [weak self] _ in
            self?.scheduleRedraw()
        }
    }

    private func scheduleRedraw() {
        guard !pendingRedraw else { return }
        pendingRedraw = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.pendingRedraw = false
            self.setNeedsDisplay(self.bounds)
        }
    }
}

enum DumpLineNumberRulerSupport {
    static func attachTextGutter(to column: DumpColumnView, textView: NSTextView) -> DumpLineNumberGutterView {
        let gutter = DumpLineNumberGutterView(source: .text(textView), scrollView: column.scrollView)
        column.attachGutter(gutter)
        return gutter
    }

    static func attachTableGutter(
        to column: DumpColumnView,
        tableView: NSTableView,
        rowHeight: CGFloat
    ) -> DumpLineNumberGutterView {
        let gutter = DumpLineNumberGutterView(
            source: .table(tableView, rowHeight: rowHeight),
            scrollView: column.scrollView
        )
        column.attachGutter(gutter)
        return gutter
    }

    static func lineStartOffsets(for text: String) -> [Int] {
        var offsets = [0]
        var location = 0
        for character in text {
            let length = character.utf16.count
            location += length
            if character == "\n" {
                offsets.append(location)
            }
        }
        return offsets
    }
}
