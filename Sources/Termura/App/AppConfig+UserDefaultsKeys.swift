import Foundation

extension AppConfig {
    /// All UserDefaults keys used by the app. No inline string literals at call sites.
    enum UserDefaultsKeys {
        // MARK: - Static keys

        /// Stores the list of project root paths that were open at last quit.
        static let openProjectPaths = "openProjectPaths"

        /// Persisted terminal font size in points.
        static let terminalFontSize = "terminalFontSize"

        /// Sentinel written after migrating the legacy default font size (15 pt to 16 pt).
        static let terminalFontSizeMigratedV1 = "terminalFontSize.migrated_v1"

        /// Sentinel written after the one-time global-to-per-project DB migration completes.
        static let projectMigrationCompleted = "projectMigrationCompleted"

        // MARK: - Per-project dynamic keys

        /// Persisted content-tab strip state for a given project root.
        static func openTabs(projectRoot: String) -> String {
            "openTabs-\(sanitized(projectRoot))"
        }

        /// Persisted selected content-tab ID for a given project root.
        static func openTabsSelected(projectRoot: String) -> String {
            "\(openTabs(projectRoot: projectRoot)).selected"
        }

        /// Persisted file-tree expanded node IDs for a given project root.
        static func fileTreeExpandedIDs(projectRoot: String) -> String {
            "fileTree.expandedIDs-\(sanitized(projectRoot))"
        }

        /// Persisted "hide ignored files" toggle state for a given project root.
        static func fileTreeHideIgnored(projectRoot: String) -> String {
            "fileTree.hideIgnored-\(sanitized(projectRoot))"
        }

        // MARK: - Per-project window state keys

        /// Persisted windowed frame for a project window, stored as an NSRect string.
        static func windowFrame(projectURL: URL) -> String {
            "window.frame-\(sanitized(projectURL.path))"
        }

        /// Whether the project window was in fullscreen at last quit.
        static func windowFullScreen(projectURL: URL) -> String {
            "window.fullScreen-\(sanitized(projectURL.path))"
        }

        // MARK: - Private

        /// Sanitizes a file-system path into a safe UserDefaults key suffix.
        /// ASCII letters, digits, `/`, `.`, `-`, `_`, and space pass through unchanged;
        /// all other Unicode scalars are replaced with `_`.
        /// Typical macOS paths (ASCII-only) produce the same output as the raw path,
        /// so existing persisted values remain accessible without migration.
        private static func sanitized(_ path: String) -> String {
            path.unicodeScalars.map { scalar -> String in
                let value = scalar.value
                let isSafe = (value >= 65 && value <= 90)    // A-Z
                          || (value >= 97 && value <= 122)   // a-z
                          || (value >= 48 && value <= 57)    // 0-9
                          || value == 47    // /
                          || value == 46    // .
                          || value == 45    // -
                          || value == 95    // _
                          || value == 32    // space
                return isSafe ? String(scalar) : "_"
            }.joined()
        }
    }
}
