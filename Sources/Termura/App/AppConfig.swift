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

    enum Terminal {
        static let maxScrollbackLines = 10000
        static let maxOutputChunksPerSession = 500
        static let ptyColumns: UInt16 = 80
        static let ptyRows: UInt16 = 24
    }

    enum Runtime {
        /// Session switch target: < 100ms
        static let sessionSwitchDeadlineSeconds: Double = 0.1
        /// Search debounce
        static let searchDebounceSeconds: Double = 0.3
        /// Notes auto-save debounce
        static let notesAutoSaveSeconds: Double = 1.0
        /// Maximum concurrent background tasks per terminal session.
        /// Bounds CPU/memory usage during high-frequency output (e.g. `cat` large file).
        static let maxConcurrentSessionTasks = 8
        /// Long command notification threshold
        static let longCommandThresholdSeconds: Double = 30.0
        /// Visor animation duration
        static let visorAnimationSeconds: Double = 0.2
        /// Delay before dismissing onboarding sheet after install.
        static let onboardingDismissDelaySeconds: Double = 1.0
    }

    enum SLO {
        /// Launch time P95 target: < 2s
        static let launchSeconds: Double = 2.0
        /// Full-text search P99 target: < 200ms
        static let searchSeconds: Double = 0.2
        /// Terminal input latency target: < 16ms (1 frame)
        static let inputLatencySeconds: Double = 0.016
    }

    enum Input {
        static let historyCapacity = 200
    }

    enum Notes {
        static let maxTitleLength = 200
    }

    enum Persistence {
        static let databaseFileName = "termura.db"
        static let directoryName = ".termura"
        static let snapshotMaxLines = 1000
        static let snapshotCompressionKey = "lzfse"
    }

    // swiftlint:disable:next type_name
    enum AI {
        /// Heuristic: chars / 4 ≈ tokens
        static let tokenEstimateDivisor: Double = 4.0
    }

    /// Per-million-token pricing for heuristic cost estimation.
    enum CostEstimation {
        static let claudeInputPerMillion: Double = 3.0
        static let claudeOutputPerMillion: Double = 15.0
        static let claudeCacheReadPerMillion: Double = 0.30
        static let defaultInputPerMillion: Double = 3.0
        static let defaultOutputPerMillion: Double = 15.0
    }

    enum ContextWindow {
        static let claudeCodeLimit = 200_000
        static let codexLimit = 128_000
        static let aiderLimit = 128_000
        static let openCodeLimit = 128_000
        static let piLimit = 128_000
        static let geminiLimit = 1_000_000
        static let unknownLimit = 100_000
        /// Fraction of context window at which to show a warning.
        static let warningThreshold: Double = 0.8
        /// Fraction of context window at which to show a critical alert.
        static let criticalThreshold: Double = 0.95
        /// Minimum interval between context window notifications (seconds).
        static let notificationCooldownSeconds: Double = 60.0
    }

    // swiftlint:disable:next type_name
    enum UI {
        static let sidebarMinWidth: Double = 220
        static let sidebarMaxWidth: Double = 480
        static let sidebarDefaultWidth: Double = 360
        static let metadataBarHeight: Double = 28
        static let metadataPanelWidth: Double = 280
        static let metadataPanelMinWidth: Double = 120
        static let metadataPanelMaxWidth: Double = 300
        static let dualPaneMinWidth: Double = 300
        static let tokenProgressWarningFraction: Double = 0.8
        static let editorMinHeightPoints: Double = 72
        static let editorMaxHeightPoints: Double = 300
        /// Delay after exiting full screen before repositioning traffic lights (100ms).
        static let fullScreenExitDelayNanoseconds: UInt64 = 100_000_000
        /// Delay before window configuration after launch (50ms).
        static let windowConfigDelayNanoseconds: UInt64 = 50_000_000
        /// Delay before focusing editor on appear (50ms).
        static let editorFocusDelayNanoseconds: UInt64 = 50_000_000
        /// Delay before prompt recheck after terminal data (100ms).
        static let promptRecheckDelayNanoseconds: UInt64 = 100_000_000
        /// Fraction of context window at which token progress turns red.
        static let tokenProgressCriticalFraction: Double = 0.9
        /// Animation duration for traffic light fade-in after full-screen exit.
        static let trafficLightFadeSeconds: Double = 0.2
        /// Height of the project path bar in points.
        static let projectPathBarHeight: Double = 32
        /// Visor panel height as a fraction of screen height.
        static let visorPanelHeightFraction: Double = 0.55
        /// Indentation per nesting level in the file tree sidebar (points).
        static let fileTreeIndentPerLevel: Double = 16
        /// Chevron indicator width in file tree rows (points).
        static let fileTreeChevronWidth: Double = 12
        /// Content tab bar height (points, excluding title bar inset).
        static let contentTabBarHeight: Double = 44
        /// Debounce delay before persisting file-tree expansion state (nanoseconds, 300ms).
        static let expansionPersistDebounceNanoseconds: UInt64 = 300_000_000
        /// Scale factor for agent icon relative to the size parameter.
        static let agentIconScaleFactor: Double = 0.75
    }

    enum ShellIntegration {
        static let hookSentinelComment = "# termura-shell-integration"
        static let shellScriptFileName = "termura.sh"
        static let shellScriptDirectory = ".termura/shell"
        static let installedDefaultsKey = "shellIntegrationInstalled"
    }

    enum Output {
        static let maxChunksPerSession = 500
        static let maxChunkOutputChars = 200_000
        static let ansiStripBatchSize = 4096
        /// Regex pattern matching shell prompt line endings (zsh/bash/fish/sh).
        /// Matches lines ending with $, %, #, or > optionally followed by whitespace.
        static let fallbackPromptPattern = ".*[$%#>]\\s*$"
        /// AI tool prompt pattern for Claude Code / Aider style prompts.
        /// Matches `>` (U+003E), U+276F, or U+203A as a bare prompt line.
        static let aiToolPromptPattern = "^[>\u{276F}\u{203A}]\\s*$"
        /// Prefix character limit for diff detection heuristic.
        static let diffDetectionPrefixLength = 2000
        /// Prefix character limit for error detection heuristic.
        static let errorDetectionPrefixLength = 3000
        /// Prefix character limit for tool-call detection heuristic.
        static let toolCallDetectionPrefixLength = 500
    }

    enum Search {
        static let maxResults = 50
        static let minQueryLength = 2
        static let previewLength = 64
    }

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
        /// Delay before injecting context after prompt detection (nanoseconds).
        static let injectionDelayNanoseconds: UInt64 = 200_000_000
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
        /// Debounce interval before refreshing git status after terminal output (seconds).
        static let refreshDebounceSeconds: Double = 0.5
        /// Maximum number of file entries to display in the sidebar.
        static let maxDisplayedFiles = 200
        /// Timeout for git CLI commands (nanoseconds). 5 seconds.
        static let commandTimeoutNanoseconds: UInt64 = 5_000_000_000
        /// Debounce interval in nanoseconds (derived from refreshDebounceSeconds).
        static let refreshDebounceNanoseconds: UInt64 = 500_000_000
    }

    enum RecentProjects {
        static let maxCount = 20
        static let fileName = "recent-projects.json"
        /// Global config directory under user home for app-level files.
        static let globalDirectoryName = ".termura"
    }

    enum Health {
        static let probeIntervalSeconds: Double = 30.0  // DB health probe interval
        static let degradedThreshold = 3                 // consecutive failures -> degraded
        static let unhealthyThreshold = 5                // consecutive failures -> unhealthy
    }

    enum CrashDiagnostics {
        static let ringBufferCapacity = 50               // max events in ring buffer
        static let snapshotIntervalSeconds: Double = 60.0
    }

    enum SemanticSearch {
        /// Embedding vector dimension (MiniLM-L6).
        static let embeddingDimension = 384
        static let chunkOverlapTokens = 50
        static let chunkMaxTokens = 256
        static let topK = 20  // top-K results to return
    }
}
