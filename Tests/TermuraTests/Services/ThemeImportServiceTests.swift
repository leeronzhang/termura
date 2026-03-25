import Testing
import Foundation
@testable import Termura

@Suite("ThemeImportService")
struct ThemeImportServiceTests {
    private let service = ThemeImportService()

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-theme-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func writeTempJSON(_ definition: ThemeDefinition, dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("\(definition.name).json")
        let data = try JSONEncoder().encode(definition)
        try data.write(to: url)
        return url
    }

    private func writeTempPlist(_ entries: [String: Any], name: String, dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("\(name).itermcolors")
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .xml, options: 0)
        try data.write(to: url)
        return url
    }

    private func makeColorEntry(red: Double, green: Double, blue: Double) -> [String: Any] {
        [
            "Red Component": red,
            "Green Component": green,
            "Blue Component": blue,
            "Alpha Component": 1.0
        ]
    }

    // MARK: - JSON import

    @Test("Import valid JSON round-trips")
    func importValidJSON() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let original = ThemeDefinition(
            id: UUID(),
            name: "TestTheme",
            isDark: true,
            colors: ["background": "#1E1E1E", "foreground": "#FFFFFF"]
        )
        let url = try writeTempJSON(original, dir: dir)
        let imported = try await service.importJSON(from: url)

        #expect(imported.name == "TestTheme")
        #expect(imported.isDark == true)
        #expect(imported.colors["background"] == "#1E1E1E")
    }

    @Test("Import invalid JSON throws invalidFormat")
    func importInvalidJSON() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("bad.json")
        try "not json at all".write(to: url, atomically: true, encoding: .utf8)

        do {
            _ = try await service.importJSON(from: url)
            Issue.record("Expected ThemeImportError.invalidFormat")
        } catch is ThemeImportError {
            // Expected
        }
    }

    @Test("Import nonexistent file throws fileReadError")
    func importMissingFile() async throws {
        let url = URL(fileURLWithPath: "/tmp/nonexistent-\(UUID().uuidString).json")
        do {
            _ = try await service.importJSON(from: url)
            Issue.record("Expected ThemeImportError.fileReadError")
        } catch is ThemeImportError {
            // Expected
        }
    }

    // MARK: - iTerm Colors import

    @Test("Import iTerm plist extracts colors")
    func importItermColors() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entries: [String: Any] = [
            "Background Color": makeColorEntry(red: 0.118, green: 0.118, blue: 0.180),
            "Foreground Color": makeColorEntry(red: 0.804, green: 0.839, blue: 0.957)
        ]
        let url = try writeTempPlist(entries, name: "Catppuccin", dir: dir)
        let theme = try await service.importItermColors(from: url)

        #expect(theme.name == "Catppuccin")
        #expect(theme.colors["background"] != nil)
        #expect(theme.colors["foreground"] != nil)
    }

    @Test("Dark background → isDark true")
    func itermDarkBackground() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entries: [String: Any] = [
            "Background Color": makeColorEntry(red: 0.118, green: 0.118, blue: 0.180)
        ]
        let url = try writeTempPlist(entries, name: "Dark", dir: dir)
        let theme = try await service.importItermColors(from: url)
        #expect(theme.isDark == true)
    }

    @Test("Light background → isDark false")
    func itermLightBackground() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entries: [String: Any] = [
            "Background Color": makeColorEntry(red: 1.0, green: 1.0, blue: 1.0)
        ]
        let url = try writeTempPlist(entries, name: "Light", dir: dir)
        let theme = try await service.importItermColors(from: url)
        #expect(theme.isDark == false)
    }

    @Test("File name used as theme name")
    func itermFileNameAsThemeName() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = try writeTempPlist([:], name: "Solarized", dir: dir)
        let theme = try await service.importItermColors(from: url)
        #expect(theme.name == "Solarized")
    }

    @Test("Invalid plist throws invalidFormat")
    func importInvalidPlist() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("bad.itermcolors")
        try "not a plist".write(to: url, atomically: true, encoding: .utf8)

        do {
            _ = try await service.importItermColors(from: url)
            Issue.record("Expected ThemeImportError.invalidFormat")
        } catch is ThemeImportError {
            // Expected
        }
    }

    // MARK: - Hex conversion

    @Test("RGB(1,0,0) → #FF0000")
    func hexConversionRed() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entries: [String: Any] = [
            "Foreground Color": makeColorEntry(red: 1.0, green: 0.0, blue: 0.0)
        ]
        let url = try writeTempPlist(entries, name: "Red", dir: dir)
        let theme = try await service.importItermColors(from: url)
        #expect(theme.colors["foreground"] == "#FF0000")
    }

    @Test("RGB(0.5,0.5,0.5) → #7F7F7F or #808080")
    func hexConversionGray() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entries: [String: Any] = [
            "Foreground Color": makeColorEntry(red: 0.5, green: 0.5, blue: 0.5)
        ]
        let url = try writeTempPlist(entries, name: "Gray", dir: dir)
        let theme = try await service.importItermColors(from: url)
        // Int(0.5 * 255) = 127 = 0x7F
        #expect(theme.colors["foreground"] == "#7F7F7F")
    }

    @Test("Missing color component returns nil entry")
    func missingColorComponent() async throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let entries: [String: Any] = [
            "Background Color": ["Red Component": 1.0, "Green Component": 0.5]
            // Missing Blue Component
        ]
        let url = try writeTempPlist(entries, name: "Broken", dir: dir)
        let theme = try await service.importItermColors(from: url)
        #expect(theme.colors["background"] == nil)
    }
}
