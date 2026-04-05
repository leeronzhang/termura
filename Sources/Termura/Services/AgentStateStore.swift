import Foundation
import Observation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentStateStore")

/// Aggregates agent states across all active sessions.
/// Provides the data layer for the multi-agent dashboard and notification system.
@Observable
@MainActor
final class AgentStateStore: AgentStateStoreProtocol {
    // MARK: - Dependencies

    private let clock: any AppClock

    init(clock: any AppClock = LiveClock()) {
        self.clock = clock
        now = clock.now()
    }

    // MARK: - Observable state

    /// All detected agent states, keyed by session ID.
    private(set) var agents: [SessionID: AgentState] = [:]

    /// Current time, ticked every `AppConfig.Runtime.agentDurationTickSeconds` while agents are
    /// active. Views bind to this instead of calling Date() in their render bodies.
    private(set) var now: Date

    // MARK: - Tick

    /// Lifecycle slot for the duration-display ticker. nonisolated(unsafe): deinit
    @ObservationIgnored private var tickTask: Task<Void, Never>?
    /// Per-session sidebar presentation models. Observation is handled by each row model,
    /// not by the dictionary itself, so sidebar updates stay row-scoped.
    @ObservationIgnored private var sidebarRowStates: [SessionID: AgentSidebarRowState] = [:]

    private func startTickIfNeeded() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled, let store = self {
                do {
                    try await Task.sleep(for: .seconds(AppConfig.Runtime.agentDurationTickSeconds))
                } catch {
                    break
                }
                store.now = store.clock.now()
                store.refreshSidebarRowDurations(now: store.now)
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
        sidebarRowState(for: state.sessionID).apply(state, now: now)
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
        // Row views observe the row-state object directly, not the dictionary entry.
        // Clear the existing object in-place so stale error/waiting badges disappear
        // immediately when an agent exits or a session is ended.
        sidebarRowStates[sessionID]?.clear()
        rebuildDerivedState()
        stopTickIfEmpty()
    }

    func clearAll() {
        agents.removeAll()
        for rowState in sidebarRowStates.values {
            rowState.clear()
        }
        sidebarRowStates.removeAll()
        totalEstimatedTokens = 0
        tickTask?.cancel()
        tickTask = nil
        rebuildDerivedState()
    }

    func sidebarRowState(for sessionID: SessionID) -> AgentSidebarRowState {
        if let existing = sidebarRowStates[sessionID] { return existing }
        let rowState = AgentSidebarRowState(sessionID: sessionID)
        if let state = agents[sessionID] {
            rowState.apply(state, now: now)
        }
        sidebarRowStates[sessionID] = rowState
        return rowState
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

    private func refreshSidebarRowDurations(now: Date) {
        for rowState in sidebarRowStates.values {
            rowState.refreshDuration(now: now)
        }
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
