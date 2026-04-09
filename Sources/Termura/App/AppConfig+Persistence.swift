import Foundation

extension AppConfig {
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
    /// Prices are approximate as of early 2026; update when models change.
    /// Note: Aider derives cost directly from its output — these are fallbacks only.
    enum CostEstimation {
        // Anthropic Claude (claude-sonnet-4 / claude-haiku-4)
        static let claudeInputPerMillion: Double = 3.0
        static let claudeOutputPerMillion: Double = 15.0
        static let claudeCacheReadPerMillion: Double = 0.30

        // OpenAI Codex / GPT-4o
        static let codexInputPerMillion: Double = 2.50
        static let codexOutputPerMillion: Double = 10.0

        // Google Gemini 2.0 Flash (most common Gemini CLI model, paid tier)
        static let geminiInputPerMillion: Double = 0.075
        static let geminiOutputPerMillion: Double = 0.30

        // Aider uses the underlying model — default to GPT-4o rates as a heuristic
        static let aiderDefaultInputPerMillion: Double = 2.50
        static let aiderDefaultOutputPerMillion: Double = 10.0

        // Generic fallback
        static let defaultInputPerMillion: Double = 3.0
        static let defaultOutputPerMillion: Double = 15.0

        /// UserDefaults key: when true, cost row is hidden in Inspector (subscription billing).
        static let subscriptionModeKey = "costDisplay.subscriptionMode"
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
}
