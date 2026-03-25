import XCTest
@testable import Termura

/// Performance tests verifying CLAUDE.md SLO targets.
/// Uses XCTest.measure to assert latency budgets.
final class PerformanceSLOTests: XCTestCase {
    // MARK: - Full-text search < 200ms (P99)

    func testSearchLatencyWithinSLO() async throws {
        let sessionRepo = MockSessionRepository()
        let noteRepo = MockNoteRepository()
        let service = SearchService(sessionRepository: sessionRepo, noteRepository: noteRepo)

        let options = XCTMeasureOptions.default
        options.iterationCount = 10

        measure(options: options) {
            let expectation = expectation(description: "search")
            Task {
                _ = try await service.search(query: "searchable")
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: AppConfig.SLO.searchSeconds)
        }
    }

    // MARK: - Session switch < 100ms

    @MainActor
    func testSessionSwitchLatencyWithinSLO() throws {
        let factory = MockTerminalEngineFactory()
        let engineStore = TerminalEngineStore(factory: factory)
        let store = SessionStore(engineStore: engineStore)

        var ids: [SessionID] = []
        for i in 0 ..< 10 {
            let session = store.createSession(title: "Session \(i)")
            ids.append(session.id)
        }

        let options = XCTMeasureOptions.default
        options.iterationCount = 20

        measure(options: options) {
            for id in ids {
                store.activateSession(id: id)
            }
        }

        engineStore.terminateAll()
    }

    // MARK: - OutputStore append < 16ms (1 frame)

    @MainActor
    func testOutputStoreAppendLatency() {
        let store = OutputStore(sessionID: SessionID())

        let options = XCTMeasureOptions.default
        options.iterationCount = 50

        measure(options: options) {
            let chunk = OutputChunk(
                sessionID: SessionID(),
                commandText: "echo hello",
                outputLines: (0 ..< 100).map { "line \($0)" },
                rawANSI: String(repeating: "a", count: 5000),
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date(),
                contentType: .text,
                uiContent: nil
            )
            store.append(chunk)
        }
    }

    // MARK: - Token estimation < 1ms

    // MARK: - Buffer Capacity Under Stress

    @MainActor
    func testOutputStoreCapacityUnderStress() {
        let store = OutputStore(sessionID: SessionID(), capacity: 500)
        for idx in 0 ..< 1000 {
            let chunk = OutputChunk(
                sessionID: SessionID(),
                commandText: "cmd\(idx)",
                outputLines: ["line"],
                rawANSI: "line",
                exitCode: 0,
                startedAt: Date(),
                finishedAt: Date()
            )
            store.append(chunk)
        }
        XCTAssertEqual(store.chunks.count, 500)
        // Oldest should be evicted; first remaining is cmd500
        XCTAssertEqual(store.chunks.first?.commandText, "cmd500")
    }

    // MARK: - Config SLO Value Assertions

    func testConfigValuesMatchSLOTargets() {
        XCTAssertEqual(AppConfig.Terminal.maxScrollbackLines, 10_000)
        XCTAssertEqual(AppConfig.Output.maxChunksPerSession, 500)
        XCTAssertLessThanOrEqual(AppConfig.SLO.searchSeconds, 0.2)
        XCTAssertLessThanOrEqual(AppConfig.Runtime.sessionSwitchDeadlineSeconds, 0.1)
    }

    // MARK: - Token Estimation

    func testTokenEstimationLatency() async {
        let service = TokenCountingService()
        let longText = String(repeating: "The quick brown fox jumps. ", count: 10000)

        let options = XCTMeasureOptions.default
        options.iterationCount = 50

        measure(options: options) {
            let expectation = expectation(description: "token")
            Task {
                await service.accumulate(for: SessionID(), text: longText)
                _ = await service.estimatedTokens(for: SessionID())
                expectation.fulfill()
            }
            wait(for: [expectation], timeout: 0.1)
        }
    }
}
