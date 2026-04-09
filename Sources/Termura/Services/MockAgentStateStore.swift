import Foundation

#if DEBUG

/// Debug preview store for `AgentStateStoreProtocol`.
/// Set `shouldRejectUpdates` to simulate state update failures (e.g., store full).
@MainActor
final class DebugAgentStateStore: AgentStateStoreProtocol {
    private(set) var agents: [SessionID: AgentState] = [:]
    var updateCallCount = 0
    var removeCallCount = 0
    var clearCallCount = 0
    /// When true, `update(state:)` records the call but does NOT store the state.
    var shouldRejectUpdates = false

    var activeAgentCount: Int {
        agents.values.count(where: { $0.status == .thinking || $0.status == .toolRunning })
    }

    var sortedAgents: [AgentState] {
        agents.values.sorted { $0.startedAt < $1.startedAt }
    }

    var sessionsNeedingAttention: [SessionID] {
        agents.values
            .filter { $0.status == .waitingInput || $0.status == .error }
            .map(\.sessionID)
    }

    var nextAttentionSessionID: SessionID? {
        sessionsNeedingAttention.first
    }

    var agentsNearingContextLimit: [AgentState] {
        agents.values.filter {
            guard $0.contextWindowLimit > 0 else { return false }
            let ratio = Double($0.tokenCount) / Double($0.contextWindowLimit)
            return ratio >= 0.8
        }
    }

    private(set) var totalEstimatedTokens: Int = 0
    var now: Date = .init()

    func update(state: AgentState) {
        updateCallCount += 1
        guard !shouldRejectUpdates else { return }
        let previous = agents[state.sessionID]
        totalEstimatedTokens += state.tokenCount - (previous?.tokenCount ?? 0)
        agents[state.sessionID] = state
    }

    func remove(sessionID: SessionID) {
        removeCallCount += 1
        totalEstimatedTokens -= agents[sessionID]?.tokenCount ?? 0
        agents.removeValue(forKey: sessionID)
    }

    func clearAll() {
        clearCallCount += 1
        agents.removeAll()
        totalEstimatedTokens = 0
    }
}

#endif
