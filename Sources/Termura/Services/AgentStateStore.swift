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

    /// The next session to jump to via Cmd+Shift+U.
    var nextAttentionSessionID: SessionID? {
        sessionsNeedingAttention.first
    }

    /// Agents approaching their context window limit.
    var agentsNearingContextLimit: [AgentState] {
        agents.values.filter(\.isContextWarning)
    }

    /// Total estimated tokens across all active agents.
    var totalEstimatedTokens: Int {
        agents.values.reduce(0) { $0 + $1.tokenCount }
    }

    // MARK: - Updates

    func update(state: AgentState) {
        let previous = agents[state.sessionID]
        agents[state.sessionID] = state

        if previous?.status != state.status {
            logger.info(
                "Agent \(state.agentType.rawValue) in \(state.sessionID): \(state.status.rawValue)"
            )
        }
    }

    func remove(sessionID: SessionID) {
        agents.removeValue(forKey: sessionID)
    }

    func clearAll() {
        agents.removeAll()
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
