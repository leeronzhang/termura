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
        /// Backpressure cap for PTY output / shell-event AsyncStreams.
        /// Oldest events are dropped once the buffer is full; prevents unbounded memory growth
        /// during high-throughput commands (e.g. `cat` on a large file).
        static let streamBufferCapacity = 512
    }

    enum Runtime {
        /// Search debounce (Combine scheduler requires Double; keep as seconds)
        static let searchDebounceSeconds: Double = 0.3
        /// Notes auto-save debounce
        static let notesAutoSave: Duration = .seconds(1)
        /// Maximum concurrent background tasks per terminal session.
        /// Bounds CPU/memory usage during high-frequency output (e.g. `cat` large file).
        static let maxConcurrentSessionTasks = 8
        /// Long command notification threshold
        static let longCommandThresholdSeconds: Double = 30.0
        /// Visor animation duration
        static let visorAnimationSeconds: Double = 0.2
        /// Delay before dismissing onboarding sheet after install.
        static let onboardingDismissDelay: Duration = .seconds(1)
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
        /// Maximum IDs per reorder batch.
        /// SQLite SQLITE_LIMIT_VARIABLE_NUMBER defaults to 999.
        /// Each row consumes 3 bindings (2 in CASE WHEN + 1 in IN), so floor(999 / 3) = 333.
        static let reorderBatchSize = 333
        /// Maximum IDs per IN-clause batch (1 binding per ID).
        /// Stays well below SQLite's SQLITE_LIMIT_VARIABLE_NUMBER = 999.
        static let inClauseBatchSize = 500
    }

    // swiftlint:disable:next type_name
    enum AI {
        /// ASCII chars per token (4 ASCII bytes ≈ 1 BPE token for English/code text).
        static let asciiCharsPerToken = 4
        /// Non-CJK, non-ASCII chars per token (Cyrillic, Arabic, Latin-extended, etc.).
        static let otherUnicodeCharsPerToken = 2
        // CJK/Hiragana/Katakana/Hangul: 1 char per token — see estimateTokens(in:).
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
        static let fullScreenExitDelay: Duration = .milliseconds(100)
        /// Delay before window configuration after launch (50ms).
        static let windowConfigDelay: Duration = .milliseconds(50)
        /// Delay before focusing editor on appear (50ms).
        static let editorFocusDelay: Duration = .milliseconds(50)
        /// Delay before prompt recheck after terminal data (100ms).
        static let promptRecheckDelay: Duration = .milliseconds(100)
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
        /// Debounce delay before persisting file-tree expansion state (300ms).
        static let expansionPersistDebounce: Duration = .milliseconds(300)
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

    enum URLs {
        /// Harness product page — shown in the free-build upsell panel.
        static let harnessProduct = "https://termura.app/harness"
    }

}
