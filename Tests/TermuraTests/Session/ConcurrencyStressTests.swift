import XCTest
@testable import Termura

/// Concurrency stress tests: verifies Actor isolation and @MainActor state
/// remain consistent under high-concurrency access patterns.
@MainActor
final class ConcurrencyStressTests: XCTestCase {
    // MARK: - AgentStateStore concurrent updates

    func testAgentStateStoreConcurrentUpdates() async {
        let store = AgentStateStore()
        let sessionIDs = (0 ..< 50).map { _ in SessionID() }

        // Fire 50 concurrent updates.
        await withTaskGroup(of: Void.self) { group in
            for id in sessionIDs {
                group.addTask { @MainActor in
                    let state = AgentState(sessionID: id, agentType: .claudeCode)
                    store.update(state: state)
                }
            }
        }

        // All 50 should be present — no lost updates.
        XCTAssertEqual(store.agents.count, 50)
    }

    func testAgentStateStoreRemoveDuringIteration() async {
        let store = AgentStateStore()
        let ids = (0 ..< 20).map { _ in SessionID() }

        for id in ids {
            store.update(state: AgentState(sessionID: id, agentType: .claudeCode))
        }

        // Concurrently remove half while reading.
        await withTaskGroup(of: Void.self) { group in
            for id in ids.prefix(10) {
                group.addTask { @MainActor in
                    store.remove(sessionID: id)
                }
            }
            // Concurrent reads.
            for _ in 0 ..< 10 {
                group.addTask { @MainActor in
                    _ = store.sessionsNeedingAttention
                    _ = store.activeAgentCount
                }
            }
        }

        XCTAssertEqual(store.agents.count, 10)
    }

    // MARK: - TokenCountingService concurrent accumulation

    func testTokenCountingConcurrentAccumulation() async {
        let service = TokenCountingService()
        let sessionID = SessionID()
        let iterations = 100

        // Concurrent accumulations from "multiple terminal outputs".
        await withTaskGroup(of: Void.self) { group in
            for _ in 0 ..< iterations {
                group.addTask {
                    await service.accumulate(for: sessionID, text: "hello world ")
                }
            }
        }

        let tokens = await service.estimatedTokens(for: sessionID)
        // "hello world " = 12 chars × 100 iterations = 1200 chars / 4 = 300 tokens
        XCTAssertEqual(tokens, 300)
    }

    // MARK: - SessionStore concurrent operations

    func testSessionStoreConcurrentCreateClose() async {
        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let store = SessionStore(engineStore: engineStore)

        // Create 20 sessions.
        var ids: [SessionID] = []
        for i in 0 ..< 20 {
            let session = store.createSession(title: "Session \(i)")
            ids.append(session.id)
        }

        XCTAssertEqual(store.sessions.count, 20)

        // Close half concurrently.
        await withTaskGroup(of: Void.self) { group in
            for id in ids.prefix(10) {
                group.addTask { @MainActor in
                    store.closeSession(id: id)
                }
            }
        }

        XCTAssertEqual(store.sessions.count, 10)
        engineStore.terminateAll()
    }

    // MARK: - OutputStore concurrent append

    func testOutputStoreConcurrentAppend() async {
        let store = OutputStore(sessionID: SessionID())

        await withTaskGroup(of: Void.self) { group in
            for i in 0 ..< 50 {
                group.addTask { @MainActor in
                    let chunk = OutputChunk(
                        sessionID: SessionID(),
                        commandText: "cmd \(i)",
                        outputLines: ["line"],
                        rawANSI: "line",
                        exitCode: 0,
                        startedAt: Date(),
                        finishedAt: Date(),
                        contentType: .text,
                        uiContent: nil
                    )
                    store.append(chunk)
                }
            }
        }

        XCTAssertEqual(store.chunks.count, 50)
    }

    // MARK: - SearchService concurrent queries

    func testSearchServiceConcurrentQueries() async throws {
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()
        let service = SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)

        // 10 concurrent searches should not crash or deadlock.
        try await withThrowingTaskGroup(of: SearchResults.self) { group in
            for i in 0 ..< 10 {
                group.addTask {
                    try await service.search(query: "query \(i)")
                }
            }
            for try await results in group {
                // Empty results are expected — just verify no crash.
                XCTAssertNotNil(results)
            }
        }
    }
}
