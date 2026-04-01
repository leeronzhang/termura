import Foundation

/// Protocol abstracting session handoff context generation and reading.
protocol SessionHandoffServiceProtocol: Actor {
    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState,
        projectRoot: String
    ) async throws

    func readExistingContext(projectRoot: String) async -> HandoffContext?
}
