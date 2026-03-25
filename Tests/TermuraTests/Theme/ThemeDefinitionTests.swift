import Foundation
import Testing
@testable import Termura

@Suite("ThemeDefinition")
struct ThemeDefinitionTests {
    // MARK: - color(fromHex:)

    @Test("Valid hex #FF0000 returns red color")
    func validHexRed() {
        let color = ThemeDefinition.color(fromHex: "#FF0000")
        #expect(color != nil)
    }

    @Test("Valid hex #000000 returns black")
    func validHexBlack() {
        let color = ThemeDefinition.color(fromHex: "#000000")
        #expect(color != nil)
    }

    @Test("Nil input returns nil")
    func nilInput() {
        let color = ThemeDefinition.color(fromHex: nil)
        #expect(color == nil)
    }

    @Test("Short string returns nil")
    func shortString() {
        let color = ThemeDefinition.color(fromHex: "#FFF")
        #expect(color == nil)
    }

    @Test("String without # prefix returns nil")
    func noHashPrefix() {
        let color = ThemeDefinition.color(fromHex: "FF0000")
        #expect(color == nil)
    }

    @Test("Empty string returns nil")
    func emptyString() {
        let color = ThemeDefinition.color(fromHex: "")
        #expect(color == nil)
    }

    // MARK: - toThemeColors()

    @Test("Dark definition produces dark-based ThemeColors")
    func darkThemeColors() {
        let def = ThemeDefinition(
            id: UUID(),
            name: "DarkTest",
            isDark: true,
            colors: ["background": "#1E1E2E"]
        )
        let colors = def.toThemeColors()
        // Should use custom background, not the base dark default.
        #expect(colors.background != ThemeColors.light.background)
    }

    @Test("Light definition produces light-based ThemeColors")
    func lightThemeColors() {
        let def = ThemeDefinition(
            id: UUID(),
            name: "LightTest",
            isDark: false,
            colors: ["background": "#FFFFFF"]
        )
        let colors = def.toThemeColors()
        #expect(colors.background != ThemeColors.dark.background)
    }

    @Test("Missing color key falls back to base")
    func missingKeyFallback() {
        let def = ThemeDefinition(
            id: UUID(),
            name: "Minimal",
            isDark: true,
            colors: [:] // No custom colors at all.
        )
        let colors = def.toThemeColors()
        // Should still produce valid colors (all fallback to base dark).
        #expect(colors.background == ThemeColors.dark.background)
    }

    // MARK: - Built-in themes

    @Test("Built-in themes are non-empty")
    func builtInNonEmpty() {
        #expect(!ThemeDefinition.builtIn.isEmpty)
    }
}
