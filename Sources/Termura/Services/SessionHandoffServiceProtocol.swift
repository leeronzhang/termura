import Foundation

/// Protocol abstracting session handoff context generation and reading.
protocol SessionHandoffServiceProtocol: Actor {
    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState
    ) async throws

    func readExistingContext(projectRoot: String) async -> HandoffContext?
}
