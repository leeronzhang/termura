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
        /// Maximum export files retained in the system temp directory.
        /// Oldest files are deleted once the count exceeds this limit.
        static let maxRetainedExports = 20
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
        /// Suffix character count scanned by InterventionService.detectRisk.
        /// Risk commands (rm -rf, git push --force, etc.) appear near the end of
        /// the agent's current output burst; scanning only the suffix avoids a full
        /// O(n) lowercased() allocation on every PTY packet.
        static let riskDetectionSuffixLength = 2000
        /// Maximum character length of the command snippet shown in the risk alert banner.
        static let riskSnippetMaxLength = 120
        /// Maximum width of the risk alert banner (pts). Wider screens center the banner.
        static let bannerMaxWidth: CGFloat = 720
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
        /// Maximum number of decision entries to keep (DB/storage limit).
        static let maxDecisionEntries = 50
        /// Maximum decisions extracted into a single handoff document.
        static let maxHandoffDecisions = 10
        /// Maximum errors extracted into a single handoff document.
        static let maxHandoffErrors = 10
        /// Maximum output lines sampled per error chunk.
        static let maxErrorLinesPerChunk = 5
        /// Minimum character length for a line to qualify as a decision entry.
        static let minDecisionLineLength = 10
        /// Maximum character length for a single decision/error entry line.
        static let entryLineMaxLength = 200
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
        /// Files older than this threshold are deleted by the startup janitor.
        /// 1 day is conservative: any drag/paste path has long been consumed before restart.
        static let staleImageAgeSeconds: Double = 86400
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
        /// Subdirectory under .termura/ for file-backed crash diagnostics.
        static let diagnosticsDirectoryName: String = "diagnostics"
        /// Filename for the file-backed crash context snapshot.
        static let crashContextFileName: String = "crash_context.json"
    }

    enum Metrics {
        /// Reservoir sample capacity per histogram metric for percentile computation.
        /// Stores the most recent N samples; percentiles are computed over this window.
        static let reservoirCapacity: Int = 256
        /// Number of persisted session metric records retained in ~/.termura/metrics/.
        static let persistedSessionCount: Int = 30
        /// Subdirectory name under .termura/ for flushed metrics JSON files.
        static let metricsDirectoryName: String = "metrics"
    }

    enum SemanticSearch {
        /// Embedding vector dimension (MiniLM-L6).
        static let embeddingDimension = 384
        static let chunkOverlapTokens = 50
        static let chunkMaxTokens = 256
        static let topK = 20
    }

    enum AgentResume {
        /// UserDefaults key for the auto-fill-on-restore toggle.
        static let autoFillEnabledKey = "agentResume.autoFillEnabled"
        /// Default value when the key has not yet been written.
        static let autoFillDefault = true
    }

    enum Attachments {
        /// Maximum number of attachments allowed per Composer session.
        static let maxCount = 3
        /// Maximum filename character length shown in a pill before truncation.
        static let pillNameMaxLength = 22
    }

    enum Diagnostics {
        /// Maximum DiagnosticItems extracted from a single OutputChunk (per-chunk cap).
        static let maxItemsPerChunk = 100
        /// Maximum total DiagnosticItems retained across all sessions in a project.
        static let maxTotalItems = 500
    }
}
