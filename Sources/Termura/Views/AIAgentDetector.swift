import Foundation

/// Resolved AI agent target plus a human-readable session label.
/// Surfaced to popover headers as "Using <displayName> · from <label>".
struct AIAgentDetection: Sendable {
    let agent: AgentType
    let sessionLabel: String?
}

/// Determines which CLI agent the user is currently using, so the AI-commit /
/// remote-setup popovers can spawn its headless variant. Priority:
///   1. Active session's agent (if it supports headless mode)
///   2. Any other session with a headless-capable agent
///   3. PATH probe via `aiCommitService.probeAvailableHeadlessAgent()` — async,
///      runs only when steps 1–2 missed. Lets the user submit a commit when
///      a CLI is installed but no interactive session is open.
///   4. nil — caller shows a "no agent detected" warning
@MainActor
enum AIAgentDetector {
    static func detect(
        sessionScope: SessionScope
    ) -> AIAgentDetection? {
        let agents = sessionScope.agentStates.agents
        if let activeID = sessionScope.store.activeSessionID,
           let state = agents[activeID],
           state.agentType.supportsHeadless {
            return AIAgentDetection(
                agent: state.agentType,
                sessionLabel: label(for: activeID, scope: sessionScope)
            )
        }
        if let state = agents.values.first(where: { $0.agentType.supportsHeadless }) {
            return AIAgentDetection(
                agent: state.agentType,
                sessionLabel: label(for: state.sessionID, scope: sessionScope)
            )
        }
        return nil
    }

    /// Detection that falls back to a PATH probe when no session-based match
    /// is found. The probe result has no `sessionLabel` because no session is
    /// associated; the popover header treats nil as "PATH-only".
    static func detectAsync(sessionScope: SessionScope,
                            probe: any AICommitServiceProtocol) async
        -> AIAgentDetection? {
        if let viaSession = detect(sessionScope: sessionScope) {
            return viaSession
        }
        guard let probed = await probe.probeAvailableHeadlessAgent() else { return nil }
        return AIAgentDetection(agent: probed, sessionLabel: nil)
    }

    private static func label(for id: SessionID, scope: SessionScope) -> String? {
        let title = scope.store.sessionTitles[id]
        guard let title, !title.isEmpty else { return nil }
        return "session \"\(title)\""
    }
}
