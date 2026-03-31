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

    /// Current time, ticked every `AppConfig.Runtime.agentDurationTickSeconds` while agents are
    /// active. Views bind to this instead of calling Date() in their render bodies.
    private(set) var now: Date = Date()

    // MARK: - Tick

    /// Lifecycle slot for the duration-display ticker. nonisolated(unsafe): deinit
    @ObservationIgnored private var tickTask: Task<Void, Never>?

    private func startTickIfNeeded() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled, let store = self {
                do {
                    try await Task.sleep(for: .seconds(AppConfig.Runtime.agentDurationTickSeconds))
                } catch {
                    break
                }
                store.now = Date()
            }
        }
    }

    private func stopTickIfEmpty() {
        guard agents.isEmpty else { return }
        tickTask?.cancel()
        tickTask = nil
    }

    // MARK: - Derived state (cached)
    // All properties below are rebuilt via rebuildDerivedState() on each mutation.
    // This keeps per-render access O(1) instead of O(n) or O(n log n).

    /// Number of sessions with an active agent.
    private(set) var activeAgentCount: Int = 0

    /// Agents sorted by display priority (waitingInput > error > thinking > toolRunning > idle > completed).
    private(set) var sortedAgents: [AgentState] = []

    /// Sessions that need user attention (waiting input or error), sorted by attention priority.
    private(set) var sessionsNeedingAttention: [SessionID] = []

    /// The next session to jump to via Cmd+Shift+U.
    private(set) var nextAttentionSessionID: SessionID?

    /// Agents approaching their context window limit.
    private(set) var agentsNearingContextLimit: [AgentState] = []

    /// Total estimated tokens across all active agents. O(1) — updated incrementally on each mutation.
    private(set) var totalEstimatedTokens: Int = 0

    // MARK: - Updates

    func update(state: AgentState) {
        let previous = agents[state.sessionID]
        totalEstimatedTokens += state.tokenCount - (previous?.tokenCount ?? 0)
        agents[state.sessionID] = state
        rebuildDerivedState()
        startTickIfNeeded()

        if previous?.status != state.status {
            logger.info(
                "Agent \(state.agentType.rawValue) in \(state.sessionID): \(state.status.rawValue)"
            )
        }
    }

    func remove(sessionID: SessionID) {
        totalEstimatedTokens -= agents[sessionID]?.tokenCount ?? 0
        agents.removeValue(forKey: sessionID)
        rebuildDerivedState()
        stopTickIfEmpty()
    }

    func clearAll() {
        agents.removeAll()
        totalEstimatedTokens = 0
        tickTask?.cancel()
        tickTask = nil
        rebuildDerivedState()
    }

    // MARK: - Derived state rebuild

    /// Single O(n) pass through agents that updates all cached derived properties.
    /// Called once per mutation (update/remove/clearAll) so render-time access is O(1).
    private func rebuildDerivedState() {
        var activeCount = 0
        var attentionAgents: [AgentState] = []
        var nearingLimit: [AgentState] = []

        for state in agents.values {
            if state.status != .completed { activeCount += 1 }
            if state.needsAttention { attentionAgents.append(state) }
            if state.isContextWarning { nearingLimit.append(state) }
        }

        attentionAgents.sort { Self.attentionPriority($0.status) < Self.attentionPriority($1.status) }

        activeAgentCount = activeCount
        sortedAgents = agents.values.sorted { lhs, rhs in
            let lp = Self.sortPriority(lhs), rp = Self.sortPriority(rhs)
            return lp != rp ? lp < rp : lhs.startedAt > rhs.startedAt
        }
        sessionsNeedingAttention = attentionAgents.map(\.sessionID)
        nextAttentionSessionID = attentionAgents.first?.sessionID
        agentsNearingContextLimit = nearingLimit
    }

    // MARK: - Priority

    private static func sortPriority(_ agent: AgentState) -> Int {
        switch agent.status {
        case .waitingInput: 0
        case .error: 1
        case .thinking: 2
        case .toolRunning: 3
        case .idle: 4
        case .completed: 5
        }
    }

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
