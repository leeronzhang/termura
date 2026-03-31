import AppKit
import Foundation
import Observation
import OSLog
import SwiftUI

private let logger = Logger(subsystem: "com.termura.app", category: "FontSettings")

/// Centralized, persisted font settings. All font consumers read from here.
/// Changed via the Settings panel — no code edits needed for font adjustments.
@Observable @MainActor
final class FontSettings {
    // MARK: - Settings

    var terminalFontFamily: String {
        didSet { persist() }
    }

    var terminalFontSize: CGFloat {
        didSet { persist() }
    }

    var editorFontSize: CGFloat {
        didSet { persist() }
    }

    // MARK: - Defaults (used when no user customization exists)

    static let defaultFamily = "Source Code Pro"
    static let defaultTerminalSize: CGFloat = 16
    static let defaultEditorSize: CGFloat = 16
    static let minSize: CGFloat = 9
    static let maxSize: CGFloat = 28
    static let zoomStep: CGFloat = 1

    // MARK: - UserDefaults keys

    private enum Keys {
        static let family = "font.family"
        static let terminalSize = "font.terminalSize"
        static let editorSize = "font.editorSize"
    }

    private let userDefaults: any UserDefaultsStoring

    // MARK: - Init

    init(userDefaults: any UserDefaultsStoring = UserDefaults.standard) {
        self.userDefaults = userDefaults
        let ud = userDefaults

        // Family
        let savedFamily = ud.string(forKey: Keys.family)
        terminalFontFamily = savedFamily ?? Self.defaultFamily

        // Terminal size — migrate old key if present
        let oldKey = "terminalFontSize"
        let oldSaved = ud.double(forKey: oldKey)
        let newSaved = ud.double(forKey: Keys.terminalSize)
        if newSaved > 0 {
            terminalFontSize = CGFloat(newSaved)
        } else if oldSaved > 0 && oldSaved != 15.0 {
            // Migrate user-customized value from old key (skip stale default 15)
            terminalFontSize = CGFloat(oldSaved)
            ud.removeObject(forKey: oldKey)
        } else {
            terminalFontSize = Self.defaultTerminalSize
            ud.removeObject(forKey: oldKey)
        }

        // Editor size
        let edSaved = ud.double(forKey: Keys.editorSize)
        editorFontSize = edSaved > 0 ? CGFloat(edSaved) : Self.defaultEditorSize

        let family = terminalFontFamily
        let tSize = terminalFontSize
        let eSize = editorFontSize
        logger.info("FontSettings loaded: family=\(family) terminal=\(tSize) editor=\(eSize)")
    }

    // MARK: - Zoom actions (Cmd+/-)

    func zoomIn() {
        terminalFontSize = min(terminalFontSize + Self.zoomStep, Self.maxSize)
        editorFontSize = min(editorFontSize + Self.zoomStep, Self.maxSize)
    }

    func zoomOut() {
        terminalFontSize = max(terminalFontSize - Self.zoomStep, Self.minSize)
        editorFontSize = max(editorFontSize - Self.zoomStep, Self.minSize)
    }

    func resetZoom() {
        terminalFontSize = Self.defaultTerminalSize
        editorFontSize = Self.defaultEditorSize
    }

    // MARK: - Font constructors

    func terminalNSFont() -> NSFont {
        NSFont(name: terminalFontFamily, size: terminalFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: terminalFontSize, weight: .regular)
    }

    func editorNSFont() -> NSFont {
        NSFont(name: terminalFontFamily, size: editorFontSize)
            ?? NSFont.monospacedSystemFont(ofSize: editorFontSize, weight: .regular)
    }

    func terminalSwiftUIFont() -> Font {
        .custom(terminalFontFamily, size: terminalFontSize)
    }

    func editorSwiftUIFont() -> Font {
        .custom(terminalFontFamily, size: editorFontSize)
    }

    // MARK: - Available monospaced font families

    // Intentionally computed: queries NSFontManager.shared at runtime (system font list is dynamic).
    static var availableMonospacedFamilies: [String] {
        let fm = NSFontManager.shared
        return fm.availableFontFamilies.filter { family in
            guard let members = fm.availableMembers(ofFontFamily: family),
                  let first = members.first,
                  let fontName = first[0] as? String,
                  let font = NSFont(name: fontName, size: 13) else { return false }
            return font.isFixedPitch
        }.sorted()
    }

    // MARK: - Persistence

    private func persist() {
        userDefaults.set(terminalFontFamily, forKey: Keys.family)
        userDefaults.set(Double(terminalFontSize), forKey: Keys.terminalSize)
        userDefaults.set(Double(editorFontSize), forKey: Keys.editorSize)
    }
}
