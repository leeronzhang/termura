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

// MARK: - Built-in Presets

extension ThemeDefinition {
    // Hardcoded string literals — parse failure is a programmer error; crash immediately.
    private static func builtinUUID(_ string: String) -> UUID {
        guard let uuid = UUID(uuidString: string) else {
            preconditionFailure("Invalid hardcoded builtin theme UUID: \(string)")
        }
        return uuid
    }

    private enum BuiltinID {
        static let termuraDark = builtinUUID("A1000001-0000-0000-0000-000000000001")
        static let termuraLight = builtinUUID("A1000001-0000-0000-0000-000000000002")
        static let solarizedDark = builtinUUID("A1000001-0000-0000-0000-000000000003")
        static let monokai = builtinUUID("A1000001-0000-0000-0000-000000000004")
    }

    static let termuraDark = ThemeDefinition(
        id: BuiltinID.termuraDark,
        name: "Termura Dark",
        isDark: true,
        colors: [
            "background": "#1E1E1E", "foreground": "#D4D4D4",
            "cursor": "#AEAFAD", "selectionBackground": "#264F78",
            "sidebarBackground": "#252526", "sidebarText": "#CCCCCC",
            "activeSessionHighlight": "#37373D",
            "ansiBlack": "#000000", "ansiRed": "#CD3131",
            "ansiGreen": "#0DBC79", "ansiYellow": "#E5E510",
            "ansiBlue": "#2472C8", "ansiMagenta": "#BC3FBC",
            "ansiCyan": "#11A8CD", "ansiWhite": "#E5E5E5",
            "keyword": "#569CD6", "string": "#CE9178",
            "comment": "#6A9955", "number": "#B5CEA8",
            "function": "#DCDCAA", "type": "#4EC9B0",
            "statusBarBackground": "#007ACC",
            "inputBackground": "#3C3C3C", "inputBorder": "#555555"
        ]
    )

    static let termuraLight = ThemeDefinition(
        id: BuiltinID.termuraLight,
        name: "Termura Light",
        isDark: false,
        colors: [
            "background": "#FFFFFF", "foreground": "#383A42",
            "cursor": "#526FFF", "selectionBackground": "#B3D3EA",
            "sidebarBackground": "#F3F3F3", "sidebarText": "#383A42",
            "activeSessionHighlight": "#E4E6F1",
            "ansiBlack": "#000000", "ansiRed": "#E45649",
            "ansiGreen": "#50A14F", "ansiYellow": "#C18401",
            "ansiBlue": "#4078F2", "ansiMagenta": "#A626A4",
            "ansiCyan": "#0184BC", "ansiWhite": "#FAFAFA",
            "keyword": "#A626A4", "string": "#50A14F",
            "comment": "#A0A1A7", "number": "#986801",
            "function": "#4078F2", "type": "#C18401",
            "statusBarBackground": "#007ACC",
            "inputBackground": "#FFFFFF", "inputBorder": "#C8C8C8"
        ]
    )

    static let solarizedDark = ThemeDefinition(
        id: BuiltinID.solarizedDark,
        name: "Solarized Dark",
        isDark: true,
        colors: [
            "background": "#002B36", "foreground": "#839496",
            "cursor": "#839496", "selectionBackground": "#073642",
            "sidebarBackground": "#073642", "sidebarText": "#839496",
            "activeSessionHighlight": "#073642",
            "ansiBlack": "#073642", "ansiRed": "#DC322F",
            "ansiGreen": "#859900", "ansiYellow": "#B58900",
            "ansiBlue": "#268BD2", "ansiMagenta": "#D33682",
            "ansiCyan": "#2AA198", "ansiWhite": "#EEE8D5",
            "keyword": "#859900", "string": "#2AA198",
            "comment": "#586E75", "number": "#D33682",
            "function": "#268BD2", "type": "#B58900",
            "statusBarBackground": "#073642",
            "inputBackground": "#073642", "inputBorder": "#586E75"
        ]
    )

    static let monokai = ThemeDefinition(
        id: BuiltinID.monokai,
        name: "Monokai",
        isDark: true,
        colors: [
            "background": "#272822", "foreground": "#F8F8F2",
            "cursor": "#F8F8F0", "selectionBackground": "#49483E",
            "sidebarBackground": "#1E1F1C", "sidebarText": "#F8F8F2",
            "activeSessionHighlight": "#3E3D32",
            "ansiBlack": "#272822", "ansiRed": "#F92672",
            "ansiGreen": "#A6E22E", "ansiYellow": "#F4BF75",
            "ansiBlue": "#66D9EF", "ansiMagenta": "#AE81FF",
            "ansiCyan": "#A1EFE4", "ansiWhite": "#F8F8F2",
            "keyword": "#F92672", "string": "#E6DB74",
            "comment": "#75715E", "number": "#AE81FF",
            "function": "#A6E22E", "type": "#66D9EF",
            "statusBarBackground": "#1E1F1C",
            "inputBackground": "#1E1F1C", "inputBorder": "#49483E"
        ]
    )

    static let builtIn: [ThemeDefinition] = [.termuraDark, .termuraLight, .solarizedDark, .monokai]
}
