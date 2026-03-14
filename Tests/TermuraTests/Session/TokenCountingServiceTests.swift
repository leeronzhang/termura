import Testing
@testable import Termura

@Suite("TokenCountingService")
struct TokenCountingServiceTests {

    // MARK: - Token estimation

    @Test("400 characters yields 100 tokens")
    func fourHundredCharsIsHundredTokens() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        let text = String(repeating: "a", count: 400)
        await service.accumulate(for: sessionID, text: text)
        let tokens = await service.estimatedTokens(for: sessionID)
        #expect(tokens == 100)
    }

    @Test("New session starts at zero tokens")
    func newSessionZeroTokens() async {
        let service = TokenCountingService()
        let tokens = await service.estimatedTokens(for: SessionID())
        #expect(tokens == 0)
    }

    @Test("Multiple accumulations are additive")
    func accumulationsAreAdditive() async {
        let service = TokenCountingService()
        let sessionID = SessionID()

        await service.accumulate(for: sessionID, text: String(repeating: "x", count: 200))
        await service.accumulate(for: sessionID, text: String(repeating: "y", count: 200))
        let tokens = await service.estimatedTokens(for: sessionID)
        // 400 chars / 4 = 100 tokens
        #expect(tokens == 100)
    }

    // MARK: - Reset

    @Test("Reset clears count to zero")
    func resetClearsCount() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        await service.accumulate(for: sessionID, text: String(repeating: "z", count: 400))
        await service.reset(for: sessionID)
        let tokens = await service.estimatedTokens(for: sessionID)
        #expect(tokens == 0)
    }

    // MARK: - Multi-session isolation

    @Test("Two sessions are tracked independently")
    func multiSessionIsolation() async {
        let service = TokenCountingService()
        let sessionA = SessionID()
        let sessionB = SessionID()

        await service.accumulate(for: sessionA, text: String(repeating: "a", count: 400))
        await service.accumulate(for: sessionB, text: String(repeating: "b", count: 800))

        let tokensA = await service.estimatedTokens(for: sessionA)
        let tokensB = await service.estimatedTokens(for: sessionB)

        #expect(tokensA == 100)
        #expect(tokensB == 200)
    }

    @Test("Reset one session does not affect another")
    func resetIsolation() async {
        let service = TokenCountingService()
        let sessionA = SessionID()
        let sessionB = SessionID()

        await service.accumulate(for: sessionA, text: String(repeating: "a", count: 400))
        await service.accumulate(for: sessionB, text: String(repeating: "b", count: 400))
        await service.reset(for: sessionA)

        let tokensA = await service.estimatedTokens(for: sessionA)
        let tokensB = await service.estimatedTokens(for: sessionB)

        #expect(tokensA == 0)
        #expect(tokensB == 100)
    }
}
