import AppKit
import Combine
import SwiftUI

struct SyntaxColorComponents: Codable, Equatable, Sendable {
    /// When set, resolves through AppKit semantic/dynamic colors at read time.
    var systemColor: String?
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1, systemColor: String? = nil) {
        self.systemColor = systemColor
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(systemColor name: String) {
        systemColor = name
        red = 0
        green = 0
        blue = 0
        alpha = 1
    }

    init(nsColor: NSColor) {
        if let name = Self.systemColorName(for: nsColor) {
            systemColor = name
            red = 0
            green = 0
            blue = 0
            alpha = 1
        } else {
            systemColor = nil
            let rgb = nsColor.usingColorSpace(.deviceRGB) ?? nsColor
            red = Double(rgb.redComponent)
            green = Double(rgb.greenComponent)
            blue = Double(rgb.blueComponent)
            alpha = Double(rgb.alphaComponent)
        }
    }

    var nsColor: NSColor {
        if let systemColor, let resolved = Self.resolveSystemColor(systemColor) {
            return resolved
        }
        return NSColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    var swiftUIColor: Color {
        Color(nsColor: nsColor)
    }

    var isLikelyLightTextOnLightBackground: Bool {
        guard systemColor == nil else { return false }
        let luminance = 0.2126 * red + 0.7152 * green + 0.0722 * blue
        return luminance > 0.72
    }

    static func resolveSystemColor(_ name: String) -> NSColor? {
        switch name {
        case "label": return .labelColor
        case "secondaryLabel": return .secondaryLabelColor
        case "tertiaryLabel": return .tertiaryLabelColor
        case "textColor": return .textColor
        case "textBackgroundColor": return .textBackgroundColor
        case "systemRed": return .systemRed
        case "systemOrange": return .systemOrange
        case "systemYellow": return .systemYellow
        case "systemGreen": return .systemGreen
        case "systemTeal": return .systemTeal
        case "systemBlue": return .systemBlue
        case "systemIndigo": return .systemIndigo
        case "systemPurple": return .systemPurple
        case "systemPink": return .systemPink
        case "systemCyan": return .systemCyan
        case "systemBrown": return .systemBrown
        default: return nil
        }
    }

    private static func systemColorName(for color: NSColor) -> String? {
        let pairs: [(String, NSColor)] = [
            ("label", .labelColor),
            ("secondaryLabel", .secondaryLabelColor),
            ("tertiaryLabel", .tertiaryLabelColor),
            ("textColor", .textColor),
            ("textBackgroundColor", .textBackgroundColor),
            ("systemRed", .systemRed),
            ("systemOrange", .systemOrange),
            ("systemYellow", .systemYellow),
            ("systemGreen", .systemGreen),
            ("systemTeal", .systemTeal),
            ("systemBlue", .systemBlue),
            ("systemIndigo", .systemIndigo),
            ("systemPurple", .systemPurple),
            ("systemPink", .systemPink),
            ("systemCyan", .systemCyan),
            ("systemBrown", .systemBrown)
        ]
        let target = color.usingColorSpace(.deviceRGB) ?? color
        for (name, candidate) in pairs {
            let rgb = candidate.usingColorSpace(.deviceRGB) ?? candidate
            if abs(rgb.redComponent - target.redComponent) < 0.02,
               abs(rgb.greenComponent - target.greenComponent) < 0.02,
               abs(rgb.blueComponent - target.blueComponent) < 0.02,
               abs(rgb.alphaComponent - target.alphaComponent) < 0.02 {
                return name
            }
        }
        return nil
    }
}

enum SyntaxHighlightColorRole: String, CaseIterable, Identifiable, Codable {
    case text
    case comment
    case address
    case bytes
    case mnemonic
    case annotation
    case tag
    case hex
    case string
    case keyword
    case ascii

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .text: return "Plain text"
        case .comment: return "Comments"
        case .address: return "Addresses"
        case .bytes: return "Byte opcodes"
        case .mnemonic: return "Mnemonics"
        case .annotation: return "Annotations"
        case .tag: return "Tags"
        case .hex: return "Hex literals"
        case .string: return "Strings"
        case .keyword: return "Keywords"
        case .ascii: return "ASCII column"
        }
    }

    var detail: String {
        switch self {
        case .text: return "Default body text in plain and disassembly views."
        case .comment: return "Line comments (# ...) and punctuation in disassembly."
        case .address: return "Program counters and hex dump offsets."
        case .bytes: return "Instruction bytes and hex dump data columns."
        case .mnemonic: return "Disassembly mnemonics (bl, stw, trap names)."
        case .annotation: return "Trailing ; xref and symbol notes in disassembly."
        case .tag: return "Bootscript XML-like tags such as <CHRP-BOOT>."
        case .hex: return "Hex constants in bootscripts and plain text."
        case .string: return "Quoted strings and bootscript constant names."
        case .keyword: return "Bootscript keywords such as constant."
        case .ascii: return "Printable ASCII in the hex dump gutter."
        }
    }
}

