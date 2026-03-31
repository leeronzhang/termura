import Foundation

/// Protocol abstracting the agent state aggregation store.
/// @MainActor: state is observed by SwiftUI views.
@MainActor
protocol AgentStateStoreProtocol: AnyObject, Sendable {
    var agents: [SessionID: AgentState] { get }
    var activeAgentCount: Int { get }
    /// Agents sorted by display priority. Cached in the real store; O(n log n) computed in mocks.
    var sortedAgents: [AgentState] { get }
    var sessionsNeedingAttention: [SessionID] { get }
    var nextAttentionSessionID: SessionID? { get }
    var agentsNearingContextLimit: [AgentState] { get }
    var totalEstimatedTokens: Int { get }
    /// Current timestamp, updated at 1-second intervals while agents are active.
    /// Views must use this instead of calling Date() in their render bodies to avoid
    /// per-render Date() + MetadataFormatter calls (O(n) sessions * render frequency).
    var now: Date { get }

    func update(state: AgentState)
    func remove(sessionID: SessionID)
    func clearAll()
}
