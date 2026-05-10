import Foundation
@testable import Termura
import XCTest

@MainActor
final class ThemeManagerTests: XCTestCase {
    private var isolatedDefaults: UserDefaults!
    private var suiteName: String!

    override func setUp() async throws {
        suiteName = "com.termura.tests.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() async throws {
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults = nil
        suiteName = nil
    }

    private func makeManager() -> ThemeManager {
        ThemeManager(userDefaults: isolatedDefaults)
    }

    // MARK: - Color lookup

    func testColorForBackgroundReturnsThemeBackground() {
        let manager = makeManager()
        let color = manager.color(for: .background)
        // Should return a non-nil Color (the current theme's background).
        XCTAssertNotNil(color)
    }

    func testColorForForegroundReturnsThemeForeground() {
        let manager = makeManager()
        let color = manager.color(for: .foreground)
        XCTAssertNotNil(color)
    }

    // MARK: - Apply theme

    func testApplyUpdatesSelectedThemeID() {
        let manager = makeManager()
        let theme = ThemeDefinition(
            id: UUID(),
            name: "TestTheme",
            isDark: true,
            colors: ["background": "#1E1E2E"]
        )
        manager.apply(definition: theme)
        XCTAssertEqual(manager.selectedThemeID, theme.id)
    }

    func testApplyPersistsToUserDefaults() {
        let manager = makeManager()
        let theme = ThemeDefinition(
            id: UUID(),
            name: "PersistTest",
            isDark: true,
            colors: [:]
        )
        manager.apply(definition: theme)
        let saved = isolatedDefaults.string(forKey: AppConfig.Theme.selectedThemeKey)
        XCTAssertEqual(saved, "PersistTest")
    }

    // MARK: - Add custom theme

    func testAddCustomThemeAppendsToAvailable() {
        let manager = makeManager()
        let countBefore = manager.availableDefinitions.count
        let theme = ThemeDefinition(
            id: UUID(),
            name: "Custom",
            isDark: true,
            colors: [:]
        )
        manager.addCustomTheme(theme)
        XCTAssertEqual(manager.availableDefinitions.count, countBefore + 1)
    }

    func testAddCustomThemeReplacesExistingByID() {
        let manager = makeManager()
        let themeID = UUID()
        let theme1 = ThemeDefinition(id: themeID, name: "V1", isDark: true, colors: [:])
        let theme2 = ThemeDefinition(id: themeID, name: "V2", isDark: true, colors: [:])

        manager.addCustomTheme(theme1)
        let countAfterFirst = manager.availableDefinitions.count
        manager.addCustomTheme(theme2)

        // Count should not increase — replaced in place.
        XCTAssertEqual(manager.availableDefinitions.count, countAfterFirst)
        let found = manager.availableDefinitions.first { $0.id == themeID }
        XCTAssertEqual(found?.name, "V2")
    }

    func testAddCustomThemeRespectsLimit() {
        let manager = makeManager()
        let builtInCount = ThemeDefinition.builtIn.count
        let limit = AppConfig.Theme.maxCustomThemes

        // Fill up to the limit.
        for i in 0 ..< limit + 5 {
            let theme = ThemeDefinition(
                id: UUID(),
                name: "Custom\(i)",
                isDark: true,
                colors: [:]
            )
            manager.addCustomTheme(theme)
        }

        // Total should not exceed builtIn + maxCustomThemes.
        XCTAssertLessThanOrEqual(
            manager.availableDefinitions.count,
            builtInCount + limit
        )
    }

    // MARK: - Color lookup across token categories

    func testColorForAllCoreUITokens() {
        let manager = makeManager()
        let coreTokens: [ThemeToken] = [
            .background, .foreground, .selectionBackground, .cursor,
            .sidebarBackground, .sidebarText, .activeSessionHighlight,
            .statusBarBackground, .inputBackground, .inputBorder
        ]
        for token in coreTokens {
            let color = manager.color(for: token)
            XCTAssertNotNil(color, "Core token \(token.rawValue) returned nil")
        }
    }

    func testColorForStatusTokens() {
        let manager = makeManager()
        let statusTokens: [ThemeToken] = [
            .statusSuccess, .statusError, .statusWarning, .statusInfo,
            .borderSubtle, .surfaceOverlay
        ]
        for token in statusTokens {
            let color = manager.color(for: token)
            XCTAssertNotNil(color, "Status token \(token.rawValue) returned nil")
        }
    }

    func testColorForSyntaxTokens() {
        let manager = makeManager()
        let syntaxTokens: [ThemeToken] = [
            .keyword, .string, .comment, .number, .function, .type
        ]
        for token in syntaxTokens {
            let color = manager.color(for: token)
            XCTAssertNotNil(color, "Syntax token \(token.rawValue) returned nil")
        }
    }

    func testColorForANSITokens() {
        let manager = makeManager()
        let ansiTokens: [ThemeToken] = [
            .ansiBlack, .ansiRed, .ansiGreen, .ansiYellow,
            .ansiBlue, .ansiMagenta, .ansiCyan, .ansiWhite,
            .ansiBrightBlack, .ansiBrightRed, .ansiBrightGreen,
            .ansiBrightYellow, .ansiBrightBlue, .ansiBrightMagenta,
            .ansiBrightCyan, .ansiBrightWhite
        ]
        for token in ansiTokens {
            let color = manager.color(for: token)
            XCTAssertNotNil(color, "ANSI token \(token.rawValue) returned nil")
        }
    }

