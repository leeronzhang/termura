import Foundation

/// Value type snapshot of live session metrics for display in the metadata bar.
struct SessionMetadata: Sendable {
    let sessionID: SessionID
    /// Heuristic token estimate (chars / 4).
    var estimatedTokenCount: Int
    /// Total characters accumulated this session.
    var totalCharacterCount: Int
    /// Token breakdown by category.
    var inputTokenCount: Int
    var outputTokenCount: Int
    var cachedTokenCount: Int
    /// Estimated cost in USD (parsed from agent output or heuristic).
    var estimatedCostUSD: Double
    /// Elapsed time since session start.
    var sessionDuration: TimeInterval
    /// Number of commands executed.
    var commandCount: Int
    /// Current working directory.
    var workingDirectory: String
    /// Number of active agents across all sessions.
    var activeAgentCount: Int
    /// Detected agent type for this session, if any.
    var currentAgentType: AgentType?
    /// Current agent status for this session, if any.
    var currentAgentStatus: AgentStatus?
    /// Brief description of what the agent is currently doing.
    var currentAgentTask: String?
    /// How long the current agent has been running.
    var agentElapsedTime: TimeInterval
    /// Agent-specific context window limit (0 if no agent detected).
    var contextWindowLimit: Int
    /// Context usage as a fraction of the context window (0.0-1.0).
    var contextUsageFraction: Double

    /// True when the token breakdown has any non-zero category.
    var hasTokenBreakdown: Bool {
        inputTokenCount > 0 || outputTokenCount > 0 || cachedTokenCount > 0
    }

    /// True when real token data was parsed from agent output (not just heuristic).
    var hasParsedTokenData: Bool {
        estimatedCostUSD > 0 || cachedTokenCount > 0
    }

    // MARK: - Factory

    static func empty(sessionID: SessionID, workingDirectory: String) -> SessionMetadata {
        SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: 0,
            totalCharacterCount: 0,
            inputTokenCount: 0,
            outputTokenCount: 0,
            cachedTokenCount: 0,
            estimatedCostUSD: 0,
            sessionDuration: 0,
            commandCount: 0,
            workingDirectory: workingDirectory,
            activeAgentCount: 0,
            currentAgentType: nil,
            currentAgentStatus: nil,
            currentAgentTask: nil,
            agentElapsedTime: 0,
            contextWindowLimit: 0,
            contextUsageFraction: 0
        )
    }
}
