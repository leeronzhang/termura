import Foundation

#if DEBUG

/// Debug fallback for previews and local environment defaults.
actor DebugSessionHandoffService: SessionHandoffServiceProtocol {
    func generateHandoff(
        session _: SessionRecord,
        chunks _: [OutputChunk],
        agentState _: AgentState,
        projectRoot _: String
    ) async throws {}

    func readExistingContext(projectRoot _: String) async -> HandoffContext? {
        nil
    }
}

#endif
