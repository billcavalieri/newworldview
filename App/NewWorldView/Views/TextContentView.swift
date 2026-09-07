import AppKit
import NewWorldROM
import SwiftUI

struct TextContentView: View {
    let text: String
    var syntax: DumpSyntaxStyle = .auto
    var scrollLinePrefix: String?
    var scrollRequestID: UUID?
    var addressSpace: AddressSpace?
    var onProgramAddressSelected: ((ProgramAddress) -> Void)?

    @EnvironmentObject private var syntaxSettings: SyntaxHighlightSettings

    var body: some View {
        MonospaceDumpView(
            text: text,
            syntax: syntax,
            palette: syntaxSettings.resolvedPalette,
            scrollLinePrefix: scrollLinePrefix,
            scrollRequestID: scrollRequestID,
            addressSpace: addressSpace,
            onProgramAddressSelected: onProgramAddressSelected
        )
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
        .clipped()
    }
}

private struct MonospaceDumpView: NSViewRepresentable {
    var text: String
    var syntax: DumpSyntaxStyle
    var palette: SyntaxHighlightPalette
    var scrollLinePrefix: String?
    var scrollRequestID: UUID?
    var addressSpace: AddressSpace?
    var onProgramAddressSelected: ((ProgramAddress) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> DumpColumnView {
        let column = DumpScrollSupport.makeTextColumn()
        let textView = Self.makeTextView()
        column.scrollView.documentView = textView
        context.coordinator.textView = textView
        let selectionHandler = DumpTextSelectionHandler()
        selectionHandler.addressSpace = addressSpace
        selectionHandler.onProgramAddressSelected = onProgramAddressSelected
        selectionHandler.onLineHighlight = { range in
            context.coordinator.applyHighlightedLine(range)
        }
        textView.delegate = selectionHandler
        context.coordinator.selectionHandler = selectionHandler
        context.coordinator.lineNumberGutter = DumpLineNumberRulerSupport.attachTextGutter(
            to: column,
            textView: textView
        )
        apply(text: text, syntax: syntax, palette: palette, to: column.scrollView, coordinator: context.coordinator)
        return column
    }

    func updateNSView(_ column: DumpColumnView, context: Context) {
        guard let textView = context.coordinator.textView else { return }
        let scrollView = column.scrollView
        if context.coordinator.plainText != text
            || context.coordinator.syntax != syntax
            || context.coordinator.palette != palette {
            apply(text: text, syntax: syntax, palette: palette, to: scrollView, coordinator: context.coordinator)
        } else if abs(context.coordinator.cachedScrollWidth - scrollView.contentView.bounds.width) > 1 {
            sizeDocument(in: scrollView, textView: textView, coordinator: context.coordinator)
        }
        context.coordinator.selectionHandler?.addressSpace = addressSpace
        context.coordinator.selectionHandler?.onProgramAddressSelected = onProgramAddressSelected
        context.coordinator.selectionHandler?.onLineHighlight = { range in
            context.coordinator.applyHighlightedLine(range)
        }
        if scrollRequestID == nil {
            context.coordinator.clearNavigationHighlight()
        } else if scrollRequestID != context.coordinator.lastScrollRequestID {
            scrollToLineIfNeeded(coordinator: context.coordinator)
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: DumpColumnView, context: Context) -> CGSize? {
        guard let width = proposal.width, let height = proposal.height else { return nil }
        return CGSize(width: width, height: height)
    }

    private func apply(
        text: String,
        syntax: DumpSyntaxStyle,
        palette: SyntaxHighlightPalette,
        to scrollView: DumpScrollView,
        coordinator: Coordinator
    ) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        let content = text.isEmpty ? " " : text
        let highlighted = DumpSyntaxHighlighter.highlight(content, style: syntax, palette: palette)
        textView.textStorage?.setAttributedString(highlighted)
        coordinator.plainText = text
        coordinator.syntax = syntax
        coordinator.palette = palette
        coordinator.cachedDocumentSize = nil
        coordinator.cachedLongestLineWidth = 0
        coordinator.clearLineHighlight(in: textView)
        if scrollRequestID == nil {
            coordinator.highlightLinePrefix = nil
            coordinator.lastScrollRequestID = nil
        }
        coordinator.selectionHandler?.resetReporting()
        let lineCount = max(1, content.components(separatedBy: "\n").count)
        coordinator.lineNumberGutter?.refresh(
            lineCount: lineCount,
            lineStartOffsets: DumpLineNumberRulerSupport.lineStartOffsets(for: content)
        )
        sizeDocument(in: scrollView, textView: textView, coordinator: coordinator)
        scrollView.contentView.scroll(to: .zero)
        if scrollRequestID != nil {
            coordinator.lastScrollRequestID = nil
            scrollToLineIfNeeded(coordinator: coordinator)
        } else {
            coordinator.clearNavigationHighlight()
        }
    }

    private func sizeDocument(
        in scrollView: DumpScrollView,
        textView: NSTextView,
        coordinator: Coordinator
    ) {
        guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
        let scrollWidth = scrollView.contentView.bounds.width
        if let cached = coordinator.cachedDocumentSize,
           abs(coordinator.cachedScrollWidth - scrollWidth) <= 1,
           textView.frame.size == cached {
            scrollView.intrinsicDocumentSize = cached
            return
        }

        layout.ensureLayout(for: container)
        let used = layout.usedRect(for: container)
        let inset = textView.textContainerInset
        let layoutWidth = ceil(used.maxX + inset.width * 2)
        let layoutHeight = ceil(used.maxY + inset.height * 2 + 8)
        let measuredWidth = max(
            layoutWidth,
            coordinator.cachedLongestLineWidth > 0
                ? coordinator.cachedLongestLineWidth
                : longestLineWidth(in: textView, coordinator: coordinator),
            scrollWidth
        )
        let size = NSSize(
            width: max(measuredWidth, 1),
            height: max(layoutHeight, 1)
        )
        textView.minSize = size
        scrollView.intrinsicDocumentSize = size
        coordinator.cachedDocumentSize = size
        coordinator.cachedScrollWidth = scrollWidth
    }

    private func longestLineWidth(in textView: NSTextView, coordinator: Coordinator) -> CGFloat {
        if coordinator.cachedLongestLineWidth > 0 {
            return coordinator.cachedLongestLineWidth
        }
        let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        var widest: CGFloat = 0
        textView.string.enumerateLines { line, _ in
            widest = max(widest, (line as NSString).size(withAttributes: [.font: font]).width)
        }
        let width = ceil(widest) + 24
        coordinator.cachedLongestLineWidth = width
        return width
    }

    private func scrollToLineIfNeeded(coordinator: Coordinator) {
        guard let prefix = scrollLinePrefix,
              let scrollRequestID,
              let textView = coordinator.textView
        else {
            coordinator.clearNavigationHighlight()
            return
        }
        guard scrollRequestID != coordinator.lastScrollRequestID else { return }
        coordinator.lastScrollRequestID = scrollRequestID
        coordinator.highlightLinePrefix = prefix
        DispatchQueue.main.async {
            coordinator.selectionHandler?.performProgrammaticSelection {
                if let range = DumpNavigationHighlight.highlightLine(matchingPrefix: prefix, in: textView) {
                    coordinator.applyHighlightedLine(range)
                }
            }
        }
    }

    private static func makeTextView() -> NSTextView {
        // TextKit 1 explicitly: the ruler/sizing code uses NSLayoutManager, and
        // switching a TextKit 2 view into compatibility mode after content is set
        // left the view laid out but never drawn.
        let textView = NSTextView(usingTextLayoutManager: false)
        textView.minSize = NSSize(width: 200, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.importsGraphics = false
        textView.usesFontPanel = false
        textView.usesFindBar = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = []
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.heightTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        return textView
    }

    final class Coordinator {
        weak var textView: NSTextView?
        var selectionHandler: DumpTextSelectionHandler?
        weak var lineNumberGutter: DumpLineNumberGutterView?
        var plainText = ""
        var syntax: DumpSyntaxStyle = .auto
        var palette: SyntaxHighlightPalette = .systemDefaults
        var lastScrollRequestID: UUID?
        var highlightLinePrefix: String?
        var highlightedLineRange: NSRange?
        var cachedDocumentSize: NSSize?
        var cachedScrollWidth: CGFloat = 0
        var cachedLongestLineWidth: CGFloat = 0

        func clearNavigationHighlight() {
            highlightLinePrefix = nil
            lastScrollRequestID = nil
        }

        func applyHighlightedLine(_ range: NSRange) {
            guard let textView else { return }
            let previous = highlightedLineRange
            highlightedLineRange = range
            DumpNavigationHighlight.setLineHighlighted(range, previous: previous, in: textView)
            if textView.selectedRange != range {
                if AppColors.isLightMode {
                    textView.setSelectedRange(NSRange(location: range.location, length: 0))
                } else {
                    textView.setSelectedRange(range)
                }
            }
        }

        func clearLineHighlight(in textView: NSTextView) {
            if let highlightedLineRange {
                DumpNavigationHighlight.setLineHighlighted(nil, previous: highlightedLineRange, in: textView)
            }
            highlightedLineRange = nil
        }
    }
}
