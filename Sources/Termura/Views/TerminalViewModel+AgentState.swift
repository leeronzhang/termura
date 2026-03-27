import AppKit
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel+Agent")

/// Extension grouping agent detection, session handoff, agent state updates, and metadata refresh.
extension TerminalViewModel {
    // MARK: - Output-based agent detection

    /// Signature patterns in terminal output that identify a running agent.
    private static var outputSignatures: [(pattern: String, type: AgentType)] {
        [
            ("claude code", .claudeCode),
            ("anthropic", .claudeCode),
            ("openai codex", .codex),
            (">_ openai codex", .codex),
            ("aider v", .aider),
            ("opencode", .openCode),
            ("gemini cli", .gemini),
            ("gemini code", .gemini)
        ]
    }

    /// Strips known agent icon prefixes from OSC terminal titles.
    static func stripAgentPrefixes(_ title: String) -> String {
        var stripped = title.trimmingCharacters(in: .whitespaces)
        let prefixes = ["\u{2733}", ">_", "\u{2726}", "\u{26A1}", "\u{203A}"]
        for prefix in prefixes where stripped.hasPrefix(prefix) {
            stripped = String(stripped.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespaces)
        }
        return stripped.isEmpty ? title : stripped
    }

    /// Scan terminal output for agent signatures and update session when a new agent is detected.
    /// Allows re-detection when a different agent starts in the same session.
    func detectAgentFromOutput(_ text: String) {
        let lower = text.lowercased()
        for (pattern, type) in Self.outputSignatures where lower.contains(pattern) {
            // Skip if already detected the same agent type.
            if hasDetectedAgentFromOutput, lastDetectedAgentType == type { return }
            hasDetectedAgentFromOutput = true
            lastDetectedAgentType = type
            sessionStore.renameSession(id: sessionID, title: type.displayName)
            sessionStore.setAgentType(id: sessionID, type: type)
            let detector = agentDetector
            spawnTracked { await detector.setDetectedType(type) }
            return
        }
    }

    // MARK: - Session Handoff

    func generateHandoffIfNeeded(exitCode: Int32) async {
        let agentDet = agentDetector
        guard let agentState = await agentDet.buildState(),
              agentState.agentType != .unknown else { return }

        guard let session = sessionStore.sessions.first(where: { $0.id == sessionID }),
              !session.workingDirectory.isEmpty else { return }

        let chunks = outputStore.chunks
        guard let handoffService = sessionHandoffService else { return }

        spawnDetachedTracked {
            do {
                try await handoffService.generateHandoff(
                    session: session,
                    chunks: chunks,
                    agentState: agentState
                )
            } catch {
                // Non-critical: handoff is best-effort background persistence;
                // user session data remains in memory and can be re-generated.
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

        // Only trigger context alerts when we have parsed token data, not heuristic.
        let hasParsedData = state.cachedTokens > 0 || state.estimatedCostUSD > 0
        if hasParsedData {
            let monitor = contextWindowMonitor
            if let alert = await monitor.evaluate(state: state) {
                contextWindowAlert = alert
            }
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
