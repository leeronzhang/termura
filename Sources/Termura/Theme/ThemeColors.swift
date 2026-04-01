import AppKit
import SwiftUI

/// 18-color terminal theme definition (background + foreground + 16 ANSI).
/// Uses SwiftUI.Color throughout.
struct ThemeColors: Sendable, Equatable {
    // MARK: - Base colors

    var background: SwiftUI.Color
    var foreground: SwiftUI.Color
    var selectionBackground: SwiftUI.Color
    var cursorColor: SwiftUI.Color

    // MARK: - ANSI 16

    var black: SwiftUI.Color
    var red: SwiftUI.Color
    var green: SwiftUI.Color
    var yellow: SwiftUI.Color
    var blue: SwiftUI.Color
    var magenta: SwiftUI.Color
    var cyan: SwiftUI.Color
    var white: SwiftUI.Color
    var brightBlack: SwiftUI.Color
    var brightRed: SwiftUI.Color
    var brightGreen: SwiftUI.Color
    var brightYellow: SwiftUI.Color
    var brightBlue: SwiftUI.Color
    var brightMagenta: SwiftUI.Color
    var brightCyan: SwiftUI.Color
    var brightWhite: SwiftUI.Color

    // MARK: - UI Chrome

    var sidebarBackground: SwiftUI.Color
    var sidebarText: SwiftUI.Color
    var activeSessionHighlight: SwiftUI.Color
}

// MARK: - Default Themes

extension ThemeColors {
    static let dark = ThemeColors(
        background: SwiftUI.Color(red: 0.118, green: 0.118, blue: 0.118),
        foreground: SwiftUI.Color(red: 0.933, green: 0.933, blue: 0.933),
        selectionBackground: SwiftUI.Color(red: 0.282, green: 0.427, blue: 0.698),
        cursorColor: SwiftUI.Color(red: 0.933, green: 0.933, blue: 0.933),
        black: SwiftUI.Color(red: 0.118, green: 0.118, blue: 0.118),
        red: SwiftUI.Color(red: 0.894, green: 0.212, blue: 0.227),
        green: SwiftUI.Color(red: 0.459, green: 0.722, blue: 0.357),
        yellow: SwiftUI.Color(red: 0.996, green: 0.816, blue: 0.298),
        blue: SwiftUI.Color(red: 0.369, green: 0.506, blue: 0.957),
        magenta: SwiftUI.Color(red: 0.725, green: 0.373, blue: 0.804),
        cyan: SwiftUI.Color(red: 0.298, green: 0.769, blue: 0.816),
        white: SwiftUI.Color(red: 0.749, green: 0.749, blue: 0.749),
        brightBlack: SwiftUI.Color(red: 0.4, green: 0.4, blue: 0.4),
        brightRed: SwiftUI.Color(red: 1.0, green: 0.451, blue: 0.451),
        brightGreen: SwiftUI.Color(red: 0.631, green: 0.910, blue: 0.553),
        brightYellow: SwiftUI.Color(red: 1.0, green: 0.953, blue: 0.553),
        brightBlue: SwiftUI.Color(red: 0.553, green: 0.686, blue: 1.0),
        brightMagenta: SwiftUI.Color(red: 0.875, green: 0.553, blue: 0.965),
        brightCyan: SwiftUI.Color(red: 0.553, green: 0.929, blue: 0.965),
        brightWhite: SwiftUI.Color(red: 0.933, green: 0.933, blue: 0.933),
        sidebarBackground: SwiftUI.Color(red: 0.094, green: 0.094, blue: 0.094),
        sidebarText: SwiftUI.Color(red: 0.8, green: 0.8, blue: 0.8),
        activeSessionHighlight: SwiftUI.Color(red: 0.282, green: 0.427, blue: 0.698)
    )

    static let light = ThemeColors(
        background: SwiftUI.Color(red: 0.98, green: 0.98, blue: 0.98),
        foreground: SwiftUI.Color(red: 0.09, green: 0.09, blue: 0.09),
        selectionBackground: SwiftUI.Color(red: 0.714, green: 0.816, blue: 1.0),
        cursorColor: SwiftUI.Color(red: 0.09, green: 0.09, blue: 0.09),
        black: SwiftUI.Color(red: 0.09, green: 0.09, blue: 0.09),
        red: SwiftUI.Color(red: 0.749, green: 0.059, blue: 0.078),
        green: SwiftUI.Color(red: 0.176, green: 0.549, blue: 0.098),
        yellow: SwiftUI.Color(red: 0.729, green: 0.506, blue: 0.0),
        blue: SwiftUI.Color(red: 0.169, green: 0.31, blue: 0.894),
        magenta: SwiftUI.Color(red: 0.529, green: 0.118, blue: 0.694),
        cyan: SwiftUI.Color(red: 0.059, green: 0.529, blue: 0.596),
        white: SwiftUI.Color(red: 0.749, green: 0.749, blue: 0.749),
        brightBlack: SwiftUI.Color(red: 0.4, green: 0.4, blue: 0.4),
        brightRed: SwiftUI.Color(red: 0.898, green: 0.11, blue: 0.129),
        brightGreen: SwiftUI.Color(red: 0.31, green: 0.698, blue: 0.212),
        brightYellow: SwiftUI.Color(red: 0.878, green: 0.659, blue: 0.0),
        brightBlue: SwiftUI.Color(red: 0.282, green: 0.459, blue: 0.957),
        brightMagenta: SwiftUI.Color(red: 0.686, green: 0.278, blue: 0.839),
        brightCyan: SwiftUI.Color(red: 0.106, green: 0.667, blue: 0.729),
        brightWhite: SwiftUI.Color(red: 0.933, green: 0.933, blue: 0.933),
        sidebarBackground: SwiftUI.Color(red: 0.937, green: 0.937, blue: 0.937),
        sidebarText: SwiftUI.Color(red: 0.2, green: 0.2, blue: 0.2),
        activeSessionHighlight: SwiftUI.Color(red: 0.714, green: 0.816, blue: 1.0)
    )
}
