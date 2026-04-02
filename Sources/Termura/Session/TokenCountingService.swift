import Foundation

// MARK: - Unicode-aware token estimation

/// Script-aware heuristic token estimate for `text`.
///
/// Divisors per script:
/// - ASCII (U+0000-U+007F):                `AppConfig.AI.asciiCharsPerToken` chars per token
/// - CJK / Hiragana / Katakana / Hangul:   1 char per token
/// - Other Unicode (Cyrillic, Arabic, etc): `AppConfig.AI.otherUnicodeCharsPerToken` chars per token
///
/// Accuracy vs. `chars / 4`:
/// - Pure ASCII text:  same result
/// - Chinese / Japanese / Korean: ~4-6x more accurate (1 char ≈ 1 token, not 0.25)
/// - Mixed content: proportional improvement based on CJK fraction
func estimateTokens(in text: String) -> Int {
    var ascii = 0
    var cjk = 0
    var other = 0
    for scalar in text.unicodeScalars {
        let cp = scalar.value
        if cp < 128 {
            ascii += 1
        } else if isCJKScalar(cp) {
            cjk += 1
        } else {
            other += 1
        }
    }
    return ascii / AppConfig.AI.asciiCharsPerToken
        + cjk
        + other / AppConfig.AI.otherUnicodeCharsPerToken
}

/// Returns true for CJK unified ideographs and CJK-adjacent scripts
/// (Hiragana, Katakana, Hangul) whose token density is ~1 char/token.
private func isCJKScalar(_ codepoint: UInt32) -> Bool {
    (0x4E00 ... 0x9FFF).contains(codepoint) // CJK Unified Ideographs
        || (0x3400 ... 0x4DBF).contains(codepoint) // CJK Extension A
        || (0xF900 ... 0xFAFF).contains(codepoint) // CJK Compatibility Ideographs
        || (0x3040 ... 0x309F).contains(codepoint) // Hiragana
        || (0x30A0 ... 0x30FF).contains(codepoint) // Katakana
        || (0xAC00 ... 0xD7AF).contains(codepoint) // Hangul Syllables
        || (0x20000 ... 0x2A6DF).contains(codepoint) // CJK Extension B (Supplementary)
}

// MARK: - TokenCountingService

/// Background actor that accumulates per-session token estimates.
/// Token estimates are computed at accumulation time using `estimateTokens(in:)`,
/// so reads are O(1) with no per-query division.
actor TokenCountingService: TokenCountingServiceProtocol {
    // MARK: - Internal Breakdown

    private struct TokenBreakdown {
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cachedTokens: Int = 0
    }

    // MARK: - State

    private var breakdowns: [SessionID: TokenBreakdown] = [:]

    // MARK: - Public API

    /// Accumulate token estimate from user input (commands).
    func accumulateInput(for sessionID: SessionID, text: String) {
        breakdowns[sessionID, default: TokenBreakdown()].inputTokens += estimateTokens(in: text)
    }

    /// Accumulate token estimate from terminal output.
    func accumulateOutput(for sessionID: SessionID, text: String) {
        breakdowns[sessionID, default: TokenBreakdown()].outputTokens += estimateTokens(in: text)
    }

    /// Record cached token count parsed from agent output.
    func accumulateCached(for sessionID: SessionID, count: Int) {
        breakdowns[sessionID, default: TokenBreakdown()].cachedTokens += count
    }

    /// Estimated total token count for a session.
    func estimatedTokens(for sessionID: SessionID) -> Int {
        let bd = breakdowns[sessionID] ?? TokenBreakdown()
        return bd.inputTokens + bd.outputTokens + bd.cachedTokens
    }

    /// Breakdown of estimated tokens by category.
    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown {
        let bd = breakdowns[sessionID] ?? TokenBreakdown()
        return TokenEstimateBreakdown(
            inputTokens: bd.inputTokens,
            outputTokens: bd.outputTokens,
            cachedTokens: bd.cachedTokens
        )
    }

    /// Override heuristic accumulation with authoritative parsed token stats.
    /// Called when accurate input/output/cache counts are extracted from agent output
    /// (e.g. "Input: 45.2k Output: 8.1k Cache read: 102.3k" in Claude Code summaries).
    func applyParsedStats(for sessionID: SessionID, inputTokens: Int, outputTokens: Int, cachedTokens: Int) {
        breakdowns[sessionID] = TokenBreakdown(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cachedTokens: cachedTokens
        )
    }

    /// Reset accumulated counts for a session (e.g., on session close).
    func reset(for sessionID: SessionID) {
        breakdowns.removeValue(forKey: sessionID)
    }
}
