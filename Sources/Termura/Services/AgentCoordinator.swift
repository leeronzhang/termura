import Foundation
import OSLog

private let logger = Logger(subsystem: "com.termura.app", category: "AgentCoordinator")

/// Coordinates agent detection, risk monitoring, and context-window alerts for a terminal session.
/// Extracted from `TerminalViewModel` to isolate agent responsibilities behind a single facade.
/// Uses a Swift actor because it owns no SwiftUI-observed state.
/// Alert state is not owned here; AsyncStreams feed TerminalViewModel's observable properties.
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
    nonisolated let riskAlertContinuation: AsyncStream<RiskAlert>.Continuation
    /// Continuation for contextWindowAlerts. Actor-isolated callers (applyAgentStateUpdate)
    /// may also use nonisolated access — Continuation is designed for concurrent yield calls.
    nonisolated let contextAlertContinuation: AsyncStream<ContextWindowAlert>.Continuation

    // MARK: - Dependencies

    /// nonisolated let: AgentStateDetector is an actor (Sendable), accessible without an extra hop.
    nonisolated let agentDetector: AgentStateDetector
    /// nonisolated let: ContextWindowMonitor is an actor (Sendable). Same rationale.
    nonisolated let contextWindowMonitor: ContextWindowMonitor
    /// nonisolated let: AgentStateStoreProtocol is Sendable and readable without an extra hop.
    nonisolated let agentStateStore: any AgentStateStoreProtocol
    /// nonisolated let: per-session identity — eliminates sessionID method parameters.
    nonisolated let sessionID: SessionID
    /// nonisolated let: session store for agent-triggered rename/type mutations.
    /// Stored here to avoid callers passing back a dependency they already hold (CLAUDE.md §1.3).
    nonisolated let sessionStore: any SessionStoreProtocol
    let metricsCollector: (any MetricsCollectorProtocol)?

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
        // WHY: Risk/context alerts bridge coordinator state into bounded async streams.
        // OWNER: AgentCoordinator owns both continuations; TEARDOWN: deinit/stop finishes them.
        // TEST: Cover alert delivery plus coordinator teardown.
        let (riskStream, riskCont) = AsyncStream.makeStream(
            of: RiskAlert.self,
            bufferingPolicy: .bufferingNewest(AppConfig.Terminal.streamBufferCapacity)
        )
        // WHY: Context-window alerts share the same lifecycle but need a separate stream.
        // OWNER: AgentCoordinator owns contextAlertContinuation; TEARDOWN: deinit/stop finishes it.
        // TEST: Cover context-window alert delivery plus teardown.
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
        // Command-based detection is authoritative — lock out output-based detection
        // to prevent false overrides when agent output contains other agents' signature
        // patterns (e.g., Claude Code discussing "gemini cli").
        hasDetectedAgentFromOutput = true
        lastDetectedAgentType = agentType
        let agentState = await agentDetector.buildState()
        await sessionStore.renameSession(id: sessionID, title: agentType.displayName)
        await sessionStore.setAgentType(id: sessionID, type: agentType)
        if let state = agentState {
            await agentStateStore.update(state: state)
        }
    }

    // MARK: - Structured signal (Phase 2 hook)

    /// Forward an authoritative OSC agent-status signal to the detector, bypassing
    /// text-rule analysis. Called when OSC 9/99/777 carries a confirmed status frame.
    /// Phase 2: wired from ShellIntegrationEvent when OSC parser emits agentStatus events.
    func applyStructuredAgentSignal(status: AgentStatus) async {
        await agentDetector.applyStructuredSignal(status)
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
