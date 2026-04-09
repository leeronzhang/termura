import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "TerminalSessionController")

// MARK: - PTY output processing & coalescing backpressure

extension TerminalSessionController {
    /// Processes a single PTY data batch: runs agent detection, then either spawns a
    /// background analysis task or coalesces into `pendingOutputBuffer` when the
    /// executor is at capacity.
    ///
    /// Coalescing guarantee: PTY output is primary business data. Silent drops (the
    /// previous `guard return`) cause state drift, incomplete handoffs, and random
    /// UI desync. When at capacity, text is accumulated in `pendingOutputBuffer`;
    /// the next task that completes calls `drainPendingBufferIfNeeded()` to flush it.
    func handlePreprocessedData(text: String, stripped: String) async {
        let sid = sessionID
        let processor = outputProcessor
        let coordinator = agentCoordinator
        let tokenService = outputProcessor.tokenCountingService

        promptObserver.schedulePromptRecheck()

        if !agentDetectedFromOutput {
            agentDetectedFromOutput = await coordinator.detectAgentFromOutputIfNeeded(stripped)
        }

        // Backpressure: coalesce into pending buffer instead of dropping.
        // All PTY output is primary business data — silent drops cause state drift,
        // incomplete handoffs, and random UI desync. When the executor is at
        // capacity, we accumulate text here; the next spawned task drains it.
        if taskExecutor.isAtCapacity {
            if var pending = pendingOutputBuffer {
                pending.text += text
                pending.stripped += stripped
                pendingOutputBuffer = pending
            } else {
                pendingOutputBuffer = (text: text, stripped: stripped)
            }
            armPendingOutputDrainIfNeeded()
            let activeCount = taskExecutor.activeCount
            logger.debug("output batch coalesced (capacity=\(activeCount))")
            return
        }

        // Drain any coalesced buffer accumulated while at capacity.
        let drainText: String
        let drainStripped: String
        if let pending = pendingOutputBuffer {
            pendingOutputBuffer = nil
            drainText = pending.text + text
            drainStripped = pending.stripped + stripped
        } else {
            drainText = text
            drainStripped = stripped
        }

        taskExecutor.spawnDetached {
            await processor.processDataOutput(drainText, stripped: drainStripped, sessionID: sid)
            await coordinator.analyzeOutput(drainStripped, tokenCountingService: tokenService)
            let update = await coordinator.computeAgentStateUpdate(
                tokenCountingService: processor.tokenCountingService
            )
            if let (state, alert) = update {
                await coordinator.applyAgentStateUpdate(state: state, alert: alert)
            }
            // After this task completes a slot is free. Drain any buffer that
            // accumulated while at capacity, so data is not stranded if no
            // further PTY packets arrive to trigger the normal drain path.
            await MainActor.run { [weak self] in
                self?.drainPendingBufferIfNeeded()
                self?.metadataObserver.scheduleMetadataRefresh()
            }
        }
    }

    /// Drains the coalescing buffer by spawning a new task when the executor has
    /// capacity. Called after each `spawnDetached` completes via `MainActor.run`.
    /// Guarantees all coalesced PTY batches are eventually processed even when
    /// the flood ends with no subsequent packet to trigger the normal drain path.
    func drainPendingBufferIfNeeded() {
        guard !taskExecutor.isAtCapacity, let pending = pendingOutputBuffer else { return }
        pendingOutputBuffer = nil
        pendingOutputDrainTask?.cancel()
        pendingOutputDrainTask = nil
        let sid = sessionID
        let processor = outputProcessor
        let coordinator = agentCoordinator
        let tokenService = outputProcessor.tokenCountingService
        taskExecutor.spawnDetached {
            await processor.processDataOutput(pending.text, stripped: pending.stripped, sessionID: sid)
            await coordinator.analyzeOutput(pending.stripped, tokenCountingService: tokenService)
            let update = await coordinator.computeAgentStateUpdate(
                tokenCountingService: processor.tokenCountingService
            )
            if let (state, alert) = update {
                await coordinator.applyAgentStateUpdate(state: state, alert: alert)
            }
            await MainActor.run { [weak self] in
                self?.drainPendingBufferIfNeeded()
                self?.metadataObserver.scheduleMetadataRefresh()
            }
        }
    }

    private func armPendingOutputDrainIfNeeded() {
        guard pendingOutputDrainTask == nil else { return }
        pendingOutputDrainTask = AutoCancellableTask(Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.pendingOutputDrainTask = nil }
            while pendingOutputBuffer != nil && taskExecutor.isAtCapacity {
                await Task.yield()
            }
            drainPendingBufferIfNeeded()
        })
    }
}
