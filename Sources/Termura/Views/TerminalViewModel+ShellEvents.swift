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
