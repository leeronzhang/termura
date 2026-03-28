import Foundation

// Feature-specific configuration constants, split from AppConfig.swift to keep each
// file within the 300-line limit required by CLAUDE.md.

extension AppConfig {
    enum Timeline {
        /// Maximum number of turns kept in SessionTimeline.
        static let maxTurns = 200
        /// Width of the timeline side panel in points.
        static let panelWidth: Double = 180
    }

    enum Theme {
        /// Maximum number of user-imported custom themes.
        static let maxCustomThemes = 20
        /// Subdirectory under `.termura/` where custom theme JSON files are stored.
        static let themesDirectoryName = "themes"
        /// UserDefaults key persisting the selected theme's name.
        static let selectedThemeKey = "selectedThemeName"
    }

    enum SessionTree {
        /// Maximum nesting depth for session branches.
        static let maxDepth = 10
        /// Maximum branches per parent node.
        static let maxBranchesPerNode = 5
        /// Maximum character length for branch summaries.
        static let summaryMaxLength = 500
    }

    enum Export {
        /// Built-in HTML template name (without extension).
        static let htmlTemplateName = "session_export"
        /// Maximum messages per export operation.
        static let maxExportMessages = 10000
    }

    enum SplitPane {
        /// Minimum width of a split pane in points.
        static let minPaneWidth: Double = 200
        /// Minimum height of a split pane in points.
        static let minPaneHeight: Double = 150
        /// Maximum recursive split depth.
        static let maxSplitDepth = 4
    }

    enum Agent {
        /// How often to poll agent status (seconds).
        static let statusPollInterval: Double = 0.5
        /// Glow animation duration for attention sessions (seconds).
        static let glowAnimationDuration: Double = 2.0
        /// Suffix character count for agent output analysis.
        static let outputAnalysisSuffixLength = 2000
        /// Minimum seconds between status transitions (suppresses noisy false positives).
        static let statusChangeCooldown: TimeInterval = 0.5
    }

    enum Harness {
        /// Rule files to detect and manage.
        static let supportedRuleFiles = [
            "AGENTS.md", "CLAUDE.md", ".cursorrules", "CONVENTIONS.md"
        ]
        /// Maximum version history entries per rule file.
        static let maxVersionHistory = 50
        /// Corruption scan interval in seconds.
        static let corruptionScanInterval: Double = 300
    }

    enum SessionHandoff {
        /// Subdirectory under project root for handoff files.
        static let directoryName = ".termura"
        /// Context file name.
        static let contextFileName = "context.md"
        /// Maximum summary length in characters.
        static let maxSummaryLength = 2000
        /// Maximum number of decision entries to keep.
        static let maxDecisionEntries = 50
        /// Maximum character length for context injection text.
        static let injectionMaxLength = 1500
        /// Delay before injecting context after prompt detection (200ms).
        static let injectionDelay: Duration = .milliseconds(200)
    }

    enum FileTree {
        /// Directories to skip when scanning the project file tree.
        static let ignoredDirectories: Set<String> = [
            ".git", ".termura", "node_modules", ".build",
            "DerivedData", ".swiftpm", "Pods", "xcuserdata"
        ]
        /// Whether to skip all dotfiles (files/dirs starting with `.`).
        static let ignoredDotfiles = true
        /// Maximum directory nesting depth to scan.
        static let maxDepth = 10
    }

    enum Git {
        /// Debounce interval before refreshing git status after terminal output.
        static let refreshDebounce: Duration = .milliseconds(500)
        /// Maximum number of file entries to display in the sidebar.
        static let maxDisplayedFiles = 200
        /// Timeout for git CLI commands (5 seconds).
        static let commandTimeout: Duration = .seconds(5)
    }

    enum DragDrop {
        static let tempImageSubdirectory = ".termura/tmp"
        static let imagePastePrefix = "paste"
        static let imagePasteExtension = "png"
    }

    enum RecentProjects {
        static let maxCount = 20
        static let fileName = "recent-projects.json"
        /// Global config directory under user home for app-level files.
        static let globalDirectoryName = ".termura"
    }

    enum Health {
        static let probeInterval: Duration = .seconds(30)
        static let degradedThreshold = 3
        static let unhealthyThreshold = 5
    }

    enum CrashDiagnostics {
        static let ringBufferCapacity = 50
    }

    enum SemanticSearch {
        /// Embedding vector dimension (MiniLM-L6).
        static let embeddingDimension = 384
        static let chunkOverlapTokens = 50
        static let chunkMaxTokens = 256
        static let topK = 20
    }
}
