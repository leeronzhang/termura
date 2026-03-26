import Foundation

/// Background actor that accumulates character counts per session
/// and provides heuristic token estimates (chars / divisor).
actor TokenCountingService: TokenCountingServiceProtocol {
    // MARK: - Internal Breakdown

    private struct CharBreakdown {
        var inputChars: Int = 0
        var outputChars: Int = 0
        var cachedTokens: Int = 0
    }

    // MARK: - State

    private var breakdowns: [SessionID: CharBreakdown] = [:]
    private let divisor: Int

    // MARK: - Init

    init() {
        let rawDivisor = Int(AppConfig.AI.tokenEstimateDivisor)
        divisor = max(1, rawDivisor)
    }

    // MARK: - Public API

    /// Accumulate character count from terminal output (backward-compatible alias).
    func accumulate(for sessionID: SessionID, text: String) {
        accumulateOutput(for: sessionID, text: text)
    }

    /// Accumulate characters from user input (commands).
    func accumulateInput(for sessionID: SessionID, text: String) {
        breakdowns[sessionID, default: CharBreakdown()].inputChars += text.count
    }

    /// Accumulate characters from terminal output.
    func accumulateOutput(for sessionID: SessionID, text: String) {
        breakdowns[sessionID, default: CharBreakdown()].outputChars += text.count
    }

    /// Record cached token count parsed from agent output.
    func accumulateCached(for sessionID: SessionID, count: Int) {
        breakdowns[sessionID, default: CharBreakdown()].cachedTokens += count
    }

    /// Estimated total token count for a session (charCount / divisor).
    func estimatedTokens(for sessionID: SessionID) -> Int {
        let bd = breakdowns[sessionID] ?? CharBreakdown()
        return (bd.inputChars + bd.outputChars) / divisor + bd.cachedTokens
    }

    /// Breakdown of estimated tokens by category.
    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown {
        let bd = breakdowns[sessionID] ?? CharBreakdown()
        return TokenEstimateBreakdown(
            inputTokens: bd.inputChars / divisor,
            outputTokens: bd.outputChars / divisor,
            cachedTokens: bd.cachedTokens
        )
    }

    /// Reset accumulated count for a session (e.g., on session close).
    func reset(for sessionID: SessionID) {
        breakdowns.removeValue(forKey: sessionID)
    }
}
