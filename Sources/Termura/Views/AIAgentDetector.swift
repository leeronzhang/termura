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
///   3. nil — caller shows a "no agent detected" warning
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

    private static func label(for id: SessionID, scope: SessionScope) -> String? {
        let title = scope.store.sessionTitles[id]
        guard let title, !title.isEmpty else { return nil }
        return "session \"\(title)\""
    }
}
