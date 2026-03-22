import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateStore")

/// Aggregates agent states across all active sessions.
/// Provides the data layer for the multi-agent dashboard and notification system.
@MainActor
final class AgentStateStore: ObservableObject {

    // MARK: - Published state

    /// All detected agent states, keyed by session ID.
    @Published private(set) var agents: [SessionID: AgentState] = [:]

    // MARK: - Computed

    /// Number of sessions with an active agent.
    var activeAgentCount: Int {
        agents.values.filter { $0.status != .completed }.count
    }

    /// Sessions that need user attention (waiting input or error).
    var sessionsNeedingAttention: [SessionID] {
        agents.values
            .filter { $0.needsAttention }
            .sorted { lhs, rhs in
                Self.attentionPriority(lhs.status) < Self.attentionPriority(rhs.status)
            }
            .map(\.sessionID)
    }

    /// The next session to jump to via Cmd+Shift+U.
    var nextAttentionSessionID: SessionID? {
        sessionsNeedingAttention.first
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
        case .waitingInput: return 0
        case .error: return 1
        case .completed: return 2
        case .thinking: return 3
        case .toolRunning: return 4
        case .idle: return 5
        }
    }
}
