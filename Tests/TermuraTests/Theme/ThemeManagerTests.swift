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
}
