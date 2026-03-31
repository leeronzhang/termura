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
        /// Debounce window before sending SIGWINCH after a layout change.
        /// Prevents spurious double-resize when SwiftUI rebuilds the terminal view tree
        /// during a session switch (first layout pass fires with a transient wrong size,
        /// second pass fires with the correct size; only the second should send SIGWINCH).
        static let resizeDebounce: Duration = .milliseconds(16)
    }

    enum Runtime {
        /// Search debounce (Combine scheduler requires Double; keep as seconds)
        static let searchDebounceSeconds: Double = 0.3
        /// Notes auto-save debounce
        static let notesAutoSave: Duration = .seconds(1)
        /// Debounce before persisting session metadata changes (rename, working directory).
        /// Intentionally separate from notesAutoSave so each can be tuned independently.
        static let sessionMetadataDebounce: Duration = .seconds(1)
        /// Maximum concurrent background tasks per terminal session.
        /// Bounds CPU/memory usage during high-frequency output (e.g. `cat` large file).
        static let maxConcurrentSessionTasks = 8
        /// Queue depth multiplier for BoundedTaskExecutor.isAtCapacity.
        /// When tracked.count >= maxConcurrent * this value, non-critical output analysis
        /// is dropped to prevent unbounded task accumulation during PTY floods.
        static let taskQueueDepthMultiplier = 4
        /// Long command notification threshold
        static let longCommandThresholdSeconds: Double = 30.0
        /// Maximum time (seconds) to wait for DB flush + handoff during app termination.
        /// If the deadline is exceeded the app still calls reply(toApplicationShouldTerminate:)
        /// rather than hanging until the OS force-kills the process.
        static let terminationFlushTimeoutSeconds: Double = 2.0
        /// Visor animation duration
        static let visorAnimationSeconds: Double = 0.2
        /// Delay before dismissing onboarding sheet after install.
        static let onboardingDismissDelay: Duration = .seconds(1)
        /// Auto-dismiss duration for transient toast banners (e.g. "Saved to Notes").
        static let toastAutoDismiss: Duration = .seconds(2)
        /// Minimum interval between SessionMetadata UI refreshes during streaming output.
        /// Prevents per-packet SwiftUI redraws during high-throughput terminal output.
        static let metadataRefreshThrottleSeconds: Double = 0.5
        /// Debounce before forking a PTY when activating a session without an existing engine.
        /// Prevents a PTY fork storm when the user rapidly clicks through the session list:
        /// only the session the user actually settles on creates a shell process.
        static let engineCreationDebounce: Duration = .milliseconds(120)
        /// Tick interval for AgentStateStore.now, which drives elapsed-duration display in sidebar
        /// and agent dashboard. 1s granularity matches the coarsest unit MetadataFormatter emits.
        static let agentDurationTickSeconds: Double = 1.0
    }

    enum SLO {
        /// Launch time P95 target: < 2s
        static let launchSeconds: Double = 2.0
        /// Session switch target: < 100ms
        static let sessionSwitchSeconds: Double = 0.1
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

    enum UI {
        static let sidebarMinWidth: Double = 220
        static let sidebarMaxWidth: Double = 480
        static let sidebarDefaultWidth: Double = 360
        /// Width below which dragging the divider collapses the sidebar (same effect as Cmd+B).
        static let sidebarCollapseThreshold: Double = 220
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
        /// Delay before toggling fullscreen when restoring window state on launch (200ms).
        /// Gives the window time to become key before the fullscreen animation starts.
        static let fullScreenRestoreDelay: Duration = .milliseconds(200)
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
        static let classifyPrefixLength = max(diffDetectionPrefixLength, errorDetectionPrefixLength, toolCallDetectionPrefixLength)
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
