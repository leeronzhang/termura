import Foundation

extension AgentCoordinator {
    // MARK: - Output analysis (background)

    /// Analyze output text for agent status changes, token stats, and risk patterns.
    /// Runs off the actor executor: only accesses nonisolated let dependencies and fires a
    /// fire-and-forget Task { @MainActor } for the risk alert callback — avoids a second
    /// blocking main-actor hop inside the spawnDetachedTracked closure
    /// (CLAUDE.md §6.1 Principle 3: single hop at closure end).
    nonisolated func analyzeOutput(
        _ stripped: String,
        tokenCountingService: any TokenCountingServiceProtocol
    ) async {
        let detector = agentDetector
        let sid = sessionID

        let currentStatus = await detector.analyzeOutput(stripped)
        if let stats = await detector.parseTokenStats(stripped) {
            if let input = stats.inputTokens, let output = stats.outputTokens {
                await tokenCountingService.applyParsedStats(
                    for: sid,
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: stats.cachedTokens ?? 0
                )
            } else if let cached = stats.cachedTokens, cached > 0 {
                await tokenCountingService.accumulateCached(for: sid, count: cached)
            }
            if let cost = stats.totalCost {
                await detector.updateCost(cost)
            }
        }
        if let risk = InterventionService.detectRisk(in: stripped, agentStatus: currentStatus) {
            riskAlertContinuation.yield(risk)
        }
    }

    // MARK: - Agent state update

    /// Compute agent state and context alert off the actor executor.
    /// All async work (token breakdown, actor hops) runs on background executors.
    /// Call `applyAgentStateUpdate(state:alert:)` to commit the result.
    nonisolated func computeAgentStateUpdate(
        tokenCountingService: any TokenCountingServiceProtocol
    ) async -> (state: AgentState, alert: ContextWindowAlert?)? {
        let detector = agentDetector
        let monitor = contextWindowMonitor
        let sid = sessionID
        let breakdown = await tokenCountingService.tokenBreakdown(for: sid)
        let contextTokens = breakdown.inputTokens + breakdown.cachedTokens
        guard var state = await detector.buildState(tokenCount: contextTokens) else { return nil }
        state.inputTokens = breakdown.inputTokens
        state.outputTokens = breakdown.outputTokens
        state.cachedTokens = breakdown.cachedTokens
        let hasParsedData = state.cachedTokens > 0 || state.estimatedCostUSD > 0
        let alert: ContextWindowAlert? = hasParsedData ? await monitor.evaluate(state: state) : nil
        return (state, alert)
    }

    /// Apply a previously computed agent state update.
    /// Hops to @MainActor for store.update (AgentStateStoreProtocol is @MainActor),
    /// then yields any context alert to the contextWindowAlerts stream.
    func applyAgentStateUpdate(state: AgentState, alert: ContextWindowAlert?) async {
        await agentStateStore.update(state: state)
        if let alert {
            contextAlertContinuation.yield(alert)
        }
    }
}
