import Foundation

/// Test double for `AgentStateStoreProtocol`.
/// Set `shouldRejectUpdates` to simulate state update failures (e.g., store full).
@MainActor
final class MockAgentStateStore: AgentStateStoreProtocol {
    private(set) var agents: [SessionID: AgentState] = [:]
    var updateCallCount = 0
    var removeCallCount = 0
    var clearCallCount = 0
    /// When true, `update(state:)` records the call but does NOT store the state.
    var shouldRejectUpdates = false

    var activeAgentCount: Int {
        agents.values.count(where: { $0.status == .thinking || $0.status == .toolRunning })
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

    var totalEstimatedTokens: Int {
        agents.values.reduce(0) { $0 + $1.tokenCount }
    }

    func update(state: AgentState) {
        updateCallCount += 1
        guard !shouldRejectUpdates else { return }
        agents[state.sessionID] = state
    }

    func remove(sessionID: SessionID) {
        removeCallCount += 1
        agents.removeValue(forKey: sessionID)
    }

    func clearAll() {
        clearCallCount += 1
        agents.removeAll()
    }
}
