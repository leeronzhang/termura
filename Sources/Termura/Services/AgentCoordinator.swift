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
/// Alert state is NOT owned here — AsyncStream properties (riskAlerts, contextWindowAlerts)
/// propagate detections to the owning TerminalViewModel, which holds the observable
/// properties observed by views.
actor AgentCoordinator {
    // MARK: - Alert streams (consumed by TerminalViewModel)

    /// Emits a RiskAlert whenever a risk pattern is detected in terminal output.
    /// Consumers (TerminalViewModel) subscribe with `for await` on MainActor.
    /// nonisolated let: AsyncStream is Sendable; accessible from nonisolated analyzeOutput
    /// without an actor hop.
    nonisolated let riskAlerts: AsyncStream<RiskAlert>
    /// Emits a ContextWindowAlert whenever the context monitor triggers.
    nonisolated let contextWindowAlerts: AsyncStream<ContextWindowAlert>

    /// Continuation for riskAlerts. nonisolated let so analyzeOutput (nonisolated) can yield
    /// without crossing the actor boundary. AsyncStream.Continuation is Sendable.
    nonisolated private let riskAlertContinuation: AsyncStream<RiskAlert>.Continuation
    /// Continuation for contextWindowAlerts. Actor-isolated callers (applyAgentStateUpdate)
    /// may also use nonisolated access — Continuation is designed for concurrent yield calls.
    nonisolated private let contextAlertContinuation: AsyncStream<ContextWindowAlert>.Continuation

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
    nonisolated let agentStateStore: any AgentStateStoreProtocol
    /// nonisolated let: per-session identity — eliminates sessionID method parameters.
    nonisolated let sessionID: SessionID
    /// nonisolated let: session store for agent-triggered rename/type mutations.
    /// Stored here to avoid callers passing back a dependency they already hold (CLAUDE.md §1.3).
    nonisolated let sessionStore: any SessionStoreProtocol
    private let metricsCollector: (any MetricsCollectorProtocol)?

    // MARK: - Agent detection state

    /// Rolling detection window stored in lowercase. A single lowercased buffer replaces the
    /// previous original-case + lowercase-mirror pair: the original-case copy was never read
    /// for detection logic, making it a pure allocation cost on every PTY packet.
    /// Trim is amortized: the buffer grows to 2×maxLen before being cut back to maxLen,
    /// halving the frequency of O(n) String copies versus trimming on every overflow.
    var agentDetectionBuffer = ""
    var hasDetectedAgentFromOutput = false
    var lastDetectedAgentType: AgentType?

    // MARK: - Init

    init(
        sessionID: SessionID,
        sessionStore: any SessionStoreProtocol,
        agentStateStore: any AgentStateStoreProtocol,
        metricsCollector: (any MetricsCollectorProtocol)? = nil // Optional: observability, nil = no-op
    ) {
        let (riskStream, riskCont) = AsyncStream.makeStream(
            of: RiskAlert.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        let (ctxStream, ctxCont) = AsyncStream.makeStream(
            of: ContextWindowAlert.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        riskAlerts = riskStream
        contextWindowAlerts = ctxStream
        riskAlertContinuation = riskCont
        contextAlertContinuation = ctxCont
        self.sessionID = sessionID
        self.sessionStore = sessionStore
        agentDetector = AgentStateDetector(sessionID: sessionID)
        contextWindowMonitor = ContextWindowMonitor()
        self.agentStateStore = agentStateStore
        self.metricsCollector = metricsCollector
    }

    // MARK: - Agent detection from commands

    /// Detect agent type from a submitted command and update session/agent state.
    /// Callers must spawn this inside a tracked task (e.g. `spawnTracked`).
    func detectAgentFromCommand(_ command: String) async {
        guard let agentType = await agentDetector.detectFromCommand(command) else { return }
        let agentState = await agentDetector.buildState()
        await sessionStore.renameSession(id: sessionID, title: agentType.displayName)
        await sessionStore.setAgentType(id: sessionID, type: agentType)
        if let state = agentState {
            await agentStateStore.update(state: state)
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
    private func bufferAndDetect(_ text: String) -> AgentType? {
        let maxLen = AppConfig.Agent.outputAnalysisSuffixLength
        // Pre-allocate backing storage on first use and after each reset to "".
        // reserveCapacity avoids repeated reallocations during the growth phase;
        // the in-place removeFirst below reuses the same backing store instead of
        // copy-assigning a new String, eliminating the allocation spike at trim time.
        if agentDetectionBuffer.isEmpty {
            agentDetectionBuffer.reserveCapacity(2 * maxLen)
        }
        // Append only the lowercased new chunk (O(chunk)).
        // The buffer stores lowercase content; original-case copy is not needed
        // because all pattern matching operates on lowercased text.
        agentDetectionBuffer += text.lowercased()
        // In-place trim: removeFirst shifts content within the existing backing store
        // (no new String allocation), whereas String(suffix(maxLen)) would allocate a
        // second maxLen buffer while the old one is still retained — peak 2x.
        // Amortised at 2x threshold: trim frequency is halved vs. trimming on every overflow.
        if agentDetectionBuffer.count > 2 * maxLen {
            agentDetectionBuffer.removeFirst(agentDetectionBuffer.count - maxLen)
        }
        // Scan only the last maxLen characters as the detection window.
        // The buffer holds at most 2*maxLen chars; suffix view is O(1) index computation.
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

    // MARK: - Output analysis (background)

    /// Analyze output text for agent status changes, token stats, and risk patterns.
    /// Runs off the actor executor: only accesses nonisolated let dependencies and fires a
    /// fire-and-forget Task { @MainActor } for the risk alert callback — avoids a second
    /// blocking main-actor hop inside the spawnDetachedTracked closure
    /// (CLAUDE.md §6.1 Principle 3: single hop at closure end).
    nonisolated func analyzeOutput(
        _ stripped: String,
        tokenCountingService: any TokenCountingServiceProtocol
    ) async {
        let detector = agentDetector
        let sid = sessionID

        let currentStatus = await detector.analyzeOutput(stripped)
        if let stats = await detector.parseTokenStats(stripped) {
            if let input = stats.inputTokens, let output = stats.outputTokens {
                // Parsed stats are authoritative — override heuristic accumulation for all
                // three categories so Input/Output/Cache reflect actual API usage, not estimates.
                await tokenCountingService.applyParsedStats(
                    for: sid,
                    inputTokens: input,
                    outputTokens: output,
                    cachedTokens: stats.cachedTokens ?? 0
                )
            } else if let cached = stats.cachedTokens, cached > 0 {
                await tokenCountingService.accumulateCached(for: sid, count: cached)
            }
            if let cost = stats.totalCost {
                await detector.updateCost(cost)
            }
        }
        if let risk = InterventionService.detectRisk(in: stripped, agentStatus: currentStatus) {
            riskAlertContinuation.yield(risk)
        }
    }

    // MARK: - Agent state update

    /// Compute agent state and context alert off the actor executor.
    /// All async work (token breakdown, actor hops) runs on background executors.
    /// Call `applyAgentStateUpdate(state:alert:)` to commit the result.
    nonisolated func computeAgentStateUpdate(
        tokenCountingService: any TokenCountingServiceProtocol
    ) async -> (state: AgentState, alert: ContextWindowAlert?)? {
        let detector = agentDetector
        let monitor = contextWindowMonitor
        let sid = sessionID
        let breakdown = await tokenCountingService.tokenBreakdown(for: sid)
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
    /// then yields any context alert to the contextWindowAlerts stream.
    func applyAgentStateUpdate(state: AgentState, alert: ContextWindowAlert?) async {
        await agentStateStore.update(state: state)
        if let alert {
            contextAlertContinuation.yield(alert)
        }
    }

    // MARK: - Execution finish reset

    /// Resets all agent detection state when the shell signals execution has finished (OSC 133 D).
    /// Without this, agent status badges remain in a non-idle state after the agent exits,
    /// keeping repeatForever animations running and causing continuous CPU drain when idle.
    func resetOnExecutionFinished() async {
        await agentDetector.reset()
        await agentStateStore.remove(sessionID: sessionID)
        hasDetectedAgentFromOutput = false
        lastDetectedAgentType = nil
        agentDetectionBuffer = ""
    }
}
