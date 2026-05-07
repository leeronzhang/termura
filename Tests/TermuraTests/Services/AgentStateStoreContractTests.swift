import Foundation
@testable import Termura
import XCTest

/// Contract tests verifying that MockAgentStateStore mirrors the behavioral
/// contract of AgentStateStore for the operations it is designed to replicate.
///
/// Known divergence — activeAgentCount:
///   Real:  counts agents where status != .completed (idle, thinking, toolRunning,
///          waitingInput, and error all count as active)
///   Mock:  counts only .thinking and .toolRunning agents
/// This drift is intentional for the mock's simplified use case; activeAgentCount
/// is excluded from contract assertions and tested in AgentStateStoreTests.swift.
@MainActor
final class AgentStateStoreContractTests: XCTestCase {
    private func makeAgent(
        sessionID: SessionID = SessionID(),
        status: AgentStatus = .idle,
        tokenCount: Int = 0
    ) -> AgentState {
        AgentState(
            sessionID: sessionID,
            agentType: .claudeCode,
            status: status,
            tokenCount: tokenCount
        )
    }

    // MARK: - Update

    /// Both implementations must store the agent state and make it retrievable by sessionID.
    func testUpdateStoresAgentContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()
        let sid = SessionID()
        let state = makeAgent(sessionID: sid, status: .thinking)

        mock.update(state: state)
        real.update(state: state)

        XCTAssertNotNil(mock.agents[sid])
        XCTAssertNotNil(real.agents[sid])
        XCTAssertEqual(mock.agents[sid]?.status, .thinking)
        XCTAssertEqual(real.agents[sid]?.status, .thinking)
    }

    /// Both implementations must overwrite existing state on repeated updates.
    func testUpdateOverwritesExistingContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()
        let sid = SessionID()

        mock.update(state: makeAgent(sessionID: sid, status: .idle))
        real.update(state: makeAgent(sessionID: sid, status: .idle))

        mock.update(state: makeAgent(sessionID: sid, status: .thinking))
        real.update(state: makeAgent(sessionID: sid, status: .thinking))

        XCTAssertEqual(mock.agents.count, 1)
        XCTAssertEqual(real.agents.count, 1)
        XCTAssertEqual(mock.agents[sid]?.status, .thinking)
        XCTAssertEqual(real.agents[sid]?.status, .thinking)
    }

    // MARK: - Remove

    /// Both implementations must remove the agent from the store.
    func testRemoveClearsAgentContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()
        let sid = SessionID()

        mock.update(state: makeAgent(sessionID: sid))
        real.update(state: makeAgent(sessionID: sid))
        mock.remove(sessionID: sid)
        real.remove(sessionID: sid)

        XCTAssertTrue(mock.agents.isEmpty)
        XCTAssertTrue(real.agents.isEmpty)
    }

    /// Both implementations must silently ignore removal of a nonexistent session.
    func testRemoveNonexistentIsNoopContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()

        mock.update(state: makeAgent())
        real.update(state: makeAgent())
        let phantomSID = SessionID()
        mock.remove(sessionID: phantomSID)
        real.remove(sessionID: phantomSID)

        XCTAssertEqual(mock.agents.count, 1)
        XCTAssertEqual(real.agents.count, 1)
    }

    // MARK: - ClearAll

    /// Both implementations must empty the store entirely.
    func testClearAllEmptiesContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()

        mock.update(state: makeAgent())
        mock.update(state: makeAgent())
        real.update(state: makeAgent())
        real.update(state: makeAgent())

        mock.clearAll()
        real.clearAll()

        XCTAssertTrue(mock.agents.isEmpty)
        XCTAssertTrue(real.agents.isEmpty)
    }

    // MARK: - Total tokens

    /// Both implementations must sum tokenCount across all stored agents.
    func testTotalEstimatedTokensContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()

        mock.update(state: makeAgent(tokenCount: 1000))
        mock.update(state: makeAgent(tokenCount: 500))
        real.update(state: makeAgent(tokenCount: 1000))
        real.update(state: makeAgent(tokenCount: 500))

        XCTAssertEqual(mock.totalEstimatedTokens, 1500)
        XCTAssertEqual(real.totalEstimatedTokens, 1500)
        XCTAssertEqual(mock.totalEstimatedTokens, real.totalEstimatedTokens)
    }

    /// Both implementations must return 0 when the store is empty.
    func testTotalEstimatedTokensZeroWhenEmptyContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()

        XCTAssertEqual(mock.totalEstimatedTokens, 0)
        XCTAssertEqual(real.totalEstimatedTokens, 0)
    }

    // MARK: - sessionsNeedingAttention

    /// Both implementations must return sessions with waitingInput or error status.
    func testSessionsNeedingAttentionContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()
        let sid1 = SessionID()
        let sid2 = SessionID()

        mock.update(state: makeAgent(sessionID: sid1, status: .waitingInput))
        mock.update(state: makeAgent(sessionID: sid2, status: .error))
        mock.update(state: makeAgent(status: .thinking))
        real.update(state: makeAgent(sessionID: sid1, status: .waitingInput))
        real.update(state: makeAgent(sessionID: sid2, status: .error))
        real.update(state: makeAgent(status: .thinking))

        let mockAttention = mock.sessionsNeedingAttention
        let realAttention = real.sessionsNeedingAttention

        XCTAssertEqual(mockAttention.count, 2)
        XCTAssertEqual(realAttention.count, 2)
        XCTAssertTrue(mockAttention.contains(sid1))
        XCTAssertTrue(mockAttention.contains(sid2))
        XCTAssertTrue(realAttention.contains(sid1))
        XCTAssertTrue(realAttention.contains(sid2))
    }

    /// Both implementations must return nil for nextAttentionSessionID when no agent
    /// needs attention.
    func testNextAttentionNilWhenNoneNeededContract() {
        let mock = MockAgentStateStore()
        let real = AgentStateStore()

        mock.update(state: makeAgent(status: .idle))
        real.update(state: makeAgent(status: .idle))

        XCTAssertNil(mock.nextAttentionSessionID)
        XCTAssertNil(real.nextAttentionSessionID)
    }
}
