import Foundation

#if DEBUG

/// Test double for `SessionHandoffServiceProtocol`.
actor MockSessionHandoffService: SessionHandoffServiceProtocol {
    var stubbedContext: HandoffContext?
    var generateCallCount = 0
    var readCallCount = 0
    var lastGenerateSession: SessionRecord?

    func generateHandoff(
        session: SessionRecord,
        chunks: [OutputChunk],
        agentState: AgentState,
        projectRoot: String
    ) async throws {
        generateCallCount += 1
        lastGenerateSession = session
    }

    func readExistingContext(projectRoot: String) async -> HandoffContext? {
        readCallCount += 1
        return stubbedContext
    }
}

#endif
