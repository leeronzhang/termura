import SwiftUI

/// A portable, serializable description of a complete theme.
/// Used for importing, exporting, and storing custom themes.
struct ThemeDefinition: Codable, Sendable, Identifiable {
    let id: UUID
    var name: String
    var isDark: Bool
    /// Semantic token raw values mapped to hex color strings (e.g. "#1E1E1E").
    var colors: [String: String]

    /// Parse a hex string (#RRGGBB) into a SwiftUI Color.
    static func color(fromHex hex: String?) -> SwiftUI.Color? {
        guard let hex, hex.count >= 7, hex.hasPrefix("#") else { return nil }
        let r = Double(Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255.0
        let g = Double(Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255.0
        let b = Double(Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255.0
        return SwiftUI.Color(red: r, green: g, blue: b)
    }

    /// Convert this definition into a ThemeColors struct for rendering.
    func toThemeColors() -> ThemeColors {
        let base: ThemeColors = isDark ? .dark : .light
        func c(_ key: String, _ fallback: SwiftUI.Color) -> SwiftUI.Color {
            ThemeDefinition.color(fromHex: colors[key]) ?? fallback
        }
        return ThemeColors(
            background: c("background", base.background),
            foreground: c("foreground", base.foreground),
            selectionBackground: c("selectionBackground", base.selectionBackground),
            cursorColor: c("cursor", base.cursorColor),
            black: c("ansiBlack", base.black),
            red: c("ansiRed", base.red),
            green: c("ansiGreen", base.green),
            yellow: c("ansiYellow", base.yellow),
            blue: c("ansiBlue", base.blue),
            magenta: c("ansiMagenta", base.magenta),
            cyan: c("ansiCyan", base.cyan),
            white: c("ansiWhite", base.white),
            brightBlack: c("ansiBrightBlack", base.brightBlack),
            brightRed: c("ansiBrightRed", base.brightRed),
            brightGreen: c("ansiBrightGreen", base.brightGreen),
            brightYellow: c("ansiBrightYellow", base.brightYellow),
            brightBlue: c("ansiBrightBlue", base.brightBlue),
            brightMagenta: c("ansiBrightMagenta", base.brightMagenta),
            brightCyan: c("ansiBrightCyan", base.brightCyan),
            brightWhite: c("ansiBrightWhite", base.brightWhite),
            sidebarBackground: c("sidebarBackground", base.sidebarBackground),
            sidebarText: c("sidebarText", base.sidebarText),
            activeSessionHighlight: c("activeSessionHighlight", base.activeSessionHighlight)
        )
    }
}
