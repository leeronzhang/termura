import Foundation

// MARK: - Shell events handling

extension TerminalViewModel {

    func handleShellEvent(_ event: ShellIntegrationEvent) async {
        switch event {
        case .promptStarted:
            isInteractivePrompt = false
            modeController.switchToEditor()
            triggerAgentResumeIfNeeded()
            await sessionServices.injectContextIfNeeded(
                workingDirectory: currentMetadata.workingDirectory,
                engine: engine,
                clock: clock
            )
        case .executionFinished:
            isInteractivePrompt = false
            modeController.switchToEditor()
            // Reset agent state so badges stop animating after the agent process exits.
            // Without this, repeatForever animations keep running, consuming ~80% CPU when idle.
            await agentCoordinator.resetOnExecutionFinished()
            // Keep local detection cache in sync with coordinator reset so the next agent
            // run re-enters the detection path from the first packet (CLAUDE.md P2-15).
            agentDetectedFromOutput = false
            // Reset token counts so the next agent run (e.g. after /clear) starts from 0
            // rather than accumulating across runs. The context window section is already
            // hidden after resetOnExecutionFinished() clears agentDetector.detectedType.
            await outputProcessor.tokenCountingService.reset(for: sessionID)
        case .executionStarted:
            isInteractivePrompt = false
            modeController.switchToPassthrough()
            detectAgentFromCurrentLine()
        case .commandStarted:
            break
        }

        if await outputProcessor.handleShellEvent(event) != nil {
            await refreshMetadata()
        }
    }

}
