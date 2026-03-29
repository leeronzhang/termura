import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalViewModel")

// MARK: - Metadata refresh

extension TerminalViewModel {
    /// Throttled wrapper for `refreshMetadata()`. Fires immediately if the throttle
    /// interval has elapsed; otherwise schedules one deferred refresh to cover the
    /// window. Additional calls while a deferred refresh is pending are no-ops —
    /// the pending task will fire and cover them all.
    ///
    /// Shell events and working-directory changes call `refreshMetadata()` directly
    /// because they are infrequent and need immediate UI accuracy.
    func scheduleMetadataRefresh(workingDirectory: String? = nil) {
        guard pendingMetadataRefreshTask == nil else { return }
        let elapsed = Date().timeIntervalSince(lastMetadataRefreshDate)
        let throttle = AppConfig.Runtime.metadataRefreshThrottleSeconds
        let delay = max(0.0, throttle - elapsed)
        let dir = workingDirectory
        pendingMetadataRefreshTask = Task { @MainActor [weak self] in
            defer { self?.pendingMetadataRefreshTask = nil }
            if delay > 0 {
                do {
                    try await Task.sleep(for: .seconds(delay))
                } catch is CancellationError {
                    // CancellationError is expected — session was closed before the throttle fired.
                    return
                } catch {
                    logger.warning("Metadata refresh throttle interrupted: \(error.localizedDescription)")
                    return
                }
                guard !Task.isCancelled else { return }
            }
            self?.lastMetadataRefreshDate = Date()
            await self?.refreshMetadata(workingDirectory: dir)
        }
    }

    func refreshMetadata(workingDirectory: String? = nil) async {
        let service = outputProcessor.tokenCountingService
        let sid = sessionID
        let breakdown = await service.tokenBreakdown(for: sid)
        let tokens = breakdown.totalTokens
        let elapsed = Date().timeIntervalSince(sessionStartTime)
        let cmdCount = outputProcessor.outputStore.chunks.count
        let dir = workingDirectory ?? currentMetadata.workingDirectory
        let agentDet = agentCoordinator.agentDetector
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
            totalCharacterCount: tokens * AppConfig.AI.asciiCharsPerToken,
            inputTokenCount: breakdown.inputTokens,
            outputTokenCount: breakdown.outputTokens,
            cachedTokenCount: breakdown.cachedTokens,
            estimatedCostUSD: cost,
            sessionDuration: elapsed,
            commandCount: cmdCount,
            workingDirectory: dir,
            activeAgentCount: agentCoordinator.agentStateStore?.activeAgentCount ?? 0,
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
