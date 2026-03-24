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

        guard let appDelegate = NSApp.delegate as? AppDelegate else { return }
        let handoffService = appDelegate.sessionHandoffService

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
        let tokens = await service.estimatedTokens(for: sid)
        guard let state = await agentDet.buildState(tokenCount: tokens) else { return }
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
        let tokens = await service.estimatedTokens(for: sid)
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let cmdCount = outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory
        let agentDet = agentDetector
        let agentState = await agentDet.buildState()

        let ctxLimit = agentState?.contextWindowLimit ?? 0
        let ctxFraction = agentState?.contextUsageFraction ?? 0

        currentMetadata = SessionMetadata(
            sessionID: sessionID,
            estimatedTokenCount: tokens,
            totalCharacterCount: tokens * Int(AppConfig.AI.tokenEstimateDivisor),
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentStateStore?.activeAgentCount ?? 0,
            currentAgentType: agentState?.agentType,
            currentAgentStatus: agentState?.status,
            contextWindowLimit: ctxLimit,
            contextUsageFraction: ctxFraction
        )
    }
}
