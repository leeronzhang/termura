import Testing
@testable import Termura

@MainActor
@Suite("AgentStateStore")
struct AgentStateStoreTests {

    private func makeStore() -> AgentStateStore {
        AgentStateStore()
    }

    private func makeAgent(
        sessionID: SessionID = SessionID(),
        type: AgentType = .claudeCode,
        status: AgentStatus = .idle,
        tokenCount: Int = 0,
        contextWindowLimit: Int? = nil
    ) -> AgentState {
        AgentState(
            sessionID: sessionID,
            agentType: type,
            status: status,
            tokenCount: tokenCount,
            contextWindowLimit: contextWindowLimit
        )
    }

    // MARK: - CRUD

    @Test("update adds a new agent")
    func updateAddsAgent() {
        let store = makeStore()
        let sid = SessionID()
        store.update(state: makeAgent(sessionID: sid))
        #expect(store.agents.count == 1)
        #expect(store.agents[sid] != nil)
    }

    @Test("update overwrites existing agent state")
    func updateOverwritesExisting() {
        let store = makeStore()
        let sid = SessionID()
        store.update(state: makeAgent(sessionID: sid, status: .idle))
        store.update(state: makeAgent(sessionID: sid, status: .thinking))
        #expect(store.agents.count == 1)
        #expect(store.agents[sid]?.status == .thinking)
    }

    @Test("remove deletes an agent")
    func removeDeletesAgent() {
        let store = makeStore()
        let sid = SessionID()
        store.update(state: makeAgent(sessionID: sid))
        store.remove(sessionID: sid)
        #expect(store.agents.isEmpty)
    }

    @Test("remove non-existent session is a no-op")
    func removeNonExistentIsNoop() {
        let store = makeStore()
        store.update(state: makeAgent())
        store.remove(sessionID: SessionID())
        #expect(store.agents.count == 1)
    }

    @Test("clearAll removes all agents")
    func clearAllRemovesAll() {
        let store = makeStore()
        store.update(state: makeAgent())
        store.update(state: makeAgent())
        store.clearAll()
        #expect(store.agents.isEmpty)
    }

    // MARK: - activeAgentCount

    @Test("activeAgentCount excludes completed agents")
    func activeCountExcludesCompleted() {
        let store = makeStore()
        store.update(state: makeAgent(status: .thinking))
        store.update(state: makeAgent(status: .completed))
        #expect(store.activeAgentCount == 1)
    }

    @Test("activeAgentCount includes thinking, toolRunning, idle, waitingInput, error")
    func activeCountIncludesNonCompleted() {
        let store = makeStore()
        store.update(state: makeAgent(status: .thinking))
        store.update(state: makeAgent(status: .toolRunning))
        store.update(state: makeAgent(status: .idle))
        store.update(state: makeAgent(status: .waitingInput))
        store.update(state: makeAgent(status: .error))
        #expect(store.activeAgentCount == 5)
    }

    // MARK: - sessionsNeedingAttention

    @Test("sessionsNeedingAttention returns waitingInput and error sessions")
    func attentionReturnsWaitingInputAndError() {
        let store = makeStore()
        let sid1 = SessionID()
        let sid2 = SessionID()
        store.update(state: makeAgent(sessionID: sid1, status: .waitingInput))
        store.update(state: makeAgent(sessionID: sid2, status: .error))
        store.update(state: makeAgent(status: .idle))
        #expect(store.sessionsNeedingAttention.count == 2)
        #expect(store.sessionsNeedingAttention.contains(sid1))
        #expect(store.sessionsNeedingAttention.contains(sid2))
    }

    @Test("sessionsNeedingAttention excludes idle and thinking")
    func attentionExcludesIdleThinking() {
        let store = makeStore()
        store.update(state: makeAgent(status: .idle))
        store.update(state: makeAgent(status: .thinking))
        store.update(state: makeAgent(status: .toolRunning))
        #expect(store.sessionsNeedingAttention.isEmpty)
    }

    @Test("sessionsNeedingAttention sorts waitingInput before error")
    func attentionSortsWaitingInputBeforeError() {
        let store = makeStore()
        let errorSid = SessionID()
        let waitingSid = SessionID()
        store.update(state: makeAgent(sessionID: errorSid, status: .error))
        store.update(state: makeAgent(sessionID: waitingSid, status: .waitingInput))
        let result = store.sessionsNeedingAttention
        #expect(result.first == waitingSid)
    }

    // MARK: - nextAttentionSessionID

    @Test("nextAttentionSessionID returns highest priority session")
    func nextAttentionReturnsHighestPriority() {
        let store = makeStore()
        let sid = SessionID()
        store.update(state: makeAgent(sessionID: sid, status: .waitingInput))
        store.update(state: makeAgent(status: .error))
        #expect(store.nextAttentionSessionID == sid)
    }

    @Test("nextAttentionSessionID is nil when no attention needed")
    func nextAttentionNilWhenNoneNeeded() {
        let store = makeStore()
        store.update(state: makeAgent(status: .idle))
        #expect(store.nextAttentionSessionID == nil)
    }

    // MARK: - agentsNearingContextLimit

    @Test("agentsNearingContextLimit filters by warning threshold")
    func contextLimitFiltersWarningThreshold() {
        let store = makeStore()
        let limit = 200_000
        let aboveWarning = Int(Double(limit) * AppConfig.ContextWindow.warningThreshold) + 1
        let belowWarning = Int(Double(limit) * AppConfig.ContextWindow.warningThreshold) - 1000

        store.update(state: makeAgent(tokenCount: aboveWarning, contextWindowLimit: limit))
        store.update(state: makeAgent(tokenCount: belowWarning, contextWindowLimit: limit))

        #expect(store.agentsNearingContextLimit.count == 1)
    }

    // MARK: - totalEstimatedTokens

    @Test("totalEstimatedTokens sums all agent token counts")
    func totalTokensSumsAll() {
        let store = makeStore()
        store.update(state: makeAgent(tokenCount: 1000))
        store.update(state: makeAgent(tokenCount: 2500))
        #expect(store.totalEstimatedTokens == 3500)
    }

    @Test("totalEstimatedTokens is zero when empty")
    func totalTokensZeroWhenEmpty() {
        let store = makeStore()
        #expect(store.totalEstimatedTokens == 0)
    }
}
