import AppKit
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "ThemeManager")

/// Manages the active theme, responds to system appearance changes,
/// and exposes available definitions (built-in + custom).
@Observable @MainActor
final class ThemeManager {
    private(set) var current: ThemeColors
    private(set) var availableDefinitions: [ThemeDefinition] = ThemeDefinition.builtIn
    private(set) var selectedThemeID: UUID?

    /// Current terminal font size — persisted via UserDefaults.
    var terminalFontSize: CGFloat {
        didSet { userDefaults.set(Double(terminalFontSize), forKey: AppConfig.UserDefaultsKeys.terminalFontSize) }
    }

    private let userDefaults: any UserDefaultsStoring
    var extendedColors: [ThemeToken: SwiftUI.Color] = [:]
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

    init(userDefaults: any UserDefaultsStoring = UserDefaults.standard) {
        self.userDefaults = userDefaults
        // Restore user-customized font size. Migrate stale old default (15) to new default (16).
        let saved = userDefaults.double(forKey: AppConfig.UserDefaultsKeys.terminalFontSize)
        let didMigrateFontSize = userDefaults.bool(forKey: AppConfig.UserDefaultsKeys.terminalFontSizeMigratedV1)
        if !didMigrateFontSize && saved == 15.0 {
            // User had the old default (15) — upgrade to new default.
            terminalFontSize = AppConfig.Fonts.terminalSize
            userDefaults.removeObject(forKey: AppConfig.UserDefaultsKeys.terminalFontSize)
            userDefaults.set(true, forKey: AppConfig.UserDefaultsKeys.terminalFontSizeMigratedV1)
        } else if saved > 0 {
            terminalFontSize = CGFloat(saved)
        } else {
            terminalFontSize = AppConfig.Fonts.terminalSize
        }
        current = ThemeManager.themeForCurrentAppearance()
        observeAppearance()
        // Lifecycle: one-shot init — restores theme from disk; defaults apply if this fails.
        // Task inherits @MainActor from ThemeManager's @MainActor init context.
        Task { [weak self] in
            await self?.restoreSelectedTheme()
        }
    }

    // MARK: - Theme Application

    func apply(definition: ThemeDefinition) {
        current = definition.toThemeColors()
        selectedThemeID = definition.id
        userDefaults.set(definition.name, forKey: AppConfig.Theme.selectedThemeKey)
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
        // WHY: Persisting a theme should not block the in-memory apply path on disk I/O.
        // OWNER: ThemeManager launches this detached save during applyTheme.
        // TEARDOWN: One-shot detached persistence ends after saveTheme(def) completes.
        // TEST: Cover immediate in-memory apply plus eventual persistence of the selected theme.
        Task.detached { await ThemeManager.saveTheme(def) }
    }

    // MARK: - Private — Persistence

    private func restoreSelectedTheme() async {
        let dir = Self.themesDirectory
        // WHY: Reading custom themes hits disk and should not run on the caller's actor.
        // OWNER: restoreSelectedTheme owns this detached read and awaits it inline.
        // TEARDOWN: Awaiting .value ensures the read finishes before restoring availableDefinitions.
        // TEST: Cover restoring built-in + custom themes from persisted state.
        let customThemes: [ThemeDefinition] = await Task.detached {
            Self.readCustomThemes(from: dir)
        }.value
        availableDefinitions = ThemeDefinition.builtIn + customThemes
        if let name = userDefaults.string(forKey: AppConfig.Theme.selectedThemeKey),
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
            logger.debug("Custom themes directory not available: \(error.localizedDescription)")
            return []
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
