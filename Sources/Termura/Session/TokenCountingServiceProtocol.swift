import Foundation

/// Protocol abstracting heuristic token counting per session.
protocol TokenCountingServiceProtocol: Actor {
    /// Accumulate characters from user input (commands).
    func accumulateInput(for sessionID: SessionID, text: String)
    /// Accumulate characters from terminal output.
    func accumulateOutput(for sessionID: SessionID, text: String)
    /// Record cached token count parsed from agent output.
    func accumulateCached(for sessionID: SessionID, count: Int)
    /// Total estimated token count for a session.
    func estimatedTokens(for sessionID: SessionID) -> Int
    /// Breakdown of estimated tokens by category.
    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown
    /// Reset accumulated counts for a session.
    func reset(for sessionID: SessionID)
}
