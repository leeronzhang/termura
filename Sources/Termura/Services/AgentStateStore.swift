import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateStore")

/// Aggregates agent states across all active sessions.
/// Provides the data layer for the multi-agent dashboard and notification system.
@Observable
@MainActor
final class AgentStateStore: AgentStateStoreProtocol {
    // MARK: - Observable state

    /// All detected agent states, keyed by session ID.
    private(set) var agents: [SessionID: AgentState] = [:]

    // MARK: - Computed

    /// Number of sessions with an active agent.
    var activeAgentCount: Int {
        agents.values.count(where: { $0.status != .completed })
    }

    /// Sessions that need user attention (waiting input or error).
    var sessionsNeedingAttention: [SessionID] {
        agents.values
            .filter(\.needsAttention)
            .sorted { lhs, rhs in
                Self.attentionPriority(lhs.status) < Self.attentionPriority(rhs.status)
            }
            .map(\.sessionID)
    }

    /// The next session to jump to via Cmd+Shift+U. O(n) — avoids triggering the full sorted chain.
    var nextAttentionSessionID: SessionID? {
        agents.values
            .filter(\.needsAttention)
            .min(by: { Self.attentionPriority($0.status) < Self.attentionPriority($1.status) })?
            .sessionID
    }

    /// Agents approaching their context window limit.
    var agentsNearingContextLimit: [AgentState] {
        agents.values.filter(\.isContextWarning)
    }

    /// Total estimated tokens across all active agents. O(1) — updated incrementally on each mutation.
    private(set) var totalEstimatedTokens: Int = 0

    // MARK: - Updates

    func update(state: AgentState) {
        let previous = agents[state.sessionID]
        totalEstimatedTokens += state.tokenCount - (previous?.tokenCount ?? 0)
        agents[state.sessionID] = state

        if previous?.status != state.status {
            logger.info(
                "Agent \(state.agentType.rawValue) in \(state.sessionID): \(state.status.rawValue)"
            )
        }
    }

    func remove(sessionID: SessionID) {
        totalEstimatedTokens -= agents[sessionID]?.tokenCount ?? 0
        agents.removeValue(forKey: sessionID)
    }

    func clearAll() {
        agents.removeAll()
        totalEstimatedTokens = 0
    }

    // MARK: - Priority

    private static func attentionPriority(_ status: AgentStatus) -> Int {
        switch status {
        case .waitingInput: 0
        case .error: 1
        case .completed: 2
        case .thinking: 3
        case .toolRunning: 4
        case .idle: 5
        }
    }
}
