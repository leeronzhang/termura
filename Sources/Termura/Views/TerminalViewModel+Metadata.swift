import Foundation

// MARK: - Metadata refresh

extension TerminalViewModel {
    func refreshMetadata(workingDirectory: String? = nil) async {
        let service = outputProcessor.tokenCountingService
        let sid = sessionID
        let breakdown = await service.tokenBreakdown(for: sid)
        // Context window usage = input + cache_read; output tokens are not in the context window.
        let tokens = breakdown.inputTokens + breakdown.cachedTokens
        let elapsed = clock.now().timeIntervalSince(sessionStartTime)
        let cmdCount = outputProcessor.outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory
        let agentDet = agentCoordinator.agentDetector
        let agentState = await agentDet.buildState(tokenCount: tokens)

        let ctxLimit = agentState?.contextWindowLimit ?? 0
        let ctxFraction = agentState?.contextUsageFraction ?? 0
        let agentElapsed = agentState.map { clock.now().timeIntervalSince($0.startedAt) } ?? 0
        let cost = agentState?.estimatedCostUSD ?? 0

        currentMetadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * AppConfig.AI.asciiCharsPerToken,
            inputTokenCount: breakdown.inputTokens,
            outputTokenCount: breakdown.outputTokens,
            cachedTokenCount: breakdown.cachedTokens,
            estimatedCostUSD: cost,
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentCoordinator.agentStateStore.activeAgentCount,
            currentAgentType: agentState?.agentType,
            currentAgentStatus: agentState?.status,
            currentAgentTask: agentState?.currentTask,
            agentElapsedTime: agentElapsed,
            contextWindowLimit: ctxLimit,
            contextUsageFraction: ctxFraction,
            agentActiveFilePath: agentState?.activeFilePath
        )
    }
}
