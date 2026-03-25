import AppKit
import Combine
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "ThemeManager")

/// Manages the active theme, responds to system appearance changes,
/// and exposes available definitions (built-in + custom).
@MainActor
final class ThemeManager: ObservableObject {
    @Published private(set) var current: ThemeColors
    @Published private(set) var availableDefinitions: [ThemeDefinition] = ThemeDefinition.builtIn
    @Published private(set) var selectedThemeID: UUID?

    /// Current terminal font size — persisted via UserDefaults.
    @Published var terminalFontSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(terminalFontSize), forKey: "terminalFontSize") }
    }

    private var extendedColors: [ThemeToken: SwiftUI.Color] = [:]
    private var appearanceObservation: NSKeyValueObservation?

    // MARK: - Font zoom

    func increaseFontSize() {
        terminalFontSize = min(terminalFontSize + AppConfig.Fonts.zoomStep, AppConfig.Fonts.maxSize)
    }

    func decreaseFontSize() {
        terminalFontSize = max(terminalFontSize - AppConfig.Fonts.zoomStep, AppConfig.Fonts.minSize)
    }

    func resetFontSize() {
        terminalFontSize = AppConfig.Fonts.terminalSize
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: "terminalFontSize")
        terminalFontSize = saved > 0 ? CGFloat(saved) : AppConfig.Fonts.terminalSize
        current = ThemeManager.themeForCurrentAppearance()
        observeAppearance()
        Task { @MainActor [weak self] in
            await self?.restoreSelectedTheme()
        }
    }

    // MARK: - Color Lookup

    func color(for token: ThemeToken) -> SwiftUI.Color {
        if let extended = extendedColors[token] { return extended }
        return uiColor(for: token) ?? syntaxColor(for: token) ?? ansiColor(for: token)
    }

    // MARK: - Theme Application

    func apply(definition: ThemeDefinition) {
        current = definition.toThemeColors()
        selectedThemeID = definition.id
        UserDefaults.standard.set(definition.name, forKey: AppConfig.Theme.selectedThemeKey)
        buildExtendedColors(from: definition)
    }

    func addCustomTheme(_ definition: ThemeDefinition) {
        let limit = ThemeDefinition.builtIn.count + AppConfig.Theme.maxCustomThemes
        guard availableDefinitions.count < limit else {
            logger.warning("Custom theme limit reached (\(AppConfig.Theme.maxCustomThemes))")
            return
        }
        if let existing = availableDefinitions.firstIndex(where: { $0.id == definition.id }) {
            availableDefinitions[existing] = definition
        } else {
            availableDefinitions.append(definition)
        }
        apply(definition: definition)
        let def = definition
        Task.detached { await ThemeManager.saveTheme(def) }
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

    private func buildExtendedColors(from definition: ThemeDefinition) {
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

    // MARK: - Private — Persistence

    private func restoreSelectedTheme() async {
        let dir = Self.themesDirectory
        let customThemes: [ThemeDefinition] = await Task.detached {
            Self.readCustomThemes(from: dir)
        }.value
        availableDefinitions = ThemeDefinition.builtIn + customThemes
        if let name = UserDefaults.standard.string(forKey: AppConfig.Theme.selectedThemeKey),
           let definition = availableDefinitions.first(where: { $0.name == name }) {
            apply(definition: definition)
        }
    }

    private nonisolated static func readCustomThemes(from dir: URL) -> [ThemeDefinition] {
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil
            )
            let decoder = JSONDecoder()
            return files.filter { $0.pathExtension == "json" }.compactMap { url in
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(ThemeDefinition.self, from: data)
                } catch {
                    logger.warning("Skipping theme file \(url.lastPathComponent): \(error)")
                    return nil
                }
            }
        } catch {
            return [] // Directory doesn't exist on first launch — expected
        }
    }

    private nonisolated static func saveTheme(_ definition: ThemeDefinition) async {
        do {
            try FileManager.default.createDirectory(
                at: themesDirectory, withIntermediateDirectories: true
            )
            let url = themesDirectory.appendingPathComponent("\(definition.name).json")
            let data = try JSONEncoder().encode(definition)
            try data.write(to: url)
        } catch {
            logger.error("Failed to save theme '\(definition.name)': \(error)")
        }
    }

    private nonisolated static var themesDirectory: URL {
        URL(fileURLWithPath: AppConfig.Paths.homeDirectory)
            .appendingPathComponent(AppConfig.Persistence.directoryName)
            .appendingPathComponent(AppConfig.Theme.themesDirectoryName)
    }

    // MARK: - Private — Appearance observation

    private func observeAppearance() {
        appearanceObservation = NSApp.observe(
            \.effectiveAppearance,
            options: [.new]
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self, selectedThemeID == nil else { return }
                current = ThemeManager.themeForCurrentAppearance()
            }
        }
    }

    private static func themeForCurrentAppearance() -> ThemeColors {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark ? .dark : .light
    }
}
