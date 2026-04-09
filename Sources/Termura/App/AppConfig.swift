import Foundation

/// Central configuration for all app-wide constants. No inline magic numbers.
enum AppConfig {
    enum Paths {
        /// Cached home directory — resolved once at process launch.
        static let homeDirectory: String = FileManager.default.homeDirectoryForCurrentUser.path
    }

    enum Fonts {
        /// Source Code Pro — bundled monospaced font for terminal, editor, and code display.
        static let terminalFamily = "Source Code Pro"
        static let terminalSize: CGFloat = 16
        static let editorSize: CGFloat = 16
        static let notesSize: CGFloat = 16
        /// Font size increment/decrement step for Cmd+/-.
        static let zoomStep: CGFloat = 1
        /// Minimum allowed terminal font size.
        static let minSize: CGFloat = 9
        /// Maximum allowed terminal font size.
        static let maxSize: CGFloat = 28
    }

    enum Input {
        static let historyCapacity = 200
    }

    enum Notes {
        static let maxTitleLength = 200
        /// Legacy single-folder location: `<project>/.termura/notes/`.
        /// Used only by KnowledgeStructureMigrationService to detect old layouts to migrate.
        /// New code should use `AppConfig.Knowledge.notesSubdirectory` under `Knowledge.directoryName`.
        static let legacyNotesDirectoryName = "notes"
        /// Maximum slug length in note filenames.
        static let maxSlugLength = 50
        /// Debounce window for file-system watcher events on the notes directory.
        static let fileWatchDebounce: Duration = .milliseconds(500)
    }

    /// Knowledge management directory layout under `<project>/.termura/`.
    /// Three-tier structure: sources (raw inputs), log (agent conversations),
    /// notes (curated outputs), plus shared attachments.
    enum Knowledge {
        /// Top-level container under `.termura/`.
        static let directoryName = "knowledge"
        /// Curated notes — the user/agent-edited markdown layer.
        static let notesSubdirectory = "notes"
        /// Raw input materials (articles, PDFs, screenshots, datasets).
        static let sourcesSubdirectory = "sources"
        /// Human ↔ AI conversation logs (filled by P2 capture).
        static let logSubdirectory = "log"
        /// Cross-note shared resources (images, diagrams, data).
        static let attachmentsSubdirectory = "attachments"
    }

    enum Search {
        static let maxResults = 50
        static let minQueryLength = 2
        static let previewLength = 64
    }

    enum URLs {
        /// Harness product page — shown in the free-build upsell panel.
        static let harnessProduct = "https://termura.app/harness"

        /// Schemes that may be opened from terminal output (OSC 8 / plain-text detection).
        /// Any URL whose scheme is not in this set is silently blocked.
        static let allowedTerminalSchemes: Set<String> = ["https", "http", "file", "mailto"]
    }

    // MARK: - Link Routing

    enum LinkRouting {
        /// UserDefaults key for link open mode preference.
        static let linkOpenModeKey = "linkRouting.openMode"
        /// Default link open mode: "internal" opens in-app, "external" opens in system browser.
        static let defaultOpenMode = "internal"

        /// File extensions routed to the internal CodeEditorView.
        static let codeExtensions: Set<String> = [
            "swift", "ts", "tsx", "js", "jsx", "py", "rs", "go",
            "rb", "java", "kt", "c", "cpp", "h", "m", "mm",
            "css", "json", "yaml", "yml", "toml"
        ]
        /// File extensions routed to the internal Markdown/rich render panel.
        static let markdownExtensions: Set<String> = ["md", "markdown", "mdx"]
        /// File extensions routed to the internal image/PDF preview.
        static let previewExtensions: Set<String> = [
            "png", "jpg", "jpeg", "gif", "svg", "pdf", "webp"
        ]
        /// File extensions loaded directly in the Panel WebView.
        static let webExtensions: Set<String> = ["html", "htm"]
    }
}
