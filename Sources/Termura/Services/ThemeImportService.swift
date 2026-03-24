import Foundation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "ThemeImportService")

protocol ThemeImportServiceProtocol: Sendable {
    func importJSON(from url: URL) async throws -> ThemeDefinition
    func importItermColors(from url: URL) async throws -> ThemeDefinition
    nonisolated func toThemeColors(_ definition: ThemeDefinition) -> ThemeColors
}

enum ThemeImportError: Error, LocalizedError {
    case fileReadError(String)
    case invalidFormat(String)

    var errorDescription: String? {
        switch self {
        case let .fileReadError(msg): "Failed to read file: \(msg)"
        case let .invalidFormat(msg): "Invalid theme format: \(msg)"
        }
    }
}

/// Imports ThemeDefinitions from .json and .itermcolors files.
actor ThemeImportService: ThemeImportServiceProtocol {
    func importJSON(from url: URL) async throws -> ThemeDefinition {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw ThemeImportError.fileReadError(error.localizedDescription)
        }
        do {
            return try JSONDecoder().decode(ThemeDefinition.self, from: data)
        } catch {
            throw ThemeImportError.invalidFormat(error.localizedDescription)
        }
    }

    func importItermColors(from url: URL) async throws -> ThemeDefinition {
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw ThemeImportError.fileReadError(error.localizedDescription)
        }
        let plist: Any
        do {
            plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        } catch {
            throw ThemeImportError.invalidFormat("PropertyList parse failed: \(error.localizedDescription)")
        }
        guard let dict = plist as? [String: Any] else {
            throw ThemeImportError.invalidFormat("Expected top-level dictionary")
        }
        let name = url.deletingPathExtension().lastPathComponent
        return parseItermDict(dict, name: name)
    }

    nonisolated func toThemeColors(_ definition: ThemeDefinition) -> ThemeColors {
        definition.toThemeColors()
    }

    // MARK: - Private

    private func parseItermDict(_ dict: [String: Any], name: String) -> ThemeDefinition {
        var colors: [String: String] = [:]
        let mapping: [(String, String)] = [
            ("Background Color", "background"), ("Foreground Color", "foreground"),
            ("Cursor Color", "cursor"), ("Selection Color", "selectionBackground"),
            ("Ansi 0 Color", "ansiBlack"), ("Ansi 1 Color", "ansiRed"),
            ("Ansi 2 Color", "ansiGreen"), ("Ansi 3 Color", "ansiYellow"),
            ("Ansi 4 Color", "ansiBlue"), ("Ansi 5 Color", "ansiMagenta"),
            ("Ansi 6 Color", "ansiCyan"), ("Ansi 7 Color", "ansiWhite"),
            ("Ansi 8 Color", "ansiBrightBlack"), ("Ansi 9 Color", "ansiBrightRed"),
            ("Ansi 10 Color", "ansiBrightGreen"), ("Ansi 11 Color", "ansiBrightYellow"),
            ("Ansi 12 Color", "ansiBrightBlue"), ("Ansi 13 Color", "ansiBrightMagenta"),
            ("Ansi 14 Color", "ansiBrightCyan"), ("Ansi 15 Color", "ansiBrightWhite")
        ]
        for (itermKey, tokenKey) in mapping {
            if let hex = hexFromItermEntry(dict[itermKey]) {
                colors[tokenKey] = hex
            }
        }
        let isDark = luminance(ofHex: colors["background"]) < 0.5
        return ThemeDefinition(id: UUID(), name: name, isDark: isDark, colors: colors)
    }

    private func hexFromItermEntry(_ value: Any?) -> String? {
        guard let colorEntry = value as? [String: Any],
              let red = colorEntry["Red Component"] as? Double,
              let green = colorEntry["Green Component"] as? Double,
              let blue = colorEntry["Blue Component"] as? Double else { return nil }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }

    private func luminance(ofHex hex: String?) -> Double {
        guard let hex, hex.count >= 7, hex.hasPrefix("#") else { return 0 }
        let rv = Double(Int(hex.dropFirst(1).prefix(2), radix: 16) ?? 0) / 255.0
        let gv = Double(Int(hex.dropFirst(3).prefix(2), radix: 16) ?? 0) / 255.0
        let bv = Double(Int(hex.dropFirst(5).prefix(2), radix: 16) ?? 0) / 255.0
        return 0.299 * rv + 0.587 * gv + 0.114 * bv
    }
}

// MARK: - Mock (struct for zero-state, protocol-compliant test double)

struct MockThemeImportService: ThemeImportServiceProtocol {
    func importJSON(from url: URL) async throws -> ThemeDefinition { .termuraDark }
    func importItermColors(from url: URL) async throws -> ThemeDefinition { .termuraDark }
    nonisolated func toThemeColors(_ definition: ThemeDefinition) -> ThemeColors { .dark }
}
