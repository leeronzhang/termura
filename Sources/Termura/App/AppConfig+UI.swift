import Foundation

extension AppConfig {
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
}
