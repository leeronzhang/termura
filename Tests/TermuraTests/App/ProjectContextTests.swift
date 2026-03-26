import XCTest
@testable import Termura

@MainActor
final class ProjectContextTests: XCTestCase {
    private var context: ProjectContext?
    private var tmpDir: URL?

    override func setUp() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("termura-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tmpDir = dir

        let factory = MockTerminalEngineFactory()
        let tokenService = TokenCountingService()
        context = try ProjectContext.open(
            at: dir,
            engineFactory: factory,
            tokenCountingService: tokenService
        )
    }

    override func tearDown() async throws {
        context = nil
        if let dir = tmpDir {
            try? FileManager.default.removeItem(at: dir)
        }
    }

    // MARK: - Display name

    func testDisplayNameReturnsLastPathComponent() throws {
        let ctx = try XCTUnwrap(context)
        let expected = ctx.projectURL.lastPathComponent
        XCTAssertEqual(ctx.displayName, expected)
        XCTAssertFalse(ctx.displayName.isEmpty)
    }

    // MARK: - Output store cache

    func testSetOutputStoreAndRetrieve() throws {
        let ctx = try XCTUnwrap(context)
        let sessionID = SessionID()
        let store = OutputStore(sessionID: sessionID)
        ctx.setOutputStore(store, for: sessionID)
        XCTAssertNotNil(ctx.outputStores[sessionID])
        XCTAssertEqual(ctx.outputStores[sessionID]?.sessionID, sessionID)
    }

    // MARK: - View state cache

    func testSetViewStateAndRetrieve() throws {
        let ctx = try XCTUnwrap(context)
        let sessionID = SessionID()
        let engine = MockTerminalEngine()
        let outputStore = OutputStore(sessionID: sessionID)
        let modeController = InputModeController()
        let mockStore = MockSessionStore()
        let tokenService = MockTokenCountingService()
        let terminalVM = TerminalViewModel(
            sessionID: sessionID,
            engine: engine,
            sessionStore: mockStore,
            outputStore: outputStore,
            tokenCountingService: tokenService,
            modeController: modeController
        )
        let editorVM = EditorViewModel(engine: engine, modeController: modeController)
        let timeline = SessionTimeline()
        let viewState = SessionViewState(
            outputStore: outputStore,
            viewModel: terminalVM,
            editorViewModel: editorVM,
            modeController: modeController,
            timeline: timeline
        )
        ctx.setViewState(viewState, for: sessionID)
        XCTAssertNotNil(ctx.sessionViewStates[sessionID])
    }

    // MARK: - Clear caches

    func testClearAllCachesRemovesEverything() throws {
        let ctx = try XCTUnwrap(context)
        let sid1 = SessionID()
        let sid2 = SessionID()
        ctx.setOutputStore(OutputStore(sessionID: sid1), for: sid1)
        ctx.setOutputStore(OutputStore(sessionID: sid2), for: sid2)
        XCTAssertEqual(ctx.outputStores.count, 2)

        ctx.clearAllCaches()
        XCTAssertTrue(ctx.sessionViewStates.isEmpty)
        XCTAssertTrue(ctx.outputStores.isEmpty)
    }
}
