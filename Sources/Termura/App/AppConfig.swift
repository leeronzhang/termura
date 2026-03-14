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
        static let contextWarningThreshold = 100_000
    }

    // swiftlint:disable:next type_name
    enum UI {
        static let sidebarMinWidth: Double = 180
        static let sidebarMaxWidth: Double = 280
        static let sidebarDefaultWidth: Double = 220
        static let metadataBarHeight: Double = 28
        static let metadataPanelWidth: Double = 160
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
        static let ansiStripBatchSize = 4_096
        /// Regex pattern matching shell prompt line endings (zsh/bash/fish/sh).
        /// Matches lines ending with $, %, #, or > optionally followed by whitespace.
        static let fallbackPromptPattern = ".*[$%#>]\\s*$"
        /// AI tool prompt pattern for Claude Code `> ` style prompts.
        /// Matches only a bare `>` line — does not overlap with OSC 133 shell prompts.
        static let aiToolPromptPattern = "^>\\s*$"
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
}
