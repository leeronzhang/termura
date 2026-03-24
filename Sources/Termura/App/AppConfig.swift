import Foundation

/// Central configuration for all app-wide constants.
/// All magic numbers must live here — never inline in logic layer.
enum AppConfig {
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
        /// Long command notification threshold
        static let longCommandThresholdSeconds: Double = 30.0
        /// Visor animation duration
        static let visorAnimationSeconds: Double = 0.2
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

    enum ContextWindow {
        static let claudeCodeLimit = 200_000
        static let codexLimit = 128_000
        static let aiderLimit = 128_000
        static let openCodeLimit = 128_000
        static let piLimit = 128_000
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
        static let sidebarMinWidth: Double = 180
        static let sidebarMaxWidth: Double = 480
        static let sidebarDefaultWidth: Double = 280
        static let metadataBarHeight: Double = 28
        static let metadataPanelWidth: Double = 280
        static let metadataPanelMinWidth: Double = 120
        static let metadataPanelMaxWidth: Double = 300
        static let tokenProgressWarningFraction: Double = 0.8
        static let editorMinHeightPoints: Double = 72
        static let editorMaxHeightPoints: Double = 300
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
        /// Matches `>` (U+003E), `❯` (U+276F), or `›` (U+203A) as a bare prompt line.
        static let aiToolPromptPattern = "^[>❯›]\\s*$"
    }

    enum Search {
        static let maxResults = 50
        static let minQueryLength = 2
        static let snippetLength = 64
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

    enum TerminalBackend: String, Sendable {
        case swiftTerm
        case libghostty
    }

    enum Backend {
        static let activeBackend: TerminalBackend = .swiftTerm
    }

    enum SemanticSearch {
        /// Embedding vector dimension (MiniLM-L6).
        static let embeddingDimension = 384
        /// Token overlap between chunks.
        static let chunkOverlapTokens = 50
        /// Maximum tokens per search chunk.
        static let chunkMaxTokens = 256
        /// Top-K results to return.
        static let topK = 20
    }
}
