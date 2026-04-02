import Foundation

// MARK: - Lifecycle helpers

extension TerminalViewModel {
    func isShellPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let shellSuffixes = ["$ ", "% ", "# ", "$", "%", "#"]
        return shellSuffixes.contains { trimmed.hasSuffix($0) }
    }

    func isAIPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let aiPrompts = [">", "❯", "›"]
        return aiPrompts.contains(trimmed)
    }

    func detectPromptFromScreenBuffer() async {
        let screen = engine.linesNearCursor(above: 20)
        let lastLine = screen.last ?? ""
        if isAIPromptLine(lastLine) {
            isInteractivePrompt = true
            return
        }
        if isShellPromptLine(lastLine) {
            isInteractivePrompt = false
        }
    }

    func refreshMetadata(workingDirectory: String? = nil) async {
        await controller.metadataObserver.refreshMetadata(workingDirectory: workingDirectory)
    }

    func scheduleMetadataRefresh(workingDirectory: String? = nil) {
        controller.metadataObserver.scheduleMetadataRefresh(workingDirectory: workingDirectory)
    }

    func spawnTracked(_ operation: @escaping @MainActor () async -> Void) {
        controller.taskExecutor.spawn(operation)
    }

    func spawnDetachedTracked(_ operation: @Sendable @escaping () async -> Void) {
        controller.taskExecutor.spawnDetached(operation)
    }

    /// Wait until tracked background work and auxiliary session tasks settle for tests.
    func waitForIdle() async {
        await controller.taskExecutor.waitForIdle()
        if let task = controller.metadataObserver.pendingMetadataRefreshTask {
            await task.value
        }
        if let task = controller.promptObserver.promptRecheckTask {
            await task.value
        }
        if let task = controller.processExitTask {
            await task.value
        }
        await sessionServices.flushPendingInjection()
        await sessionServices.flushPendingHandoff()
    }

    /// Waits until queued output-analysis work has drained for this session.
    /// Used on process exit so final snapshots are taken from settled state.
    func waitForOutputProcessingIdle() async {
        await controller.waitForOutputProcessingIdle()
    }
}
