import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel+Agent")

/// Extension grouping session handoff, agent state updates, and metadata refresh.
extension TerminalViewModel {
    // MARK: - Session Handoff

    func generateHandoffIfNeeded(exitCode: Int32) async {
        let agentDet = agentDetector
        guard let agentState = await agentDet.buildState(),
              agentState.agentType != .unknown else { return }

        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }),
              !session.workingDirectory.isEmpty else { return }

        let chunks = outputStore.chunks
        guard let handoffService = sessionHandoffService else { return }

        Task.detached {
            do {
                try await handoffService.generateHandoff(
                    session: session,
                    chunks: chunks,
                    agentState: agentState
                )
            } catch {
                logger.error("Session handoff failed: \(error)")
            }
        }
    }

    // MARK: - Agent State

    func updateAgentState() async {
        let agentDet = agentDetector
        let service = tokenCountingService
        let sid = sessionID
        let breakdown = await service.tokenBreakdown(for: sid)
        guard var state = await agentDet.buildState(tokenCount: breakdown.totalTokens) else { return }
        state.inputTokens = breakdown.inputTokens
        state.outputTokens = breakdown.outputTokens
        state.cachedTokens = breakdown.cachedTokens
        agentStateStore?.update(state: state)

        let monitor = contextWindowMonitor
        if let alert = await monitor.evaluate(state: state) {
            contextWindowAlert = alert
        }
    }

    // MARK: - Metadata

    func refreshMetadata(workingDirectory: String? = nil) async {
        let service = tokenCountingService
        let sid = sessionID
        let breakdown = await service.tokenBreakdown(for: sid)
        let tokens = breakdown.totalTokens
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let cmdCount = outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory
        let agentDet = agentDetector
        let agentState = await agentDet.buildState()

        let ctxLimit = agentState?.contextWindowLimit ?? 0
        let ctxFraction = agentState?.contextUsageFraction ?? 0
        let agentElapsed = agentState.map {
            Date().timeIntervalSince($0.startedAt)
        } ?? 0
        let cost = agentState?.estimatedCostUSD ?? 0

        currentMetadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * Int(AppConfig.AI.tokenEstimateDivisor),
            inputTokenCount: breakdown.inputTokens,
            outputTokenCount: breakdown.outputTokens,
            cachedTokenCount: breakdown.cachedTokens,
            estimatedCostUSD: cost,
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentStateStore?.activeAgentCount ?? 0,
            currentAgentType: agentState?.agentType,
            currentAgentStatus: agentState?.status,
            currentAgentTask: agentState?.currentTask,
            agentElapsedTime: agentElapsed,
            contextWindowLimit: ctxLimit,
            contextUsageFraction: ctxFraction
        )
    }
}
