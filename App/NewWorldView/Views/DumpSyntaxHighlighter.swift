import AppKit
import Foundation

enum DumpSyntaxStyle: Equatable {
    case auto
    case plain
    case bootscript
    case disassembly
}

enum DumpSyntaxHighlighter {
    private static var font: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
    }

    private static var boldFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    }

    private static let disassemblyLine = try! NSRegularExpression(
        pattern: #"^([0-9A-Fa-f]{8}):  (.{18})(\S+)(.*?)(;\s*.*)?$"#
    )
    private static let bootscriptTag = try! NSRegularExpression(pattern: #"<[^>]+>"#)
    private static let bootscriptConstant = try! NSRegularExpression(
        pattern: #"h#\s+([0-9A-Fa-f]+)\s+(constant)\s+([-\w]+)"#
    )
    private static let hexToken = try! NSRegularExpression(pattern: #"\b0x[0-9A-Fa-f]+\b|[0-9A-Fa-f]{16,}\b"#)
    private static let quotedString = try! NSRegularExpression(pattern: #""[^"]*""#)
    private static let lineComment = try! NSRegularExpression(pattern: #"(^|\s)#.*$"#)

    static func resolve(_ style: DumpSyntaxStyle, text: String) -> DumpSyntaxStyle {
        switch style {
        case .auto:
            if text.contains("<CHRP-BOOT>") || (text.contains("h#") && text.contains("constant")) {
                return .bootscript
            }
            if text.split(separator: "\n", maxSplits: 4, omittingEmptySubsequences: false)
                .contains(where: { $0.range(of: #"^[0-9A-Fa-f]{8}:\s+"#, options: .regularExpression) != nil }) {
                return .disassembly
            }
            return .plain
        case .plain, .bootscript, .disassembly:
            return style
        }
    }

    static func highlight(
        _ text: String,
        style: DumpSyntaxStyle,
        palette: SyntaxHighlightPalette = .systemDefaults
    ) -> NSAttributedString {
        let resolved = resolve(style, text: text)
        switch resolved {
        case .disassembly:
            return highlightDisassembly(text, palette: palette)
        case .bootscript:
            return highlightBootscript(text, palette: palette)
        case .plain:
            return highlightPlain(text, palette: palette)
        case .auto:
            return highlightPlain(text, palette: palette)
        }
    }

    static func highlightHexLine(
        _ line: String,
        font: NSFont,
        palette: SyntaxHighlightPalette = .systemDefaults
    ) -> NSAttributedString {
        let textColor = palette.text.nsColor
        let addressColor = palette.address.nsColor
        let bytesColor = palette.bytes.nsColor
        let asciiColor = palette.ascii.nsColor

        let result = NSMutableAttributedString(
            string: line,
            attributes: [.font: font, .foregroundColor: textColor]
        )
        if line.count >= 8 {
            result.addAttribute(.foregroundColor, value: addressColor, range: NSRange(location: 0, length: 8))
        }
        if let pipe = line.firstIndex(of: "|") {
            let hexStart = line.index(line.startIndex, offsetBy: min(10, line.count))
            let hexLength = line.distance(from: hexStart, to: pipe)
            if hexLength > 0 {
                let range = NSRange(location: 10, length: hexLength)
                result.addAttribute(.foregroundColor, value: bytesColor, range: range)
            }
            let asciiStart = line.index(after: pipe)
            if asciiStart < line.endIndex, let endPipe = line[asciiStart...].firstIndex(of: "|") {
                let asciiRange = NSRange(
                    location: line.distance(from: line.startIndex, to: asciiStart),
                    length: line.distance(from: asciiStart, to: endPipe)
                )
                result.addAttribute(.foregroundColor, value: asciiColor, range: asciiRange)
            }
        }
        return result
    }

    private static func highlightDisassembly(_ text: String, palette: SyntaxHighlightPalette) -> NSAttributedString {
        let textColor = palette.text.nsColor
        let commentColor = palette.comment.nsColor
        let addressColor = palette.address.nsColor
        let bytesColor = palette.bytes.nsColor
        let mnemonicColor = palette.mnemonic.nsColor
        let annotationColor = palette.annotation.nsColor

        let result = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        for (index, line) in lines.enumerated() {
            if index > 0 {
                result.append(NSAttributedString(string: "\n", attributes: baseAttributes(palette: palette)))
            }
            if line.hasPrefix("#") {
                result.append(attributed(line, color: commentColor, palette: palette))
                continue
            }
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = disassemblyLine.firstMatch(in: line, range: range) else {
                result.append(attributed(line, color: textColor, palette: palette))
                continue
            }
            appendGroup(result, nsLine, match.range(at: 1), color: addressColor, font: boldFont)
            result.append(attributed(":  ", color: commentColor, palette: palette))
            appendGroup(result, nsLine, match.range(at: 2), color: bytesColor)
            appendGroup(result, nsLine, match.range(at: 3), color: mnemonicColor, font: boldFont)
            let tailRange = match.range(at: 4)
            if tailRange.location != NSNotFound, tailRange.length > 0 {
                appendGroup(result, nsLine, tailRange, color: textColor)
            }
            let commentRange = match.range(at: 5)
            if commentRange.location != NSNotFound, commentRange.length > 0 {
                appendGroup(result, nsLine, commentRange, color: annotationColor)
            }
        }
        return result
    }

    private static func highlightBootscript(_ text: String, palette: SyntaxHighlightPalette) -> NSAttributedString {
        let tagColor = palette.tag.nsColor
        let hexColor = palette.hex.nsColor
        let keywordColor = palette.keyword.nsColor
        let stringColor = palette.string.nsColor
        let commentColor = palette.comment.nsColor

        let result = NSMutableAttributedString(string: text, attributes: baseAttributes(palette: palette))
        applyMatches(bootscriptTag, in: text, to: result, color: tagColor, font: boldFont)
        applyMatches(bootscriptConstant, in: text, to: result) { _, match in
            result.addAttributes(
                [.foregroundColor: hexColor, .font: font],
                range: match.range(at: 1)
            )
            result.addAttributes(
                [.foregroundColor: keywordColor, .font: boldFont],
                range: match.range(at: 2)
            )
            result.addAttributes(
                [.foregroundColor: stringColor, .font: font],
                range: match.range(at: 3)
            )
        }
        applyMatches(hexToken, in: text, to: result, color: hexColor)
        applyMatches(quotedString, in: text, to: result, color: stringColor)
        applyMatches(lineComment, in: text, to: result, color: commentColor)
        return result
    }

    private static func highlightPlain(_ text: String, palette: SyntaxHighlightPalette) -> NSAttributedString {
        let tagColor = palette.tag.nsColor
        let hexColor = palette.hex.nsColor
        let stringColor = palette.string.nsColor
        let commentColor = palette.comment.nsColor

        let result = NSMutableAttributedString(string: text, attributes: baseAttributes(palette: palette))
        applyMatches(bootscriptTag, in: text, to: result, color: tagColor, font: boldFont)
        applyMatches(hexToken, in: text, to: result, color: hexColor)
        applyMatches(quotedString, in: text, to: result, color: stringColor)
        applyMatches(lineComment, in: text, to: result, color: commentColor)
        return result
    }

    private static func baseAttributes(palette: SyntaxHighlightPalette) -> [NSAttributedString.Key: Any] {
        [.font: font, .foregroundColor: palette.text.nsColor]
    }

    private static func attributed(
        _ string: String,
        color: NSColor,
        palette: SyntaxHighlightPalette,
        font: NSFont? = nil
    ) -> NSAttributedString {
        var attributes = baseAttributes(palette: palette)
        attributes[.foregroundColor] = color
        if let font {
            attributes[.font] = font
        }
        return NSAttributedString(string: string, attributes: attributes)
    }

    private static func appendGroup(
        _ result: NSMutableAttributedString,
        _ string: NSString,
        _ range: NSRange,
        color: NSColor,
        font: NSFont? = nil
    ) {
        guard range.location != NSNotFound, range.length > 0 else { return }
        var attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? self.font,
            .foregroundColor: color
        ]
        if let font {
            attributes[.font] = font
        }
        result.append(NSAttributedString(string: string.substring(with: range), attributes: attributes))
    }

    private static func applyMatches(
        _ regex: NSRegularExpression,
        in text: String,
        to result: NSMutableAttributedString,
        color: NSColor,
        font: NSFont? = nil
    ) {
        applyMatches(regex, in: text, to: result) { _, match in
            var attributes: [NSAttributedString.Key: Any] = [
                .foregroundColor: color,
                .font: font ?? self.font
            ]
            if let font {
                attributes[.font] = font
            }
            result.addAttributes(attributes, range: match.range)
        }
    }

    private static func applyMatches(
        _ regex: NSRegularExpression,
        in text: String,
        to result: NSMutableAttributedString,
        apply: (NSString, NSTextCheckingResult) -> Void
    ) {
        let nsString = text as NSString
        let range = NSRange(location: 0, length: nsString.length)
        regex.enumerateMatches(in: text, range: range) { match, _, _ in
            guard let match else { return }
            apply(nsString, match)
        }
    }
}
