import SwiftUI

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
        static let gruvboxMaterialLight = builtinUUID("A1000001-0000-0000-0000-000000000005")
        static let gruvboxMaterialDark = builtinUUID("A1000001-0000-0000-0000-000000000006")
    }

    // Bright ANSI + status/border/surface entries are explicit on every
    // built-in so cross-theme rendering doesn't silently fall through to
    // the hardcoded `ThemeColors.dark` / `.light` palette and pollute a
    // theme's color identity. Sources:
    //   - VS Code default Dark+ / Light+ terminal palette
    //   - https://ethanschoonover.com/solarized
    //   - https://github.com/monokai
    //   - https://github.com/sainnhe/gruvbox-material-vscode
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
            "ansiBrightBlack": "#666666", "ansiBrightRed": "#F14C4C",
            "ansiBrightGreen": "#23D18B", "ansiBrightYellow": "#F5F543",
            "ansiBrightBlue": "#3B8EEA", "ansiBrightMagenta": "#D670D6",
            "ansiBrightCyan": "#29B8DB", "ansiBrightWhite": "#E5E5E5",
            "keyword": "#569CD6", "string": "#CE9178",
            "comment": "#6A9955", "number": "#B5CEA8",
            "function": "#DCDCAA", "type": "#4EC9B0",
            "statusBarBackground": "#007ACC",
            "inputBackground": "#3C3C3C", "inputBorder": "#555555",
            "statusSuccess": "#4EC9B0", "statusError": "#F48771",
            "statusWarning": "#CCA700", "statusInfo": "#75BEFF",
            "borderSubtle": "#2D2D2D", "surfaceOverlay": "#2D2D2D"
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
            "ansiBrightBlack": "#4F525D", "ansiBrightRed": "#CA1243",
            "ansiBrightGreen": "#50A14F", "ansiBrightYellow": "#C18401",
            "ansiBrightBlue": "#4078F2", "ansiBrightMagenta": "#A626A4",
            "ansiBrightCyan": "#0184BC", "ansiBrightWhite": "#FFFFFF",
            "keyword": "#A626A4", "string": "#50A14F",
            "comment": "#A0A1A7", "number": "#986801",
            "function": "#4078F2", "type": "#C18401",
            "statusBarBackground": "#007ACC",
            "inputBackground": "#FFFFFF", "inputBorder": "#C8C8C8",
            "statusSuccess": "#50A14F", "statusError": "#E45649",
            "statusWarning": "#C18401", "statusInfo": "#4078F2",
            "borderSubtle": "#E5E5E6", "surfaceOverlay": "#F5F5F5"
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
            "ansiBrightBlack": "#002B36", "ansiBrightRed": "#CB4B16",
            "ansiBrightGreen": "#586E75", "ansiBrightYellow": "#657B83",
            "ansiBrightBlue": "#839496", "ansiBrightMagenta": "#6C71C4",
            "ansiBrightCyan": "#93A1A1", "ansiBrightWhite": "#FDF6E3",
            "keyword": "#859900", "string": "#2AA198",
            "comment": "#586E75", "number": "#D33682",
            "function": "#268BD2", "type": "#B58900",
            "statusBarBackground": "#073642",
            "inputBackground": "#073642", "inputBorder": "#586E75",
            "statusSuccess": "#859900", "statusError": "#DC322F",
            "statusWarning": "#B58900", "statusInfo": "#268BD2",
            "borderSubtle": "#586E75", "surfaceOverlay": "#073642"
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
            "ansiBrightBlack": "#75715E", "ansiBrightRed": "#F92672",
            "ansiBrightGreen": "#A6E22E", "ansiBrightYellow": "#F4BF75",
            "ansiBrightBlue": "#66D9EF", "ansiBrightMagenta": "#AE81FF",
            "ansiBrightCyan": "#A1EFE4", "ansiBrightWhite": "#F9F8F5",
            "keyword": "#F92672", "string": "#E6DB74",
            "comment": "#75715E", "number": "#AE81FF",
            "function": "#A6E22E", "type": "#66D9EF",
            "statusBarBackground": "#1E1F1C",
            "inputBackground": "#1E1F1C", "inputBorder": "#49483E",
            "statusSuccess": "#A6E22E", "statusError": "#F92672",
            "statusWarning": "#FD971F", "statusInfo": "#66D9EF",
            "borderSubtle": "#49483E", "surfaceOverlay": "#1E1F1C"
        ]
    )

    /// Gruvbox Material Light — palette transcribed from sainnhe's
    /// upstream VS Code theme (themes/gruvbox-material-light.json,
    /// gruvbox-material-vscode @ master). Half-alpha values from the
    /// source were collapsed to opaque RGB since `ThemeColors` stores
    /// opaque-only.
    static let gruvboxMaterialLight = ThemeDefinition(
        id: BuiltinID.gruvboxMaterialLight,
        name: "Gruvbox Material Light",
        isDark: false,
        colors: [
            "background": "#FBF1C7", "foreground": "#654735",
            "cursor": "#654735", "selectionBackground": "#D5C4A1",
            "sidebarBackground": "#FBF1C7", "sidebarText": "#928374",
            "activeSessionHighlight": "#E0CFA9",
            "ansiBlack": "#4F3829", "ansiRed": "#C14A4A",
            "ansiGreen": "#6C782E", "ansiYellow": "#B47109",
            "ansiBlue": "#45707A", "ansiMagenta": "#945E80",
            "ansiCyan": "#4C7A5D", "ansiWhite": "#928374",
            "ansiBrightBlack": "#654735", "ansiBrightRed": "#C14A4A",
            "ansiBrightGreen": "#6C782E", "ansiBrightYellow": "#B47109",
            "ansiBrightBlue": "#45707A", "ansiBrightMagenta": "#945E80",
            "ansiBrightCyan": "#4C7A5D", "ansiBrightWhite": "#F2E5BC",
            "keyword": "#C14A4A", "string": "#B47109",
            "comment": "#928374", "number": "#945E80",
            "function": "#6C782E", "type": "#45707A",
            "statusBarBackground": "#FBF1C7",
            "inputBackground": "#FBF1C7", "inputBorder": "#E0CFA9",
            "statusSuccess": "#6C782E", "statusError": "#C14A4A",
            "statusWarning": "#D8A657", "statusInfo": "#7DAEA3",
            "borderSubtle": "#E0CFA9", "surfaceOverlay": "#F2E5BC"
        ]
    )

    /// Gruvbox Material Dark — palette transcribed from sainnhe's
    /// upstream VS Code theme (themes/gruvbox-material-dark.json,
    /// gruvbox-material-vscode @ master). Selection / list / input
    /// alpha-blended source colors were collapsed to opaque RGB.
    static let gruvboxMaterialDark = ThemeDefinition(
        id: BuiltinID.gruvboxMaterialDark,
        name: "Gruvbox Material Dark",
        isDark: true,
        colors: [
            "background": "#292828", "foreground": "#D4BE98",
            "cursor": "#D4BE98", "selectionBackground": "#504945",
            "sidebarBackground": "#292828", "sidebarText": "#928374",
            "activeSessionHighlight": "#45403D",
            "ansiBlack": "#32302F", "ansiRed": "#EA6962",
            "ansiGreen": "#A9B665", "ansiYellow": "#D8A657",
            "ansiBlue": "#7DAEA3", "ansiMagenta": "#D3869B",
            "ansiCyan": "#89B482", "ansiWhite": "#D4BE98",
            "ansiBrightBlack": "#928374", "ansiBrightRed": "#EA6962",
            "ansiBrightGreen": "#A9B665", "ansiBrightYellow": "#D8A657",
            "ansiBrightBlue": "#7DAEA3", "ansiBrightMagenta": "#D3869B",
            "ansiBrightCyan": "#89B482", "ansiBrightWhite": "#DDC7A1",
            "keyword": "#EA6962", "string": "#D8A657",
            "comment": "#928374", "number": "#D3869B",
            "function": "#A9B665", "type": "#7DAEA3",
            "statusBarBackground": "#292828",
            "inputBackground": "#292828", "inputBorder": "#45403D",
            "statusSuccess": "#A9B665", "statusError": "#EA6962",
            "statusWarning": "#D8A657", "statusInfo": "#7DAEA3",
            "borderSubtle": "#45403D", "surfaceOverlay": "#32302F"
        ]
    )

    static let builtIn: [ThemeDefinition] = [
        .termuraDark, .termuraLight,
        .gruvboxMaterialDark, .gruvboxMaterialLight,
        .solarizedDark, .monokai
    ]
}
