import AppKit
import SwiftUI

extension ThemeManager {
    // MARK: - Color Lookup

    func color(for token: ThemeToken) -> SwiftUI.Color {
        if let extended = extendedColors[token] { return extended }
        return uiColor(for: token) ?? syntaxColor(for: token) ?? ansiColor(for: token)
    }

    // MARK: - Private — Color helpers

    private func uiColor(for token: ThemeToken) -> SwiftUI.Color? {
        if let core = uiCoreColor(for: token) { return core }
        return uiStatusColor(for: token)
    }

    private func uiCoreColor(for token: ThemeToken) -> SwiftUI.Color? {
        switch token {
        case .background: current.background
        case .foreground: current.foreground
        case .selectionBackground: current.selectionBackground
        case .cursor: current.cursorColor
        case .sidebarBackground: current.sidebarBackground
        case .sidebarText: current.sidebarText
        case .activeSessionHighlight: current.activeSessionHighlight
        case .statusBarBackground: current.sidebarBackground
        case .inputBackground: current.background
        case .inputBorder: current.foreground.opacity(0.2)
        default: nil
        }
    }

    private func uiStatusColor(for token: ThemeToken) -> SwiftUI.Color? {
        switch token {
        case .statusSuccess: current.green
        case .statusError: current.red
        case .statusWarning: current.yellow
        case .statusInfo: current.blue
        case .borderSubtle: current.foreground.opacity(AppUI.Opacity.border)
        case .surfaceOverlay: current.background.opacity(AppUI.Opacity.secondary)
        default: nil
        }
    }

    private func syntaxColor(for token: ThemeToken) -> SwiftUI.Color? {
        switch token {
        case .keyword: current.blue
        case .string: current.green
        case .comment: current.brightBlack
        case .number: current.magenta
        case .function: current.yellow
        case .type: current.cyan
        default: nil
        }
    }

    private func ansiColor(for token: ThemeToken) -> SwiftUI.Color {
        ansiColorMap[token] ?? current.foreground
    }

    private var ansiColorMap: [ThemeToken: SwiftUI.Color] {
        [
            .ansiBlack: current.black, .ansiRed: current.red,
            .ansiGreen: current.green, .ansiYellow: current.yellow,
            .ansiBlue: current.blue, .ansiMagenta: current.magenta,
            .ansiCyan: current.cyan, .ansiWhite: current.white,
            .ansiBrightBlack: current.brightBlack, .ansiBrightRed: current.brightRed,
            .ansiBrightGreen: current.brightGreen, .ansiBrightYellow: current.brightYellow,
            .ansiBrightBlue: current.brightBlue, .ansiBrightMagenta: current.brightMagenta,
            .ansiBrightCyan: current.brightCyan, .ansiBrightWhite: current.brightWhite
        ]
    }

    // MARK: - Private — Extended colors

    func buildExtendedColors(from definition: ThemeDefinition) {
        let tokenMap: [(String, ThemeToken)] = [
            ("keyword", .keyword), ("string", .string), ("comment", .comment),
            ("number", .number), ("function", .function), ("type", .type),
            ("statusBarBackground", .statusBarBackground),
            ("inputBackground", .inputBackground), ("inputBorder", .inputBorder)
        ]
        extendedColors = [:]
        for (key, token) in tokenMap {
            if let parsed = ThemeDefinition.color(fromHex: definition.colors[key]) {
                extendedColors[token] = parsed
            }
        }
    }
}
