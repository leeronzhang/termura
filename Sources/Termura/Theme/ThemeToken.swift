import Foundation

/// Semantic token enum for theme color slots.
/// Views should reference tokens, not raw colors, for theme-engine compatibility.
enum ThemeToken: String, CaseIterable, Sendable {
    // Terminal
    case background
    case foreground
    case selectionBackground
    case cursor

    // ANSI 16
    case ansiBlack
    case ansiRed
    case ansiGreen
    case ansiYellow
    case ansiBlue
    case ansiMagenta
    case ansiCyan
    case ansiWhite
    case ansiBrightBlack
    case ansiBrightRed
    case ansiBrightGreen
    case ansiBrightYellow
    case ansiBrightBlue
    case ansiBrightMagenta
    case ansiBrightCyan
    case ansiBrightWhite

    // UI Chrome
    case sidebarBackground
    case sidebarText
    case activeSessionHighlight
    case statusBarBackground
    case inputBackground
    case inputBorder

    // Syntax Highlighting
    case keyword
    case string
    case comment
    case number
    case function
    case type
}
