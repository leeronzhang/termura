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

    // MARK: - Output store cache (via viewStateManager)

    func testSetOutputStoreAndRetrieve() throws {
        let ctx = try XCTUnwrap(context)
        let vsm = ctx.viewStateManager
        let sessionID = SessionID()
        let store = OutputStore(sessionID: sessionID)
        vsm.registerOutputStore(store, for: sessionID)
        XCTAssertNotNil(vsm.outputStores[sessionID])
        XCTAssertEqual(vsm.outputStores[sessionID]?.sessionID, sessionID)
    }

    // MARK: - View state cache (via viewStateManager)

    func testSetViewStateAndRetrieve() throws {
        let ctx = try XCTUnwrap(context)
        let vsm = ctx.viewStateManager
        let sessionID = SessionID()
        let engine = MockTerminalEngine()

        let state = vsm.viewState(for: sessionID, engine: engine)
        XCTAssertNotNil(state.viewModel)
        XCTAssertNotNil(vsm.sessionViewStates[sessionID])
    }

    // MARK: - Clear caches

    func testClearAllCachesRemovesEverything() throws {
        let ctx = try XCTUnwrap(context)
        let vsm = ctx.viewStateManager
        let sid1 = SessionID()
        let sid2 = SessionID()
        vsm.registerOutputStore(OutputStore(sessionID: sid1), for: sid1)
        vsm.registerOutputStore(OutputStore(sessionID: sid2), for: sid2)
        XCTAssertEqual(vsm.outputStores.count, 2)

        vsm.clearAll()
        XCTAssertTrue(vsm.sessionViewStates.isEmpty)
        XCTAssertTrue(vsm.outputStores.isEmpty)
    }
}
