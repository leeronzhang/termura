import Foundation

extension AgentCoordinator {
    // MARK: - Agent detection from output

    /// Signature patterns in terminal output that identify a running agent.
    static let outputSignatures: [(pattern: String, type: AgentType)] = [
        ("claude code", .claudeCode),
        ("anthropic", .claudeCode),
        ("openai codex", .codex),
        (">_ openai codex", .codex),
        ("aider v", .aider),
        ("opencode", .openCode),
        ("gemini cli", .gemini),
        ("gemini code", .gemini)
    ]

    /// Check-and-detect in a single actor hop, eliminating the TOCTOU pattern that
    /// arises from a caller doing `await hasDetectedAgentFromOutput` then separately
    /// `await detectAgentFromOutput`. Both the guard and the mutation execute inside
    /// the actor without a suspension point between them.
    ///
    /// Returns `true` once detection is confirmed (either already was, or just occurred),
    /// so callers can cache the result and skip future hops (CLAUDE.md P2-15).
    @discardableResult
    func detectAgentFromOutputIfNeeded(_ text: String) async -> Bool {
        guard !hasDetectedAgentFromOutput else { return true }
        await detectAgentFromOutput(text)
        return hasDetectedAgentFromOutput
    }

    /// Scan terminal output for agent signatures and update session when detected.
    ///
    /// All shared-state mutations (buffer, flags) are confined to the synchronous
    /// `bufferAndDetect` helper so no interleaving task can observe intermediate state
    /// across suspension points. The async section uses only the locally captured type.
    func detectAgentFromOutput(_ text: String) async {
        guard let detectedType = bufferAndDetect(text) else { return }

        if let collector = metricsCollector {
            Task { await collector.increment(.agentDetected) }
        }
        await sessionStore.renameSession(id: sessionID, title: detectedType.displayName)
        await sessionStore.setAgentType(id: sessionID, type: detectedType)
        await agentDetector.setDetectedType(detectedType)
        if let state = await agentDetector.buildState() {
            await agentStateStore.update(state: state)
        }
    }

    /// Appends `text` to the rolling detection buffer, trims it when the amortized
    /// threshold is reached, then returns the first newly matched agent type.
    /// Returns `nil` if no match is found, or the match is a duplicate of the already-known
    /// agent type (dedup guard).
    ///
    /// This is a **synchronous** function with no suspension points. All writes to
    /// `agentDetectionBuffer`, `hasDetectedAgentFromOutput`, and `lastDetectedAgentType`
    /// happen here, atomically from the perspective of the actor executor.
    ///
    /// Allocation profile:
    /// - Per packet: one O(chunk) `lowercased()` append — unavoidable.
    /// - O(maxLen) trim copy: amortized once per maxLen bytes of input (2x threshold),
    ///   vs. once per packet in the previous dual-buffer approach.
    func bufferAndDetect(_ text: String) -> AgentType? {
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        if agentDetectionBuffer.isEmpty {
            agentDetectionBuffer.reserveCapacity(2 * maxLen)
        }
        agentDetectionBuffer += text.lowercased()
        if agentDetectionBuffer.count > 2 * maxLen {
            agentDetectionBuffer.removeFirst(agentDetectionBuffer.count - maxLen)
        }
        let window = agentDetectionBuffer.count <= maxLen
            ? agentDetectionBuffer[...]
            : agentDetectionBuffer.suffix(maxLen)
        for (pattern, type) in Self.outputSignatures where window.contains(pattern) {
            if hasDetectedAgentFromOutput, lastDetectedAgentType == type { return nil }
            hasDetectedAgentFromOutput = true
            lastDetectedAgentType = type
            return type
        }
        return nil
    }
}
