import XCTest
@testable import Termura

/// Integration test: verifies the ProjectContext → SessionStore → Engine → OutputStore
/// full chain works end-to-end with real (in-memory) services.
@MainActor
final class ProjectContextIntegrationTests: XCTestCase {
    private var tempDir: URL = FileManager.default.temporaryDirectory

    override func setUp() async throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        do {
            try FileManager.default.removeItem(at: tempDir)
        } catch {
            // Cleanup failure in tests is non-fatal.
            XCTFail("Failed to clean up temp dir: \(error)")
        }
    }

    // MARK: - Factory creates all services

    func testOpenProjectCreatesAllServices() throws {
        let ctx = try ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: TokenCountingService()
        )
        XCTAssertNotNil(ctx.sessionStore)
        XCTAssertNotNil(ctx.agentStateStore)
        XCTAssertNotNil(ctx.commandRouter)
        XCTAssertNotNil(ctx.notesViewModel)
        XCTAssertEqual(ctx.displayName, tempDir.lastPathComponent)
    }

    // MARK: - Session lifecycle chain

    func testCreateSessionRegistersEngine() throws {
        let mockEngine = MockTerminalEngine()
        let factory = MockTerminalEngineFactory(engine: mockEngine)
        let ctx = try ProjectContext.open(
            at: tempDir,
            engineFactory: factory,
            tokenCountingService: TokenCountingService()
        )

        let session = ctx.sessionStore.createSession(title: "Test")
        XCTAssertEqual(ctx.sessionStore.sessions.count, 1)
        XCTAssertEqual(ctx.sessionStore.activeSessionID, session.id)

        let engine = ctx.engineStore.engine(for: session.id)
        XCTAssertNotNil(engine)
    }

    // MARK: - View state cache

    func testViewStateCacheLazyCreation() throws {
        let mockEngine = MockTerminalEngine()
        let factory = MockTerminalEngineFactory(engine: mockEngine)
        let ctx = try ProjectContext.open(
            at: tempDir,
            engineFactory: factory,
            tokenCountingService: TokenCountingService()
        )
        let session = ctx.sessionStore.createSession(title: "Test")

        let vsm = ctx.viewStateManager
        let state1 = vsm.viewState(for: session.id, engine: mockEngine)
        XCTAssertNotNil(state1.viewModel)
        XCTAssertNotNil(state1.outputStore)

        let state2 = vsm.viewState(for: session.id, engine: mockEngine)
        XCTAssertTrue(state1 === state2)
        XCTAssertNotNil(vsm.outputStores[session.id])
    }

    // MARK: - Close cleans up

    func testCloseProjectClearsState() throws {
        let ctx = try ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: TokenCountingService()
        )
        ctx.sessionStore.createSession(title: "Test")
        ctx.close()

        XCTAssertTrue(ctx.viewStateManager.sessionViewStates.isEmpty)
        XCTAssertTrue(ctx.viewStateManager.outputStores.isEmpty)
    }

    // MARK: - CommandRouter chunk notification chain

    func testChunkCompletionFlowsThroughCommandRouter() throws {
        let ctx = try ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: TokenCountingService()
        )

        var received: OutputChunk?
        ctx.commandRouter.onChunkCompleted { chunk in
            received = chunk
        }

        let chunk = OutputChunk(
            sessionID: SessionID(),
            commandText: "test",
            outputLines: ["hello"],
            rawANSI: "hello",
            exitCode: 0,
            startedAt: Date(),
            finishedAt: Date(),
            contentType: .text,
            uiContent: nil
        )

        let store = OutputStore(sessionID: SessionID(), commandRouter: ctx.commandRouter)
        store.append(chunk)

        XCTAssertNotNil(received)
        XCTAssertEqual(received?.commandText, "test")
    }
}
