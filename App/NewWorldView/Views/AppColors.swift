import AppKit
import SwiftUI

enum AppColors {
    static var windowBackground: Color { Color(nsColor: .windowBackgroundColor) }
    static var controlBackground: Color { Color(nsColor: .controlBackgroundColor) }
    static var textBackground: Color { Color(nsColor: .textBackgroundColor) }
    static var separator: Color { Color(nsColor: .separatorColor) }

    static var label: Color { Color(nsColor: .labelColor) }
    static var secondaryLabel: Color { Color(nsColor: .secondaryLabelColor) }

    static var selectedBackground: Color { Color(nsColor: .selectedContentBackgroundColor) }
    static var selectedForeground: Color { Color(nsColor: .alternateSelectedControlTextColor) }

    /// ROM pane navigation row highlight — light grey in Aqua, accent selection in dark mode.
    static var rowHighlightBackground: NSColor {
        isLightMode ? .unemphasizedSelectedContentBackgroundColor : .selectedContentBackgroundColor
    }

    static var rowHighlightForeground: NSColor {
        isLightMode ? .labelColor : .alternateSelectedControlTextColor
    }

    static var isLightMode: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .aqua
    }
}
