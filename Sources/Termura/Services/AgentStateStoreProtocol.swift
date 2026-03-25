import Foundation

/// Protocol abstracting the agent state aggregation store.
/// @MainActor: state is observed by SwiftUI views.
@MainActor
protocol AgentStateStoreProtocol: AnyObject {
    var agents: [SessionID: AgentState] { get }
    var activeAgentCount: Int { get }
    var sessionsNeedingAttention: [SessionID] { get }
    var nextAttentionSessionID: SessionID? { get }
    var agentsNearingContextLimit: [AgentState] { get }
    var totalEstimatedTokens: Int { get }

    func update(state: AgentState)
    func remove(sessionID: SessionID)
    func clearAll()
}
