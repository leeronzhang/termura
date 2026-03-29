import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentCoordinator")

/// Coordinates agent detection, state management, risk monitoring, and context
/// window alerts for a terminal session.
///
/// Extracted from `TerminalViewModel` to reduce its init parameter count and
/// isolate agent-related responsibilities behind a single facade.
///
/// Actor isolation: no SwiftUI-observed state — uses Swift native actor per CLAUDE.md §6.1 Principle 1.
///
/// Alert state is NOT owned here — callbacks propagate detections to the owning
/// TerminalViewModel, which holds the observable properties observed by views.
actor AgentCoordinator {
    // MARK: - Alert callbacks (wired by TerminalViewModel in init)

    /// Called on MainActor when a risk alert is detected. TerminalViewModel applies
    /// the deduplication guard (skip if alert already pending) and sets its own state.
    ///
    /// nonisolated(unsafe): set exactly once from TerminalViewModel.init (@MainActor) before
    /// any background tasks are spawned. Never mutated again — safe for concurrent reads.
    nonisolated(unsafe) var onRiskAlertDetected: (@MainActor @Sendable (RiskAlert) -> Void)?
    /// Called on MainActor when a context-window alert is computed.
    ///
    /// Same nonisolated(unsafe) guarantee as onRiskAlertDetected above.
    nonisolated(unsafe) var onContextWindowAlertDetected: (@MainActor @Sendable (ContextWindowAlert) -> Void)?

    // MARK: - Dependencies

    /// nonisolated let: AgentStateDetector is an actor (Sendable). Accessible from
    /// nonisolated methods (analyzeOutput, computeAgentStateUpdate) and @MainActor callers
    /// without crossing the AgentCoordinator actor boundary.
    nonisolated let agentDetector: AgentStateDetector
    /// nonisolated let: ContextWindowMonitor is an actor (Sendable). Same rationale.
    nonisolated let contextWindowMonitor: ContextWindowMonitor
    /// nonisolated let: AgentStateStoreProtocol: Sendable (protocol constraint added).
    /// Allows TerminalViewModel+Metadata.swift to read store properties from @MainActor context
    /// without an extra actor hop through AgentCoordinator.
    nonisolated let agentStateStore: (any AgentStateStoreProtocol)?
    private let metricsCollector: (any MetricsCollectorProtocol)?

    // MARK: - Agent detection state

    var agentDetectionBuffer = ""
    /// Mirrors `agentDetectionBuffer` but stored lowercased, updated incrementally.
    /// Avoids re-lowercasing the entire accumulated buffer on every PTY packet.
    private var agentDetectionBufferLower = ""
    var hasDetectedAgentFromOutput = false
    var lastDetectedAgentType: AgentType?

    // MARK: - Init

    init(
        sessionID: SessionID,
        agentStateStore: (any AgentStateStoreProtocol)? = nil,
        metricsCollector: (any MetricsCollectorProtocol)? = nil
    ) {
        agentDetector = AgentStateDetector(sessionID: sessionID)
        contextWindowMonitor = ContextWindowMonitor()
        self.agentStateStore = agentStateStore
        self.metricsCollector = metricsCollector
    }

    // MARK: - Agent detection from commands

    /// Detect agent type from a submitted command and update session/agent state.
    /// Callers must spawn this inside a tracked task (e.g. `spawnTracked`).
    func detectAgentFromCommand(
        _ command: String,
        sessionStore: any SessionStoreProtocol,
        sessionID: SessionID
    ) async {
        guard let agentType = await agentDetector.detectFromCommand(command) else { return }
        let agentState = await agentDetector.buildState()
        await sessionStore.renameSession(id: sessionID, title: agentType.displayName)
        await sessionStore.setAgentType(id: sessionID, type: agentType)
        if let state = agentState {
            await agentStateStore?.update(state: state)
        }
    }

    // MARK: - Agent detection from output

    /// Signature patterns in terminal output that identify a running agent.
    private static let outputSignatures: [(pattern: String, type: AgentType)] = [
        ("claude code", .claudeCode),
        ("anthropic", .claudeCode),
        ("openai codex", .codex),
        (">_ openai codex", .codex),
        ("aider v", .aider),
        ("opencode", .openCode),
        ("gemini cli", .gemini),
        ("gemini code", .gemini)
    ]

    /// Unicode symbols commonly used as status indicators in terminal titles.
    private static let symbolPrefixSet: CharacterSet = {
        CharacterSet(charactersIn:
            "\u{2733}\u{273B}\u{2731}" + // asterisks
            "\u{2726}\u{2605}\u{2606}" + // stars
            "\u{00B7}\u{2022}\u{2027}\u{2219}\u{22C5}\u{2024}\u{2981}" + // dots/bullets (standard)
            "\u{0387}\u{FF65}\u{30FB}\u{16EB}\u{1427}" + // dot look-alikes (Greek, halfwidth, katakana, runic, Canadian)
            "\u{25CF}\u{25CB}\u{25C9}\u{2B24}\u{2B58}\u{26AB}\u{26AA}" + // circles
            "\u{25AA}\u{25AB}\u{25C6}\u{25C7}" + // geometric
            "\u{203A}\u{276F}\u{2192}\u{26A1}" + // arrows/prompt
            "\u{2714}\u{2718}\u{23F3}" + // status
            "\u{2012}\u{2013}\u{2014}\u{2015}" + // dashes
            "\u{FEFF}\u{200B}\u{200C}\u{200D}\u{2060}\u{00AD}" // invisible/format chars
        )
    }()

    /// Returns true for non-ASCII Unicode scalars that belong to symbol or format categories
    /// and are therefore safe to strip as leading title prefixes. ASCII punctuation is excluded
    /// to avoid stripping legitimate characters like "." or "!" that may start a title.
    private static func isStrippableSymbolCategory(_ scalar: Unicode.Scalar) -> Bool {
        guard scalar.value > 0x007F else { return false }
        switch scalar.properties.generalCategory {
        case .format, .otherSymbol, .mathSymbol, .modifierSymbol:
            return true
        case .otherPunctuation:
            // Strip non-ASCII "other punctuation" (covers dot look-alikes in any script).
            return true
        default:
            return false
        }
    }

    /// Strips known agent icon prefixes from OSC terminal titles.
    static func stripAgentPrefixes(_ title: String) -> String {
        var stripped = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let multiCharPrefixes = [">_"]
        var didStrip = true
        while didStrip {
            didStrip = false
            for prefix in multiCharPrefixes where stripped.hasPrefix(prefix) {
                stripped = String(stripped.dropFirst(prefix.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
            if let first = stripped.unicodeScalars.first,
               symbolPrefixSet.contains(first) || isStrippableSymbolCategory(first) {
                stripped = String(stripped.unicodeScalars.dropFirst())
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                didStrip = true
            }
        }
        return stripped.isEmpty ? title : stripped
    }

    /// Scan terminal output for agent signatures and update session when detected.
    ///
    /// All shared-state mutations (buffer, flags) are confined to the synchronous
    /// `bufferAndDetect` helper so no interleaving task can observe intermediate state
    /// across suspension points. The async section uses only the locally captured type.
    func detectAgentFromOutput(
        _ text: String,
        sessionStore: any SessionStoreProtocol,
        sessionID: SessionID
    ) async {
        guard let detectedType = bufferAndDetect(text) else { return }

        if let collector = metricsCollector {
            Task { await collector.increment(.agentDetected) }
        }
        await sessionStore.renameSession(id: sessionID, title: detectedType.displayName)
        await sessionStore.setAgentType(id: sessionID, type: detectedType)
        await agentDetector.setDetectedType(detectedType)
        if let state = await agentDetector.buildState() {
            await agentStateStore?.update(state: state)
        }
    }

    /// Appends `text` to the rolling detection buffer, trims it to the configured
    /// suffix window, then returns the first newly matched agent type.
    /// Returns `nil` if the buffer yields no match, or if the match duplicates the
    /// already-known agent type (dedup guard).
    ///
    /// This is a **synchronous** function with no suspension points. All writes to
    /// `agentDetectionBuffer`, `hasDetectedAgentFromOutput`, and `lastDetectedAgentType`
    /// happen here, atomically from the perspective of the actor executor.
    private func bufferAndDetect(_ text: String) -> AgentType? {
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        // Append only the new chunk to both buffers. Lowercase only the incoming text
        // (O(new_chunk)) rather than re-lowercasing the entire accumulated buffer (O(maxLen))
        // on every PTY packet — this is a hot path called for every byte of terminal output.
        agentDetectionBuffer += text
        agentDetectionBufferLower += text.lowercased()
        // Trim both buffers in sync when the suffix window is exceeded.
        if agentDetectionBuffer.count > maxLen {
            agentDetectionBuffer = String(agentDetectionBuffer.suffix(maxLen))
            agentDetectionBufferLower = String(agentDetectionBufferLower.suffix(maxLen))
        }
        for (pattern, type) in Self.outputSignatures where agentDetectionBufferLower.contains(pattern) {
            if hasDetectedAgentFromOutput, lastDetectedAgentType == type { return nil }
            hasDetectedAgentFromOutput = true
            lastDetectedAgentType = type
            return type
        }
        return nil
    }

    // MARK: - Output analysis (background)

    /// Analyze output text for agent status changes, token stats, and risk patterns.
    /// Runs off the actor executor: only accesses nonisolated let dependencies and fires a
    /// fire-and-forget Task { @MainActor } for the risk alert callback — avoids a second
    /// blocking main-actor hop inside the spawnDetachedTracked closure
    /// (CLAUDE.md §6.1 Principle 3: single hop at closure end).
    nonisolated func analyzeOutput(
        _ stripped: String,
        sessionID: SessionID,
        tokenCountingService: any TokenCountingServiceProtocol
    ) async {
        let detector = agentDetector

        await detector.analyzeOutput(stripped)
        if let stats = await detector.parseTokenStats(stripped) {
            if let cached = stats.cachedTokens, cached > 0 {
                await tokenCountingService.accumulateCached(for: sessionID, count: cached)
            }
            if let cost = stats.totalCost {
                await detector.updateCost(cost)
            }
        }
        if let risk = InterventionService.detectRisk(in: stripped) {
            // Fire-and-forget: does not block the spawnDetachedTracked closure.
            let callback = onRiskAlertDetected
            Task { @MainActor in callback?(risk) }
        }
    }

    // MARK: - Agent state update

    /// Compute agent state and context alert off the actor executor.
    /// All async work (token breakdown, actor hops) runs on background executors.
    /// Call `applyAgentStateUpdate(state:alert:)` to commit the result.
    nonisolated func computeAgentStateUpdate(
        tokenCountingService: any TokenCountingServiceProtocol,
        sessionID: SessionID
    ) async -> (state: AgentState, alert: ContextWindowAlert?)? {
        let detector = agentDetector
        let monitor = contextWindowMonitor
        let breakdown = await tokenCountingService.tokenBreakdown(for: sessionID)
        guard var state = await detector.buildState(tokenCount: breakdown.totalTokens) else { return nil }
        state.inputTokens = breakdown.inputTokens
        state.outputTokens = breakdown.outputTokens
        state.cachedTokens = breakdown.cachedTokens
        let hasParsedData = state.cachedTokens > 0 || state.estimatedCostUSD > 0
        let alert: ContextWindowAlert? = hasParsedData ? await monitor.evaluate(state: state) : nil
        return (state, alert)
    }

    /// Apply a previously computed agent state update.
    /// Hops to @MainActor for store.update (AgentStateStoreProtocol is @MainActor),
    /// then fires the context alert callback as a fire-and-forget Task { @MainActor }.
    func applyAgentStateUpdate(state: AgentState, alert: ContextWindowAlert?) async {
        await agentStateStore?.update(state: state)
        if let alert {
            let callback = onContextWindowAlertDetected
            Task { @MainActor in callback?(alert) }
        }
    }

    // MARK: - Execution finish reset

    /// Resets all agent detection state when the shell signals execution has finished (OSC 133 D).
    /// Without this, agent status badges remain in a non-idle state after the agent exits,
    /// keeping repeatForever animations running and causing continuous CPU drain when idle.
    func resetOnExecutionFinished(sessionID: SessionID) async {
        await agentDetector.reset()
        await agentStateStore?.remove(sessionID: sessionID)
        hasDetectedAgentFromOutput = false
        lastDetectedAgentType = nil
        agentDetectionBuffer = ""
        agentDetectionBufferLower = ""
    }
}
