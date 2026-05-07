@testable import Termura
import XCTest

private final class ProjectContextOutputGate: @unchecked Sendable { // swiftlint:disable:this unchecked_sendable_documentation
    private let condition = NSCondition()
    private var isBlocked = true

    func waitIfBlocked() {
        condition.lock()
        defer { condition.unlock() }
        while isBlocked {
            condition.wait()
        }
    }

    func release() {
        condition.lock()
        isBlocked = false
        condition.broadcast()
        condition.unlock()
    }
}

private actor BlockingTokenService: TokenCountingServiceProtocol {
    nonisolated let gate = ProjectContextOutputGate()

    func accumulateInput(for sessionID: SessionID, text: String) {}

    func accumulateOutput(for sessionID: SessionID, text: String) {
        gate.waitIfBlocked()
    }

    func accumulateCached(for sessionID: SessionID, count: Int) {}

    func estimatedTokens(for sessionID: SessionID) -> Int { 0 }

    func tokenBreakdown(for sessionID: SessionID) -> TokenEstimateBreakdown { .zero }

    func applyParsedStats(for sessionID: SessionID, inputTokens: Int, outputTokens: Int, cachedTokens: Int) {}

    func reset(for sessionID: SessionID) {}

    nonisolated func releaseOutput() {
        gate.release()
    }
}

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

    func testOpenProjectCreatesAllServices() async throws {
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: TokenCountingService()
        )
        XCTAssertNotNil(ctx.sessionScope.store)
        XCTAssertNotNil(ctx.sessionScope.agentStates)
        XCTAssertNotNil(ctx.commandRouter)
        XCTAssertNotNil(ctx.notesViewModel)
        XCTAssertEqual(ctx.displayName, tempDir.lastPathComponent)
    }

    // MARK: - Session lifecycle chain

    func testCreateSessionRegistersEngine() async throws {
        let mockEngine = MockTerminalEngine()
        let factory = MockTerminalEngineFactory(engine: mockEngine)
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: factory,
            tokenCountingService: TokenCountingService()
        )

        let session = ctx.sessionScope.store.createSession(title: "Test")
        XCTAssertEqual(ctx.sessionScope.store.sessions.count, 1)
        XCTAssertEqual(ctx.sessionScope.store.activeSessionID, session.id)

        let engine = ctx.sessionScope.engines.engine(for: session.id)
        XCTAssertNotNil(engine)
    }

    // MARK: - View state cache

    func testViewStateCacheLazyCreation() async throws {
        let mockEngine = MockTerminalEngine()
        let factory = MockTerminalEngineFactory(engine: mockEngine)
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: factory,
            tokenCountingService: TokenCountingService()
        )
        let session = ctx.sessionScope.store.createSession(title: "Test")

        let vsm = ctx.viewStateManager
        let state1 = vsm.viewState(for: session.id, engine: mockEngine)
        XCTAssertNotNil(state1.viewModel)
        XCTAssertNotNil(state1.outputStore)

        let state2 = vsm.viewState(for: session.id, engine: mockEngine)
        XCTAssertTrue(state1 === state2)
        XCTAssertNotNil(vsm.outputStores[session.id])
    }

    // MARK: - Close cleans up

    func testCloseProjectClearsState() async throws {
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: TokenCountingService()
        )
        ctx.sessionScope.store.createSession(title: "Test")
        await ctx.close()

        XCTAssertTrue(ctx.viewStateManager.sessionViewStates.isEmpty)
        XCTAssertTrue(ctx.viewStateManager.outputStores.isEmpty)
        XCTAssertNil(ctx.sessionScope.store.errorMessage)
    }

    func testCloseProjectWaitsForEngineTermination() async throws {
        let engine = MockTerminalEngine()
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(engine: engine),
            tokenCountingService: TokenCountingService()
        )
        ctx.sessionScope.store.createSession(title: "Close waits")

        await ctx.close()

        XCTAssertEqual(engine.terminateCallCount, 1)
        XCTAssertFalse(engine.isRunning)
        XCTAssertNil(ctx.sessionScope.store.errorMessage)
    }

    // MARK: - Session close lifecycle

    /// Verifies CLAUDE.md "生命周期对称性 P0": closing a session must call
    /// TokenCountingService.reset(for:) so the shared actor does not accumulate
    /// stale entries from closed sessions.
    ///
    /// Note: viewStateManager is lazy — it must be accessed before closeSession
    /// so the sessionDidClose subscription is wired up.
    func testCloseSessionResetsTokenCountingService() async throws {
        let tokenService = MockTokenCountingService()
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: tokenService
        )

        let session = ctx.sessionScope.store.createSession(title: "Token Lifecycle")

        // Trigger lazy init — this registers the sessionDidClose subscription.
        // In production the UI always accesses viewStateManager before any session close.
        _ = ctx.viewStateManager

        // Seed stubbedTokens directly (MockTokenCountingService.accumulateOutput
        // only increments a call counter; it does not populate the estimate map).
        await tokenService.setStubbed(tokens: 100, for: session.id)
        let before = await tokenService.estimatedTokens(for: session.id)
        XCTAssertEqual(before, 100, "Pre-condition: stubbed token count should be visible")

        await ctx.sessionScope.store.deleteSession(id: session.id)
        // Allow the fire-and-forget Task inside the sessionDidClose sink to complete.
        try await yieldForDuration(seconds: 0.05)

        let resetCount = await tokenService.resetCallCount
        XCTAssertEqual(resetCount, 1, "reset(for:) must be called exactly once on session close")

        let after = await tokenService.estimatedTokens(for: session.id)
        XCTAssertEqual(after, 0, "Token counts must be zero after session close")
    }

    // MARK: - CommandRouter chunk notification chain

    func testChunkCompletionFlowsThroughCommandRouter() async throws {
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(),
            tokenCountingService: TokenCountingService()
        )

        var received: OutputChunk?
        _ = ctx.commandRouter.onChunkCompleted { chunk in
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

    // MARK: - Flush lifecycle

    func testFlushPendingWritesWaitsForSessionViewModelWork() async throws {
        let engine = MockTerminalEngine()
        let tokenService = BlockingTokenService()
        let ctx = try await ProjectContext.open(
            at: tempDir,
            engineFactory: MockTerminalEngineFactory(engine: engine),
            tokenCountingService: tokenService
        )
        let session = ctx.sessionScope.store.createSession(title: "Flush waits")
        _ = ctx.viewStateManager.viewState(for: session.id, engine: engine)

        engine.emit(.data(Data("pending output".utf8)))
        try await yieldForDuration(seconds: 0.05)

        var didFinishFlush = false
        let flushTask = Task { @MainActor in
            await ctx.flushPendingWrites()
            didFinishFlush = true
        }

        try await yieldForDuration(seconds: 0.05)
        XCTAssertFalse(didFinishFlush, "flushPendingWrites should wait for in-flight session work")

        tokenService.releaseOutput()
        await flushTask.value
        XCTAssertTrue(didFinishFlush)
        await ctx.close()
    }
}
