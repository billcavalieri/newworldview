import AppKit
import SwiftUI

extension View {
    func hoverHelp(_ text: String) -> some View {
        overlay {
            HoverHelpTracker(text: text)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHint(text)
    }
}

private struct HoverHelpTracker: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> HoverHelpTrackingView {
        HoverHelpTrackingView(text: text)
    }

    func updateNSView(_ nsView: HoverHelpTrackingView, context: Context) {
        nsView.helpText = text
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: HoverHelpTrackingView, context: Context) -> CGSize? {
        CGSize(
            width: proposal.width ?? nsView.bounds.width,
            height: proposal.height ?? nsView.bounds.height
        )
    }
}

private final class HoverHelpTrackingView: NSView {
    var helpText: String {
        didSet {
            if HoverHelpPanel.shared.activeText == helpText {
                HoverHelpPanel.shared.refreshContent(text: helpText)
            }
        }
    }

    init(text: String) {
        helpText = text
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateTrackingAreas()
    }

    override func layout() {
        super.layout()
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        guard bounds.width > 0, bounds.height > 0 else { return }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        guard let window else { return }
        let screenRect = window.convertToScreen(convert(bounds, to: nil))
        HoverHelpPanel.shared.show(text: helpText, anchor: screenRect)
    }

    override func mouseExited(with event: NSEvent) {
        HoverHelpPanel.shared.hide(text: helpText)
    }
}

@MainActor
private final class HoverHelpPanel {
    static let shared = HoverHelpPanel()

    private(set) var activeText: String?
    private var panel: NSPanel?

    func show(text: String, anchor: NSRect) {
        guard !text.isEmpty, anchor.width > 0, anchor.height > 0 else { return }

        activeText = text
        let panel = panel ?? makePanel()
        self.panel = panel
        layoutPanel(panel, text: text)

        let panelSize = panel.frame.size
        var originX = anchor.midX - panelSize.width / 2
        originX = max(8, min(originX, (NSScreen.main?.frame.width ?? originX) - panelSize.width - 8))

        // AppKit screen coordinates: anchor.maxY is the top edge of the button.
        var originY = anchor.maxY + 8
        let screenTop = NSScreen.main?.frame.maxY ?? originY + panelSize.height
        if originY + panelSize.height > screenTop - 8 {
            originY = anchor.minY - panelSize.height - 8
        }

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
        if !panel.isVisible {
            panel.orderFront(nil)
        }
    }

    func hide(text: String) {
        guard activeText == text else { return }
        activeText = nil
        panel?.orderOut(nil)
    }

    func refreshContent(text: String) {
        guard let panel else { return }
        layoutPanel(panel, text: text)
    }

    private func layoutPanel(_ panel: NSPanel, text: String) {
        guard let label = panel.contentView?.subviews.first as? NSTextField else { return }

        label.stringValue = text
        label.preferredMaxLayoutWidth = 300
        label.sizeToFit()

        let padding = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let textWidth = min(max(label.intrinsicContentSize.width, 180), 300)
        let textHeight = label.sizeThatFits(NSSize(width: textWidth, height: .greatestFiniteMagnitude)).height
        let contentSize = NSSize(
            width: textWidth + padding.left + padding.right,
            height: textHeight + padding.top + padding.bottom
        )

        label.frame = NSRect(
            x: padding.left,
            y: padding.bottom,
            width: textWidth,
            height: textHeight
        )
        panel.contentView?.setFrameSize(contentSize)
        panel.setContentSize(contentSize)
    }

    private func makePanel() -> NSPanel {
        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.textColor = .labelColor
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.cell?.wraps = true
        label.cell?.isScrollable = false
        label.usesSingleLineMode = false
        label.preferredMaxLayoutWidth = 300

        let padding = NSEdgeInsets(top: 10, left: 12, bottom: 10, right: 12)
        let contentSize = NSSize(width: 324, height: 44)
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        container.layer?.cornerRadius = 10
        container.layer?.borderColor = NSColor.separatorColor.cgColor
        container.layer?.borderWidth = 1

        label.frame = NSRect(
            x: padding.left,
            y: padding.bottom,
            width: 300,
            height: 24
        )
        container.addSubview(label)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = container
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        return panel
    }
}
