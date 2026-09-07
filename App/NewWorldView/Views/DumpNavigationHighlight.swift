import AppKit

enum DumpNavigationHighlight {
    static func lineRange(matchingPrefix prefix: String, in text: String) -> NSRange? {
        let lines = text.components(separatedBy: "\n")
        guard let lineIndex = lines.firstIndex(where: { $0.hasPrefix(prefix) }) else { return nil }
        var location = 0
        for index in 0..<lineIndex {
            location += lines[index].utf16.count + 1
        }
        let length = max(1, lines[lineIndex].utf16.count)
        return NSRange(location: location, length: length)
    }

    @MainActor
    static func highlightLine(matchingPrefix prefix: String, in textView: NSTextView) -> NSRange? {
        guard let range = lineRange(matchingPrefix: prefix, in: textView.string) else { return nil }
        textView.scrollRangeToVisible(range)
        return range
    }

    static func setLineHighlighted(
        _ range: NSRange?,
        previous previousRange: NSRange?,
        in textView: NSTextView
    ) {
        guard let storage = textView.textStorage else { return }
        storage.beginEditing()
        if let previousRange, isValid(previousRange, in: textView.string) {
            storage.removeAttribute(.backgroundColor, range: previousRange)
            if !AppColors.isLightMode {
                storage.removeAttribute(.foregroundColor, range: previousRange)
            }
        }
        if let range, isValid(range, in: textView.string) {
            storage.addAttribute(.backgroundColor, value: AppColors.rowHighlightBackground, range: range)
            if !AppColors.isLightMode {
                storage.addAttribute(.foregroundColor, value: AppColors.rowHighlightForeground, range: range)
            }
        }
        storage.endEditing()
    }

    static func highlightColors(forHighlighted isHighlighted: Bool) -> (background: NSColor, foreground: NSColor) {
        if isHighlighted {
            return (AppColors.rowHighlightBackground, AppColors.rowHighlightForeground)
        }
        return (.textBackgroundColor, .textColor)
    }

    private static func isValid(_ range: NSRange, in text: String) -> Bool {
        range.location != NSNotFound
            && range.length > 0
            && range.location + range.length <= text.utf16.count
    }
}
