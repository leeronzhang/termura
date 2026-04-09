import SwiftUI

/// Generates CSS custom-property declarations from ThemeColors.
/// Used by WebPanelView to inject theme variables into the WKWebView.
enum ThemeCSSGenerator {
    /// Produces a complete `:root { --termura-xxx: #rrggbb; ... }` block.
    static func generate(from colors: ThemeColors) -> String {
        let pairs = colorPairs(from: colors)
        var css = ":root {\n"
        for (name, hex) in pairs {
            css += "  --termura-\(name): \(hex);\n"
        }
        css += "}\n"
        return css
    }

    // MARK: - Private

    private static func colorPairs(from colors: ThemeColors) -> [(String, String)] {
        [
            ("background", colors.background.hexRGB),
            ("foreground", colors.foreground.hexRGB),
            ("selection-background", colors.selectionBackground.hexRGB),
            ("cursor", colors.cursorColor.hexRGB),
            ("ansi-black", colors.black.hexRGB),
            ("ansi-red", colors.red.hexRGB),
            ("ansi-green", colors.green.hexRGB),
            ("ansi-yellow", colors.yellow.hexRGB),
            ("ansi-blue", colors.blue.hexRGB),
            ("ansi-magenta", colors.magenta.hexRGB),
            ("ansi-cyan", colors.cyan.hexRGB),
            ("ansi-white", colors.white.hexRGB),
            ("ansi-bright-black", colors.brightBlack.hexRGB),
            ("ansi-bright-red", colors.brightRed.hexRGB),
            ("ansi-bright-green", colors.brightGreen.hexRGB),
            ("ansi-bright-yellow", colors.brightYellow.hexRGB),
            ("ansi-bright-blue", colors.brightBlue.hexRGB),
            ("ansi-bright-magenta", colors.brightMagenta.hexRGB),
            ("ansi-bright-cyan", colors.brightCyan.hexRGB),
            ("ansi-bright-white", colors.brightWhite.hexRGB),
            ("sidebar-background", colors.sidebarBackground.hexRGB),
            ("sidebar-text", colors.sidebarText.hexRGB),
            ("active-highlight", colors.activeSessionHighlight.hexRGB)
        ]
    }
}