struct SyntaxHighlightPalette: Codable, Equatable, Sendable {
    var text: SyntaxColorComponents
    var comment: SyntaxColorComponents
    var address: SyntaxColorComponents
    var bytes: SyntaxColorComponents
    var mnemonic: SyntaxColorComponents
    var annotation: SyntaxColorComponents
    var tag: SyntaxColorComponents
    var hex: SyntaxColorComponents
    var string: SyntaxColorComponents
    var keyword: SyntaxColorComponents
    var ascii: SyntaxColorComponents

    subscript(role: SyntaxHighlightColorRole) -> SyntaxColorComponents {
        get {
            switch role {
            case .text: return text
            case .comment: return comment
            case .address: return address
            case .bytes: return bytes
            case .mnemonic: return mnemonic
            case .annotation: return annotation
            case .tag: return tag
            case .hex: return hex
            case .string: return string
            case .keyword: return keyword
            case .ascii: return ascii
            }
        }
        set {
            switch role {
            case .text: text = newValue
            case .comment: comment = newValue
            case .address: address = newValue
            case .bytes: bytes = newValue
            case .mnemonic: mnemonic = newValue
            case .annotation: annotation = newValue
            case .tag: tag = newValue
            case .hex: hex = newValue
            case .string: string = newValue
            case .keyword: keyword = newValue
            case .ascii: ascii = newValue
            }
        }
    }

    static var systemDefaults: SyntaxHighlightPalette {
        SyntaxHighlightPalette(
            text: SyntaxColorComponents(systemColor: "label"),
            comment: SyntaxColorComponents(systemColor: "secondaryLabel"),
            address: SyntaxColorComponents(systemColor: "systemBlue"),
            bytes: SyntaxColorComponents(systemColor: "label"),
            mnemonic: SyntaxColorComponents(systemColor: "systemBlue"),
            annotation: SyntaxColorComponents(systemColor: "systemPink"),
            tag: SyntaxColorComponents(systemColor: "systemBlue"),
            hex: SyntaxColorComponents(systemColor: "systemBrown"),
            string: SyntaxColorComponents(systemColor: "systemGreen"),
            keyword: SyntaxColorComponents(systemColor: "systemTeal"),
            ascii: SyntaxColorComponents(systemColor: "secondaryLabel")
        )
    }

    func normalizedForCurrentAppearance() -> SyntaxHighlightPalette {
        guard AppColors.isLightMode else { return self }
        var copy = self
        if copy.text.isLikelyLightTextOnLightBackground {
            copy.text = SyntaxColorComponents(systemColor: "label")
        }
        if copy.comment.isLikelyLightTextOnLightBackground {
            copy.comment = SyntaxColorComponents(systemColor: "secondaryLabel")
        }
        if copy.bytes.isLikelyLightTextOnLightBackground {
            copy.bytes = SyntaxColorComponents(systemColor: "label")
        }
        if copy.ascii.isLikelyLightTextOnLightBackground {
            copy.ascii = SyntaxColorComponents(systemColor: "secondaryLabel")
        }
        return copy
    }
}

@MainActor
final class SyntaxHighlightSettings: ObservableObject {
    static let storageKey = "NewWorldView.syntaxHighlightPalette"

    @Published private(set) var palette: SyntaxHighlightPalette {
        didSet {
            guard palette != oldValue else { return }
            save()
        }
    }

    /// Palette with semantic colors resolved for the current appearance.
    var resolvedPalette: SyntaxHighlightPalette {
        palette.normalizedForCurrentAppearance()
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(SyntaxHighlightPalette.self, from: data) {
            palette = decoded.normalizedForCurrentAppearance()
        } else {
            palette = .systemDefaults
        }
    }

    func resetToDefaults() {
        palette = .systemDefaults
    }

    func setColor(_ color: Color, for role: SyntaxHighlightColorRole) {
        var updated = palette
        updated[role] = SyntaxColorComponents(nsColor: NSColor(color))
        palette = updated
    }

    func color(for role: SyntaxHighlightColorRole) -> Color {
        resolvedPalette[role].swiftUIColor
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(palette) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