    func testAllThemeTokensReturnColor() {
        let manager = makeManager()
        for token in ThemeToken.allCases {
            let color = manager.color(for: token)
            XCTAssertNotNil(color, "Token \(token.rawValue) returned nil")
        }
    }

    // MARK: - Built-in palette completeness (regression)

    /// Regression: built-ins previously omitted bright ANSI 8-15 and the
    /// six status/border/surface keys, so `toThemeColors()` silently fell
    /// through to `ThemeColors.dark` / `.light`. Effect: Solarized Dark
    /// and Monokai shipped with identical bright-ANSI palettes (both Dark+
    /// greys), and importing themes that didn't ship status/border keys
    /// rendered Termura's defaults instead of their own palette. Pin the
    /// invariant so every shipped built-in declares the full 31-token set.
    func testEveryBuiltInDeclaresAllPaletteTokens() {
        let requiredKeys: [String] = [
            "background", "foreground", "cursor", "selectionBackground",
            "sidebarBackground", "sidebarText", "activeSessionHighlight",
            "ansiBlack", "ansiRed", "ansiGreen", "ansiYellow",
            "ansiBlue", "ansiMagenta", "ansiCyan", "ansiWhite",
            "ansiBrightBlack", "ansiBrightRed", "ansiBrightGreen",
            "ansiBrightYellow", "ansiBrightBlue", "ansiBrightMagenta",
            "ansiBrightCyan", "ansiBrightWhite",
            "keyword", "string", "comment", "number", "function", "type",
            "statusBarBackground", "inputBackground", "inputBorder",
            "statusSuccess", "statusError", "statusWarning", "statusInfo",
            "borderSubtle", "surfaceOverlay"
        ]
        for definition in ThemeDefinition.builtIn {
            for key in requiredKeys {
                XCTAssertNotNil(definition.colors[key],
                                "Built-in '\(definition.name)' is missing palette key '\(key)' — it would silently fall back to ThemeColors.dark/.light and pollute the theme's identity")
            }
        }
    }

    /// Regression: the six semantic UI tokens (statusSuccess/Error/Warning/
    /// Info, borderSubtle, surfaceOverlay) were not in `buildExtendedColors`'
    /// tokenMap, so a theme that defined them in `colors[...]` couldn't
    /// actually override the ANSI-derived defaults. Verify the new entries
    /// flow through.
    func testStatusAndSurfaceTokensFlowThroughExtendedColors() {
        let manager = makeManager()
        let probe = ThemeDefinition(
            id: UUID(),
            name: "ExtendedProbe",
            isDark: true,
            colors: [
                "statusSuccess": "#112233", "statusError": "#445566",
                "statusWarning": "#778899", "statusInfo": "#AABBCC",
                "borderSubtle": "#DDEEFF", "surfaceOverlay": "#001122"
            ]
        )
        manager.apply(definition: probe)
        // If the tokenMap didn't include these keys, color(for:) would fall
        // through to `uiStatusColor`'s ANSI-derived default (current.green
        // for statusSuccess etc.), not the hex we provided.
        XCTAssertEqual(manager.color(for: .statusSuccess),
                       ThemeDefinition.color(fromHex: "#112233"))
        XCTAssertEqual(manager.color(for: .statusError),
                       ThemeDefinition.color(fromHex: "#445566"))
        XCTAssertEqual(manager.color(for: .statusWarning),
                       ThemeDefinition.color(fromHex: "#778899"))
        XCTAssertEqual(manager.color(for: .statusInfo),
                       ThemeDefinition.color(fromHex: "#AABBCC"))
        XCTAssertEqual(manager.color(for: .borderSubtle),
                       ThemeDefinition.color(fromHex: "#DDEEFF"))
        XCTAssertEqual(manager.color(for: .surfaceOverlay),
                       ThemeDefinition.color(fromHex: "#001122"))
    }

    /// A definition that omits the new keys still works — the lookup
    /// falls through to `uiStatusColor`'s ANSI-derived defaults rather
    /// than crashing or returning nil.
    func testThemeWithoutStatusKeysStillResolvesAllTokens() {
        let manager = makeManager()
        let bare = ThemeDefinition(
            id: UUID(),
            name: "Bare",
            isDark: true,
            colors: ["background": "#101010", "foreground": "#F0F0F0"]
        )
        manager.apply(definition: bare)
        for token in ThemeToken.allCases {
            XCTAssertNotNil(manager.color(for: token),
                            "Bare theme should resolve \(token.rawValue) via fallback chain")
        }
    }

    func testGruvboxMaterialBuiltinsArePresentAndDarknessFlagsCorrect() {
        let names = ThemeDefinition.builtIn.map(\.name)
        XCTAssertTrue(names.contains("Gruvbox Material Light"),
                      "Gruvbox Material Light must be a shipped built-in")
        XCTAssertTrue(names.contains("Gruvbox Material Dark"),
                      "Gruvbox Material Dark must be a shipped built-in")
        let light = ThemeDefinition.builtIn.first { $0.name == "Gruvbox Material Light" }
        let dark = ThemeDefinition.builtIn.first { $0.name == "Gruvbox Material Dark" }
        XCTAssertEqual(light?.isDark, false)
        XCTAssertEqual(dark?.isDark, true)
    }
}
